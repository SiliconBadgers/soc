// Test assembly: every execution endpoint returns an error, without tensor computation.
module command_router_test_top (
  input logic clk_i,
  input logic rst_ni,
  input logic quiesce_i,
  output logic idle_o,
  input logic cmd_valid_i,
  output logic cmd_ready_o,
  input command_pkg::command_t cmd_i,
  output logic completion_valid_o,
  input logic completion_ready_i,
  output command_pkg::completion_t completion_o
);
  import command_pkg::*;

  logic [NUM_ROUTES-1:0] request_valid;
  logic [NUM_ROUTES-1:0] request_ready;
  logic [NUM_ROUTES-1:0] response_valid;
  logic [NUM_ROUTES-1:0] response_ready;
  completion_t responses[NUM_ROUTES];

  command_router u_command_router (
    .clk_i,
    .rst_ni,
    .quiesce_i,
    .idle_o,
    .cmd_valid_i,
    .cmd_ready_o,
    .cmd_i,
    .completion_valid_o,
    .completion_ready_i,
    .completion_o,
    .request_valid_o(request_valid),
    .request_ready_i(request_ready),
    .response_valid_i(response_valid),
    .response_ready_o(response_ready),
    .responses_i(responses)
  );

  engine_stub #(
    .ReturnStatus(StatusUnimplemented)
  ) u_matrix (
    .clk_i,
    .rst_ni,
    .cmd_i,
    .cmd_valid_i(request_valid[RouteMatrix]),
    .cmd_ready_o(request_ready[RouteMatrix]),
    .completion_valid_o(response_valid[RouteMatrix]),
    .completion_ready_i(response_ready[RouteMatrix]),
    .completion_o(responses[RouteMatrix])
  );

  engine_stub #(
    .ReturnStatus(StatusUnimplemented)
  ) u_vector (
    .clk_i,
    .rst_ni,
    .cmd_i,
    .cmd_valid_i(request_valid[RouteVector]),
    .cmd_ready_o(request_ready[RouteVector]),
    .completion_valid_o(response_valid[RouteVector]),
    .completion_ready_i(response_ready[RouteVector]),
    .completion_o(responses[RouteVector])
  );

  engine_stub #(
    .ReturnStatus(StatusUnimplemented)
  ) u_state (
    .clk_i,
    .rst_ni,
    .cmd_i,
    .cmd_valid_i(request_valid[RouteState]),
    .cmd_ready_o(request_ready[RouteState]),
    .completion_valid_o(response_valid[RouteState]),
    .completion_ready_i(response_ready[RouteState]),
    .completion_o(responses[RouteState])
  );

  engine_stub #(
    .ReturnStatus(StatusUnimplemented)
  ) u_memory (
    .clk_i,
    .rst_ni,
    .cmd_i,
    .cmd_valid_i(request_valid[RouteMemory]),
    .cmd_ready_o(request_ready[RouteMemory]),
    .completion_valid_o(response_valid[RouteMemory]),
    .completion_ready_i(response_ready[RouteMemory]),
    .completion_o(responses[RouteMemory])
  );

  engine_stub #(
    .ReturnStatus(StatusBadCommand)
  ) u_invalid (
    .clk_i,
    .rst_ni,
    .cmd_i,
    .cmd_valid_i(request_valid[RouteInvalid]),
    .cmd_ready_o(request_ready[RouteInvalid]),
    .completion_valid_o(response_valid[RouteInvalid]),
    .completion_ready_i(response_ready[RouteInvalid]),
    .completion_o(responses[RouteInvalid])
  );
endmodule
