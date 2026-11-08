module controller_firmware_tb;
  timeunit 1ns; timeprecision 1ps;
  logic clk = 1'b0;
  logic rst_n = 1'b0;
  logic [31:0] host_addr = '0, host_wdata = '0, host_rdata;
  logic [3:0] host_be = 4'hf;
  logic awvalid = 1'b0, awready, wvalid = 1'b0, wready;
  logic bvalid, bready = 1'b0;
  logic arvalid = 1'b0, arready, rvalid, rready = 1'b0;
  logic [1:0] bresp, rresp;
  logic [2:0] issue_valid, issue_ready = '0;
  logic [2:0][511:0] issue_payload;
  logic [2:0][  1:0] increment = '0;
  logic [2:0] engine_idle = '0, engine_fault = '0;
  logic host_irq, done, fault;
  int unsigned command_count = 0;
  int unsigned cpu_reads = 0;
  int unsigned firmware_word;
  logic [31:0] read_value;
  logic inject_bad_result;
  int unsigned stalled_cycles = 0, host_stall_reads = 0, payload_words = 0;
  int unsigned cpu_writes = 0, dependency_writes = 0, queue_commits = 0;
  logic missing_stall;
  logic [31:0] image[4096];
  string firmware_path;
  int unsigned image_words;

  always #5ns clk = ~clk;
  top_level_controller #(
    .PayloadWidth(512),
    .CounterWidth(32),
    .QueueDepth  (2)
  ) u_dut (
    .clk_i(clk),
    .rst_ni(rst_n),
    .awaddr_i(host_addr),
    .awvalid_i(awvalid),
    .awready_o(awready),
    .wdata_i(host_wdata),
    .wstrb_i(host_be),
    .wvalid_i(wvalid),
    .wready_o(wready),
    .bresp_o(bresp),
    .bvalid_o(bvalid),
    .bready_i(bready),
    .araddr_i(host_addr),
    .arvalid_i(arvalid),
    .arready_o(arready),
    .rdata_o(host_rdata),
    .rresp_o(rresp),
    .rvalid_o(rvalid),
    .rready_i(rready),
    .issue_valid_o(issue_valid),
    .issue_ready_i(issue_ready),
    .issue_payload_o(issue_payload),
    .increment_i(increment),
    .engine_idle_i(engine_idle),
    .engine_fault_i(engine_fault),
    .host_irq_o(host_irq),
    .done_o(done),
    .fault_o(fault)
  );

  always @(posedge clk) begin
    if (rst_n) begin
      if (u_dut.u_system.data_req && u_dut.u_system.data_we &&
          u_dut.u_system.data_addr == 32'h40000108 && !u_dut.u_system.data_gnt) begin
        stalled_cycles <= stalled_cycles + 1;
      end
      if (u_dut.u_system.data_req && u_dut.u_system.data_gnt && u_dut.u_system.data_we &&
          u_dut.u_system.data_addr[31:12] == 20'h40000) begin
        cpu_writes <= cpu_writes + 1;
        if (u_dut.u_system.data_be != 4'hf || u_dut.u_system.data_addr[1:0] != 0)
          $fatal(1, "C firmware issued a partial or unaligned CSR store");
        case (u_dut.u_system.data_addr[11:0])
          'h100, 'h104, 'h200, 'h204, 'h300, 'h304: begin
            dependency_writes <= dependency_writes + 1;
            case (u_dut.u_system.data_addr[11:0])
              'h200, 'h300:
              if (u_dut.u_system.data_wdata != 3) $fatal(1, "C dependency target mismatch");
              'h204: if (u_dut.u_system.data_wdata != 1) $fatal(1, "C dependency target mismatch");
              default:
              if (u_dut.u_system.data_wdata != 0) $fatal(1, "C dependency target mismatch");
            endcase
          end
          'h108, 'h208, 'h308: queue_commits <= queue_commits + 1;
          default: ;
        endcase
      end
      command_count <= command_count + 32'($countones(issue_valid & issue_ready));
      if (u_dut.u_system.data_req && u_dut.u_system.data_gnt && !u_dut.u_system.data_we) begin
        cpu_reads <= cpu_reads + 1;
      end
    end
  end

  task automatic host_access(input bit write_access, input logic [31:0] address,
                             input logic [31:0] value, input bit expect_error,
                             output logic [31:0] response);
    bit accepted;
    response = '0;
    @(negedge clk);
    host_addr  = address;
    host_wdata = value;
    if (write_access) begin
      awvalid  = 1'b1;
      accepted = 1'b0;
      for (int cycle = 0; cycle < 100; cycle++) begin
        @(posedge clk);
        if (awready) begin
          accepted = 1'b1;
          break;
        end
      end
      if (!accepted) begin
        $fatal(1, "AXI address write timeout address=%h", address);
      end
      @(negedge clk);
      awvalid  = 1'b0;
      wvalid   = 1'b1;
      accepted = 1'b0;
      for (int cycle = 0; cycle < 100; cycle++) begin
        @(posedge clk);
        if (wready) begin
          accepted = 1'b1;
          break;
        end
      end
      if (!accepted) begin
        $fatal(1, "AXI write data timeout address=%h", address);
      end
      @(negedge clk);
      wvalid   = 1'b0;
      bready   = 1'b1;
      accepted = 1'b0;
      for (int cycle = 0; cycle < 100; cycle++) begin
        @(posedge clk);
        if (bvalid) begin
          accepted = 1'b1;
          if (bresp != (expect_error ? 2'b10 : 2'b00)) begin
            $fatal(1, "AXI write response mismatch address=%h response=%b", address, bresp);
          end
          break;
        end
      end
      if (!accepted) begin
        $fatal(1, "AXI write response timeout address=%h", address);
      end
      @(negedge clk);
      bready = 1'b0;
    end else begin
      arvalid  = 1'b1;
      accepted = 1'b0;
      for (int cycle = 0; cycle < 100; cycle++) begin
        @(posedge clk);
        if (arready) begin
          accepted = 1'b1;
          break;
        end
      end
      if (!accepted) begin
        $fatal(1, "AXI read address timeout address=%h", address);
      end
      @(negedge clk);
      arvalid  = 1'b0;
      rready   = 1'b1;
      accepted = 1'b0;
      for (int cycle = 0; cycle < 100; cycle++) begin
        @(posedge clk);
        if (rvalid) begin
          accepted = 1'b1;
          response = host_rdata;
          if (rresp != (expect_error ? 2'b10 : 2'b00)) begin
            $fatal(1, "AXI read response mismatch address=%h response=%b", address, rresp);
          end
          break;
        end
      end
      if (!accepted) begin
        $fatal(1, "AXI read response timeout address=%h", address);
      end
      @(negedge clk);
      rready = 1'b0;
    end
    if (expect_error && response != 0) begin
      $fatal(1, "error response must contain zero");
    end
  endtask

  task automatic accept_record(input int unsigned queue_index, input int unsigned serial);
    bit offered;
    offered = 0;
    for (int cycle = 0; cycle < 5000; cycle++) begin
      @(negedge clk);
      if (fault) $fatal(1, "C firmware faulted waiting for command");
      if (issue_valid[queue_index]) begin
        offered = 1;
        break;
      end
    end
    if (!offered) $fatal(1, "C firmware command offer timed out");
    for (int word_index = 0; word_index < 16; word_index++) begin
      if (issue_payload[queue_index][32*word_index+:32] !==
          32'hc1000000 + 32'(serial * 256 + word_index)) begin
        $fatal(1, "C firmware payload mismatch queue=%0d serial=%0d word=%0d", queue_index, serial,
               word_index);
      end
      payload_words++;
    end
    repeat (4) begin
      @(negedge clk);
      if (!issue_valid[queue_index]) $fatal(1, "C firmware offer was not retained");
      for (int word_index = 0; word_index < 16; word_index++) begin
        if (issue_payload[queue_index][32*word_index+:32] !==
            32'hc1000000 + 32'(serial * 256 + word_index))
          $fatal(1, "C firmware payload changed during backpressure");
      end
    end
    issue_ready[queue_index] = 1;
    @(posedge clk);
    if (!issue_valid[queue_index]) $fatal(1, "C firmware acceptance lost its offer");
    for (int word_index = 0; word_index < 16; word_index++) begin
      if (issue_payload[queue_index][32*word_index+:32] !==
          32'hc1000000 + 32'(serial * 256 + word_index))
        $fatal(1, "C firmware accepted payload mismatch");
    end
    @(negedge clk);
    issue_ready[queue_index] = 0;
  endtask

  task automatic milestone(input int unsigned queue_index, input logic [1:0] amount);
    @(negedge clk);
    increment[queue_index] = amount;
    @(negedge clk);
    increment[queue_index] = 0;
  endtask

  initial begin
    #1000000ns;
    $fatal(1, "C firmware test timed out");
  end

  initial begin
    bit observed_stall;
    bit finish_stall;
    missing_stall = 0;
    inject_bad_result = 0;
    void'($value$plusargs("missing_stall=%b", missing_stall));
    void'($value$plusargs("inject_bad_result=%b", inject_bad_result));
    if (!$value$plusargs(
        "firmware=%s", firmware_path
      ) || !$value$plusargs(
        "firmware_words=%d", image_words
      ) || image_words == 0 || image_words > 4000)
      $fatal(1, "C firmware image arguments missing or invalid");
    $readmemh(firmware_path, image, 0, image_words - 1);
    repeat (4) @(negedge clk);
    rst_n = 1;
    repeat (3) @(negedge clk);
    for (int word_index = 0; word_index < int'(image_words); word_index++) begin
      if ($isunknown(image[word_index])) $fatal(1, "C firmware image contains undefined word");
      host_write(32'h10080 + 32'(word_index * 4), image[word_index]);
    end
    host_write('h00c, 'h13579bdf);
    host_write('h018, 3);
    host_write('h004, 1);
    observed_stall = 0;
    if (!missing_stall) begin
      for (int cycle = 0; cycle < 5000; cycle++) begin
        @(negedge clk);
        if (fault) $fatal(1, "C firmware faulted before queue backpressure");
        if (u_dut.u_system.data_req && u_dut.u_system.data_we &&
            u_dut.u_system.data_addr == 32'h40000108 && !u_dut.u_system.data_gnt &&
            stalled_cycles >= 20) begin
          observed_stall = 1;
          break;
        end
      end
      if (!observed_stall) $fatal(1, "C firmware queue-full backpressure was never observed");
      repeat (3) begin
        host_access(0, 'h008, 0, 0, read_value);
        if (read_value != 1 || !u_dut.u_system.data_req || u_dut.u_system.data_gnt ||
            u_dut.u_system.data_addr != 32'h40000108 || command_count != 0)
          $fatal(1, "host status service failed during C firmware COMMIT stall");
        host_stall_reads++;
      end
      host_access(0, 'h02c, 0, 0, read_value);
      if (read_value[8] || read_value[2:0] != 3'b110 || u_dut.u_system.data_gnt)
        $fatal(1, "C firmware COMMIT stall did not fill the Memory queue");
    end
    if (!observed_stall || host_stall_reads < 3 || stalled_cycles < 20)
      $fatal(1, "C firmware backpressure prerequisite missing");
    accept_record(0, 1);
    accept_record(0, 2);
    accept_record(0, 3);
    for (int cycle = 0; cycle < 5000; cycle++) begin
      @(negedge clk);
      if (fault) $fatal(1, "C firmware faulted while submitting dependent commands");
      if (queue_commits == 5) break;
      if (cycle == 4999) $fatal(1, "C firmware dependent submissions timed out");
    end
    if (issue_valid != 0 || command_count != 3 || queue_commits != 5)
      $fatal(1, "C firmware submissions or initial dependencies mismatch");
    milestone(0, 2);
    repeat (4) @(negedge clk);
    if (issue_valid != 0) $fatal(1, "C firmware dependency released before memory target three");
    milestone(0, 1);
    accept_record(2, 5);
    if (issue_valid[1]) $fatal(1, "Matrix second dependency released before vector target one");
    milestone(2, 1);
    accept_record(1, 4);
    milestone(1, 1);
    finish_stall = 0;
    for (int cycle = 0; cycle < 5000; cycle++) begin
      @(negedge clk);
      if (u_dut.u_system.data_req && u_dut.u_system.data_we &&
          u_dut.u_system.data_addr == 32'h40000044 && !u_dut.u_system.data_gnt) begin
        finish_stall = 1;
        break;
      end
    end
    if (!finish_stall || done || fault) $fatal(1, "C firmware FINISH did not wait for engine idle");
    host_access(0, 'h010, 0, 0, read_value);
    if (read_value != 'h600dc0de) $fatal(1, "C firmware result missing before final drain");
    engine_idle = '1;
    repeat (20) @(negedge clk);
    if (!done || !host_irq || fault) $fatal(1, "C firmware completion missing");
    host_access(0, 'h010, 0, 0, read_value);
    if (read_value != (inject_bad_result ? 'hdead : 'h600dc0de))
      $fatal(1, "C firmware result mismatch");
    if (command_count != 5 || queue_commits != 5 || dependency_writes != 10 ||
        payload_words != 80 || cpu_reads < 3 || cpu_writes != 101)
      $fatal(1, "C firmware transaction count prerequisite missing");
    $display({"RESULT controller_firmware commands=%0d cpu_reads=%0d cpu_writes=%0d ",
              "stalls=%0d host_reads=%0d words=%0d dependencies=%0d commits=%0d PASS"},
               command_count, cpu_reads, cpu_writes, stalled_cycles, host_stall_reads,
               payload_words, dependency_writes, queue_commits);
    $finish;
  end

  task automatic host_write(input logic [31:0] address, input logic [31:0] value);
    logic [31:0] ignored;
    host_access(1'b1, address, value, 1'b0, ignored);
  endtask

endmodule
