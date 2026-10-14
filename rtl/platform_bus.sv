// Round-robin bus arbitration around the HLS-generated RAM/register service.
// Clients 0/1/2/3 are CPU instruction, CPU data, matrix and host, respectively.
module platform_bus (
  input logic clk_i,
  input logic rst_ni,
  input logic [3:0] req_i,
  output logic [3:0] gnt_o,
  input logic [3:0] we_i,
  input logic [3:0][31:0] addr_i,
  input logic [3:0][31:0] wdata_i,
  input logic [3:0][3:0] be_i,
  output logic [3:0] rvalid_o,
  output logic [31:0] rdata_o,
  output logic error_o,
  input logic [31:0] response_delay_i,
  input logic [31:0] grant_period_i,
  output logic initialized_o,
  input logic router_idle_i,
  output logic cmd_valid_o,
  input logic cmd_ready_i,
  output command_pkg::command_t cmd_o,
  input logic completion_valid_i,
  output logic completion_ready_o,
  input command_pkg::completion_t completion_i
);
  typedef enum logic [2:0] {
    ResetRequest,
    Choose,
    Grant,
    Launch,
    WaitResult,
    DelayResponse
  } state_e;
  localparam logic [2:0] OWNER_DESCRIPTOR = 3'd4;
  localparam logic [2:0] OWNER_RESET = 3'd5;
  state_e state_q;
  logic [2:0] owner_q;
  logic [1:0] next_q, choice;
  logic have_choice;
  logic [31:0] address_q, write_data_q, router_status_q, sequence_q;
  logic [7:0] operation_q, byte_enable_q;
  logic [63:0] result, result_q;
  logic done;
  logic [31:0] delay_q, phase_q;
  logic fetch_q, pending_q;
  logic [4:0] descriptor_index_q;
  logic [31:0] descriptor_q[32];

  platform_memory u_platform_memory (
    .clock(clk_i),
    .reset(rst_ni),
    .start_port(state_q == Launch),
    .done_port(done),
    .address(address_q),
    .write_data(write_data_q),
    .operation(operation_q),
    .byte_enable(byte_enable_q),
    .router_status(router_status_q),
    .completed_sequence(sequence_q),
    .return_port(result)
  );
  assign cmd_valid_o = pending_q;
  always_comb begin
    cmd_o = '0;
    cmd_o.abi_version = descriptor_q[0][15:0];
    cmd_o.opcode = descriptor_q[0][31:16];
    cmd_o.context_id = descriptor_q[2];
    cmd_o.sequence_id = descriptor_q[3];
    cmd_o.a_addr = {descriptor_q[5], descriptor_q[4]};
    cmd_o.b_addr = {descriptor_q[7], descriptor_q[6]};
    cmd_o.c_addr = {descriptor_q[9], descriptor_q[8]};
    cmd_o.state_addr = {descriptor_q[13], descriptor_q[12]};
    cmd_o.m = descriptor_q[16];
    cmd_o.n = descriptor_q[17];
    cmd_o.k = descriptor_q[18];
    cmd_o.a_stride = descriptor_q[20];
    cmd_o.b_stride = descriptor_q[21];
    cmd_o.c_stride = descriptor_q[22];
    cmd_o.format_id = descriptor_q[23];
    choice = next_q;
    have_choice = 1'b0;
    for (int unsigned offset = 0; offset < 4; offset++) begin
      if (!have_choice && req_i[2'(next_q+2'(offset))]) begin
        choice = 2'(next_q + 2'(offset));
        have_choice = 1'b1;
      end
    end
    gnt_o = '0;
    if (state_q == Grant && owner_q < 4) gnt_o[owner_q[1:0]] = 1'b1;
    rvalid_o = '0;
    if (state_q == DelayResponse && delay_q == 0 && owner_q < 4) rvalid_o[owner_q[1:0]] = 1'b1;
    rdata_o = result_q[31:0];
    error_o = result_q[32];
  end
  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      state_q <= ResetRequest;
      owner_q <= OWNER_RESET;
      next_q <= '0;
      address_q <= '0;
      write_data_q <= '0;
      operation_q <= '0;
      byte_enable_q <= '0;
      router_status_q <= '0;
      sequence_q <= '0;
      result_q <= '0;
      delay_q <= '0;
      phase_q <= '0;
      fetch_q <= 1'b0;
      pending_q <= 1'b0;
      descriptor_index_q <= '0;
      initialized_o <= 1'b0;
      completion_ready_o <= 1'b0;
      for (int unsigned index = 0; index < 32; index++) descriptor_q[index] <= '0;
    end else begin
      completion_ready_o <= 1'b0;
      if (phase_q + 1 >= grant_period_i) phase_q <= '0;
      else phase_q <= phase_q + 1;
      if (pending_q && cmd_ready_i) pending_q <= 1'b0;
      case (state_q)
        ResetRequest: begin
          operation_q <= 8'd2;
          owner_q <= OWNER_RESET;
          state_q <= Launch;
        end
        Choose: begin
          if (fetch_q) begin
            owner_q <= OWNER_DESCRIPTOR;
            operation_q <= 8'd3;
            address_q <= {27'b0, descriptor_index_q};
            state_q <= Launch;
          end else if (phase_q == 0 && have_choice) begin
            owner_q <= {1'b0, choice};
            next_q <= choice + 1'b1;
            address_q <= addr_i[choice];
            write_data_q <= wdata_i[choice];
            byte_enable_q <= {4'b0, be_i[choice]};
            operation_q <= choice == 2 ? (we_i[choice] ? 8'd5 : 8'd4) : {7'b0, we_i[choice]};
            router_status_q <= {
              16'b0,
              completion_i.status,
              6'b0,
              completion_valid_i,
              router_idle_i && !pending_q && !fetch_q
            };
            sequence_q <= completion_i.sequence_id;
            state_q <= Grant;
          end
        end
        Grant: state_q <= Launch;
        Launch: state_q <= WaitResult;
        WaitResult:
        if (done) begin
          result_q <= result;
          if (owner_q == OWNER_RESET) begin
            initialized_o <= 1'b1;
            state_q <= Choose;
          end else if (owner_q == OWNER_DESCRIPTOR) begin
            descriptor_q[descriptor_index_q] <= result[31:0];
            if (descriptor_index_q == 31) begin
              fetch_q   <= 1'b0;
              pending_q <= 1'b1;
            end else descriptor_index_q <= descriptor_index_q + 1'b1;
            state_q <= Choose;
          end else begin
            if (result[33]) begin
              fetch_q <= 1'b1;
              descriptor_index_q <= '0;
            end
            if (result[34]) completion_ready_o <= 1'b1;
            delay_q <= response_delay_i;
            state_q <= DelayResponse;
          end
        end
        DelayResponse:
        if (delay_q == 0) state_q <= Choose;
        else delay_q <= delay_q - 1;
        default: state_q <= ResetRequest;
      endcase
    end
  end
  SingleGrant_A :
  assert property (@(posedge clk_i) $onehot0(gnt_o));
  SingleResponse_A :
  assert property (@(posedge clk_i) $onehot0(rvalid_o));
  StableCommand_A :
  assert property (@(posedge clk_i) disable iff (!rst_ni)
      cmd_valid_o && !cmd_ready_i |=> cmd_valid_o && $stable(
    cmd_o
  ));
  DescriptorRead_A :
  assert property (@(posedge clk_i) disable iff (!rst_ni)
      state_q == WaitResult && done && owner_q == OWNER_DESCRIPTOR |-> !result[32]);
endmodule
