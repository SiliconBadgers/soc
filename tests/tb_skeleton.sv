module tb_skeleton;
  import sb_types_pkg::*;
  logic clk = 0;
  always #5 clk = ~clk;
  logic rst_n = 0, quiesce = 0, idle, valid = 0, ready, done, take = 0;
  command_t cmd;
  completion_t result;
  sb_accelerator_top dut (.clk_i(clk), .rst_ni(rst_n), .quiesce_i(quiesce),
    .idle_o(idle), .cmd_valid_i(valid), .cmd_ready_o(ready), .cmd_i(cmd),
    .completion_valid_o(done), .completion_ready_i(take), .completion_o(result));
  task automatic tick;
    @(posedge clk); #1;
  endtask
  task automatic command(input logic [15:0] op, input logic [31:0] seq, input status_e expected);
    @(negedge clk); cmd = '0; cmd.abi = 1; cmd.opcode = op; cmd.sequence_id = seq; valid = 1;
    if (!ready) $fatal(1,"not ready before submit");
    tick(); @(negedge clk); valid = 0;
    repeat (4) begin
      tick();
      if (!done || ready || result.sequence_id != seq || result.status != expected)
        $fatal(1,"completion or backpressure failure");
      cmd.sequence_id = seq + 99; // Payload mutation must not change accepted result.
    end
    @(negedge clk); take = 1; tick(); @(negedge clk); take = 0;
    tick(); if (!idle || done) $fatal(1,"completion not released");
  endtask
  initial begin
    cmd = '0; repeat (3) tick(); @(negedge clk); rst_n = 1; tick();
    command(1, 1, StatusUnimplemented);
    command('h8002, 2, StatusUnimplemented);
    command('h8003, 3, StatusUnimplemented);
    command('h8004, 4, StatusUnimplemented);
    command('hffff, 5, StatusBadCommand);
    @(negedge clk); quiesce = 1; valid = 1; tick();
    if (ready || done || !idle) $fatal(1,"quiesce accepted work");
    @(negedge clk); quiesce = 0; valid = 0;
    // Quiesce must retain an outstanding completion while blocking another command.
    @(negedge clk); cmd.abi = 1; cmd.opcode = 1; cmd.sequence_id = 6; valid = 1;
    tick(); @(negedge clk); quiesce = 1; cmd.sequence_id = 99;
    repeat (3) begin
      tick();
      if (ready || idle || !done || result.sequence_id != 6)
        $fatal(1,"quiesce lost owned command or accepted new work");
    end
    @(negedge clk); take = 1; tick(); @(negedge clk); take = 0;
    tick(); if (ready || !idle || done) $fatal(1,"quiesce did not drain");
    @(negedge clk); valid = 0; quiesce = 0;
    // Reset cancels stub state only; real traffic will require a drain protocol.
    command(1, 7, StatusUnimplemented);
    @(negedge clk); cmd.abi = 0; cmd.sequence_id = 8; valid = 1;
    tick(); @(negedge clk); valid = 0; tick();
    if (!done || result.status != StatusBadCommand) $fatal(1,"ABI validation");
    @(negedge clk); rst_n = 0; tick();
    if (done || !idle) $fatal(1,"reset did not flush stub");
    $display("PASS skeleton: 8 commands, all routes, ABI error, backpressure, quiesce, reset");
    $finish;
  end
  initial begin #10000; $fatal(1,"timeout"); end
endmodule
