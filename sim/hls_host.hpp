#pragma once
#include "hls_signals.hpp"
#include <cstdint>
#include <fstream>
#include <iostream>
#include <stdexcept>
#include <string>
#include <vector>

// Host driver only. Device RAM, MMIO and descriptor fetching execute in RTL.
class SimHost {
    bool host_accepted = false, host_responded = false, host_error = false;
    uint32_t host_read_data = 0;
    uint64_t columns = 0, reads = 0, writes = 0;
    uint32_t transaction(uint32_t address, uint32_t data, bool write, uint8_t be = 15) {
        top.host_addr_i = address; top.host_wdata_i = data;
        top.host_we_i = write; top.host_be_i = be; top.host_req_i = 1;
        uint64_t grant_deadline = cycles + 100000;
        do {
            if (cycles >= grant_deadline) throw std::runtime_error("host bus grant timeout");
            tick();
        } while (!host_accepted);
        top.host_req_i = 0;
        uint64_t deadline = cycles + 100000;
        do {
            if (cycles >= deadline) throw std::runtime_error("host bus response timeout");
            tick();
        } while (!host_responded);
        if (host_error) throw std::runtime_error("hardware rejected host bus access");
        return host_read_data;
    }
    uint32_t load(uint32_t address) { return transaction(address, 0, false); }
    void store(uint32_t address, uint32_t value, uint8_t be = 15) {
        transaction(address, value, true, be);
    }
    void reset_platform() {
        top.cpu_enable_i = 0; top.host_req_i = 0; top.quiesce_i = 0; top.rst_ni = 0;
        for (unsigned i = 0; i < 8; ++i) tick();
        top.rst_ni = 1;
        until([&] { return top.initialized_o != 0; });
    }
public:
    HlsSignals top;
    uint64_t cycles = 0, doorbells = 0, completions = 0, completion_stall_cycles = 0;
    explicit SimHost(const std::string &firmware, int latency = 1, int period = 1) {
        if (latency < 1 || period < 1) throw std::runtime_error("invalid memory service settings");
        top.response_delay_i = uint32_t(latency - 1); top.grant_period_i = uint32_t(period);
        std::ifstream input(firmware, std::ios::binary);
        if (!input) throw std::runtime_error("cannot open firmware binary");
        std::vector<uint8_t> code((std::istreambuf_iterator<char>(input)), {});
        if (code.empty() || code.size() > 0x1f80) throw std::runtime_error("firmware overlaps mailbox");
        reset_platform();
        // Explicit bus initialization makes the test independent of FPGA RAM power-up values.
        for (uint32_t address = 0; address < 65536; address += 4) store(address, 0);
        for (uint32_t i = 0; i < code.size(); i += 4) {
            uint32_t word = 0;
            for (uint32_t byte = 0; byte < 4 && i + byte < code.size(); ++byte)
                word |= uint32_t(code[i + byte]) << (byte * 8);
            store(0x80 + i, word);
        }
        reset();
    }
    void reset() {
        reset_platform();
        doorbells = 0; completions = 0; completion_stall_cycles = 0;
        for (unsigned offset = 0; offset < 24; offset += 4) store(0x2000 + offset, 0);
        top.cpu_enable_i = 1;
        until([&] { return load(0x2014) == 0x52454144; });
    }
    void tick() {
        top.clk_i = 0; top.eval();
        host_accepted = top.host_req_i && top.host_gnt_o;
        host_responded = top.host_rvalid_o;
        host_read_data = top.host_rdata_o;
        host_error = top.host_error_o;
        if (top.rst_ni) {
            doorbells += top.cmd_accepted_o;
            completions += top.completion_accepted_o;
            completion_stall_cycles += top.completion_valid_o && !top.completion_accepted_o;
            columns += top.matrix_column_o;
            reads += top.matrix_read_o;
            writes += top.matrix_write_o;
            if (top.cpu_fault_o) throw std::runtime_error("CPU hardware bus fault");
        }
        top.clk_i = 1; top.eval(); ++cycles;
    }
    template<class Predicate> void until(Predicate predicate, uint64_t limit = 1000000) {
        uint64_t deadline = cycles + limit;
        while (!predicate()) {
            if (cycles >= deadline) throw std::runtime_error("HLS CPU/command timeout");
            tick();
        }
    }
    struct Result { uint32_t status, sequence; uint64_t cycles; };
    struct MatrixCommand {
        uint32_t m = 8, n = 8, k = 8;
        uint64_t a = 0x3000, b = 0x4000, c = 0x5000;
        uint32_t a_stride = 8, b_stride = 8, c_stride = 32, format = 0xffff0001;
    };
    uint64_t matrix_columns() const { return columns; }
    uint64_t matrix_reads() const { return reads; }
    uint64_t matrix_writes() const { return writes; }
    void write_word(uint32_t address, uint32_t value) { store(address, value); }
    uint32_t read_word(uint32_t address) { return load(address); }
    void write_byte(uint32_t address, uint8_t value) {
        if (address < 0x3000 || address >= 0xf000) throw std::runtime_error("tensor write outside RAM");
        store(address & ~3u, uint32_t(value) << ((address & 3) * 8), uint8_t(1u << (address & 3)));
    }
    uint8_t read_byte(uint32_t address) {
        if (address < 0x3000 || address >= 0xf000) throw std::runtime_error("tensor read outside RAM");
        return uint8_t(load(address & ~3u) >> ((address & 3) * 8));
    }
    uint64_t begin_command(uint16_t op, uint32_t seq, uint32_t m, uint32_t n,
                           uint32_t k, uint16_t abi, const MatrixCommand *matrix = nullptr) {
        if (load(0x2000)) throw std::runtime_error("host mailbox already occupied");
        for (unsigned i = 0; i < 128; i += 4) store(0x2100 + i, 0);
        store(0x2100, uint32_t(op) << 16 | abi); store(0x210c, seq);
        store(0x2140, m); store(0x2144, n); store(0x2148, k);
        if (matrix) {
            auto address = [&](uint32_t offset, uint64_t value) {
                store(0x2100 + offset, uint32_t(value));
                store(0x2104 + offset, uint32_t(value >> 32));
            };
            address(16, matrix->a); address(24, matrix->b); address(32, matrix->c);
            store(0x2150, matrix->a_stride); store(0x2154, matrix->b_stride);
            store(0x2158, matrix->c_stride); store(0x215c, matrix->format);
        }
        store(0x2010, 0); store(0x2004, seq); store(0x2000, 1);
        return cycles;
    }
    Result finish_command(uint64_t start) {
        until([&] { return load(0x2010) == 1; });
        if (load(0x2000) != 0 || completions != doorbells)
            throw std::runtime_error("ownership released prematurely");
        uint32_t status = load(0x2008), sequence = load(0x200c);
        return {status, sequence, cycles - start};
    }
    Result submit(uint16_t op, uint32_t seq, uint32_t m = 1, uint32_t n = 1,
                  uint32_t k = 1, uint16_t abi = 1) {
        return finish_command(begin_command(op, seq, m, n, k, abi));
    }
    uint64_t begin_matrix(uint32_t seq, const MatrixCommand &command, uint16_t abi = 1) {
        return begin_command(1, seq, command.m, command.n, command.k, abi, &command);
    }
    Result submit_matrix(uint32_t seq, const MatrixCommand &command, uint16_t abi = 1) {
        return finish_command(begin_matrix(seq, command, abi));
    }
};
