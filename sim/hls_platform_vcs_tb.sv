// DPI crosses only the external host bus; all device behavior is RTL.
module hls_platform_vcs_tb;
  timeunit 1ns; timeprecision 1ps;
  logic clk_i;
  logic rst_ni;
  logic cpu_enable_i;
  logic host_req_i;
  logic host_we_i;
  logic [31:0] host_addr_i;
  logic [31:0] host_wdata_i;
  logic [3:0] host_be_i;
  logic [31:0] response_delay_i;
  logic [31:0] grant_period_i;
  logic quiesce_i;
  logic host_gnt_o;
  logic host_rvalid_o;
  logic [31:0] host_rdata_o;
  logic host_error_o;
  logic initialized_o;
  logic cpu_fault_o;
  logic cmd_accepted_o;
  logic completion_valid_o;
  logic completion_accepted_o;
  logic matrix_column_o;
  logic matrix_read_o;
  logic matrix_write_o;
  logic idle_o;
  string firmware, model;
  int latency, grant_period, status;
  import "DPI-C" context task run_probe(
    input string firmware,
    input string model,
    input int latency,
    input int grant_period,
    output int status
  );
  export "DPI-C" task sim_eval;
  task automatic sim_eval(input bit [351:0] inputs, output logic [415:0] outputs);
    clk_i = inputs[0+:1];
    rst_ni = inputs[32+:1];
    cpu_enable_i = inputs[64+:1];
    host_req_i = inputs[96+:1];
    host_we_i = inputs[128+:1];
    host_addr_i = inputs[160+:32];
    host_wdata_i = inputs[192+:32];
    host_be_i = inputs[224+:4];
    response_delay_i = inputs[256+:32];
    grant_period_i = inputs[288+:32];
    quiesce_i = inputs[320+:1];
    #1ns;
    outputs = '0;
    outputs[0+:1] = host_gnt_o;
    outputs[32+:1] = host_rvalid_o;
    outputs[64+:32] = host_rdata_o;
    outputs[96+:1] = host_error_o;
    outputs[128+:1] = initialized_o;
    outputs[160+:1] = cpu_fault_o;
    outputs[192+:1] = cmd_accepted_o;
    outputs[224+:1] = completion_valid_o;
    outputs[256+:1] = completion_accepted_o;
    outputs[288+:1] = matrix_column_o;
    outputs[320+:1] = matrix_read_o;
    outputs[352+:1] = matrix_write_o;
    outputs[384+:1] = idle_o;
  endtask
  soc_top u_soc (
    .clk_i,
    .rst_ni,
    .cpu_enable_i,
    .host_req_i,
    .host_we_i,
    .host_addr_i,
    .host_wdata_i,
    .host_be_i,
    .response_delay_i,
    .grant_period_i,
    .quiesce_i,
    .host_gnt_o,
    .host_rvalid_o,
    .host_rdata_o,
    .host_error_o,
    .initialized_o,
    .cpu_fault_o,
    .cmd_accepted_o,
    .completion_valid_o,
    .completion_accepted_o,
    .matrix_column_o,
    .matrix_read_o,
    .matrix_write_o,
    .idle_o
  );
  initial begin
    if (!$value$plusargs("firmware=%s", firmware)) $fatal(1, "Missing firmware");
    if (!$value$plusargs("model=%s", model)) model = "";
    if (!$value$plusargs("latency=%d", latency)) latency = 1;
    if (!$value$plusargs("grant_period=%d", grant_period)) grant_period = 1;
    run_probe(firmware, model, latency, grant_period, status);
    if (status != 0) $fatal(1, "Host probe failed with status %0d", status);
    $finish;
  end
endmodule
