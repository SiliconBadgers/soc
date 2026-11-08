module controller_axi_lite_tb;
  timeunit 1ns; timeprecision 1ps;
  logic clk_i = 1'b0;
  logic rst_ni = 1'b0;
  logic [31:0] awaddr_i, wdata_i, araddr_i;
  logic [3:0] wstrb_i;
  logic awvalid_i, awready_o, wvalid_i, wready_o, bvalid_o, bready_i;
  logic arvalid_i, arready_o, rvalid_o, rready_i;
  logic [1:0] bresp_o, rresp_o;
  logic [31:0] rdata_o;
  logic host_req_o, host_gnt_i, host_we_o, host_rvalid_i, host_error_i;
  logic [31:0] host_addr_o, host_wdata_o, host_rdata_i;
  logic [3:0] host_be_o;
  int grant_delay;
  int transfers;
  int stalls;
  int resets;
  int missing_reset;
  int missing_stall;
  int wrong_result;
  logic [31:0] held_data;
  logic [1:0] held_response;

  always #5ns clk_i = ~clk_i;
  controller_axi_lite u_dut (
    .clk_i,
    .rst_ni,
    .awaddr_i,
    .awvalid_i,
    .awready_o,
    .wdata_i,
    .wstrb_i,
    .wvalid_i,
    .wready_o,
    .bresp_o,
    .bvalid_o,
    .bready_i,
    .araddr_i,
    .arvalid_i,
    .arready_o,
    .rdata_o,
    .rresp_o,
    .rvalid_o,
    .rready_i,
    .host_req_o,
    .host_gnt_i,
    .host_we_o,
    .host_addr_o,
    .host_wdata_o,
    .host_be_o,
    .host_rvalid_i,
    .host_rdata_i,
    .host_error_i
  );

  assign host_gnt_i = rst_ni && host_req_o && (missing_stall != 0 || grant_delay >= 4);
  always @(posedge clk_i) begin
    if (!rst_ni) begin
      host_rvalid_i <= 1'b0;
      host_rdata_i  <= '0;
      host_error_i  <= 1'b0;
      grant_delay   <= 0;
    end else begin
      host_rvalid_i <= host_req_o && host_gnt_i;
      if (host_req_o && !host_gnt_i) begin
        grant_delay <= grant_delay + 1;
        stalls <= stalls + 1;
      end else begin
        grant_delay <= 0;
      end
      if (host_req_o && host_gnt_i) begin
        transfers <= transfers + 1;
        host_error_i <= host_addr_o[12];
        host_rdata_i <= host_addr_o ^ 32'h5a5a00ff;
        if (host_we_o && (host_wdata_o != (host_addr_o ^ 32'h12345678) || host_be_o != 4'h5)) begin
          $fatal(1, "AXI write fields did not remain paired");
        end
      end
    end
  end

  task automatic send_address(input logic [31:0] address);
    @(negedge clk_i);
    awaddr_i  = address;
    awvalid_i = 1'b1;
    do @(posedge clk_i); while (!awready_o);
    @(negedge clk_i);
    awvalid_i = 1'b0;
    awaddr_i  = '1;
  endtask

  task automatic send_data(input logic [31:0] address);
    @(negedge clk_i);
    wdata_i  = address ^ 32'h12345678;
    wstrb_i  = 4'h5;
    wvalid_i = 1'b1;
    do @(posedge clk_i); while (!wready_o);
    @(negedge clk_i);
    wvalid_i = 1'b0;
    wdata_i  = '1;
    wstrb_i  = '0;
  endtask

  task automatic write_word(input logic [31:0] address, input int separation);
    fork
      begin
        if (separation < 0) repeat (-separation) @(negedge clk_i);
        send_address(address);
      end
      begin
        if (separation > 0) repeat (separation) @(negedge clk_i);
        send_data(address);
      end
    join
    wait (bvalid_o);
    @(negedge clk_i);
    held_response = bresp_o;
    if (held_response !== (address[12] ? 2'b10 : 2'b00)) begin
      $fatal(1, "AXI write error response mismatch");
    end
    repeat (4) begin
      @(negedge clk_i);
      if (!bvalid_o || bresp_o !== held_response) begin
        $fatal(1, "AXI write response changed under backpressure");
      end
    end
    bready_i = 1'b1;
    @(negedge clk_i);
    bready_i = 1'b0;
  endtask

  task automatic read_word(input logic [31:0] address);
    @(negedge clk_i);
    araddr_i  = address;
    arvalid_i = 1'b1;
    do @(posedge clk_i); while (!arready_o);
    @(negedge clk_i);
    arvalid_i = 1'b0;
    araddr_i  = '1;
    wait (rvalid_o);
    @(negedge clk_i);
    held_data = rdata_o;
    if (rdata_o !== (address ^ 32'h5a5a00ff ^ 32'(wrong_result)) ||
        rresp_o !== (address[12] ? 2'b10 : 2'b00)) begin
      $fatal(1, "WRONG_RESULT AXI read mismatch");
    end
    repeat (4) begin
      @(negedge clk_i);
      if (!rvalid_o || rdata_o !== held_data || rresp_o !== (address[12] ? 2'b10 : 2'b00)) begin
        $fatal(1, "AXI read response changed under backpressure");
      end
    end
    rready_i = 1'b1;
    @(negedge clk_i);
    rready_i = 1'b0;
  endtask

  initial begin
    awaddr_i = '0;
    wdata_i = '0;
    araddr_i = '0;
    wstrb_i = '0;
    awvalid_i = 1'b0;
    wvalid_i = 1'b0;
    arvalid_i = 1'b0;
    bready_i = 1'b0;
    rready_i = 1'b0;
    transfers = 0;
    stalls = 0;
    resets = 0;
    missing_reset = 0;
    missing_stall = 0;
    wrong_result = 0;
    void'($value$plusargs("missing_reset=%d", missing_reset));
    void'($value$plusargs("missing_stall=%d", missing_stall));
    void'($value$plusargs("wrong_result=%d", wrong_result));
    repeat (3) @(negedge clk_i);
    rst_ni = 1'b1;
    // Exercise address-before-data, data-before-address, and simultaneous traffic.
    for (int n = 0; n < 12; n++) begin
      fork
        write_word(32'h200 + 32'(n * 4), (n % 3 - 1) * 3);
        read_word(32'h400 + 32'(n * 4));
      join
    end
    write_word(32'h1000, 2);
    read_word(32'h1004);
    if (missing_reset == 0) begin
      send_address(32'h700);
      if (!u_dut.aw_pending_q || u_dut.w_pending_q) begin
        $fatal(1, "MISSING_RESET expected partial write before reset");
      end
      rst_ni = 1'b0;
      resets++;
      repeat (3) @(negedge clk_i);
      if (bvalid_o || rvalid_o || host_req_o) begin
        $fatal(1, "Reset retained an AXI transaction");
      end
      rst_ni = 1'b1;
      write_word(32'h704, -2);
      read_word(32'h708);
    end
    if (resets != 1) $fatal(1, "MISSING_RESET");
    if (stalls == 0) $fatal(1, "MISSING_STALL");
    if (transfers != (missing_reset == 0 ? 28 : 26)) $fatal(1, "Transfer count mismatch");
    $display("RESULT controller_axi_lite transfers=%0d stalls=%0d resets=%0d PASS", transfers,
             stalls, resets);
    $finish;
  end
  initial begin
    #100us;
    $fatal(1, "AXI_TIMEOUT");
  end
endmodule
