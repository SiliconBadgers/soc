// Provisional integration boundary. Not the accepted software ABI.
package sb_types_pkg;
  typedef enum logic [2:0] {
    EngineMatrix, EngineVector, EngineState, EngineMemory, EngineInvalid
  } engine_e;
  typedef enum logic [7:0] {
    StatusUnimplemented = 8'h80,
    StatusBadCommand = 8'h81
  } status_e;
  typedef struct packed {
    logic [31:0] sequence_id;
    logic [31:0] context_id;
    logic [15:0] opcode;
    logic [15:0] abi;
    logic [63:0] a_addr, b_addr, c_addr, state_addr;
    logic [31:0] m, n, k;
    logic [31:0] a_stride, b_stride, c_stride, format_id;
  } command_t;
  typedef struct packed {
    logic [31:0] sequence_id;
    status_e status;
  } completion_t;
  // Only opcode 1 comes from the slide baseline. Others are test routing values.
  function automatic engine_e target_engine(input logic [15:0] opcode);
    case (opcode)
      16'd1: return EngineMatrix;
      16'h8002: return EngineVector;
      16'h8003: return EngineState;
      16'h8004: return EngineMemory;
      default: return EngineInvalid;
    endcase
  endfunction
endpackage
