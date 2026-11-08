// One clock domain. Reset cancels the CPU epoch and pending responses; RAM survives reset.
module controller_system #(
  parameter int unsigned RamWords = 4096,
  parameter int unsigned PayloadWidth = 128,
  parameter int unsigned CounterWidth = 16,
  parameter int unsigned QueueDepth = 4
) (
  input logic clk_i,
  input logic rst_ni,
  input logic host_req_i,
  output logic host_gnt_o,
  input logic host_we_i,
  input logic [31:0] host_addr_i,
  input logic [31:0] host_wdata_i,
  input logic [3:0] host_be_i,
  output logic host_rvalid_o,
  output logic [31:0] host_rdata_o,
  output logic host_error_o,
  output logic [2:0] issue_valid_o,
  input logic [2:0] issue_ready_i,
  output logic [2:0][PayloadWidth-1:0] issue_payload_o,
  input logic [2:0][1:0] increment_i,
  input logic [2:0] engine_idle_i,
  input logic [2:0] engine_fault_i,
  output logic host_irq_o,
  output logic done_o,
  output logic fault_o
);
  localparam logic [31:0] RAM_BYTES = 32'(RamWords * 4);
  logic [31:0] ram[RamWords];
  logic run, cpu_irq, cpu_fault_q;
  logic cpu_fault_event;
  logic cpu_data_allowed;
  logic core_release_n, core_rst_n;
  logic [1:0] reset_release_q;
  logic instr_req, instr_gnt, instr_rvalid_q;
  logic [31:0] instr_addr, instr_rdata_q;
  logic data_req, data_gnt, data_we;
  logic [3:0] data_be;
  logic [31:0] data_addr, data_wdata, data_rdata;
  logic instr_in_ram, data_in_ram, data_in_regs;
  logic data_local_rvalid_q;
  logic [31:0] data_local_rdata_q;
  logic regs_cpu_gnt, regs_cpu_rvalid, regs_cpu_error;
  logic [31:0] regs_cpu_rdata;
  logic host_in_regs, host_in_ram, host_ram_allowed;
  logic regs_host_gnt, regs_host_rvalid, regs_host_error;
  logic [31:0] regs_host_rdata;
  logic host_local_rvalid_q, host_local_error_q;
  logic [31:0] host_local_rdata_q;

  initial begin
    if (RamWords < 33 || RamWords > 32'h1000_0000) begin
      $fatal(1, "RamWords must include entry 0x80 and fit below CPU MMIO");
    end
  end

  // Registered MMIO errors stop new CPU side effects before the sticky latch updates.
  assign cpu_fault_event = cpu_fault_q || (regs_cpu_rvalid && regs_cpu_error);
  assign core_release_n  = rst_ni && run && !fault_o && !cpu_fault_event;
  always_ff @(posedge clk_i or negedge core_release_n) begin
    if (!core_release_n) begin
      reset_release_q <= '0;
    end else begin
      reset_release_q <= {reset_release_q[0], 1'b1};
    end
  end
  assign core_rst_n = reset_release_q[1];
  assign instr_in_ram = instr_addr < RAM_BYTES;
  assign data_in_ram = data_addr < RAM_BYTES;
  assign data_in_regs = data_addr[31:12] == 20'h40000;
  assign cpu_data_allowed = core_rst_n && !cpu_fault_event && !(|engine_fault_i);
  assign instr_gnt = core_rst_n && !cpu_fault_event && instr_req;
  assign data_gnt = cpu_data_allowed && data_req && (!data_in_regs || regs_cpu_gnt);
  assign data_rdata = regs_cpu_rvalid ? regs_cpu_rdata : data_local_rdata_q;
  assign host_in_regs = host_addr_i[31:12] == '0;
  assign host_in_ram = host_addr_i >= 32'h10000 && (host_addr_i - 32'h10000) < RAM_BYTES;
  assign host_ram_allowed = host_in_ram && !run && host_addr_i[1:0] == 2'b00;
  assign host_gnt_o = rst_ni && host_req_i && (!host_in_regs || regs_host_gnt);
  assign host_rvalid_o = regs_host_rvalid || host_local_rvalid_q;
  assign host_rdata_o = regs_host_rvalid ? regs_host_rdata : host_local_rdata_q;
  assign host_error_o = regs_host_rvalid ? regs_host_error : host_local_error_q;

  // Independent registered read ports permit instruction fetch and CPU data access together.
  // Host RAM writes use the data port only while START has not been accepted.
  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      instr_rvalid_q <= 1'b0;
      instr_rdata_q <= '0;
      data_local_rvalid_q <= 1'b0;
      data_local_rdata_q <= '0;
      host_local_rvalid_q <= 1'b0;
      host_local_error_q <= 1'b0;
      host_local_rdata_q <= '0;
      cpu_fault_q <= 1'b0;
    end else begin
      instr_rvalid_q <= instr_req && instr_gnt;
      instr_rdata_q  <= '0;
      if (instr_req && instr_gnt) begin
        if (instr_in_ram) begin
          instr_rdata_q <= ram[instr_addr>>2];
        end else begin
          cpu_fault_q <= 1'b1;
        end
      end
      data_local_rvalid_q <= data_req && data_gnt && !data_in_regs;
      data_local_rdata_q  <= '0;
      if (data_req && data_gnt && !data_in_regs) begin
        if (data_in_ram) begin
          data_local_rdata_q <= ram[data_addr>>2];
        end else begin
          cpu_fault_q <= 1'b1;
        end
      end
      if (regs_cpu_rvalid && regs_cpu_error) begin
        cpu_fault_q <= 1'b1;
      end
      host_local_rvalid_q <= host_req_i && host_gnt_o && !host_in_regs;
      host_local_error_q  <= 1'b0;
      host_local_rdata_q  <= '0;
      if (host_req_i && host_gnt_o && !host_in_regs) begin
        if (host_ram_allowed) begin
          host_local_rdata_q <= ram[(host_addr_i-32'h10000)>>2];
        end else begin
          host_local_error_q <= 1'b1;
        end
      end
    end
  end

  // START excludes the host and CPU write enables from the same RAM data port.
  // RAM has no reset; firmware and data are replaced by explicit host writes.
  always_ff @(posedge clk_i) begin
    if (rst_ni) begin
      if (data_req && data_gnt && data_in_ram && data_we) begin
        for (int byte_index = 0; byte_index < 4; byte_index++) begin
          if (data_be[byte_index]) begin
            ram[data_addr>>2][byte_index*8+:8] <= data_wdata[byte_index*8+:8];
          end
        end
      end else if (host_req_i && host_gnt_o && host_ram_allowed && host_we_i) begin
        for (int byte_index = 0; byte_index < 4; byte_index++) begin
          if (host_be_i[byte_index]) begin
            ram[(host_addr_i-32'h10000)>>2][byte_index*8+:8] <= host_wdata_i[byte_index*8+:8];
          end
        end
      end
    end
  end

  FaultEdgeBlocksCpuData_A :
  assert property (
    @(posedge clk_i) disable iff (!rst_ni)
    ((|engine_fault_i) || cpu_fault_event) |-> !data_gnt
  );

  CoreResetQuietsBus_A :
  assert property (@(posedge clk_i) disable iff (!rst_ni) !core_rst_n |-> !instr_gnt && !data_gnt);

  riscv_wrapper u_riscv (
    .clk_i,
    .rst_ni(core_rst_n),
    .fetch_enable_i(core_rst_n),
    .irq_external_i(cpu_irq),
    .instr_req_o(instr_req),
    .instr_gnt_i(instr_gnt),
    .instr_rvalid_i(core_rst_n && instr_rvalid_q),
    .instr_addr_o(instr_addr),
    .instr_rdata_i(instr_rdata_q),
    .data_req_o(data_req),
    .data_gnt_i(data_gnt),
    .data_rvalid_i(core_rst_n && (data_local_rvalid_q || regs_cpu_rvalid)),
    .data_we_o(data_we),
    .data_be_o(data_be),
    .data_addr_o(data_addr),
    .data_wdata_o(data_wdata),
    .data_rdata_i(data_rdata)
  );

  controller_regs #(
    .PayloadWidth(PayloadWidth),
    .CounterWidth(CounterWidth),
    .QueueDepth  (QueueDepth)
  ) u_controller_regs (
    .clk_i,
    .rst_ni,
    .host_req_i(host_req_i && host_in_regs && rst_ni),
    .host_gnt_o(regs_host_gnt),
    .host_we_i,
    .host_addr_i,
    .host_wdata_i,
    .host_be_i,
    .host_rvalid_o(regs_host_rvalid),
    .host_rdata_o(regs_host_rdata),
    .host_error_o(regs_host_error),
    .cpu_req_i(cpu_data_allowed && data_req && data_in_regs),
    .cpu_gnt_o(regs_cpu_gnt),
    .cpu_we_i(data_we),
    .cpu_addr_i({20'b0, data_addr[11:0]}),
    .cpu_wdata_i(data_wdata),
    .cpu_be_i(data_be),
    .cpu_rvalid_o(regs_cpu_rvalid),
    .cpu_rdata_o(regs_cpu_rdata),
    .cpu_error_o(regs_cpu_error),
    .cpu_fault_i(cpu_fault_event),
    .engine_fault_i,
    .engine_idle_i,
    .run_o(run),
    .job_arg_o(),
    .host_irq_o,
    .cpu_irq_o(cpu_irq),
    .done_o,
    .fault_o,
    .issue_valid_o,
    .issue_ready_i,
    .issue_payload_o,
    .increment_i
  );
endmodule
