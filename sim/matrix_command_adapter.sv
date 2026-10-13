// Simulation-only command/memory adapter around Adam Shebani's unmodified array.
// Single clock; reset cancels pending work and completion. The parent releases reset
// synchronously. Prior RAM writes are not rolled back. DPI RAM accesses take no bus cycles.
// Format 0xffff0001 is a test encoding: row-major signed INT8 A/B, signed INT32 C,
// byte strides, 1<=M,K<=8 and 1<=N<=16. Smaller A tiles are zero-padded to 8x8.
// Only RAM [0x3000,0xf000) may hold tensors; C must not overlap either input.
module matrix_command_adapter (
  input logic clk_i,
  input logic rst_ni,
  input command_pkg::command_t cmd_i,
  input logic cmd_valid_i,
  output logic cmd_ready_o,
  output logic completion_valid_o,
  input logic completion_ready_i,
  output command_pkg::completion_t completion_o
);
  import command_pkg::*;

  localparam int unsigned ROWS = 8;
  localparam int unsigned COLS = 8;
  localparam logic [31:0] TEST_FORMAT = 32'hffff0001;
  localparam completion_status_e STATUS_SUCCESS = completion_status_e'(8'h00);
  localparam int unsigned WATCHDOG_CYCLES = 1024;

  typedef enum logic [2:0] {
    Idle,
    LoadA,
    SendA,
    LoadB,
    SendB,
    Drain,
    Complete
  } state_e;

  state_e state_q;
  command_t command_q;
  completion_t completion_q;
  logic [31:0] row_q;
  logic [31:0] column_q;
  logic [31:0] received_q;
  logic [31:0] active_cycles_q;
  logic [COLS*8-1:0] a_row_q;
  logic [COLS*8-1:0] b_column_q;
  logic a_ready;
  logic a_full;
  logic b_ready;
  logic c_valid;
  logic [ROWS*32-1:0] c_column;
  logic mode_error;

  import "DPI-C" function void matrix_note_column();
  import "DPI-C" function int matrix_read_byte(input longint unsigned address);
  import "DPI-C" function int matrix_write_word(
    input longint unsigned address,
    input logic [31:0] value
  );

  function automatic logic [7:0] read_memory(input longint unsigned address);
    int value;
    value = matrix_read_byte(address);
    if (value < 0) begin
      $fatal(1, "matrix memory read failed");
    end
    return 8'(value);
  endfunction

  function automatic logic valid_layout(input command_t command);
    logic [63:0] a_end;
    logic [63:0] b_end;
    logic [63:0] c_end;
    a_end = command.a_addr + 64'(command.m - 1) * 64'(command.a_stride) + 64'(command.k);
    b_end = command.b_addr + 64'(command.k - 1) * 64'(command.b_stride) + 64'(command.n);
    c_end = command.c_addr + 64'(command.m - 1) * 64'(command.c_stride) + 64'(command.n) * 4;
    return command.m >= 1 && command.m <= ROWS && command.k >= 1 && command.k <= COLS &&
        command.n >= 1 && command.n <= 16 && command.a_stride >= command.k &&
        command.b_stride >= command.n && command.c_stride >= command.n * 4 &&
        command.c_stride[1:0] == 2'b00 && command.c_addr[1:0] == 2'b00 &&
        command.a_addr >= 64'h3000 && command.a_addr < 64'hf000 &&
        command.b_addr >= 64'h3000 && command.b_addr < 64'hf000 &&
        command.c_addr >= 64'h3000 && command.c_addr < 64'hf000 &&
        a_end <= 64'hf000 && b_end <= 64'hf000 && c_end <= 64'hf000 &&
        (c_end <= command.a_addr || a_end <= command.c_addr) &&
        (c_end <= command.b_addr || b_end <= command.c_addr);
  endfunction

  assign cmd_ready_o = (state_q == Idle);
  assign completion_valid_o = (state_q == Complete);
  assign completion_o = completion_q;

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
      column_q <= '0;
      received_q <= '0;
      active_cycles_q <= '0;
      a_row_q <= '0;
      b_column_q <= '0;
    end else begin
      if (state_q != Idle && state_q != Complete) begin
        active_cycles_q <= active_cycles_q + 1;
        if (active_cycles_q >= WATCHDOG_CYCLES) begin
          $fatal(1, "matrix command did not complete within its watchdog");
        end
      end
      case (state_q)
        Idle: begin
          if (cmd_valid_i && cmd_ready_o) begin
            command_q <= cmd_i;
            completion_q.sequence_id <= cmd_i.sequence_id;
            row_q <= ROWS - 1;
            column_q <= '0;
            received_q <= '0;
            active_cycles_q <= '0;
            if (cmd_i.format_id != TEST_FORMAT) begin
              completion_q.status <= StatusUnimplemented;
              state_q <= Complete;
            end else if (!valid_layout(cmd_i)) begin
              completion_q.status <= StatusBadCommand;
              state_q <= Complete;
            end else begin
              completion_q.status <= STATUS_SUCCESS;
              state_q <= LoadA;
            end
          end
        end
        LoadA: begin
          for (int unsigned k = 0; k < COLS; k++) begin
            if (row_q < command_q.m && k < command_q.k) begin
              a_row_q[k*8+:8] <=
                read_memory(command_q.a_addr + 64'(row_q) * 64'(command_q.a_stride) + 64'(k));
            end else begin
              a_row_q[k*8+:8] <= '0;
            end
          end
          state_q <= SendA;
        end
        SendA: begin
          if (a_ready) begin
            if (row_q == 0) begin
              state_q <= LoadB;
            end else begin
              row_q   <= row_q - 1;
              state_q <= LoadA;
            end
          end
        end
        LoadB: begin
          for (int unsigned k = 0; k < COLS; k++) begin
            if (k < command_q.k) begin
              b_column_q[k*8+:8] <=
                read_memory(command_q.b_addr + 64'(k) * 64'(command_q.b_stride) + 64'(column_q));
            end else begin
              b_column_q[k*8+:8] <= '0;
            end
          end
          state_q <= SendB;
        end
        SendB: begin
          if (b_ready) begin
            matrix_note_column();
            if (column_q + 1 == command_q.n) begin
              state_q <= Drain;
            end else begin
              column_q <= column_q + 1;
              state_q  <= LoadB;
            end
          end
        end
        Drain: begin
          // The array has no output backpressure. Capture every valid column below.
          if (c_valid && received_q + 1 == command_q.n) begin
            state_q <= Complete;
          end
        end
        Complete: begin
          if (completion_ready_i) begin
            state_q <= Idle;
          end
        end
        default: begin
          $fatal(1, "invalid matrix adapter state");
        end
      endcase
      if (c_valid) begin
        if (state_q == Idle || state_q == Complete || received_q >= command_q.n) begin
          $fatal(1, "unexpected matrix output column");
        end
        for (int unsigned row = 0; row < ROWS; row++) begin
          if (row < command_q.m) begin
            if (matrix_write_word(
                command_q.c_addr + 64'(row) * 64'(command_q.c_stride) + 64'(received_q) * 4,
                c_column[row*32+:32]
              ) != 0) begin
              $fatal(1, "matrix C memory write failed or contained unknown bits");
            end
          end
        end
        received_q <= received_q + 1;
        if (received_q + 1 == command_q.n && state_q != Drain) begin
          $fatal(1, "last matrix output arrived before all input columns were sent");
        end
      end
    end
  end

  SupportedMode_A :
  assert property (@(posedge clk_i) disable iff (!rst_ni) !mode_error);
  LoadedTile_A :
  assert property (@(posedge clk_i) disable iff (!rst_ni)
      state_q == SendB && column_q == 0 |-> a_full);
  StableCompletion_A :
  assert property (@(posedge clk_i) disable iff (!rst_ni)
      completion_valid_o && !completion_ready_i |=>
      completion_valid_o && $stable(
    completion_o
  ));
endmodule
