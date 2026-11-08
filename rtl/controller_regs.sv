// Both register ports share clk_i. Reset release is synchronized by the parent.
module controller_regs #(
  parameter int unsigned PayloadWidth = 128,
  parameter int unsigned CounterWidth = 16,
  parameter int unsigned QueueDepth   = 4
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
  input logic cpu_req_i,
  output logic cpu_gnt_o,
  input logic cpu_we_i,
  input logic [31:0] cpu_addr_i,
  input logic [31:0] cpu_wdata_i,
  input logic [3:0] cpu_be_i,
  output logic cpu_rvalid_o,
  output logic [31:0] cpu_rdata_o,
  output logic cpu_error_o,
  output logic run_o,
  output logic [31:0] job_arg_o,
  output logic host_irq_o,
  output logic cpu_irq_o,
  output logic done_o,
  output logic fault_o,
  input logic cpu_fault_i,
  input logic [2:0] engine_fault_i,
  input logic [2:0] engine_idle_i,
  output logic [2:0] issue_valid_o,
  output logic [2:0][PayloadWidth-1:0] issue_payload_o,
  input logic [2:0] issue_ready_i,
  input logic [2:0][1:0] increment_i
);
  localparam int unsigned COUNT_WIDTH = $clog2(QueueDepth + 1);
  controller_host_pkg::controller_host__in_t host_hw_in;
  controller_host_pkg::controller_host__out_t host_hw_out;
  controller_firmware_pkg::controller_firmware__in_t firmware_hw_in;
  controller_firmware_pkg::controller_firmware__out_t firmware_hw_out;
  logic run_q, done_q, fault_q, fault_live;
  logic armed_q, satisfied_q;
  logic [2:0] mask_q;
  logic [2:0][CounterWidth-1:0] snapshot_q;
  logic [2:0][CounterWidth-1:0] progress;
  logic [2:0][CounterWidth-1:0] target_q;
  logic [2:0][PayloadWidth-1:0] payload_q;
  logic [2:0][1:0][CounterWidth-1:0] dependency_q;
  logic [2:0][COUNT_WIDTH-1:0] count_q;
  logic [2:0] push_valid, push_ready, empty;
  logic queue_push_valid[3], queue_push_ready[3];
  logic [PayloadWidth-1:0] queue_push_payload[3], queue_issue_payload[3];
  logic [CounterWidth-1:0] queue_wait_target_0[3], queue_wait_target_1[3];
  logic queue_issue_valid[3], queue_issue_ready[3];
  logic [1:0] queue_increment[3];
  logic [CounterWidth-1:0] queue_progress[3];
  logic [2:0] externally_offered_q;
  logic [1:0] req, we, grant, pre_error, permit, response_error;
  logic [1:0][31:0] addr, wdata, be_bits, response_data;
  logic [1:0][3:0] be;
  logic [1:0] generated_req, rd_ack, rd_error, wr_ack, wr_error;
  logic [1:0] stall_rd, stall_wr;
  logic [1:0][31:0] rd_data;
  logic [1:0] pending;
  logic wait_met, finish_ready, start_event, arm_event, clear_event, finish_event;
  logic [CounterWidth-1:0] difference;

  assign req = {cpu_req_i, host_req_i};
  assign we = {cpu_we_i, host_we_i};
  assign addr = {cpu_addr_i, host_addr_i};
  assign wdata = {cpu_wdata_i, host_wdata_i};
  assign be = {cpu_be_i, host_be_i};
  assign host_gnt_o = rst_ni && grant[0];
  assign cpu_gnt_o = rst_ni && grant[1];
  assign run_o = run_q;
  assign done_o = done_q;
  assign fault_o = fault_q;
  assign job_arg_o = host_hw_out.job_arg.value.value;
  assign pending = {host_hw_out.irq_pending.fault.value, host_hw_out.irq_pending.completion.value};
  assign host_irq_o = |(pending & host_hw_out.irq_enable.value.value);
  assign cpu_irq_o = armed_q && satisfied_q;
  assign fault_live = fault_q || cpu_fault_i || (|engine_fault_i);
  assign finish_ready = satisfied_q && (&empty) && (&engine_idle_i);
  assign start_event = host_hw_out.control.req && host_hw_out.control.req_is_wr;
  assign arm_event = firmware_hw_out.wait_arm.req && firmware_hw_out.wait_arm.req_is_wr;
  assign clear_event = firmware_hw_out.wait_clear.req;
  assign finish_event = firmware_hw_out.finish.req;

  always_comb begin
    wait_met   = 1'b1;
    difference = '0;
    for (int q = 0; q < 3; q++) begin
      difference = progress[q] - snapshot_q[q];
      if (mask_q[q] && difference[CounterWidth-1]) begin
        wait_met = 1'b0;
      end
      empty[q] = count_q[q] == 0;
      target_q[q] = firmware_hw_out.wait_target[q].value.value;
      for (int d = 0; d < 2; d++) begin
        dependency_q[q][d] = firmware_hw_out.queue[q].dependency[d].value.value;
      end
      for (int w = 0; w < PayloadWidth / 32; w++) begin
        payload_q[q][32*w+:32] = firmware_hw_out.queue[q].payload[w].value.value;
      end
      push_valid[q] = firmware_hw_out.queue[q].commit.req;
    end
  end

  // Reject malformed writes before generated storage or access strobes can change state.
  // Queue and drain waits stay outside the regblocks, leaving host reads independent.
  always_comb begin
    pre_error = '0;
    permit = '1;
    be_bits = '0;
    for (int p = 0; p < 2; p++) begin
      for (int b = 0; b < 4; b++) begin
        be_bits[p][8*b+:8] = {8{be[p][b]}};
      end
      pre_error[p] = addr[p][31:12] != 0 || addr[p][1:0] != 0;
      if (we[p]) begin
        pre_error[p] |= be[p] != 4'hf;
        if (p == 0) begin
          pre_error[p] |= (wdata[p] & ~controller_access_pkg::host_write_mask(addr[p])) != 0;
        end else begin
          pre_error[p] |= (wdata[p] & ~controller_access_pkg::firmware_write_mask(addr[p])) != 0;
        end
        case (addr[p])
          32'h004: pre_error[p] |= p != 0 || wdata[p] != 1 || run_q || fault_live;
          32'h00c: pre_error[p] |= p != 0 || run_q;
          32'h010: pre_error[p] |= p != 1 || !run_q || done_q || fault_live;
          32'h014, 32'h018: pre_error[p] |= p != 0;
          32'h03c: pre_error[p] |= p != 1 || (wdata[p] >> 3) != 0;
          32'h044: begin
            pre_error[p] |= p != 1 || wdata[p] != 1 || !armed_q || !run_q || done_q || fault_live;
            permit[p] = finish_ready;
          end
          32'h048: pre_error[p] |= p != 1 || wdata[p] != 1;
          default: ;
        endcase
        for (int q = 0; q < 3; q++) begin
          if (addr[p] == 32'h100 * (q + 1) + 32'h08) begin
            pre_error[p] |= p != 1 || wdata[p] != 1 || !run_q || done_q || fault_live;
            permit[p] = push_ready[q];
          end
        end
      end
    end
  end

  for (genvar p = 0; p < 2; p++) begin : gen_native
    assign generated_req[p] = rst_ni && req[p] && !pre_error[p] && permit[p];
    assign grant[p] = req[p] && (pre_error[p] ||
        (permit[p] && !(we[p] ? stall_wr[p] : stall_rd[p]) &&
         (we[p] ? wr_ack[p] : rd_ack[p])));
    assign response_error[p] = pre_error[p] || (we[p] ? wr_error[p] : rd_error[p]);
    assign response_data[p] = response_error[p] || we[p] ? '0 : rd_data[p];
  end

  // The generated passthrough views have no retiming. Register their matching
  // acknowledgment and data here to implement the native one-cycle response.
  controller_host u_host_view (
    .clk(clk_i),
    .arst_n(rst_ni),
    .s_cpuif_req(generated_req[0]),
    .s_cpuif_req_is_wr(we[0]),
    .s_cpuif_addr(addr[0][11:0]),
    .s_cpuif_wr_data(wdata[0]),
    .s_cpuif_wr_biten(be_bits[0]),
    .s_cpuif_req_stall_wr(stall_wr[0]),
    .s_cpuif_req_stall_rd(stall_rd[0]),
    .s_cpuif_rd_ack(rd_ack[0]),
    .s_cpuif_rd_err(rd_error[0]),
    .s_cpuif_rd_data(rd_data[0]),
    .s_cpuif_wr_ack(wr_ack[0]),
    .s_cpuif_wr_err(wr_error[0]),
    .hwif_in(host_hw_in),
    .hwif_out(host_hw_out)
  );
  controller_firmware u_firmware_view (
    .clk(clk_i),
    .arst_n(rst_ni),
    .s_cpuif_req(generated_req[1]),
    .s_cpuif_req_is_wr(we[1]),
    .s_cpuif_addr(addr[1][11:0]),
    .s_cpuif_wr_data(wdata[1]),
    .s_cpuif_wr_biten(be_bits[1]),
    .s_cpuif_req_stall_wr(stall_wr[1]),
    .s_cpuif_req_stall_rd(stall_rd[1]),
    .s_cpuif_rd_ack(rd_ack[1]),
    .s_cpuif_rd_err(rd_error[1]),
    .s_cpuif_rd_data(rd_data[1]),
    .s_cpuif_wr_ack(wr_ack[1]),
    .s_cpuif_wr_err(wr_error[1]),
    .hwif_in(firmware_hw_in),
    .hwif_out(firmware_hw_out)
  );

  always_comb begin
    host_hw_in = '{default: '0};
    firmware_hw_in = '{default: '0};
    host_hw_in.control.rd_ack = host_hw_out.control.req && !host_hw_out.control.req_is_wr;
    host_hw_in.control.wr_ack = start_event;
    host_hw_in.control.rd_data.value = {31'b0, run_q};
    firmware_hw_in.control.rd_ack = firmware_hw_out.control.req &&
                                         !firmware_hw_out.control.req_is_wr;
    firmware_hw_in.control.rd_data.value = {31'b0, run_q};
    host_hw_in.status.value.next = {29'b0, fault_q, done_q, run_q};
    firmware_hw_in.status.value.next = {29'b0, fault_q, done_q, run_q};
    firmware_hw_in.job_arg.value.next = host_hw_out.job_arg.value.value;
    host_hw_in.result.value.next = firmware_hw_out.result.value.value;
    host_hw_in.irq_pending.completion.hwset = finish_event;
    host_hw_in.irq_pending.fault.hwset = cpu_fault_i || (|engine_fault_i);
    firmware_hw_in.irq_pending.value.next = {30'b0, pending};
    firmware_hw_in.irq_enable.value.next = host_hw_out.irq_enable.value.value;
    host_hw_in.queue_status.value.next = {21'b0, push_ready, 5'b0, empty};
    firmware_hw_in.queue_status.value.next = {21'b0, push_ready, 5'b0, empty};
    host_hw_in.wait_arm.rd_ack = host_hw_out.wait_arm.req && !host_hw_out.wait_arm.req_is_wr;
    host_hw_in.wait_arm.rd_data.value = {31'b0, armed_q};
    firmware_hw_in.wait_arm.rd_ack = firmware_hw_out.wait_arm.req &&
                                          !firmware_hw_out.wait_arm.req_is_wr;
    firmware_hw_in.wait_arm.wr_ack = arm_event;
    firmware_hw_in.wait_arm.rd_data.value = {31'b0, armed_q};
    host_hw_in.wait_status.value.next = {30'b0, satisfied_q, armed_q};
    firmware_hw_in.wait_status.value.next = {30'b0, satisfied_q, armed_q};
    firmware_hw_in.finish.wr_ack = finish_event;
    firmware_hw_in.wait_clear.wr_ack = clear_event;
    for (int q = 0; q < 3; q++) begin
      host_hw_in.progress[q].value.next = 32'(progress[q]);
      firmware_hw_in.progress[q].value.next = 32'(progress[q]);
      host_hw_in.wait_target[q].value.next = target_q[q];
      firmware_hw_in.queue[q].commit.wr_ack = firmware_hw_out.queue[q].commit.req;
      for (int d = 0; d < 2; d++) begin
        host_hw_in.queue[q].dependency[d].value.next = dependency_q[q][d];
      end
      for (int w = 0; w < PayloadWidth / 32; w++) begin
        host_hw_in.queue[q].payload[w].value.next = payload_q[q][32*w+:32];
      end
    end
  end

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      run_q <= 1'b0;
      done_q <= 1'b0;
      fault_q <= 1'b0;
      armed_q <= 1'b0;
      satisfied_q <= 1'b0;
      mask_q <= '0;
      snapshot_q <= '0;
      count_q <= '0;
      host_rvalid_o <= 1'b0;
      cpu_rvalid_o <= 1'b0;
      host_rdata_o <= '0;
      cpu_rdata_o <= '0;
      host_error_o <= 1'b0;
      cpu_error_o <= 1'b0;
    end else begin
      run_q <= run_q || start_event;
      done_q <= done_q || finish_event;
      fault_q <= fault_live;
      satisfied_q <= satisfied_q || (armed_q && wait_met);
      if (arm_event) begin
        armed_q <= 1'b1;
        satisfied_q <= 1'b0;
        mask_q <= firmware_hw_out.wait_arm.wr_data.value[2:0];
        snapshot_q <= target_q;
      end else if (clear_event) begin
        armed_q <= 1'b0;
        satisfied_q <= 1'b0;
      end
      for (int q = 0; q < 3; q++) begin
        case ({
          push_valid[q] && push_ready[q], issue_valid_o[q] && issue_ready_i[q]
        })
          2'b10:   count_q[q] <= count_q[q] + 1'b1;
          2'b01:   count_q[q] <= count_q[q] - 1'b1;
          default: ;
        endcase
      end
      host_rvalid_o <= req[0] && grant[0];
      cpu_rvalid_o  <= req[1] && grant[1];
      host_rdata_o  <= response_data[0];
      cpu_rdata_o   <= response_data[1];
      host_error_o  <= response_error[0];
      cpu_error_o   <= response_error[1];
    end
  end

  initial begin
    assert (PayloadWidth == controller_config_pkg::PayloadWidth &&
            CounterWidth == controller_config_pkg::CounterWidth)
    else $fatal(1, "Controller parameters differ from the generated CSR configuration");
  end

  command_queues #(
    .QueueDepth(QueueDepth),
    .PayloadWidth(PayloadWidth),
    .CounterWidth(CounterWidth),
    .NumQueues(3),
    .NumCounters(3)
  ) u_command_queues (
    .clk_i,
    .rst_ni,
    .push_valid_i(queue_push_valid),
    .push_ready_o(queue_push_ready),
    .push_payload_i(queue_push_payload),
    .push_wait_target_0_i(queue_wait_target_0),
    .push_wait_target_1_i(queue_wait_target_1),
    .issue_valid_o(queue_issue_valid),
    .issue_ready_i(queue_issue_ready),
    .issue_payload_o(queue_issue_payload),
    .increment_i(queue_increment),
    .progress_o(queue_progress)
  );

  for (genvar q = 0; q < 3; q++) begin : gen_count_checks
    assign queue_push_valid[q] = push_valid[q];
    assign push_ready[q] = queue_push_ready[q];
    assign queue_push_payload[q] = payload_q[q];
    assign queue_wait_target_0[q] = dependency_q[q][0];
    assign queue_wait_target_1[q] = dependency_q[q][1];
    assign queue_increment[q] = increment_i[q];
    assign progress[q] = queue_progress[q];

    // The queue retains its raw head. Track which offer reached the unit so a
    // fault can block later heads without withdrawing a stalled visible offer.
    assign issue_valid_o[q] = queue_issue_valid[q] && (!fault_live || externally_offered_q[q]);
    assign queue_issue_ready[q] = issue_ready_i[q] && (!fault_live || externally_offered_q[q]);
    assign issue_payload_o[q] = queue_issue_payload[q];
    always_ff @(posedge clk_i or negedge rst_ni) begin
      if (!rst_ni) begin
        externally_offered_q[q] <= 1'b0;
      end else begin
        externally_offered_q[q] <= issue_valid_o[q] && !issue_ready_i[q];
      end
    end

    VisibleOfferStable_A :
    assert property (
      @(posedge clk_i) disable iff (!rst_ni)
      issue_valid_o[q] && !issue_ready_i[q] |=> issue_valid_o[q] && $stable(
      issue_payload_o[q]
    ))
    else $fatal(1, "Stalled controller issue changed");
    FaultBlocksNewOffer_A :
    assert property (
      @(posedge clk_i) disable iff (!rst_ni)
      fault_live && !externally_offered_q[q] |-> !issue_valid_o[q] && !queue_issue_ready[q]
    )
    else $fatal(1, "Fault allowed a new command offer");
    OccupancyBounded_A :
    assert property (@(posedge clk_i) disable iff (!rst_ni) count_q[q] <= COUNT_WIDTH'(QueueDepth))
    else $fatal(1, "Controller occupancy exceeded queue capacity");
    EmptyIssueForbidden_A :
    assert property (@(posedge clk_i) disable iff (!rst_ni) issue_valid_o[q] |-> count_q[q] != '0)
    else $fatal(1, "Controller occupancy disagrees with issue");
  end

  initial begin
    PayloadWidthValid_A :
    assert (PayloadWidth >= 32 && PayloadWidth <= 1792 && PayloadWidth % 32 == 0)
    else $fatal(1, "PayloadWidth must fit a queue window");
    ConfigurationValid_A :
    assert (CounterWidth >= 2 && CounterWidth <= 32 && QueueDepth >= 1)
    else $fatal(1, "Unsupported controller parameters");
  end
endmodule
