module controller_regs_tb;
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
  logic [2:0][127:0] issue_payload;
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

  always #5 clk = ~clk;

  controller_regs #(
    .PayloadWidth(128),
    .CounterWidth(4),
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
      $fatal(1, "controller_regs: %s", description);
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

  task automatic issue_one(input int queue_index, input logic [127:0] expected_payload);
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
    $fatal(1, "controller_regs timeout");
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
    if (!$value$plusargs("missing_stall=%b", missing_stall)) begin
      missing_stall = 1'b0;
    end
    if (!$value$plusargs("missing_reset=%b", missing_reset)) begin
      missing_reset = 1'b0;
    end
    if (!$value$plusargs("wrong_result=%b", wrong_result)) begin
      wrong_result = 1'b0;
    end
    if (!missing_reset) begin
      reset_controller();
    end
    check(reset_checks != 0, "reset scenario prerequisite");
    read_check(0, 0, 1);
    write_reg(0, 32'h00c, 32'h12345678);
    read_check(1, 32'h00c, 32'h12345678);
    write_reg(1, 32'h004, 1, 1);
    write_reg(0, 32'h004, 1);
    write_reg(0, 32'h004, 1, 1);
    write_reg(0, 32'h00c, 0, 1);
    write_reg(0, 32'h010, 0, 1);
    write_reg(0, 32'h120, 0, 1);
    write_reg(1, 32'h020, 0, 1);
    write_reg(1, 32'h030, 16, 1);
    write_reg(1, 32'h100, 16, 1);
    write_reg(1, 32'h03c, 8, 1);
    write_reg(1, 32'h108, 2, 1);
    write_reg(1, 32'h044, 1, 1);
    access_reg(0, 0, 32'h1000, 0, 0, 1, observed);
    access_reg(0, 0, 32'h1120, 0, 0, 1, observed);
    access_reg(0, 0, 32'h121, 0, 0, 1, observed);
    access_reg(0, 0, 32'h002, 0, 0, 1, observed);
    access_reg(1, 0, 32'h108, 0, 0, 1, observed);
    access_reg(1, 1, 32'h120, 32'hbad, 4'h1, 1, observed);
    read_check(0, 32'h120, 0);
    access_reg(0, 1, 32'h018, 3, 4'h1, 1, observed);
    read_check(0, 32'h018, 0);
    write_reg(1, 32'h120, 32'h11111111);
    write_reg(1, 32'h124, 32'h22222222);
    write_reg(1, 32'h128, 32'h33333333);
    write_reg(1, 32'h12c, 32'h44444444);
    write_reg(1, 32'h108, 1);
    write_reg(1, 32'h120, 32'haaaaaaaa);
    write_reg(1, 32'h108, 1);
    repeat (2) begin
      @(negedge clk);
      check(issue_valid[0] && issue_payload[0] == 128'h44444444333333332222222211111111,
            "offer stable while staging changes");
    end
    if (!missing_stall) begin
      @(negedge clk);
      cpu_req = 1;
      cpu_we = 1;
      cpu_addr = 32'h108;
      cpu_wdata = 1;
      #1;
      check(!cpu_gnt, "full queue stalls commit");
      access_reg(0, 0, 32'h008, 0, 0, 0, observed);
      check(observed == 1 && !cpu_gnt && !cpu_rvalid, "host responsive while CPU stalled");
      stall_checks++;
      issue_one(0, 128'h44444444333333332222222211111111);
      // The released full-queue request transfers on the next rising edge.
      @(posedge clk);
      #1;
      check(cpu_rvalid && !cpu_error, "stalled commit responds when capacity returns");
      @(negedge clk);
      cpu_req = 0;
      issue_one(0, 128'h444444443333333322222222aaaaaaaa);
      issue_one(0, 128'h444444443333333322222222aaaaaaaa);
    end
    check(stall_checks != 0, "stall scenario prerequisite");
    access_reg(1, 1, 32'h108, 1, 4'h1, 1, observed);
    read_check(0, 32'h02c, 32'h707);

    // A matrix command waits for the memory progress counter.
    write_reg(1, 32'h200, 2);
    write_reg(1, 32'h204, 2);
    write_reg(1, 32'h220, 32'h55);
    write_reg(1, 32'h208, 1);
    check(!issue_valid[1], "cross-queue dependency blocks issue");
    pulse_increment(0, 2);
    read_check(0, 32'h020, 2);
    check(!issue_valid[1], "second cross-queue dependency still blocks issue");
    pulse_increment(2, 2);
    issue_one(1, 128'h55);
    write_reg(1, 32'h030, 4);
    write_reg(1, 32'h034, 2);
    write_reg(1, 32'h03c, 3);
    check(!cpu_irq, "wait arm clears old completion");
    pulse_increment(0, 2);
    repeat (2) @(negedge clk);
    check(!cpu_irq, "firmware wait requires every masked counter");
    pulse_increment(1, 2);
    repeat (2) @(negedge clk);
    check(cpu_irq, "+2 progress satisfies firmware wait");
    wait_checks++;
    // Reach 14, then use masked target zero to observe a real wrap dependency.
    repeat (5) pulse_increment(0, 2);
    read_check(0, 32'h020, 14);
    write_reg(1, 32'h030, 0);
    write_reg(1, 32'h03c, 1);
    repeat (2) @(negedge clk);
    check(!cpu_irq, "target zero before wrap remains blocked");
    pulse_increment(0, 2);
    repeat (2) @(negedge clk);
    check(cpu_irq, "target zero satisfied after wrap");
    wait_checks++;
    repeat (5) pulse_increment(0, 2);
    check(cpu_irq, "satisfied wait retained beyond half range");
    write_reg(1, 32'h048, 1);
    check(!cpu_irq, "wait clear disarms IRQ");
    write_reg(1, 32'h03c, 0);
    repeat (2) @(negedge clk);
    check(cpu_irq, "empty mask satisfies");
    write_reg(0, 32'h018, 3);
    write_reg(1, 32'h010, 32'hfeed1234);
    read_check(0, 32'h010, wrong_result ? 32'hdead : 32'hfeed1234);
    write_reg(1, 32'h308, 1);
    @(negedge clk);
    engine_idle = 3'b011;
    cpu_req = 1;
    cpu_we = 1;
    cpu_addr = 32'h044;
    cpu_wdata = 1;
    #1;
    check(!cpu_gnt && !done, "FINISH waits for physical drain");
    issue_one(2, 0);
    #1;
    check(!cpu_gnt && !done, "empty queue does not imply idle engine");
    access_reg(0, 0, 32'h010, 0, 0, 0, observed);
    check(observed == 32'hfeed1234, "host result readable during FINISH");
    @(negedge clk);
    engine_idle = '1;
    host_req = 1;
    host_we = 1;
    host_addr = 32'h014;
    host_wdata = 1;
    @(posedge clk);
    #1;
    check(done && host_irq && run, "done set wins concurrent W1C and run stays set");
    @(negedge clk);
    host_req = 0;
    cpu_req  = 0;
    read_check(0, 32'h014, 1);
    write_reg(0, 32'h014, 1);
    check(!host_irq, "done interrupt clears");
    write_reg(1, 32'h108, 1, 1);
    reset_controller();
    write_reg(0, 32'h004, 1);
    write_reg(0, 32'h018, 3);
    write_reg(1, 32'h108, 1);
    write_reg(1, 32'h108, 1);
    @(negedge clk);
    engine_fault = 1;
    host_req = 1;
    host_we = 1;
    host_addr = 32'h014;
    host_wdata = 2;
    @(posedge clk);
    #1;
    check(fault && host_irq && issue_valid[0], "fault set wins clear, preserves queued offer");
    @(negedge clk);
    host_req = 0;
    engine_fault = 0;
    write_reg(1, 32'h108, 1, 1);
    issue_one(0, 0);
    pulse_increment(1, 2);
    pulse_increment(2, 2);
    repeat (3) @(negedge clk);
    check(!issue_valid[0], "fault suppresses new offers after retained head is accepted");
    access_reg(0, 0, 32'h02c, 0, 0, 0, observed);
    check(observed[2:0] == 3'b110, "fault leaves the unoffered command queued");
    reset_controller();
    write_reg(0, 32'h004, 1);
    write_reg(1, 32'h108, 1);
    write_reg(1, 32'h108, 1);
    @(negedge clk);
    cpu_req = 1;
    cpu_we = 1;
    cpu_addr = 32'h108;
    cpu_wdata = 1;
    #1;
    check(!cpu_gnt, "reset begins during stalled commit");
    reset_controller();
    write_reg(0, 32'h004, 1);
    @(negedge clk);
    cpu_fault = 1;
    cpu_req = 1;
    cpu_we = 1;
    cpu_addr = 32'h108;
    cpu_wdata = 1;
    @(posedge clk);
    #1;
    check(cpu_rvalid && cpu_error && !issue_valid[0], "same-edge fault rejects commit");
    @(negedge clk);
    cpu_fault = 0;
    cpu_req   = 0;
    check(fault, "CPU fault sticky");
    reset_controller();
    check(reset_checks >= 5 && wait_checks >= 2 && issue_checks >= 5,
          "scenario coverage prerequisites");
    $display("CONTROLLER_REGS_PASS checks=%0d resets=%0d stalls=%0d issues=%0d waits=%0d", checks,
             reset_checks, stall_checks, issue_checks, wait_checks);
    $finish;
  end
endmodule
