// Synthesizable platform service. No allocation, file I/O, exceptions or DPI.
// The RTL arbiter serializes instruction, data, host and matrix transactions.
// Return bits: [31:0] data, [32] bus fault, [33] submit, [34] acknowledge.
// Reset operation clears control registers; RAM is initialized by the host.
#include <stdint.h>

extern "C" uint64_t platform_memory(uint32_t address, uint32_t write_data,
                                     uint8_t operation, uint8_t byte_enable,
                                     uint32_t router_status, uint32_t completed_sequence) {
    static uint32_t ram[16384];
    static uint32_t descriptor[32];
    static uint32_t pointer_low, pointer_high, descriptor_bytes, submit_sequence;
    const uint64_t fault = uint64_t(1) << 32;

    if (operation == 2) {
        pointer_low = 0;
        pointer_high = 0;
        descriptor_bytes = 128;
        submit_sequence = 0;
        return 0;
    }
    if (operation == 3) {
        return address < 32 ? descriptor[address] : fault;
    }
    if (operation == 4) {
        if (address < 0x3000 || address >= 0xf000) return fault;
        return (ram[address >> 2] >> ((address & 3) * 8)) & 255;
    }
    if (operation == 5) {
        if (address < 0x3000 || address >= 0xf000 || (address & 3)) return fault;
        ram[address >> 2] = write_data;
        return 0;
    }
    if (operation > 1 || (address & 3)) return fault;
    if (address < 65536) {
        uint32_t index = address >> 2;
        if (operation == 0) return ram[index];
        uint32_t mask = 0;
        for (unsigned byte = 0; byte < 4; ++byte) {
            if (byte_enable & (1u << byte)) mask |= 255u << (byte * 8);
        }
        ram[index] = (ram[index] & ~mask) | (write_data & mask);
        return 0;
    }
    if (operation == 0) {
        switch (address) {
            case 0x10000000: return 0x53424130;
            case 0x10000004: return 1;
            case 0x10000008: return 1;
            case 0x1000000c:
                return (router_status & 2) ? ((router_status >> 8) ? 24 : 20) :
                       ((router_status & 1) ? 17 : 2);
            case 0x10000024: return completed_sequence;
            case 0x10000028: return router_status >> 8;
            default: return fault;
        }
    }
    if (byte_enable != 15) return fault;
    switch (address) {
        case 0x10000010: pointer_low = write_data; return 0;
        case 0x10000014: pointer_high = write_data; return 0;
        case 0x10000018: descriptor_bytes = write_data; return 0;
        case 0x1000001c: submit_sequence = write_data; return 0;
        case 0x10000020:
            if (write_data != 1 || !(router_status & 1) || (router_status & 2) ||
                pointer_high != 0x20000000 || (pointer_low & 127) ||
                descriptor_bytes != 128 || pointer_low > 65536 - 128) return fault;
            if (ram[(pointer_low + 12) >> 2] != submit_sequence) return fault;
            for (unsigned word = 0; word < 32; ++word)
                descriptor[word] = ram[(pointer_low >> 2) + word];
            return uint64_t(1) << 33;
        case 0x10000034:
            if (write_data != 1 || !(router_status & 2)) return fault;
            return uint64_t(1) << 34;
        default: return fault;
    }
}
