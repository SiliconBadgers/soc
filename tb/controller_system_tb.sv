module controller_system_tb;
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
  logic [2:0][127:0] issue_payload;
  logic [2:0][  1:0] increment = '0;
  logic [2:0] engine_idle = '0, engine_fault = '0;
  logic host_irq, done, fault;
  int unsigned command_count = 0;
  int unsigned cpu_reads = 0;
  int unsigned firmware_word;
  logic [31:0] read_value;
  logic inject_bad_result;
  bit store_seen;

  always #5ns clk = ~clk;
  top_level_controller u_dut (
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

  task automatic host_write(input logic [31:0] address, input logic [31:0] value);
    logic [31:0] ignored;
    host_access(1'b1, address, value, 1'b0, ignored);
  endtask

  // RV32I encoders keep the fixture independent of a toolchain installation.
  function automatic logic [31:0] store_word(input int unsigned offset, input int unsigned source);
    return {7'(offset >> 5), 5'(source), 5'd1, 3'b010, 5'(offset), 7'h23};
  endfunction

  function automatic logic [31:0] load_word(input int unsigned offset);
    return {12'(offset), 5'd1, 3'b010, 5'd3, 7'h03};
  endfunction

  task automatic emit(input logic [31:0] instruction);
    host_write(32'h10080 + firmware_word * 4, instruction);
    firmware_word++;
  endtask

  // Both pinned frontends can fetch beyond a taken jump. Define a guard after
  // each loaded program so speculative reads never consume uninitialized RAM.
  task automatic pad_firmware;
    repeat (8) emit(32'h00000013);  // addi x0, x0, 0.
  endtask

  task automatic load_job;
    firmware_word = 0;
    emit(32'h400000b7);  // lui x1, 0x40000: register base.
    emit(32'h00100113);  // addi x2, x0, 1.
    emit(32'h01100213);  // addi x4, x0, 0x11.
    emit(store_word('h120, 4));
    emit(store_word('h108, 2));
    emit(store_word('h200, 2));  // Matrix waits for memory progress 1.
    emit(32'h02200213);
    emit(store_word('h220, 4));
    emit(store_word('h208, 2));
    emit(store_word('h304, 2));  // Vector waits for matrix progress 1.
    emit(32'h03300213);
    emit(store_word('h320, 4));
    emit(store_word('h308, 2));
    emit(load_word('h020));
    emit(store_word('h030, 2));
    emit(store_word('h034, 2));
    emit(store_word('h038, 2));
    emit(32'h00700213);
    emit(store_word('h03c, 4));
    emit(load_word('h040));
    emit(32'h0021f193);  // andi x3, x3, 2.
    emit(32'hfe018ce3);  // beq x3, x0, -8: poll latched wait.
    emit(32'h05a00213);
    emit(store_word('h010, 4));
    emit(store_word('h044, 2));
    emit(32'h0000006f);  // Keep running after FINISH.
    pad_firmware();
  endtask

  task automatic reset_epoch;
    @(negedge clk);
    rst_n = 1'b0;
    awvalid = 1'b0;
    wvalid = 1'b0;
    arvalid = 1'b0;
    bready = 1'b0;
    rready = 1'b0;
    issue_ready = '0;
    increment = '0;
    engine_idle = '0;
    engine_fault = '0;
    repeat (4) @(negedge clk);
    rst_n = 1'b1;
    repeat (3) @(negedge clk);
  endtask

  task automatic accept_command(input int unsigned queue_index,
                                input logic [31:0] expected_payload);
    bit offered;
    offered = 1'b0;
    for (int cycle = 0; cycle < 3000; cycle++) begin
      @(negedge clk);
      if (issue_valid[queue_index]) begin
        offered = 1'b1;
        break;
      end
      if (fault) begin
        $fatal(1, "unexpected core fault waiting for queue %0d", queue_index);
      end
    end
    if (!offered || issue_payload[queue_index] !== {96'b0, expected_payload}) begin
      $fatal(1, "queue %0d offer mismatch payload=%h", queue_index, issue_payload[queue_index]);
    end
    repeat (4) begin
      @(negedge clk);
      if (!issue_valid[queue_index] ||
          issue_payload[queue_index] !== {96'b0, expected_payload}) begin
        $fatal(1, "stalled command changed");
      end
    end
    issue_ready[queue_index] = 1'b1;
    @(negedge clk);
    issue_ready[queue_index] = 1'b0;
  endtask

  task automatic milestone(input int unsigned queue_index);
    @(negedge clk);
    increment[queue_index] = 2'd1;
    @(negedge clk);
    increment[queue_index] = '0;
  endtask

  task automatic run_job;
    load_job();
    host_write('h018, 3);
    host_write('h004, 1);
    host_access(1'b1, 'h10080, '0, 1'b1, read_value);
    host_access(1'b0, 'h10080, '0, 1'b1, read_value);
    accept_command(0, 'h11);
    repeat (30) @(negedge clk);
    if (issue_valid[1] || issue_valid[2] || done) begin
      $fatal(1, "dependencies released before progress");
    end
    milestone(0);
    accept_command(1, 'h22);
    if (issue_valid[2]) begin
      $fatal(1, "vector dependency released before matrix milestone");
    end
    milestone(1);
    accept_command(2, 'h33);
    milestone(2);
    repeat (100) @(negedge clk);
    host_access(1'b0, 'h010, '0, 1'b0, read_value);
    if (read_value != 'h5a || done || host_irq) begin
      $fatal(1, "FINISH did not wait for engine idle result=%h", read_value);
    end
    host_access(1'b0, 'h040, '0, 1'b0, read_value);
    if (read_value != 3 || !u_dut.u_system.cpu_irq) begin
      $fatal(1, "firmware wait did not latch satisfaction");
    end
    engine_idle = '1;
    for (int cycle = 0; cycle < 300; cycle++) begin
      @(negedge clk);
      if (done) begin
        break;
      end
    end
    if (!done || !host_irq || fault) begin
      $fatal(1, "completion/interrupt missing");
    end
    host_access(1'b0, 'h010, '0, 1'b0, read_value);
    if (read_value != (inject_bad_result ? 'h5b : 'h5a)) begin
      $fatal(1, "firmware result mismatch value=%h", read_value);
    end
    host_write('h014, 1);
    if (host_irq || !done || !u_dut.u_system.run || !u_dut.u_system.core_rst_n) begin
      $fatal(1, "completion acknowledgement changed run or failed to clear IRQ");
    end
  endtask

  initial begin
    inject_bad_result = 1'b0;
    if ($value$plusargs("inject_bad_result=%d", inject_bad_result)) begin
      $display("Deliberate result corruption enabled");
    end
    reset_epoch();
    host_access(1'b0, 'h20000, '0, 1'b1, read_value);
    host_access(1'b0, 'h10081, '0, 1'b1, read_value);
    host_write('h10000, 'h11223344);
    host_be = 4'b0101;
    host_write('h10000, 'haabbccdd);
    host_be = 4'hf;
    host_access(1'b0, 'h10000, '0, 1'b0, read_value);
    if (read_value != 'h11bb33dd) begin
      $fatal(1, "RAM byte write mismatch");
    end
    run_job();
    reset_epoch();
    run_job();
    if (command_count != 6 || cpu_reads < 4) begin
      $fatal(1, "execution counts mismatch commands=%0d reads=%0d", command_count, cpu_reads);
    end
    reset_epoch();
    firmware_word = 0;
    emit(32'h500000b7);  // Invalid CPU data window.
    emit(load_word(0));
    emit(32'h0000006f);
    pad_firmware();
    host_write('h018, 2);
    host_write('h004, 1);
    for (int cycle = 0; cycle < 1000; cycle++) begin
      @(negedge clk);
      if (fault) begin
        break;
      end
    end
    if (!fault || !host_irq || done || u_dut.u_system.core_rst_n) begin
      $fatal(1, "CPU bus fault failed to halt and notify");
    end
    host_access(1'b0, 'h008, '0, 1'b0, read_value);
    if (read_value != 5) begin
      $fatal(1, "host inaccessible after fault");
    end
    reset_epoch();
    if (fault || done || host_irq) begin
      $fatal(1, "reset failed to clear epoch");
    end
    firmware_word = 0;
    emit(32'h400000b7);
    emit(32'h00100113);
    emit(store_word(0, 2));  // ABI_VERSION is read-only: halt before the following COMMIT.
    emit(store_word('h108, 2));
    emit(32'h0000006f);
    pad_firmware();
    host_write('h018, 2);
    host_write('h004, 1);
    repeat (200) @(negedge clk);
    if (!fault || !host_irq || done || u_dut.u_system.core_rst_n || issue_valid != 0 ||
        command_count != 6) begin
      $fatal(1, "CPU MMIO fault allowed a later side effect");
    end
    reset_epoch();
    firmware_word = 0;
    emit(32'h500000b7);
    emit(32'h00008067);  // jalr x0, x1, 0: invalid instruction window.
    pad_firmware();
    host_write('h018, 2);
    host_write('h004, 1);
    repeat (200) @(negedge clk);
    if (!fault || !host_irq || done || u_dut.u_system.core_rst_n) begin
      $fatal(1, "CPU instruction fault failed to halt and notify");
    end
    reset_epoch();
    host_write('h10200, 'habcdef01);
    firmware_word = 0;
    emit(32'h20000093);  // addi x1, x0, 0x200: RAM data address.
    emit(32'h00700113);
    emit(store_word(0, 2));
    emit(32'h0000006f);
    pad_firmware();
    host_write('h018, 2);
    host_write('h004, 1);
    store_seen = 1'b0;
    for (int cycle = 0; cycle < 1000; cycle++) begin
      @(negedge clk);
      if (u_dut.u_system.data_req && u_dut.u_system.data_we &&
          u_dut.u_system.data_addr == 'h200) begin
        store_seen = 1'b1;
        engine_fault[0] = 1'b1;
        #1ns;
        if (u_dut.u_system.data_gnt) begin
          $fatal(1, "engine fault did not suppress coincident RAM store");
        end
        break;
      end
    end
    if (!store_seen) begin
      $fatal(1, "fault-edge RAM store was never attempted");
    end
    repeat (4) @(negedge clk);
    if (!fault || !host_irq || u_dut.u_system.core_rst_n) begin
      $fatal(1, "engine fault failed to stop core");
    end
    reset_epoch();
    host_access(1'b0, 'h10200, '0, 1'b0, read_value);
    if (read_value != 'habcdef01) begin
      $fatal(1, "RAM store changed memory on engine fault edge");
    end
    $display("RESULT controller_system commands=%0d cpu_reads=%0d PASS", command_count, cpu_reads);
    $finish;
  end

  initial begin
    #500000ns;
    $fatal(1, "controller system test timed out");
  end
endmodule
