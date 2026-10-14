#pragma once
#include "svdpi.h"
#include <cstdint>
#include <stdexcept>
#include <string>
extern "C" int sim_eval(const svBitVecVal *, svLogicVecVal *);
struct DpiDisabled {};
struct HlsSignals {
    uint32_t clk_i = 0, rst_ni = 0, cpu_enable_i = 0, host_req_i = 0, host_we_i = 0;
    uint32_t host_addr_i = 0, host_wdata_i = 0, host_be_i = 15;
    uint32_t response_delay_i = 0, grant_period_i = 1, quiesce_i = 0;
    uint32_t host_gnt_o = 0, host_rvalid_o = 0, host_rdata_o = 0, host_error_o = 0;
    uint32_t initialized_o = 0, cpu_fault_o = 0, cmd_accepted_o = 0;
    uint32_t completion_valid_o = 0, completion_accepted_o = 0, matrix_column_o = 0;
    uint32_t matrix_read_o = 0, matrix_write_o = 0, idle_o = 0;
    void eval() {
        svBitVecVal inputs[11] = {clk_i, rst_ni, cpu_enable_i, host_req_i, host_we_i,
            host_addr_i, host_wdata_i, host_be_i, response_delay_i, grant_period_i, quiesce_i};
        svLogicVecVal outputs[13]{};
        if (sim_eval(inputs, outputs)) throw DpiDisabled{};
        auto read = [&](unsigned index, const char *name, bool required = true) {
            if (rst_ni && required && outputs[index].bval)
                throw std::runtime_error(std::string("Unknown HLS RTL output: ") + name);
            return outputs[index].aval;
        };
        host_gnt_o = read(0, "host_gnt_o");
        host_rvalid_o = read(1, "host_rvalid_o");
        host_rdata_o = read(2, "host_rdata_o", host_rvalid_o);
        host_error_o = read(3, "host_error_o", host_rvalid_o);
        initialized_o = read(4, "initialized_o");
        cpu_fault_o = read(5, "cpu_fault_o");
        cmd_accepted_o = read(6, "cmd_accepted_o");
        completion_valid_o = read(7, "completion_valid_o");
        completion_accepted_o = read(8, "completion_accepted_o");
        matrix_column_o = read(9, "matrix_column_o");
        matrix_read_o = read(10, "matrix_read_o");
        matrix_write_o = read(11, "matrix_write_o");
        idle_o = read(12, "idle_o");
    }
};
