module platform_memory_tb;
  timeunit 1ns; timeprecision 1ps;
  logic clk = 1'b0;
  logic rst_n = 1'b0;
  logic start = 1'b0;
  logic done;
  logic [31:0] address, write_data, router_status, sequence_id;
  logic [7:0] operation, byte_enable;
  logic [63:0] result, expected;
  string vectors;
  int file_handle, fields, checks, waited;
  bit corrupt;
  always #5ns clk = !clk;
  platform_memory u_memory (
    .clock(clk),
    .reset(rst_n),
    .start_port(start),
    .done_port(done),
    .address(address),
    .write_data(write_data),
    .operation(operation),
    .byte_enable(byte_enable),
    .router_status(router_status),
    .completed_sequence(sequence_id),
    .return_port(result)
  );
  initial begin
    if (!$value$plusargs("vectors=%s", vectors)) $fatal(1, "Missing vectors");
    file_handle = $fopen(vectors, "r");
    if (file_handle == 0) $fatal(1, "Cannot open vectors");
    if (!$value$plusargs("corrupt=%b", corrupt)) corrupt = 1'b0;
    checks = 0;
    repeat (4) @(negedge clk);
    rst_n = 1'b1;
    while (!$feof(
      file_handle
    )) begin
      fields = $fscanf(
        file_handle,
        "%h %h %h %h %h %h %h\n",
        address,
        write_data,
        operation,
        byte_enable,
        router_status,
        sequence_id,
        expected
      );
      if (fields != 7) $fatal(1, "Malformed vector after check %0d", checks);
      @(negedge clk);
      start = 1'b1;
      @(negedge clk);
      start  = 1'b0;
      waited = 0;
      while (!done && waited < 1024) begin
        @(negedge clk);
        waited++;
      end
      if (!done) $fatal(1, "HLS function timeout at check %0d", checks);
      if (corrupt && checks == 0) expected ^= 64'd1;
      if (result !== expected)
        $fatal(1, "HLS contract mismatch at check %0d: %h != %h", checks, result, expected);
      checks++;
    end
    $fclose(file_handle);
    if (checks != 16485) $fatal(1, "Incomplete contract vectors: %0d", checks);
    $display("{\"test\":\"hls_platform_contract\",\"checks\":%0d,\"pass\":true}", checks);
    $finish;
  end
endmodule
