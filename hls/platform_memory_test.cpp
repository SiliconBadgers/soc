#include <stdint.h>
#include <cstdlib>
#include <iostream>
#include <fstream>
#include <array>

extern "C" uint64_t platform_memory(uint32_t, uint32_t, uint8_t, uint8_t, uint32_t, uint32_t);

int main(int argc, char **argv) {
    unsigned checks = 0;
    std::ofstream vectors;
    if (argc == 2) {
        vectors.open(argv[1]);
        if (!vectors) return 1;
        vectors << std::hex;
    }
    std::array<uint32_t, 6> inputs{};
    auto expect = [&](uint64_t actual, uint64_t expected) {
        ++checks;
        if (actual != expected) {
            std::cerr << "check " << checks << ": " << actual << " != " << expected << '\n';
            std::exit(1);
        }
        if (vectors.is_open()) {
            for (auto value : inputs) vectors << value << ' ';
            vectors << expected << '\n';
        }
    };
    auto access = [&](uint32_t a, uint32_t d = 0, uint8_t op = 0, uint8_t be = 15,
                     uint32_t status = 1, uint32_t seq = 0) {
        inputs = {a, d, op, be, status, seq};
        return platform_memory(a, d, op, be, status, seq);
    };
    const uint64_t fault = uint64_t(1) << 32;
    expect(access(0, 0, 2), 0);
    for (unsigned a = 0; a < 65536; a += 4) expect(access(a, 0, 1), 0);
    expect(access(0xfffc, 0x88776655, 1), 0);
    expect(access(0xfffc, 0xaabbccdd, 1, 5), 0);
    expect(access(0xfffc), 0x88bb66dd);
    expect(access(3), fault);
    expect(access(65536), fault);
    expect(access(0x10000000), 0x53424130);
    expect(access(0x1000000c), 17);
    expect(access(0x1000000c, 0, 0, 15, 0), 2);
    expect(access(0x1000000c, 0, 0, 15, 2), 20);
    expect(access(0x1000000c, 0, 0, 15, 0x8102), 24);
    expect(access(0x10000024, 0, 0, 15, 2, 42), 42);
    expect(access(0x10000028, 0, 0, 15, 0x8102), 0x81);
    expect(access(0x10000010, 0x2100, 1, 1), fault);
    expect(access(0x10000010, 0x2100, 1), 0);
    expect(access(0x10000014, 0x20000000, 1), 0);
    expect(access(0x1000001c, 7, 1), 0);
    expect(access(0x10000020, 1, 1), fault); // Sequence mismatch.
    for (unsigned i = 0; i < 32; ++i) expect(access(0x2100 + i * 4, i + 4, 1), 0);
    expect(access(0x10000020, 1, 1, 15, 0), fault); // Busy.
    expect(access(0x10000020, 1, 1), uint64_t(1) << 33);
    expect(access(0x2100, 999, 1), 0); // Captured descriptor is immutable.
    for (unsigned i = 0; i < 32; ++i) expect(access(i, 0, 3), i + 4);
    expect(access(32, 0, 3), fault);
    expect(access(0x10000034, 1, 1), fault);
    expect(access(0x10000034, 1, 1, 15, 2), uint64_t(1) << 34);
    expect(access(0x3000, 0x80ff017f, 5), 0);
    expect(access(0x3000, 0, 4), 127);
    expect(access(0x3001, 0, 4), 1);
    expect(access(0x3002, 0, 4), 255);
    expect(access(0x3003, 0, 4), 128);
    expect(access(0x2fff, 0, 4), fault);
    expect(access(0xf000, 0, 4), fault);
    expect(access(0xeffc, 123, 5), 0);
    expect(access(0xeffc), 123);
    expect(access(0xeffd, 0, 5), fault);
    expect(access(0, 0, 2), 0);
    expect(access(0xfffc), 0x88bb66dd); // Control reset preserves RAM.
    expect(access(0x10000020, 1, 1), fault);
    std::cout << "PASS platform C++ contract: " << checks << " checks\n";
}
