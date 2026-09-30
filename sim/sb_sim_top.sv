// Host-driven test wrapper. Firmware memory and MMIO servicing live in sim/sim_host.hpp.
module sb_sim_top (
  input logic clk_i, rst_ni,
  output logic instr_req_o,
  input logic instr_gnt_i, instr_rvalid_i,
  output logic [31:0] instr_addr_o,
  input logic [31:0] instr_rdata_i,
  output logic data_req_o,
  input logic data_gnt_i, data_rvalid_i,
  output logic data_we_o,
  output logic [3:0] data_be_o,
  output logic [31:0] data_addr_o, data_wdata_o,
  input logic [31:0] data_rdata_i,
  input logic cmd_valid_i,
  output logic cmd_ready_o,
  input logic [15:0] opcode_i, abi_i,
  input logic [31:0] sequence_i, context_i, m_i, n_i, k_i,
  input logic [63:0] a_addr_i, b_addr_i, c_addr_i, state_addr_i,
  input logic [31:0] a_stride_i, b_stride_i, c_stride_i, format_i,
  output logic completion_valid_o,
  input logic completion_ready_i,
  output logic [31:0] completed_sequence_o,
  output logic [7:0] status_o,
  input logic quiesce_i,
  output logic idle_o
);
  sb_control_subsystem control_subsystem (
    .clk_i, .rst_ni, .instr_req_o, .instr_gnt_i, .instr_rvalid_i,
    .instr_addr_o, .instr_rdata_i, .data_req_o, .data_gnt_i, .data_rvalid_i,
    .data_we_o, .data_be_o, .data_addr_o, .data_wdata_o, .data_rdata_i
  );
  sb_types_pkg::command_t command;
  sb_types_pkg::completion_t completion;
  always_comb begin
    command = '0;
    command.sequence_id = sequence_i; command.context_id = context_i;
    command.opcode = opcode_i; command.abi = abi_i;
    command.m = m_i; command.n = n_i; command.k = k_i;
    command.a_addr = a_addr_i; command.b_addr = b_addr_i; command.c_addr = c_addr_i;
    command.state_addr = state_addr_i; command.a_stride = a_stride_i;
    command.b_stride = b_stride_i; command.c_stride = c_stride_i; command.format_id = format_i;
  end
  sb_accelerator_top accelerator (.clk_i, .rst_ni, .quiesce_i, .idle_o,
    .cmd_valid_i, .cmd_ready_o, .cmd_i(command),
    .completion_valid_o, .completion_ready_i, .completion_o(completion));
  assign completed_sequence_o = completion.sequence_id;
  assign status_o = completion.status;
endmodule
