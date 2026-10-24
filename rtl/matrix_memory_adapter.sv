// One outstanding memory request and one matrix column at a time.
// The array has no C backpressure; its complete column is captured before writeback.
module matrix_memory_adapter (
  input logic clk_i,
  input logic rst_ni,
  input command_pkg::command_t cmd_i,
  input logic cmd_valid_i,
  output logic cmd_ready_o,
  output logic completion_valid_o,
  input logic completion_ready_i,
  output command_pkg::completion_t completion_o,
  output logic mem_req_o,
  input logic mem_gnt_i,
  output logic mem_we_o,
  output logic [31:0] mem_addr_o,
  output logic [31:0] mem_wdata_o,
  input logic mem_rvalid_i,
  input logic [31:0] mem_rdata_i,
  input logic mem_error_i,
  output logic column_accepted_o
);
  import command_pkg::*;
  localparam int unsigned ROWS = 8;
  localparam int unsigned COLS = 8;
  localparam logic [31:0] TEST_FORMAT = 32'hffff0001;
  typedef enum logic [3:0] {
    Idle,
    LoadA,
    WaitA,
    SendA,
    LoadB,
    WaitB,
    SendB,
    WaitC,
    StoreC,
    WaitWrite,
    Complete
  } state_e;
  state_e state_q;
  command_t command_q;
  completion_t completion_q;
  logic [31:0] row_q, lane_q, column_q;
  logic [63:0] a_row_q, b_column_q;
  logic [255:0] c_column_q, c_column;
  logic a_ready, a_full, b_ready, c_valid, mode_error;

  function automatic logic valid_layout(input command_t command);
    logic [63:0] a_end, b_end, c_end;
    a_end = command.a_addr + 64'(command.m - 1) * 64'(command.a_stride) + 64'(command.k);
    b_end = command.b_addr + 64'(command.k - 1) * 64'(command.b_stride) + 64'(command.n);
    c_end = command.c_addr + 64'(command.m - 1) * 64'(command.c_stride) + 64'(command.n) * 4;
    return command.m >= 1 && command.m <= ROWS && command.k >= 1 && command.k <= COLS &&
        command.n >= 1 && command.n <= 16 && command.a_stride >= command.k &&
        command.b_stride >= command.n && command.c_stride >= command.n * 4 &&
        command.c_stride[1:0] == 0 && command.c_addr[1:0] == 0 &&
        command.a_addr >= 64'h3000 && command.a_addr < 64'hf000 &&
        command.b_addr >= 64'h3000 && command.b_addr < 64'hf000 &&
        command.c_addr >= 64'h3000 && command.c_addr < 64'hf000 &&
        a_end <= 64'hf000 && b_end <= 64'hf000 && c_end <= 64'hf000 &&
        (c_end <= command.a_addr || a_end <= command.c_addr) &&
        (c_end <= command.b_addr || b_end <= command.c_addr);
  endfunction

  assign cmd_ready_o = state_q == Idle;
  assign completion_valid_o = state_q == Complete;
  assign completion_o = completion_q;
  assign column_accepted_o = state_q == SendB && b_ready;
  always_comb begin
    mem_req_o = 1'b0;
    mem_we_o = state_q == StoreC || state_q == WaitWrite;
    mem_addr_o = '0;
    mem_wdata_o = c_column_q[row_q[2:0]*32+:32];
    case (state_q)
      LoadA: begin
        mem_req_o  = row_q < command_q.m && lane_q < command_q.k;
        mem_addr_o = 32'(command_q.a_addr) + row_q * command_q.a_stride + lane_q;
      end
      LoadB: begin
        mem_req_o  = lane_q < command_q.k;
        mem_addr_o = 32'(command_q.b_addr) + lane_q * command_q.b_stride + column_q;
      end
      StoreC: begin
        mem_req_o  = 1'b1;
        mem_addr_o = 32'(command_q.c_addr) + row_q * command_q.c_stride + column_q * 4;
      end
      default: ;
    endcase
  end
  bpu_sa_array #(
    .Rows(ROWS),
    .Cols(COLS),
    .AccW(32)
  ) u_matrix_array (
    .clk_i,
    .rst_ni,
    .mode_i(1'b0),
    .err_mode_o(mode_error),
    .a_valid_i(state_q == SendA),
    .a_ready_o(a_ready),
    .a_row_i(a_row_q),
    .a_full_o(a_full),
    .b_valid_i(state_q == SendB),
    .b_ready_o(b_ready),
    .b_col_i(b_column_q),
    .c_valid_o(c_valid),
    .c_col_o(c_column)
  );
  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      state_q <= Idle;
      command_q <= '0;
      completion_q <= '0;
      row_q <= '0;
      lane_q <= '0;
      column_q <= '0;
      a_row_q <= '0;
      b_column_q <= '0;
      c_column_q <= '0;
    end else begin
      case (state_q)
        Idle:
        if (cmd_valid_i) begin
          command_q <= cmd_i;
          completion_q.sequence_id <= cmd_i.sequence_id;
          row_q <= ROWS - 1;
          lane_q <= '0;
          column_q <= '0;
          if (cmd_i.format_id != TEST_FORMAT) begin
            completion_q.status <= StatusUnimplemented;
            state_q <= Complete;
          end else if (!valid_layout(cmd_i)) begin
            completion_q.status <= StatusBadCommand;
            state_q <= Complete;
          end else begin
            completion_q.status <= completion_status_e'(8'h00);
            state_q <= LoadA;
          end
        end
        LoadA: begin
          if (!mem_req_o) begin
            a_row_q[lane_q[2:0]*8+:8] <= '0;
            if (lane_q == COLS - 1) state_q <= SendA;
            else lane_q <= lane_q + 1;
          end else if (mem_gnt_i) state_q <= WaitA;
        end
        WaitA:
        if (mem_rvalid_i) begin
          a_row_q[lane_q[2:0]*8+:8] <= mem_rdata_i[7:0];
          if (lane_q == COLS - 1) state_q <= SendA;
          else begin
            lane_q  <= lane_q + 1;
            state_q <= LoadA;
          end
        end
        SendA:
        if (a_ready) begin
          lane_q <= '0;
          if (row_q == 0) state_q <= LoadB;
          else begin
            row_q   <= row_q - 1;
            state_q <= LoadA;
          end
        end
        LoadB: begin
          if (!mem_req_o) begin
            b_column_q[lane_q[2:0]*8+:8] <= '0;
            if (lane_q == COLS - 1) state_q <= SendB;
            else lane_q <= lane_q + 1;
          end else if (mem_gnt_i) state_q <= WaitB;
        end
        WaitB:
        if (mem_rvalid_i) begin
          b_column_q[lane_q[2:0]*8+:8] <= mem_rdata_i[7:0];
          if (lane_q == COLS - 1) state_q <= SendB;
          else begin
            lane_q  <= lane_q + 1;
            state_q <= LoadB;
          end
        end
        SendB: if (b_ready) state_q <= WaitC;
        WaitC:
        if (c_valid) begin
          c_column_q <= c_column;
          row_q <= '0;
          state_q <= StoreC;
        end
        StoreC: if (mem_gnt_i) state_q <= WaitWrite;
        WaitWrite:
        if (mem_rvalid_i) begin
          if (row_q + 1 < command_q.m) begin
            row_q   <= row_q + 1;
            state_q <= StoreC;
          end else if (column_q + 1 == command_q.n) state_q <= Complete;
          else begin
            column_q <= column_q + 1;
            lane_q   <= '0;
            state_q  <= LoadB;
          end
        end
        Complete: if (completion_ready_i) state_q <= Idle;
        default: state_q <= Idle;
      endcase
      if (mem_rvalid_i && mem_error_i) begin
        completion_q.status <= StatusBadCommand;
        state_q <= Complete;
      end
    end
  end
  SupportedMode_A :
  assert property (@(posedge clk_i) disable iff (!rst_ni) !mode_error);
  LoadedTile_A :
  assert property (@(posedge clk_i) disable iff (!rst_ni)
      state_q == SendB && column_q == 0 |-> a_full);
  ExpectedColumn_A :
  assert property (@(posedge clk_i) disable iff (!rst_ni) c_valid |-> state_q == WaitC);
  StableRequest_A :
  assert property (@(posedge clk_i) disable iff (!rst_ni)
      mem_req_o && !mem_gnt_i |=> mem_req_o && $stable(
    {mem_we_o, mem_addr_o, mem_wdata_o}
  ));
  StableCompletion_A :
  assert property (@(posedge clk_i) disable iff (!rst_ni)
      completion_valid_o && !completion_ready_i |=> completion_valid_o && $stable(
    completion_o
  ));
endmodule
