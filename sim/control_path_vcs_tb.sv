// Simulation-only DPI bridge. The host advances one settled phase per call.
module control_path_vcs_tb;
  timeunit 1ns; timeprecision 1ps;

  logic clk_i;
  logic rst_ni;
  logic instr_req_o;
  logic instr_gnt_i;
  logic instr_rvalid_i;
  logic [31:0] instr_addr_o;
  logic [31:0] instr_rdata_i;
  logic data_req_o;
  logic data_gnt_i;
  logic data_rvalid_i;
  logic data_we_o;
  logic [3:0] data_be_o;
  logic [31:0] data_addr_o;
  logic [31:0] data_wdata_o;
  logic [31:0] data_rdata_i;
  logic cmd_valid_i;
  logic cmd_ready_o;
  logic [15:0] opcode_i;
  logic [15:0] abi_version_i;
  logic [31:0] sequence_id_i;
  logic [31:0] context_id_i;
  logic [31:0] m_i;
  logic [31:0] n_i;
  logic [31:0] k_i;
  logic [63:0] a_addr_i;
  logic [63:0] b_addr_i;
  logic [63:0] c_addr_i;
  logic [63:0] state_addr_i;
  logic [31:0] a_stride_i;
  logic [31:0] b_stride_i;
  logic [31:0] c_stride_i;
  logic [31:0] format_id_i;
  logic completion_valid_o;
  logic completion_ready_i;
  logic [31:0] completed_sequence_id_o;
  logic [7:0] completion_status_o;
  logic quiesce_i;
  logic idle_o;
  string firmware;
  string model;
  int latency;
  int grant_period;
  int status;

  import "DPI-C" context task run_probe(
    input string firmware,
    input string model,
    input int latency,
    input int grant_period,
    output int status
  );
  export "DPI-C" task sim_eval;

  task automatic sim_eval(input bit [959:0] inputs, output logic [383:0] outputs);
    clk_i = inputs[0+:1];
    rst_ni = inputs[32+:1];
    instr_gnt_i = inputs[64+:1];
    instr_rvalid_i = inputs[96+:1];
    instr_rdata_i = inputs[128+:32];
    data_gnt_i = inputs[160+:1];
    data_rvalid_i = inputs[192+:1];
    data_rdata_i = inputs[224+:32];
    cmd_valid_i = inputs[256+:1];
    opcode_i = inputs[288+:16];
    abi_version_i = inputs[320+:16];
    sequence_id_i = inputs[352+:32];
    context_id_i = inputs[384+:32];
    m_i = inputs[416+:32];
    n_i = inputs[448+:32];
    k_i = inputs[480+:32];
    a_addr_i = inputs[512+:64];
    b_addr_i = inputs[576+:64];
    c_addr_i = inputs[640+:64];
    state_addr_i = inputs[704+:64];
    a_stride_i = inputs[768+:32];
    b_stride_i = inputs[800+:32];
    c_stride_i = inputs[832+:32];
    format_id_i = inputs[864+:32];
    completion_ready_i = inputs[896+:1];
    quiesce_i = inputs[928+:1];
    #1ns;
    outputs = '0;
    outputs[0+:1] = instr_req_o;
    outputs[32+:32] = instr_addr_o;
    outputs[64+:1] = data_req_o;
    outputs[96+:1] = data_we_o;
    outputs[128+:4] = data_be_o;
    outputs[160+:32] = data_addr_o;
    outputs[192+:32] = data_wdata_o;
    outputs[224+:1] = cmd_ready_o;
    outputs[256+:1] = completion_valid_o;
    outputs[288+:32] = completed_sequence_id_o;
    outputs[320+:8] = completion_status_o;
    outputs[352+:1] = idle_o;
  endtask

  control_path_sim_top u_control_path (
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
    .data_rdata_i,
    .cmd_valid_i,
    .cmd_ready_o,
    .opcode_i,
    .abi_version_i,
    .sequence_id_i,
    .context_id_i,
    .m_i,
    .n_i,
    .k_i,
    .a_addr_i,
    .b_addr_i,
    .c_addr_i,
    .state_addr_i,
    .a_stride_i,
    .b_stride_i,
    .c_stride_i,
    .format_id_i,
    .completion_valid_o,
    .completion_ready_i,
    .completed_sequence_id_o,
    .completion_status_o,
    .quiesce_i,
    .idle_o
  );

  initial begin
    if (!$value$plusargs("firmware=%s", firmware)) begin
      $fatal(1, "Missing +firmware=<binary>");
    end
    if (!$value$plusargs("model=%s", model)) begin
      model = "";
    end
    if (!$value$plusargs("latency=%d", latency)) begin
      latency = 1;
    end
    if (!$value$plusargs("grant_period=%d", grant_period)) begin
      grant_period = 1;
    end
    run_probe(firmware, model, latency, grant_period, status);
    if (status != 0) begin
      $fatal(1, "Host probe failed with status %0d", status);
    end
    $finish;
  end
endmodule
