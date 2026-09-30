// A replaceable boundary, deliberately no datapath and no successful completion.
module sb_engine_stub #(
  parameter sb_types_pkg::status_e ReturnStatus = sb_types_pkg::StatusUnimplemented
) (
  input logic clk_i,
  input logic rst_ni,
  input logic cmd_valid_i,
  output logic cmd_ready_o,
  input sb_types_pkg::command_t cmd_i,
  output logic completion_valid_o,
  input logic completion_ready_i,
  output sb_types_pkg::completion_t completion_o
);
  assign cmd_ready_o = !completion_valid_o;
  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      completion_valid_o <= 1'b0;
      completion_o <= '0;
    end else begin
      if (completion_valid_o && completion_ready_i) completion_valid_o <= 1'b0;
      if (cmd_valid_i && cmd_ready_o) begin
        completion_valid_o <= 1'b1;
        completion_o.sequence_id <= cmd_i.sequence_id;
        completion_o.status <= ReturnStatus;
      end
    end
  end
  assert property (@(posedge clk_i) disable iff (!rst_ni)
    completion_valid_o && !completion_ready_i |=>
    completion_valid_o && $stable(completion_o));
endmodule
