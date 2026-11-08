module controller_generated_tb;
  timeunit 1ns; timeprecision 1ps;
  logic clk = 1'b0;
  logic rst_n = 1'b0;
  logic host_req, host_gnt, host_we, host_rvalid, host_error;
  logic [31:0] host_addr, host_wdata, host_rdata;
  logic [3:0] host_be;
  logic cpu_req, cpu_gnt, cpu_we, cpu_rvalid, cpu_error;
  logic [31:0] cpu_addr, cpu_wdata, cpu_rdata;
  logic [3:0] cpu_be;
  logic run, done, fault, host_irq, cpu_irq;
  logic [31:0] job_arg;
  logic cpu_fault;
  logic [2:0] engine_fault, engine_idle, issue_valid, issue_ready;
  logic [2:0][511:0] issue_payload;
  logic [2:0][1:0] increment;
  int unsigned checks = 0;
  int unsigned reset_checks = 0;
  int unsigned stall_checks = 0;
  int unsigned issue_checks = 0;
  int unsigned wait_checks = 0;
  logic [31:0] observed;
  logic missing_stall;
  logic missing_reset;
  logic wrong_result;
  logic [511:0] expected_record;
  int unsigned payload_words = 0;
  int unsigned seeded_wraps = 0;

  always #5 clk = ~clk;

  controller_regs #(
    .PayloadWidth(512),
    .CounterWidth(32),
    .QueueDepth  (2)
  ) u_dut (
    .clk_i(clk),
    .rst_ni(rst_n),
    .host_req_i(host_req),
    .host_gnt_o(host_gnt),
    .host_we_i(host_we),
    .host_addr_i(host_addr),
    .host_wdata_i(host_wdata),
    .host_be_i(host_be),
    .host_rvalid_o(host_rvalid),
    .host_rdata_o(host_rdata),
    .host_error_o(host_error),
    .cpu_req_i(cpu_req),
    .cpu_gnt_o(cpu_gnt),
    .cpu_we_i(cpu_we),
    .cpu_addr_i(cpu_addr),
    .cpu_wdata_i(cpu_wdata),
    .cpu_be_i(cpu_be),
    .cpu_rvalid_o(cpu_rvalid),
    .cpu_rdata_o(cpu_rdata),
    .cpu_error_o(cpu_error),
    .run_o(run),
    .job_arg_o(job_arg),
    .host_irq_o(host_irq),
    .cpu_irq_o(cpu_irq),
    .done_o(done),
    .fault_o(fault),
    .cpu_fault_i(cpu_fault),
    .engine_fault_i(engine_fault),
    .engine_idle_i(engine_idle),
    .issue_valid_o(issue_valid),
    .issue_payload_o(issue_payload),
    .issue_ready_i(issue_ready),
    .increment_i(increment)
  );

  task automatic check(input logic condition, input string description);
    if (condition !== 1'b1) begin
      $fatal(1, "controller_generated: %s", description);
    end
    checks++;
  endtask

  // Drive requests on falling edges and sample registered responses after NBA updates.
  task automatic access_reg(input bit cpu, input bit write_enable, input logic [31:0] address,
                            input logic [31:0] value, input logic [3:0] enables,
                            input bit expected_error, output logic [31:0] read_value);
    @(negedge clk);
    if (cpu) begin
      cpu_req = 1'b1;
      cpu_we = write_enable;
      cpu_addr = address;
      cpu_wdata = value;
      cpu_be = enables;
    end else begin
      host_req = 1'b1;
      host_we = write_enable;
      host_addr = address;
      host_wdata = value;
      host_be = enables;
    end
    for (int cycle = 0; cycle < 100; cycle++) begin
      @(posedge clk);
      if (cpu ? cpu_gnt : host_gnt) begin
        break;
      end
      check(!(cpu ? cpu_rvalid : host_rvalid), "no response before acceptance");
      if (cycle == 99) $fatal(1, "CSR request acceptance timed out");
    end
    #1;
    check(cpu ? cpu_rvalid : host_rvalid, "registered response");
    check((cpu ? cpu_error : host_error) === expected_error, "response error");
    read_value = cpu ? cpu_rdata : host_rdata;
    if (expected_error) begin
      check(read_value == 0, "error read data zero");
    end
    @(negedge clk);
    if (cpu) begin
      cpu_req = 1'b0;
    end else begin
      host_req = 1'b0;
    end
  endtask

  task automatic write_reg(input bit cpu, input logic [31:0] address, input logic [31:0] value,
                           input bit expected_error = 0);
    logic [31:0] unused_data;
    access_reg(cpu, 1, address, value, 4'hf, expected_error, unused_data);
  endtask

  task automatic read_check(input bit cpu, input logic [31:0] address,
                            input logic [31:0] expected_value);
    logic [31:0] read_value;
    access_reg(cpu, 0, address, 0, 0, 0, read_value);
    check(read_value === expected_value, $sformatf(
          "read %h got %h expected %h", address, read_value, expected_value));
  endtask

  task automatic reset_controller;
    @(negedge clk);
    rst_n = 1'b0;
    cpu_req = 1'b0;
    host_req = 1'b0;
    issue_ready = '0;
    increment = '0;
    cpu_fault = 1'b0;
    engine_fault = '0;
    engine_idle = '1;
    repeat (2) @(negedge clk);
    rst_n = 1'b1;
    @(posedge clk);
    #1;
    check(!run && !done && !fault && !cpu_irq && !host_irq, "reset control state");
    check(issue_valid == 0, "reset cancels queued commands");
    read_check(0, 32'h02c, 32'h707);
    read_check(0, 32'h020, 0);
    read_check(0, 32'h120, 0);
    reset_checks++;
  endtask

  task automatic pulse_increment(input int queue_index, input logic [1:0] amount);
    @(negedge clk);
    increment[queue_index] = amount;
    @(negedge clk);
    increment = '0;
  endtask

  task automatic issue_one(input int queue_index, input logic [511:0] expected_payload);
    @(negedge clk);
    check(issue_valid[queue_index], "expected command offered");
    check(issue_payload[queue_index] === expected_payload, "atomic staged payload");
    issue_ready[queue_index] = 1'b1;
    @(negedge clk);
    issue_ready = '0;
    issue_checks++;
  endtask

  initial begin
    #100000;
    $fatal(1, "generated controller test timed out");
  end

  initial begin
    host_req = 0;
    cpu_req = 0;
    host_we = 0;
    cpu_we = 0;
    host_addr = 0;
    cpu_addr = 0;
    host_wdata = 0;
    cpu_wdata = 0;
    host_be = 4'hf;
    cpu_be = 4'hf;
    issue_ready = 0;
    increment = 0;
    cpu_fault = 0;
    engine_fault = 0;
    engine_idle = '1;
    missing_stall = 0;
    missing_reset = 0;
    wrong_result = 0;
    void'($value$plusargs("missing_stall=%b", missing_stall));
    void'($value$plusargs("missing_reset=%b", missing_reset));
    void'($value$plusargs("wrong_result=%b", wrong_result));
    if (!missing_reset) reset_controller();
    check(reset_checks != 0, "reset scenario prerequisite");
    read_check(0, 0, 1);
    write_reg(0, 'h004, 1);

    // Exercise all 16 payload words, including Matrix fields above bit 127.
    for (int word_index = 0; word_index < 16; word_index++) begin
      expected_record[32*word_index+:32] = 32'hc0010000 + 32'(word_index);
      write_reg(1, 'h220 + 32'(word_index * 4), expected_record[32*word_index+:32]);
      read_check(0, 'h220 + 32'(word_index * 4), expected_record[32*word_index+:32]);
      payload_words++;
    end
    write_reg(1, 'h208, 1);
    write_reg(1, 'h25c, 'hfeedface);
    repeat (3) begin
      @(negedge clk);
      check(issue_valid[1] && issue_payload[1] === expected_record,
            "complete offered record retained while staging changes");
    end
    write_reg(1, 'h208, 1);
    expected_record[511:480] = 'hfeedface;
    if (!missing_stall) begin
      @(negedge clk);
      cpu_req = 1;
      cpu_we = 1;
      cpu_addr = 'h208;
      cpu_wdata = 1;
      repeat (5) begin
        @(posedge clk);
        check(!cpu_gnt && !cpu_rvalid, "full wide FIFO holds commit pending");
      end
      access_reg(0, 0, 'h008, 0, 0, 0, observed);
      check(observed == 1 && !cpu_gnt, "host read completes beside stalled firmware commit");
      stall_checks++;
      @(negedge clk);
      issue_ready[1] = 1;
      @(posedge clk);
      #1;
      @(negedge clk);
      issue_ready = '0;
      issue_checks++;
      for (int cycle = 0; cycle < 100; cycle++) begin
        @(posedge clk);
        if (cpu_gnt) break;
        if (cycle == 99) $fatal(1, "wide commit did not resume after dequeue");
      end
      #1;
      check(cpu_rvalid && !cpu_error, "resumed wide commit has one successful response");
      @(negedge clk);
      cpu_req = 0;
      issue_one(1, expected_record);
      issue_one(1, expected_record);
      repeat (3) @(negedge clk);
      check(issue_valid == 0, "pending wide commit enqueued exactly once");
    end
    check(stall_checks != 0, "stall scenario prerequisite");
    access_reg(1, 1, 'h25c, 0, 4'h1, 1, observed);
    read_check(0, 'h25c, 'hfeedface);
    write_reg(0, 'h25c, 0, 1);
    read_check(1, 'h25c, 'hfeedface);
    access_reg(0, 0, 'h260, 0, 0, 1, observed);

    // At progress zero, the exact 32-bit half-range target is unsatisfied.
    write_reg(1, 'h030, 'h80000000);
    write_reg(1, 'h03c, 1);
    repeat (3) @(negedge clk);
    check(!cpu_irq, "32-bit half-range comparison is unsatisfied");
    write_reg(1, 'h030, 'hffffffff);
    repeat (3) @(negedge clk);
    check(!cpu_irq, "editing wait staging preserves the armed snapshot");
    write_reg(1, 'h03c, 1);
    repeat (3) @(negedge clk);
    check(cpu_irq, "32-bit target just before zero is reached after wrap");
    wait_checks++;

    // Seed only the starting state; real increment pulses exercise the wrap.
    @(negedge clk);
    force u_dut.u_command_queues.u_shared_scoreboard.progress_q[0] = 32'hfffffffe;
    @(negedge clk);
    release u_dut.u_command_queues.u_shared_scoreboard.progress_q[0];
    seeded_wraps++;
    read_check(0, 'h020, 'hfffffffe);
    write_reg(1, 'h030, 0);
    write_reg(1, 'h03c, 1);
    repeat (3) @(negedge clk);
    check(!cpu_irq, "masked zero target waits before 32-bit wrap");
    pulse_increment(0, 1);
    read_check(1, 'h020, 'hffffffff);
    check(!cpu_irq, "zero target remains pending at all-ones progress");
    pulse_increment(0, 1);
    read_check(0, 'h020, 0);
    repeat (3) @(negedge clk);
    check(cpu_irq, "zero target satisfies after 32-bit wrap");
    wait_checks++;
    write_reg(1, 'h048, 1);
    check(!cpu_irq, "wait clear removes generated interrupt state");
    write_reg(1, 'h010, 'h12345678);
    read_check(0, 'h010, wrong_result ? 'hdead : 'h12345678);
    reset_controller();
    read_check(0, 'h25c, 0);
    check(
      reset_checks == 2 && payload_words == 16 && seeded_wraps == 1 && issue_checks == 3 &&
          wait_checks == 2,
      "wide configuration scenario prerequisites");
    $display({"CONTROLLER_REGS_PASS checks=%0d resets=%0d stalls=%0d issues=%0d ",
              "waits=%0d words=%0d seeded_wraps=%0d"}, checks, reset_checks, stall_checks,
               issue_checks, wait_checks, payload_words, seeded_wraps);
    $finish;
  end
endmodule
