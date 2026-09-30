// Existing cores behind the same uncached instruction/data boundary.
module sb_control_subsystem (
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
  input logic [31:0] data_rdata_i
);
`ifdef SB_CV32E40P
  cv32e40p_top #(.COREV_PULP(0), .COREV_CLUSTER(0), .FPU(0)) core (
    .clk_i, .rst_ni, .hart_id_i(32'b0),
    .instr_req_o, .instr_gnt_i, .instr_rvalid_i, .instr_addr_o, .instr_rdata_i,
    .data_req_o, .data_gnt_i, .data_rvalid_i, .data_we_o, .data_be_o,
    .data_addr_o, .data_wdata_o, .data_rdata_i, .boot_addr_i(32'h80),
    .pulp_clock_en_i(1'b1), .scan_cg_en_i(1'b0), .mtvec_addr_i(32'h0),
    .dm_halt_addr_i(32'h0), .dm_exception_addr_i(32'h0), .irq_i(32'h0),
    .debug_req_i(1'b0), .fetch_enable_i(1'b1)
  );
`else
  import ibex_pkg::*;
  logic [4:0] ra, rb, rw;
  logic [31:0] da, db, dw;
  logic we, dummy_id, dummy_wb;
  logic [ibex_cheriot_pkg::REGCAP_W-1:0] ca, cb, cw;
  ibex_register_file_ff rf (
    .clk_i, .rst_ni, .test_en_i(1'b0), .cheriot_enable_i(IbexMuBiOff),
    .dummy_instr_id_i(dummy_id), .dummy_instr_wb_i(dummy_wb),
    .raddr_a_i(ra), .raddr_b_i(rb), .rdata_a_o(da), .rdata_b_o(db),
    .rcap_a_o(ca), .rcap_b_o(cb), .wcap_a_i(cw),
    .waddr_a_i(rw), .wdata_a_i(dw), .we_a_i(we)
  );
  ibex_core #(.RV32M(RV32MFast), .RV32B(RV32BNone), .ICache(0),
    .PMPEnable(0), .SecureIbex(0), .WritebackStage(0)) core (
    .clk_i, .rst_ni, .hart_id_i(32'b0),
    .instr_req_o, .instr_gnt_i, .instr_rvalid_i, .instr_addr_o, .instr_rdata_i,
    .data_req_o, .data_gnt_i, .data_rvalid_i, .data_we_o, .data_be_o,
    .data_addr_o, .data_wdata_o, .data_rdata_i, .boot_addr_i(32'h0),
    .cheriot_enable_i(IbexMuBiOff), .instr_err_i(1'b0), .data_err_i(1'b0),
    .data_tag_i(1'b0), .dummy_instr_id_o(dummy_id), .dummy_instr_wb_o(dummy_wb),
    .rf_raddr_a_o(ra), .rf_raddr_b_o(rb), .rf_waddr_wb_o(rw), .rf_we_wb_o(we),
    .rf_wdata_wb_ecc_o(dw), .rf_rdata_a_ecc_i(da), .rf_rdata_b_ecc_i(db),
    .rf_wcap_ecc_wb_o(cw), .rf_rcap_a_ecc_i(ca), .rf_rcap_b_ecc_i(cb),
    .ic_tag_rdata_i('{default:'0}), .ic_data_rdata_i('{default:'0}),
    .ic_scr_key_valid_i(1'b0), .irq_software_i(1'b0), .irq_timer_i(1'b0),
    .irq_external_i(1'b0), .irq_fast_i(15'b0), .irq_nm_i(1'b0),
    .debug_req_i(1'b0), .fetch_enable_i(IbexMuBiOn), .mcounteren_writable_i(IbexMuBiOff)
  );
`endif
endmodule
