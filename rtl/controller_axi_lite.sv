// AXI4-Lite transport for the controller's registered native host port.
module controller_axi_lite (
  input logic clk_i,
  input logic rst_ni,
  input logic [31:0] awaddr_i,
  input logic awvalid_i,
  output logic awready_o,
  input logic [31:0] wdata_i,
  input logic [3:0] wstrb_i,
  input logic wvalid_i,
  output logic wready_o,
  output logic [1:0] bresp_o,
  output logic bvalid_o,
  input logic bready_i,
  input logic [31:0] araddr_i,
  input logic arvalid_i,
  output logic arready_o,
  output logic [31:0] rdata_o,
  output logic [1:0] rresp_o,
  output logic rvalid_o,
  input logic rready_i,
  output logic host_req_o,
  input logic host_gnt_i,
  output logic host_we_o,
  output logic [31:0] host_addr_o,
  output logic [31:0] host_wdata_o,
  output logic [3:0] host_be_o,
  input logic host_rvalid_i,
  input logic [31:0] host_rdata_i,
  input logic host_error_i
);
  typedef enum logic [2:0] {
    Idle,
    ReadRequest,
    WriteRequest,
    ReadResponse,
    WriteResponse
  } state_e;
  state_e state_q;
  logic aw_pending_q;
  logic w_pending_q;
  logic ar_pending_q;
  logic prefer_write_q;
  logic [31:0] awaddr_q;
  logic [31:0] wdata_q;
  logic [3:0] wstrb_q;
  logic [31:0] araddr_q;

  assign awready_o = rst_ni && !aw_pending_q && !bvalid_o &&
      state_q != WriteRequest && state_q != WriteResponse;
  assign wready_o = rst_ni && !w_pending_q && !bvalid_o &&
      state_q != WriteRequest && state_q != WriteResponse;
  assign arready_o = rst_ni && !ar_pending_q && !rvalid_o &&
      state_q != ReadRequest && state_q != ReadResponse;
  assign host_req_o = rst_ni && (state_q == ReadRequest || state_q == WriteRequest);
  assign host_we_o = state_q == WriteRequest;
  assign host_addr_o = host_we_o ? awaddr_q : araddr_q;
  assign host_wdata_o = host_we_o ? wdata_q : '0;
  assign host_be_o = host_we_o ? wstrb_q : 4'hf;

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      state_q <= Idle;
      aw_pending_q <= 1'b0;
      w_pending_q <= 1'b0;
      ar_pending_q <= 1'b0;
      prefer_write_q <= 1'b1;
      awaddr_q <= '0;
      wdata_q <= '0;
      wstrb_q <= '0;
      araddr_q <= '0;
      bvalid_o <= 1'b0;
      bresp_o <= '0;
      rvalid_o <= 1'b0;
      rresp_o <= '0;
      rdata_o <= '0;
    end else begin
      if (awvalid_i && awready_o) begin
        aw_pending_q <= 1'b1;
        awaddr_q <= awaddr_i;
      end
      if (wvalid_i && wready_o) begin
        w_pending_q <= 1'b1;
        wdata_q <= wdata_i;
        wstrb_q <= wstrb_i;
      end
      if (arvalid_i && arready_o) begin
        ar_pending_q <= 1'b1;
        araddr_q <= araddr_i;
      end
      if (bvalid_o && bready_i) begin
        bvalid_o <= 1'b0;
      end
      if (rvalid_o && rready_i) begin
        rvalid_o <= 1'b0;
      end
      case (state_q)
        Idle: begin
          if (aw_pending_q && w_pending_q && (!ar_pending_q || prefer_write_q)) begin
            state_q <= WriteRequest;
          end else if (ar_pending_q) begin
            state_q <= ReadRequest;
          end
        end
        WriteRequest: begin
          if (host_gnt_i) begin
            aw_pending_q <= 1'b0;
            w_pending_q <= 1'b0;
            prefer_write_q <= 1'b0;
            state_q <= WriteResponse;
          end
        end
        ReadRequest: begin
          if (host_gnt_i) begin
            ar_pending_q <= 1'b0;
            prefer_write_q <= 1'b1;
            state_q <= ReadResponse;
          end
        end
        WriteResponse: begin
          if (host_rvalid_i) begin
            bvalid_o <= 1'b1;
            bresp_o  <= host_error_i ? 2'b10 : 2'b00;
            state_q  <= Idle;
          end
        end
        ReadResponse: begin
          if (host_rvalid_i) begin
            rvalid_o <= 1'b1;
            rresp_o  <= host_error_i ? 2'b10 : 2'b00;
            rdata_o  <= host_rdata_i;
            state_q  <= Idle;
          end
        end
        default: state_q <= Idle;
      endcase
    end
  end

  HostRequestStable_A :
  assert property (
    @(posedge clk_i) disable iff (!rst_ni)
    host_req_o && !host_gnt_i |=> host_req_o &&
      $stable(
    {host_we_o, host_addr_o, host_wdata_o, host_be_o}
  ))
  else $fatal(1, "Stalled native host request changed");
  WriteResponseStable_A :
  assert property (
    @(posedge clk_i) disable iff (!rst_ni)
    bvalid_o && !bready_i |=> bvalid_o && $stable(
    bresp_o
  ))
  else $fatal(1, "Stalled AXI write response changed");
  ReadResponseStable_A :
  assert property (
    @(posedge clk_i) disable iff (!rst_ni)
    rvalid_o && !rready_i |=> rvalid_o && $stable(
    {rdata_o, rresp_o}
  ))
  else $fatal(1, "Stalled AXI read response changed");
endmodule
