#pragma once
#include "sim_signals.hpp"
#include "matrix_memory.hpp"
#include <array>
#include <cstdint>
#include <cstring>
#include <fstream>
#include <iostream>
#include <stdexcept>
#include <string>
#include <vector>

// Simulation-only platform. Real DMA, SRAM banking, IRQs and cache coherence are absent.
class SimHost {
    struct Response { int wait = -1; uint32_t value = 0; } irsp, drsp;
    std::array<uint8_t, 65536> ram{};
    MatrixMemory matrix_memory{ram};
    uint32_t ptr_lo = 0, ptr_hi = 0, bytes = 128, submit_seq = 0;
    bool pending_command = false, ack = false;
    int memory_latency, grant_period;
    uint32_t load(uint32_t address) const {
        if ((address & 3) || address > ram.size() - 4) throw std::runtime_error("RAM address out of range or unaligned");
        uint32_t value = 0;
        for (int i = 0; i < 4; ++i) value |= uint32_t(ram[address+i]) << (8*i);
        return value;
    }
    void store(uint32_t address, uint32_t value, uint8_t be = 15) {
        if ((address & 3) || address > ram.size() - 4) throw std::runtime_error("RAM write out of range or unaligned");
        for (int i = 0; i < 4; ++i) if (be & (1 << i)) ram[address+i] = uint8_t(value >> (8*i));
    }
    uint32_t read_bus(uint32_t address) {
        if (address < ram.size()) return load(address);
        switch (address) {
            case 0x10000000: return 0x53424130;
            case 0x10000004: return 1;
            case 0x10000008: return 1; // Simulation INT8 matrix adapter available.
            case 0x1000000c: return top.completion_valid_o ?
                (top.completion_status_o == 0 ? 20 : 24) :
                (top.idle_o && !pending_command ? 17 : 2); // Test bits: done/fault, ready/busy, quiescent.
            case 0x10000024: return top.completed_sequence_id_o;
            case 0x10000028: return top.completion_status_o;
            default: throw std::runtime_error("unsupported MMIO read");
        }
    }
    void write_bus(uint32_t address, uint32_t value, uint8_t be) {
        if (address < ram.size()) { store(address,value,be); return; }
        if (be != 15) throw std::runtime_error("test MMIO requires full-word writes");
        switch (address) {
            case 0x10000010: ptr_lo=value; break;
            case 0x10000014: ptr_hi=value; break;
            case 0x10000018: bytes=value; break;
            case 0x1000001c: submit_seq=value; break;
            case 0x10000020: {
                if (value != 1 || pending_command || !top.idle_o || top.completion_valid_o)
                    throw std::runtime_error("illegal doorbell");
                if (ptr_hi != 0x20000000 || ptr_lo % 128 || bytes != 128 || ptr_lo > ram.size()-128)
                    throw std::runtime_error("descriptor pointer/size rejected by simulation adapter");
                auto word=[&](int off) { return load(ptr_lo+off); };
                auto addr=[&](int off) { return uint64_t(word(off)) | (uint64_t(word(off+4))<<32); };
                if (word(12) != submit_seq) throw std::runtime_error("descriptor sequence mismatch");
                top.abi_version_i=word(0)&0xffff; top.opcode_i=word(0)>>16;
                top.context_id_i=word(8); top.sequence_id_i=word(12);
                top.a_addr_i=addr(16); top.b_addr_i=addr(24); top.c_addr_i=addr(32); top.state_addr_i=addr(48);
                top.m_i=word(64); top.n_i=word(68); top.k_i=word(72);
                top.a_stride_i=word(80); top.b_stride_i=word(84); top.c_stride_i=word(88); top.format_id_i=word(92);
                pending_command=true; ++doorbells; break;
            }
            case 0x10000034:
                if (value != 1 || !top.completion_valid_o) throw std::runtime_error("illegal completion acknowledgement");
                ack=true; break;
            default: throw std::runtime_error("unsupported MMIO write");
        }
    }
public:
    SimSignals top;
    uint64_t cycles=0, doorbells=0, completions=0, completion_stall_cycles=0;
    explicit SimHost(const std::string &firmware, int latency=1, int period=1)
      : memory_latency(latency), grant_period(period) {
        if (latency<1 || period<1) throw std::runtime_error("invalid memory service settings");
        std::ifstream f(firmware,std::ios::binary);
        if (!f) throw std::runtime_error("cannot open firmware binary");
        std::vector<char> code((std::istreambuf_iterator<char>(f)),{});
        if (code.empty() || code.size()>0x1f80) throw std::runtime_error("firmware overlaps mailbox");
        std::memcpy(ram.data()+0x80,code.data(),code.size());
        reset();
    }
    void reset() {
        irsp = {}; drsp = {};
        pending_command = false; ack = false;
        doorbells = 0; completions = 0; completion_stall_cycles = 0;
        ptr_lo = 0; ptr_hi = 0; bytes = 128; submit_seq = 0;
        for (unsigned off = 0; off < 24; off += 4) store(0x2000 + off, 0);
        top.quiesce_i=0;top.cmd_valid_i=0;top.completion_ready_i=0;
        top.instr_gnt_i=0;top.instr_rvalid_i=0;top.instr_rdata_i=0;
        top.data_gnt_i=0;top.data_rvalid_i=0;top.data_rdata_i=0;
        top.rst_ni=0;
        for(int i=0;i<8;++i) { top.clk_i=0;top.eval();top.clk_i=1;top.eval(); }
        top.rst_ni=1;
        until([&] { return load(0x2014)==0x52454144; },20000);
    }
    ~SimHost() { top.final(); }
    void tick() {
        top.clk_i=0;
        top.instr_gnt_i=0;top.data_gnt_i=0;top.instr_rvalid_i=0;top.data_rvalid_i=0;
        auto respond=[](Response &r, auto &valid, auto &data) {
            if(r.wait==0) { valid=1; data=r.value; r.wait=-1; }
            else if(r.wait>0) --r.wait;
        };
        respond(irsp,top.instr_rvalid_i,top.instr_rdata_i);
        respond(drsp,top.data_rvalid_i,top.data_rdata_i);
        top.eval();
        if(cycles%grant_period==0) {
            if(top.instr_req_o && irsp.wait<0 && !top.instr_rvalid_i) {
                top.instr_gnt_i=1; irsp={memory_latency-1,load(top.instr_addr_o)};
            }
            if(top.data_req_o && drsp.wait<0 && !top.data_rvalid_i) {
                top.data_gnt_i=1;
                uint32_t value=0;
                if(top.data_we_o) write_bus(top.data_addr_o,top.data_wdata_o,top.data_be_o);
                else value=read_bus(top.data_addr_o);
                drsp={memory_latency-1,value};
            }
        }
        top.cmd_valid_i=pending_command;top.completion_ready_i=ack;
        top.eval();
        bool accepted=top.cmd_valid_i && top.cmd_ready_o;
        bool released=top.completion_valid_o && top.completion_ready_i;
        if (top.completion_valid_o && !top.completion_ready_i) ++completion_stall_cycles;
        top.clk_i=1;top.eval();++cycles;
        if(accepted) pending_command=false;
        if(released) { ack=false;++completions; }
    }
    template<class Predicate> void until(Predicate predicate, uint64_t limit=100000) {
        auto stop=cycles+limit;
        while(!predicate()) {
            if(cycles>=stop) throw std::runtime_error("CPU/command simulation timed out");
            tick();
        }
    }
    struct Result { uint32_t status, sequence; uint64_t cycles; };
    struct MatrixCommand {
        uint32_t m = 8, n = 8, k = 8;
        uint64_t a = 0x3000, b = 0x4000, c = 0x5000;
        uint32_t a_stride = 8, b_stride = 8, c_stride = 32;
        uint32_t format = 0xffff0001; // Simulation INT8 A/B, INT32 C; not the proposed INT4 ABI.
    };
    uint64_t matrix_columns() const { return matrix_memory.columns; }
    uint64_t matrix_reads() const { return matrix_memory.reads; }
    uint64_t matrix_writes() const { return matrix_memory.writes; }
    void write_byte(uint32_t address, uint8_t value) {
        if (address < 0x3000 || address >= 0xf000) throw std::runtime_error("tensor write outside RAM");
        ram[address] = value;
    }
    uint8_t read_byte(uint32_t address) const {
        if (address < 0x3000 || address >= 0xf000) throw std::runtime_error("tensor read outside RAM");
        return ram[address];
    }
    uint64_t begin_command(uint16_t op, uint32_t seq, uint32_t m, uint32_t n,
                           uint32_t k, uint16_t abi, const MatrixCommand *matrix = nullptr) {
        if(load(0x2000)) throw std::runtime_error("host mailbox already occupied");
        for(int i=0;i<128;i+=4) store(0x2100+i,0);
        store(0x2100,uint32_t(op)<<16|abi);store(0x210c,seq);
        store(0x2140,m);store(0x2144,n);store(0x2148,k);
        if (matrix) {
            auto address = [&](uint32_t offset, uint64_t value) {
                store(0x2100 + offset, uint32_t(value));
                store(0x2104 + offset, uint32_t(value >> 32));
            };
            address(16, matrix->a); address(24, matrix->b); address(32, matrix->c);
            store(0x2150, matrix->a_stride); store(0x2154, matrix->b_stride);
            store(0x2158, matrix->c_stride); store(0x215c, matrix->format);
        }
        store(0x2010,0);store(0x2004,seq);store(0x2000,1);
        return cycles;
    }
    Result finish_command(uint64_t start) {
        until([&] { return load(0x2010)==1; });
        if(load(0x2000)!=0 || completions!=doorbells) throw std::runtime_error("ownership released prematurely");
        return {load(0x2008),load(0x200c),cycles-start};
    }
    Result submit(uint16_t op, uint32_t seq, uint32_t m=1, uint32_t n=1, uint32_t k=1, uint16_t abi=1) {
        return finish_command(begin_command(op, seq, m, n, k, abi));
    }
    uint64_t begin_matrix(uint32_t seq, const MatrixCommand &command, uint16_t abi = 1) {
        return begin_command(1, seq, command.m, command.n, command.k, abi, &command);
    }
    Result submit_matrix(uint32_t seq, const MatrixCommand &command, uint16_t abi = 1) {
        return finish_command(begin_matrix(seq, command, abi));
    }
};
