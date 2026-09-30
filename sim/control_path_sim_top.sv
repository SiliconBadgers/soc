// Host-driven test wrapper. Firmware memory and MMIO servicing live in sim/sim_host.hpp.
module control_path_sim_top (
  input logic clk_i,
  input logic rst_ni,
  output logic instr_req_o,
  input logic instr_gnt_i,
  input logic instr_rvalid_i,
  output logic [31:0] instr_addr_o,
  input logic [31:0] instr_rdata_i,
  output logic data_req_o,
  input logic data_gnt_i,
  input logic data_rvalid_i,
  output logic data_we_o,
  output logic [3:0] data_be_o,
  output logic [31:0] data_addr_o,
  output logic [31:0] data_wdata_o,
  input logic [31:0] data_rdata_i,
  input logic cmd_valid_i,
  output logic cmd_ready_o,
  input logic [15:0] opcode_i,
  input logic [15:0] abi_version_i,
  input logic [31:0] sequence_id_i,
  input logic [31:0] context_id_i,
  input logic [31:0] m_i,
  input logic [31:0] n_i,
  input logic [31:0] k_i,
  input logic [63:0] a_addr_i,
  input logic [63:0] b_addr_i,
  input logic [63:0] c_addr_i,
  input logic [63:0] state_addr_i,
  input logic [31:0] a_stride_i,
  input logic [31:0] b_stride_i,
  input logic [31:0] c_stride_i,
  input logic [31:0] format_id_i,
  output logic completion_valid_o,
  input logic completion_ready_i,
  output logic [31:0] completed_sequence_id_o,
  output logic [7:0] completion_status_o,
  input logic quiesce_i,
  output logic idle_o
);
  command_pkg::command_t command;
  command_pkg::completion_t completion;

  riscv_wrapper u_riscv (
    .clk_i,
    .rst_ni,
    .instr_req_o,
    .instr_gnt_i,
    .instr_rvalid_i,
    .instr_addr_o,
    .instr_rdata_i,
    .data_req_o,
    .data_gnt_i,
    .data_rvalid_i,
    .data_we_o,
    .data_be_o,
    .data_addr_o,
    .data_wdata_o,
    .data_rdata_i
  );
  always_comb begin
    command = '0;
    command.sequence_id = sequence_id_i;
    command.context_id = context_id_i;
    command.opcode = opcode_i;
    command.abi_version = abi_version_i;
    command.m = m_i;
    command.n = n_i;
    command.k = k_i;
    command.a_addr = a_addr_i;
    command.b_addr = b_addr_i;
    command.c_addr = c_addr_i;
    command.state_addr = state_addr_i;
    command.a_stride = a_stride_i;
    command.b_stride = b_stride_i;
    command.c_stride = c_stride_i;
    command.format_id = format_id_i;
  end
  command_router_test_top u_command_router_test (
    .clk_i,
    .rst_ni,
    .quiesce_i,
    .idle_o,
    .cmd_valid_i,
    .cmd_ready_o,
    .cmd_i(command),
    .completion_valid_o,
    .completion_ready_i,
    .completion_o(completion)
  );
  assign completed_sequence_id_o = completion.sequence_id;
  assign completion_status_o = completion.status;
endmodule
