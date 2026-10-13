#pragma once
#include "svdpi.h"
#include <array>
#include <cstdint>
#include <iostream>
#include <stdexcept>

// Shared simulation RAM only. Tensor multiplication stays in bpu_sa_array.
struct MatrixMemory {
    std::array<uint8_t, 65536> &bytes;
    uint64_t reads = 0, writes = 0, columns = 0;
    inline static MatrixMemory *active = nullptr;
    explicit MatrixMemory(std::array<uint8_t, 65536> &storage) : bytes(storage) {
        if (active) throw std::runtime_error("Only one simulation RAM may be active");
        active = this;
    }
    ~MatrixMemory() { active = nullptr; }
    MatrixMemory(const MatrixMemory &) = delete;
    MatrixMemory &operator=(const MatrixMemory &) = delete;
};

extern "C" void matrix_note_column() {
    if (MatrixMemory::active) ++MatrixMemory::active->columns;
}
extern "C" int matrix_read_byte(unsigned long long address) {
    auto *memory = MatrixMemory::active;
    if (!memory || address < 0x3000 || address >= 0xf000) return -1;
    ++memory->reads;
    return memory->bytes[size_t(address)];
}
extern "C" int matrix_write_word(unsigned long long address, const svLogicVecVal *value) {
    auto *memory = MatrixMemory::active;
    if (!memory || address < 0x3000 || address > 0xf000 - 4 ||
        (address & 3) || value->bval) return -1;
    for (unsigned byte = 0; byte < 4; ++byte)
        memory->bytes[size_t(address) + byte] = uint8_t(value->aval >> (8 * byte));
    ++memory->writes;
    return 0;
}
