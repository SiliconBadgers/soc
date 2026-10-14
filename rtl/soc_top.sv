// Synthesizable prototype: existing RISC-V, HLS memory/register service and INT8 array.
// The host loads firmware through this bus while cpu_enable_i is low.
module soc_top (
  input logic clk_i,
  input logic rst_ni,
  input logic cpu_enable_i,
  input logic host_req_i,
  output logic host_gnt_o,
  input logic host_we_i,
  input logic [31:0] host_addr_i,
  input logic [31:0] host_wdata_i,
  input logic [3:0] host_be_i,
  output logic host_rvalid_o,
  output logic [31:0] host_rdata_o,
  output logic host_error_o,
  input logic [31:0] response_delay_i,
  input logic [31:0] grant_period_i,
  input logic quiesce_i,
  output logic initialized_o,
  output logic cpu_fault_o,
  output logic cmd_accepted_o,
  output logic completion_valid_o,
  output logic completion_accepted_o,
  output logic matrix_column_o,
  output logic matrix_read_o,
  output logic matrix_write_o,
  output logic idle_o
);
  import command_pkg::*;
  logic [3:0] req, gnt, we, rvalid;
  logic [3:0][31:0] addr, wdata;
  logic [3:0][3:0] be;
  logic [31:0] rdata;
  logic error;
  logic cmd_valid, cmd_ready, completion_ready;
  command_t command;
  completion_t completion;
  logic [NUM_ROUTES-1:0] request_valid, request_ready, response_valid, response_ready;
  completion_t responses[NUM_ROUTES];
  assign host_gnt_o = gnt[3];
  assign host_rvalid_o = rvalid[3];
  assign host_rdata_o = rdata;
  assign host_error_o = error;
  assign req[3] = host_req_i;
  assign we[3] = host_we_i;
  assign addr[3] = host_addr_i;
  assign wdata[3] = host_wdata_i;
  assign be[3] = host_be_i;
  assign we[0] = 1'b0;
  assign wdata[0] = '0;
  assign be[0] = 4'hf;
  assign be[2] = 4'hf;
  assign cmd_accepted_o = cmd_valid && cmd_ready;
  assign completion_accepted_o = completion_valid_o && completion_ready;
  assign matrix_read_o = rvalid[2] && !we[2] && !error;
  assign matrix_write_o = rvalid[2] && we[2] && !error;
  // CV32E40P's selected bus has no error input. Halt either CPU on a bus fault;
  // the host observes cpu_fault_o and must reset/reload before continuing.
  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) cpu_fault_o <= 1'b0;
    else if (error && |rvalid[1:0]) cpu_fault_o <= 1'b1;
  end
  riscv_wrapper u_riscv (
    .clk_i,
    .rst_ni(rst_ni && cpu_enable_i && initialized_o && !cpu_fault_o),
    .instr_req_o(req[0]),
    .instr_gnt_i(gnt[0]),
    .instr_rvalid_i(rvalid[0]),
    .instr_addr_o(addr[0]),
    .instr_rdata_i(rdata),
    .data_req_o(req[1]),
    .data_gnt_i(gnt[1]),
    .data_rvalid_i(rvalid[1]),
    .data_we_o(we[1]),
    .data_be_o(be[1]),
    .data_addr_o(addr[1]),
    .data_wdata_o(wdata[1]),
    .data_rdata_i(rdata)
  );
  platform_bus u_platform_bus (
    .clk_i,
    .rst_ni,
    .req_i(req),
    .gnt_o(gnt),
    .we_i(we),
    .addr_i(addr),
    .wdata_i(wdata),
    .be_i(be),
    .rvalid_o(rvalid),
    .rdata_o(rdata),
    .error_o(error),
    .response_delay_i,
    .grant_period_i,
    .initialized_o,
    .router_idle_i(idle_o),
    .cmd_valid_o(cmd_valid),
    .cmd_ready_i(cmd_ready),
    .cmd_o(command),
    .completion_valid_i(completion_valid_o),
    .completion_ready_o(completion_ready),
    .completion_i(completion)
  );
  command_router u_command_router (
    .clk_i,
    .rst_ni,
    .quiesce_i,
    .idle_o,
    .cmd_valid_i(cmd_valid),
    .cmd_ready_o(cmd_ready),
    .cmd_i(command),
    .completion_valid_o,
    .completion_ready_i(completion_ready),
    .completion_o(completion),
    .request_valid_o(request_valid),
    .request_ready_i(request_ready),
    .response_valid_i(response_valid),
    .response_ready_o(response_ready),
    .responses_i(responses)
  );
  matrix_memory_adapter u_matrix (
    .clk_i,
    .rst_ni,
    .cmd_i(command),
    .cmd_valid_i(request_valid[RouteMatrix]),
    .cmd_ready_o(request_ready[RouteMatrix]),
    .completion_valid_o(response_valid[RouteMatrix]),
    .completion_ready_i(response_ready[RouteMatrix]),
    .completion_o(responses[RouteMatrix]),
    .mem_req_o(req[2]),
    .mem_gnt_i(gnt[2]),
    .mem_we_o(we[2]),
    .mem_addr_o(addr[2]),
    .mem_wdata_o(wdata[2]),
    .mem_rvalid_i(rvalid[2]),
    .mem_rdata_i(rdata),
    .mem_error_i(error),
    .column_accepted_o(matrix_column_o)
  );
  for (genvar route = 1; route < NUM_ROUTES; route++) begin : g_unsupported
    command_error_endpoint #(
      .ReturnStatus(route == int'(RouteInvalid) ? StatusBadCommand : StatusUnimplemented)
    ) u_endpoint (
      .clk_i,
      .rst_ni,
      .cmd_i(command),
      .cmd_valid_i(request_valid[route]),
      .cmd_ready_o(request_ready[route]),
      .completion_valid_o(response_valid[route]),
      .completion_ready_i(response_ready[route]),
      .completion_o(responses[route])
    );
  end
endmodule
