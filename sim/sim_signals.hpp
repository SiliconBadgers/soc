#pragma once
#include "svdpi.h"
#include <cstdint>
#include <stdexcept>
#include <string>

// Packed words match the explicit slices in control_path_vcs_tb.sim_eval.
extern "C" int sim_eval(const svBitVecVal *, svLogicVecVal *);
struct DpiDisabled {};

struct SimSignals {
    uint32_t clk_i = 0;
    uint32_t rst_ni = 0;
    uint32_t instr_req_o = 0;
    uint32_t instr_gnt_i = 0;
    uint32_t instr_rvalid_i = 0;
    uint32_t instr_addr_o = 0;
    uint32_t instr_rdata_i = 0;
    uint32_t data_req_o = 0;
    uint32_t data_gnt_i = 0;
    uint32_t data_rvalid_i = 0;
    uint32_t data_we_o = 0;
    uint32_t data_be_o = 0;
    uint32_t data_addr_o = 0;
    uint32_t data_wdata_o = 0;
    uint32_t data_rdata_i = 0;
    uint32_t cmd_valid_i = 0;
    uint32_t cmd_ready_o = 0;
    uint32_t opcode_i = 0;
    uint32_t abi_version_i = 0;
    uint32_t sequence_id_i = 0;
    uint32_t context_id_i = 0;
    uint32_t m_i = 0;
    uint32_t n_i = 0;
    uint32_t k_i = 0;
    uint64_t a_addr_i = 0;
    uint64_t b_addr_i = 0;
    uint64_t c_addr_i = 0;
    uint64_t state_addr_i = 0;
    uint32_t a_stride_i = 0;
    uint32_t b_stride_i = 0;
    uint32_t c_stride_i = 0;
    uint32_t format_id_i = 0;
    uint32_t completion_valid_o = 0;
    uint32_t completion_ready_i = 0;
    uint32_t completed_sequence_id_o = 0;
    uint32_t completion_status_o = 0;
    uint32_t quiesce_i = 0;
    uint32_t idle_o = 0;

    void final() {}
    void eval() {
        svBitVecVal inputs[30]{};
        svLogicVecVal outputs[12]{};
        inputs[0] = uint32_t(clk_i);
        inputs[1] = uint32_t(rst_ni);
        inputs[2] = uint32_t(instr_gnt_i);
        inputs[3] = uint32_t(instr_rvalid_i);
        inputs[4] = uint32_t(instr_rdata_i);
        inputs[5] = uint32_t(data_gnt_i);
        inputs[6] = uint32_t(data_rvalid_i);
        inputs[7] = uint32_t(data_rdata_i);
        inputs[8] = uint32_t(cmd_valid_i);
        inputs[9] = uint32_t(opcode_i);
        inputs[10] = uint32_t(abi_version_i);
        inputs[11] = uint32_t(sequence_id_i);
        inputs[12] = uint32_t(context_id_i);
        inputs[13] = uint32_t(m_i);
        inputs[14] = uint32_t(n_i);
        inputs[15] = uint32_t(k_i);
        inputs[16] = uint32_t(a_addr_i);
        inputs[17] = uint32_t(a_addr_i >> 32);
        inputs[18] = uint32_t(b_addr_i);
        inputs[19] = uint32_t(b_addr_i >> 32);
        inputs[20] = uint32_t(c_addr_i);
        inputs[21] = uint32_t(c_addr_i >> 32);
        inputs[22] = uint32_t(state_addr_i);
        inputs[23] = uint32_t(state_addr_i >> 32);
        inputs[24] = uint32_t(a_stride_i);
        inputs[25] = uint32_t(b_stride_i);
        inputs[26] = uint32_t(c_stride_i);
        inputs[27] = uint32_t(format_id_i);
        inputs[28] = uint32_t(completion_ready_i);
        inputs[29] = uint32_t(quiesce_i);
        if (sim_eval(inputs, outputs)) throw DpiDisabled{};
        auto read = [&](unsigned index, const char *name, bool required) {
            if (required && outputs[index].bval)
                throw std::runtime_error(std::string("Unknown RTL output: ") + name);
            return outputs[index].aval;
        };
        instr_req_o = read(0, "instr_req_o", rst_ni);
        instr_addr_o = read(1, "instr_addr_o", rst_ni && instr_req_o);
        data_req_o = read(2, "data_req_o", rst_ni);
        data_we_o = read(3, "data_we_o", rst_ni && data_req_o);
        data_be_o = read(4, "data_be_o", rst_ni && data_req_o);
        data_addr_o = read(5, "data_addr_o", rst_ni && data_req_o);
        data_wdata_o = read(6, "data_wdata_o", rst_ni && data_req_o && data_we_o);
        cmd_ready_o = read(7, "cmd_ready_o", rst_ni);
        completion_valid_o = read(8, "completion_valid_o", rst_ni);
        completed_sequence_id_o = read(9, "completed_sequence_id_o", rst_ni && completion_valid_o);
        completion_status_o = read(10, "completion_status_o", rst_ni && completion_valid_o);
        idle_o = read(11, "idle_o", rst_ni);
    }
};
