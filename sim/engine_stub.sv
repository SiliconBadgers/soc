// A replaceable boundary, deliberately no datapath and no successful completion.
module engine_stub #(
  parameter command_pkg::completion_status_e ReturnStatus = command_pkg::StatusUnimplemented
) (
  input logic clk_i,
  input logic rst_ni,
  input logic cmd_valid_i,
  output logic cmd_ready_o,
  input command_pkg::command_t cmd_i,
  output logic completion_valid_o,
  input logic completion_ready_i,
  output command_pkg::completion_t completion_o
);
  assign cmd_ready_o = !completion_valid_o;
  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      completion_valid_o <= 1'b0;
      completion_o <= '0;
    end else begin
      if (completion_valid_o && completion_ready_i) begin
        completion_valid_o <= 1'b0;
      end else if (cmd_valid_i && cmd_ready_o) begin
        completion_valid_o <= 1'b1;
        completion_o.sequence_id <= cmd_i.sequence_id;
        completion_o.status <= ReturnStatus;
      end
    end
  end
  property completion_stable_p;
    @(posedge clk_i) disable iff (!rst_ni)
    completion_valid_o && !completion_ready_i
    |=> completion_valid_o && $stable(
      completion_o
    );
  endproperty
  CompletionStable_A :
  assert property (completion_stable_p);
endmodule
