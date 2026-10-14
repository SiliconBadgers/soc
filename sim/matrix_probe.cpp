#include "sim_host.hpp"
#include <cstdlib>
#include <functional>

// Independent scalar oracle. The simulated CPU submits every accepted/rejected command.
int main(int argc, char **argv) {
    try {
        if (argc < 2) throw std::runtime_error("usage: matrix_probe firmware.bin [latency] [grant_period]");
        SimHost sim(argv[1], argc > 2 ? std::stoi(argv[2]) : 1, argc > 3 ? std::stoi(argv[3]) : 1);
        uint32_t sequence = 1;
        unsigned valid = 0, invalid = 0, elements = 0;
        uint64_t command_cycles = 0, completion_stalls = 0;
        bool inject = std::getenv("MATRIX_INJECT_FAILURE") &&
                      std::string(std::getenv("MATRIX_INJECT_FAILURE")) == "1";
        auto fill = [&](const SimHost::MatrixCommand &d, int pattern) {
#ifdef HLS_PLATFORM
            for (uint32_t address = 0x3000; address < 0xf000; address += 4) sim.write_word(address, 0xa5a5a5a5);
#else
            for (uint32_t address = 0x3000; address < 0xf000; ++address) sim.write_byte(address, 0xa5);
#endif
            for (unsigned i = 0; i < d.m; ++i)
                for (unsigned k = 0; k < d.k; ++k) {
                    int value = pattern == 1 ? -128 : pattern == 2 ? 127 : int((i * 19 + k * 7) % 256) - 128;
                    sim.write_byte(uint32_t(d.a + i * d.a_stride + k), uint8_t(value));
                }
            for (unsigned k = 0; k < d.k; ++k)
                for (unsigned j = 0; j < d.n; ++j) {
                    int value = pattern == 1 ? -128 : pattern == 2 ? -128 : int((k * 31 + j * 11 + 5) % 256) - 128;
                    sim.write_byte(uint32_t(d.b + k * d.b_stride + j), uint8_t(value));
                }
        };
        auto snapshot = [&]() {
            std::vector<uint8_t> bytes;
#ifdef HLS_PLATFORM
            for (uint32_t address = 0x3000; address < 0xf000; address += 4) {
                auto word = sim.read_word(address);
                for (unsigned byte = 0; byte < 4; ++byte) bytes.push_back(uint8_t(word >> (byte * 8)));
            }
#else
            for (uint32_t address = 0x3000; address < 0xf000; ++address) bytes.push_back(sim.read_byte(address));
#endif
            return bytes;
        };
        auto check = [&](const SimHost::MatrixCommand &d, int pattern) {
            fill(d, pattern);
            auto expected = snapshot();
            for (unsigned i = 0; i < d.m; ++i) {
                for (unsigned j = 0; j < d.n; ++j) {
                    int32_t sum = 0;
                    for (unsigned k = 0; k < d.k; ++k) {
                        auto signed_byte = [](uint8_t x) { return x < 128 ? int32_t(x) : int32_t(x) - 256; };
                        sum += signed_byte(sim.read_byte(uint32_t(d.a + i * d.a_stride + k))) *
                               signed_byte(sim.read_byte(uint32_t(d.b + k * d.b_stride + j)));
                    }
                    if (inject && valid == 0 && i == 0 && j == 0) ++sum;
                    for (unsigned byte = 0; byte < 4; ++byte)
                        expected[size_t(d.c - 0x3000 + i * d.c_stride + j * 4 + byte)] = uint8_t(uint32_t(sum) >> (8 * byte));
                    ++elements;
                }
            }
            auto writes_before = sim.matrix_writes();
            auto columns_before = sim.matrix_columns();
            auto stalls_before = sim.completion_stall_cycles;
            auto result = sim.submit_matrix(sequence, d);
            if (result.status != 0 || result.sequence != sequence++) throw std::runtime_error("matrix completion failed");
            if (sim.matrix_writes() - writes_before != uint64_t(d.m) * d.n)
                throw std::runtime_error("wrong matrix output write count");
            if (sim.matrix_columns() - columns_before != d.n || sim.completion_stall_cycles == stalls_before)
                throw std::runtime_error("matrix stream/completion stall scenario missed");
            completion_stalls += sim.completion_stall_cycles - stalls_before;
            if (snapshot() != expected) throw std::runtime_error("matrix result or RAM guard mismatch");
            command_cycles += result.cycles;
            ++valid;
        };
        SimHost::MatrixCommand d;
        check(d, 0);
        check(d, 1);
        check(d, 2);
        d.m = 3; d.n = 5; d.k = 7; d.a_stride = 11; d.b_stride = 9; d.c_stride = 32;
        check(d, 0);
        d.m = 1; d.n = 1; d.k = 1;
        check(d, 1);
        d.m = 8; d.n = 16; d.k = 8; d.a_stride = 8; d.b_stride = 20; d.c_stride = 68;
        check(d, 0);
        // Legal range boundary: the final output byte is the final byte of tensor RAM.
        d.m = 1; d.n = 1; d.k = 8; d.c = 0xeffc; d.c_stride = 4;
        check(d, 0);

        const std::vector<std::function<void(SimHost::MatrixCommand &)>> bad = {
            [](auto &x) { x.m = 0; }, [](auto &x) { x.k = 9; }, [](auto &x) { x.n = 17; },
            [](auto &x) { x.a_stride = 7; }, [](auto &x) { x.b_stride = 7; },
            [](auto &x) { x.c_stride = 31; }, [](auto &x) { x.c = 0x5001; },
            [](auto &x) { x.a = 0x2000; }, [](auto &x) { x.b = 0x100000000ull; },
            [](auto &x) { x.c = 0xeffc; }, [](auto &x) { x.c = x.a; },
            [](auto &x) { x.c = x.b; }, [](auto &x) { x.a_stride = 0xffffffffu; }
        };
        for (const auto &mutate : bad) {
            SimHost::MatrixCommand wrong;
            mutate(wrong);
            auto before = snapshot();
            auto reads = sim.matrix_reads(), writes = sim.matrix_writes();
            auto result = sim.submit_matrix(sequence, wrong);
            if (result.sequence != sequence++ || result.status != 0x81 || snapshot() != before ||
                sim.matrix_reads() != reads || sim.matrix_writes() != writes)
                throw std::runtime_error("invalid matrix command touched memory or returned wrong status");
            ++invalid;
        }
        for (unsigned which = 0; which < 2; ++which) {
            SimHost::MatrixCommand wrong;
            if (which == 0) wrong.format = 1; // Proposed INT4 format is not implemented here.
            auto before = snapshot();
            auto result = sim.submit_matrix(sequence, wrong, which == 1 ? 0 : 1);
            if (result.sequence != sequence++ || result.status != (which == 0 ? 0x80u : 0x81u) || snapshot() != before)
                throw std::runtime_error("unsupported format/ABI was not rejected");
            ++invalid;
        }
        // Reset after the real array accepts its first B column, before any C write.
        d = {};
        fill(d, 0);
        auto before = snapshot();
        auto columns = sim.matrix_columns(), writes = sim.matrix_writes();
        sim.begin_matrix(sequence++, d);
        sim.until([&]() { return sim.matrix_columns() > columns; });
        if (sim.matrix_writes() != writes) throw std::runtime_error("reset prerequisite missed");
        sim.reset();
        for (unsigned cycle = 0; cycle < 100; ++cycle) sim.tick();
        if (sim.matrix_writes() != writes || snapshot() != before || sim.top.completion_valid_o || sim.completions)
            throw std::runtime_error("cancelled matrix leaked output or completion after reset");
        check(d, 0);
        std::cout << "{\"test\":\"matrix_cpu_to_rtl\",\"valid_commands\":" << valid
                  << ",\"rejected_commands\":" << invalid << ",\"checked_elements\":" << elements
                  << ",\"active_resets\":1,\"completion_stall_cycles\":" << completion_stalls
                  << ",\"command_cycles\":" << command_cycles << ",\"pass\":true}\n";
        return 0;
    } catch (const std::exception &error) {
        std::cerr << error.what() << '\n';
        return 1;
    }
}
