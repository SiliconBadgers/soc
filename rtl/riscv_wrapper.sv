// Existing cores behind the same uncached instruction/data boundary.
module riscv_wrapper (
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
  input logic [31:0] data_rdata_i
);
`ifdef USE_CV32E40P
  cv32e40p_top #(
    .COREV_PULP(0),
    .COREV_CLUSTER(0),
    .FPU(0)
  ) u_core (
    .clk_i,
    .rst_ni,
    .hart_id_i(32'b0),
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
    .data_rdata_i,
    .boot_addr_i(32'h80),
    .pulp_clock_en_i(1'b1),
    .scan_cg_en_i(1'b0),
    .mtvec_addr_i(32'h0),
    .dm_halt_addr_i(32'h0),
    .dm_exception_addr_i(32'h0),
    .irq_i(32'h0),
    .debug_req_i(1'b0),
    .fetch_enable_i(1'b1),
    // Unused status/debug/cache outputs in this uncached simulation configuration.
    .irq_ack_o(),
    .irq_id_o(),
    .debug_havereset_o(),
    .debug_running_o(),
    .debug_halted_o(),
    .core_sleep_o()
  );
`else
  import ibex_pkg::*;
  logic [4:0] rf_read_addr_a;
  logic [4:0] rf_read_addr_b;
  logic [4:0] rf_write_addr;
  logic [31:0] rf_read_data_a;
  logic [31:0] rf_read_data_b;
  logic [31:0] rf_write_data;
  logic rf_write_enable;
  logic dummy_instr_id;
  logic dummy_instr_wb;
  logic [ibex_cheriot_pkg::REGCAP_W-1:0] rf_read_cap_a;
  logic [ibex_cheriot_pkg::REGCAP_W-1:0] rf_read_cap_b;
  logic [ibex_cheriot_pkg::REGCAP_W-1:0] rf_write_cap;
  ibex_register_file_ff u_register_file (
    .clk_i,
    .rst_ni,
    .test_en_i(1'b0),
    .cheriot_enable_i(IbexMuBiOff),
    .dummy_instr_id_i(dummy_instr_id),
    .dummy_instr_wb_i(dummy_instr_wb),
    .raddr_a_i(rf_read_addr_a),
    .raddr_b_i(rf_read_addr_b),
    .rdata_a_o(rf_read_data_a),
    .rdata_b_o(rf_read_data_b),
    .rcap_a_o(rf_read_cap_a),
    .rcap_b_o(rf_read_cap_b),
    .wcap_a_i(rf_write_cap),
    .waddr_a_i(rf_write_addr),
    .wdata_a_i(rf_write_data),
    .we_a_i(rf_write_enable)
  );
  ibex_core #(
    .RV32M(RV32MFast),
    .RV32B(RV32BNone),
    .ICache(0),
    .PMPEnable(0),
    .SecureIbex(0),
    .WritebackStage(0)
  ) u_core (
    .clk_i,
    .rst_ni,
    .hart_id_i(32'b0),
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
    .data_rdata_i,
    .boot_addr_i(32'h0),
    .cheriot_enable_i(IbexMuBiOff),
    .instr_err_i(1'b0),
    .data_err_i(1'b0),
    .data_tag_i(1'b0),
    .dummy_instr_id_o(dummy_instr_id),
    .dummy_instr_wb_o(dummy_instr_wb),
    .rf_raddr_a_o(rf_read_addr_a),
    .rf_raddr_b_o(rf_read_addr_b),
    .rf_waddr_wb_o(rf_write_addr),
    .rf_we_wb_o(rf_write_enable),
    .rf_wdata_wb_ecc_o(rf_write_data),
    .rf_rdata_a_ecc_i(rf_read_data_a),
    .rf_rdata_b_ecc_i(rf_read_data_b),
    .rf_wcap_ecc_wb_o(rf_write_cap),
    .rf_rcap_a_ecc_i(rf_read_cap_a),
    .rf_rcap_b_ecc_i(rf_read_cap_b),
    .ic_tag_rdata_i('{default: '0}),
    .ic_data_rdata_i('{default: '0}),
    .ic_scr_key_valid_i(1'b0),
    .irq_software_i(1'b0),
    .irq_timer_i(1'b0),
    .irq_external_i(1'b0),
    .irq_fast_i(15'b0),
    .irq_nm_i(1'b0),
    .debug_req_i(1'b0),
    .fetch_enable_i(IbexMuBiOn),
    .mcounteren_writable_i(IbexMuBiOff),
    // Unused status/debug/cache outputs in this uncached simulation configuration.
    .data_tag_o(),
    .ic_tag_req_o(),
    .ic_tag_write_o(),
    .ic_tag_addr_o(),
    .ic_tag_wdata_o(),
    .ic_data_req_o(),
    .ic_data_write_o(),
    .ic_data_addr_o(),
    .ic_data_wdata_o(),
    .ic_scr_key_req_o(),
    .irq_pending_o(),
    .crash_dump_o(),
    .double_fault_seen_o(),
    .alert_minor_o(),
    .alert_major_internal_o(),
    .alert_major_bus_o(),
    .core_busy_o()
  );
`endif
endmodule
