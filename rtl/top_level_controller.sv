// AWS OCL-facing controller assembly. Unit channels share clk_i and rst_ni.
module top_level_controller #(
  parameter int unsigned RamWords = 4096,
  parameter int unsigned QueueDepth = 4,
  parameter int unsigned PayloadWidth = 128,
  parameter int unsigned CounterWidth = 16
) (
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
  output logic [2:0] issue_valid_o,
  input logic [2:0] issue_ready_i,
  output logic [2:0][PayloadWidth-1:0] issue_payload_o,
  input logic [2:0][1:0] increment_i,
  input logic [2:0] engine_idle_i,
  input logic [2:0] engine_fault_i,
  output logic host_irq_o,
  output logic done_o,
  output logic fault_o
);
  logic host_req;
  logic host_gnt;
  logic host_we;
  logic [31:0] host_addr;
  logic [31:0] host_wdata;
  logic [3:0] host_be;
  logic host_rvalid;
  logic [31:0] host_rdata;
  logic host_error;

  controller_axi_lite u_host_transport (
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
    .host_req_o(host_req),
    .host_gnt_i(host_gnt),
    .host_we_o(host_we),
    .host_addr_o(host_addr),
    .host_wdata_o(host_wdata),
    .host_be_o(host_be),
    .host_rvalid_i(host_rvalid),
    .host_rdata_i(host_rdata),
    .host_error_i(host_error)
  );

  controller_system #(
    .RamWords(RamWords),
    .QueueDepth(QueueDepth),
    .PayloadWidth(PayloadWidth),
    .CounterWidth(CounterWidth)
  ) u_system (
    .clk_i,
    .rst_ni,
    .host_req_i(host_req),
    .host_gnt_o(host_gnt),
    .host_we_i(host_we),
    .host_addr_i(host_addr),
    .host_wdata_i(host_wdata),
    .host_be_i(host_be),
    .host_rvalid_o(host_rvalid),
    .host_rdata_o(host_rdata),
    .host_error_o(host_error),
    .issue_valid_o,
    .issue_ready_i,
    .issue_payload_o,
    .increment_i,
    .engine_idle_i,
    .engine_fault_i,
    .host_irq_o,
    .done_o,
    .fault_o
  );
endmodule
