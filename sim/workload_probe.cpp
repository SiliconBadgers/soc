#include "sim_host.hpp"
#include "llama.h"
#include "ggml.h"
#include "ggml-backend.h"
#include <algorithm>
#include <cmath>
#include <cstdlib>
#include <cstring>
#include <memory>

// Partial hardware co-execution: replace eight outputs of the first eligible
// projection in each llama_decode call, before downstream nodes consume them.
// Both comparison paths use the same explicit symmetric INT8 quantization.
// Other outputs and operations retain the original llama.cpp CPU implementation.
struct WorkloadProbe {
    SimHost &sim;
    bool hardware = false, armed = false;
    std::string error;
    uint32_t sequence = 0;
    uint64_t hardware_cycles = 0, checked_products = 0, replaced_values = 0;
    unsigned hardware_stages = 0;
    std::vector<std::string> tensors;
    std::vector<uint32_t> inner_dimensions, token_counts;

    static std::vector<int8_t> quantize(const std::vector<float> &values, float &scale) {
        float peak = 0;
        for (float value : values) {
            if (!std::isfinite(value)) throw std::runtime_error("nonfinite projection input");
            peak = std::max(peak, std::abs(value));
        }
        scale = peak > 0 ? peak / 127.0f : 1.0f;
        std::vector<int8_t> result;
        for (float value : values)
            result.push_back(int8_t(std::max(-127l, std::min(127l, std::lround(value / scale)))));
        return result;
    }

    void replace(ggml_tensor *tensor) {
        auto *weights = tensor->src[0], *activation = tensor->src[1];
        const uint32_t k_size = uint32_t(weights->ne[0]);
        const uint32_t m_size = 8, n_size = uint32_t(tensor->ne[1]);
        if (k_size == 0 || k_size > 8192 || n_size == 0 || n_size > 16 ||
            weights->ne[1] < 8 || activation->type != GGML_TYPE_F32 ||
            tensor->type != GGML_TYPE_F32 || tensor->nb[0] != sizeof(float) ||
            activation->nb[0] != sizeof(float)) throw std::runtime_error("unsupported projection layout");
        std::vector<std::vector<int8_t>> a(m_size), b(n_size);
        std::vector<float> a_scale(m_size), b_scale(n_size), values(k_size);
        std::vector<uint8_t> packed(ggml_row_size(weights->type, k_size));
        for (uint32_t row = 0; row < m_size; ++row) {
            ggml_backend_tensor_get(weights, packed.data(), row * weights->nb[1], packed.size());
            if (weights->type == GGML_TYPE_F32) std::memcpy(values.data(), packed.data(), k_size * 4);
            else {
                auto *traits = ggml_get_type_traits(weights->type);
                if (!traits->to_float) throw std::runtime_error("weight dequantizer unavailable");
                traits->to_float(packed.data(), values.data(), k_size);
            }
            a[row] = quantize(values, a_scale[row]);
        }
        for (uint32_t column = 0; column < n_size; ++column) {
            ggml_backend_tensor_get(activation, values.data(), column * activation->nb[1], k_size * 4);
            b[column] = quantize(values, b_scale[column]);
        }
        std::vector<int64_t> sums(m_size * n_size, 0);
        for (uint32_t start = 0; start < k_size; start += 8) {
            SimHost::MatrixCommand command;
            command.m = m_size; command.n = n_size; command.k = std::min(8u, k_size - start);
            command.a_stride = 8; command.b_stride = 16; command.c_stride = 64;
            if (hardware) {
                for (uint32_t row = 0; row < m_size; ++row)
                    for (uint32_t block = 0; block < 2; ++block) {
                        uint32_t word = 0;
                        for (uint32_t byte = 0; byte < 4; ++byte) {
                            uint32_t k = block * 4 + byte;
                            if (k < command.k) word |= uint32_t(uint8_t(a[row][start + k])) << (8 * byte);
                        }
                        sim.write_word(uint32_t(command.a) + row * 8 + block * 4, word);
                    }
                for (uint32_t k = 0; k < command.k; ++k)
                    for (uint32_t block = 0; block < (n_size + 3) / 4; ++block) {
                        uint32_t word = 0;
                        for (uint32_t byte = 0; byte < 4; ++byte) {
                            uint32_t column = block * 4 + byte;
                            if (column < n_size) word |= uint32_t(uint8_t(b[column][start + k])) << (8 * byte);
                        }
                        sim.write_word(uint32_t(command.b) + k * 16 + block * 4, word);
                    }
                auto result = sim.submit_matrix(++sequence, command);
                if (result.status != 0 || result.sequence != sequence)
                    throw std::runtime_error("workload matrix command failed");
                hardware_cycles += result.cycles;
            }
            for (uint32_t row = 0; row < m_size; ++row)
                for (uint32_t column = 0; column < n_size; ++column) {
                    int32_t expected = 0;
                    for (uint32_t k = 0; k < command.k; ++k)
                        expected += int32_t(a[row][start + k]) * int32_t(b[column][start + k]);
                    int32_t actual = expected;
                    if (hardware) {
                        actual = int32_t(sim.read_word(uint32_t(command.c) + row * 64 + column * 4));
                        if (std::getenv("WORKLOAD_INJECT_FAILURE") && sequence == 1 && row == 0 && column == 0)
                            ++expected;
                        if (actual != expected) throw std::runtime_error("real-workload RTL arithmetic mismatch");
                        ++checked_products;
                    }
                    sums[row * n_size + column] += actual;
                }
        }
        std::vector<float> replacement(m_size);
        for (uint32_t column = 0; column < n_size; ++column) {
            for (uint32_t row = 0; row < m_size; ++row)
                replacement[row] = float(sums[row * n_size + column]) * a_scale[row] * b_scale[column];
            ggml_backend_tensor_set(tensor, replacement.data(), column * tensor->nb[1], m_size * 4);
        }
        if (hardware) {
            replaced_values += m_size * n_size;
            ++hardware_stages;
            tensors.emplace_back(tensor->name);
            inner_dimensions.push_back(k_size); token_counts.push_back(n_size);
        }
    }

    static bool callback(ggml_tensor *tensor, bool ask, void *data) {
        auto &probe = *static_cast<WorkloadProbe *>(data);
        if (ask) return probe.armed && tensor->op == GGML_OP_MUL_MAT &&
            tensor->src[0] && tensor->src[1] && tensor->src[0]->ne[1] >= 8 &&
            tensor->src[0]->ne[2] == 1 && tensor->src[0]->ne[3] == 1 &&
            tensor->ne[2] == 1 && tensor->ne[3] == 1 &&
            tensor->src[1]->type == GGML_TYPE_F32;
        try {
            probe.replace(tensor); probe.armed = false; return true;
        } catch (const std::exception &error) {
            probe.error = error.what(); return false;
        }
    }
};

int main(int argc, char **argv) {
    try {
        if (argc != 3) throw std::runtime_error("usage: workload_probe firmware.bin model.gguf");
        SimHost sim(argv[1]);
        llama_backend_init();
        auto mp = llama_model_default_params(); mp.n_gpu_layers = 0;
        std::unique_ptr<llama_model, decltype(&llama_model_free)> model(
            llama_model_load_from_file(argv[2], mp), llama_model_free);
        if (!model) throw std::runtime_error("model load failed");
        auto *vocab = llama_model_get_vocab(model.get());
        std::string prompt = "The purpose of a hardware accelerator is";
        int count = -llama_tokenize(vocab, prompt.c_str(), int(prompt.size()), nullptr, 0, true, true);
        if (count < 1 || count > 16) throw std::runtime_error("unexpected prompt token count");
        std::vector<llama_token> tokens(count);
        if (llama_tokenize(vocab, prompt.c_str(), int(prompt.size()), tokens.data(), count, true, true) != count)
            throw std::runtime_error("tokenization failed");
        WorkloadProbe probe{sim};
        auto run = [&](int mode) {
            probe.hardware = mode == 2;
            auto cp = llama_context_default_params();
            cp.n_ctx = 256; cp.n_batch = 128; cp.n_ubatch = 128;
            cp.n_threads = 1; cp.n_threads_batch = 1;
            if (mode != 0) { cp.cb_eval = WorkloadProbe::callback; cp.cb_eval_user_data = &probe; }
            std::unique_ptr<llama_context, decltype(&llama_free)> context(
                llama_init_from_model(model.get(), cp), llama_free);
            if (!context) throw std::runtime_error("context creation failed");
            auto batch = llama_batch_get_one(tokens.data(), count);
            llama_token next = 0;
            std::vector<std::vector<float>> logits;
            for (unsigned stage = 0; stage < 2; ++stage) {
                probe.armed = mode != 0;
                if (llama_decode(context.get(), batch) != 0 || !probe.error.empty() || probe.armed)
                    throw std::runtime_error("workload projection was not completed: " + probe.error);
                auto *values = llama_get_logits_ith(context.get(), -1);
                logits.emplace_back(values, values + llama_vocab_n_tokens(vocab));
                next = llama_token(std::max_element(logits.back().begin(), logits.back().end()) - logits.back().begin());
                batch = llama_batch_get_one(&next, 1);
            }
            return logits;
        };
        auto original = run(0);
        auto reference = run(1);
        auto actual = run(2);
        double worst = 0, original_delta = 0;
        uint64_t compared_logits = 0;
        for (size_t stage = 0; stage < reference.size(); ++stage)
            for (size_t i = 0; i < reference[stage].size(); ++i) {
                if (!std::isfinite(reference[stage][i]) || !std::isfinite(actual[stage][i]))
                    throw std::runtime_error("nonfinite workload logits");
                worst = std::max(worst, double(std::abs(reference[stage][i] - actual[stage][i])));
                original_delta = std::max(original_delta, double(std::abs(reference[stage][i] - original[stage][i])));
                ++compared_logits;
            }
        if (worst > 1e-5 || probe.hardware_stages != 2 || probe.sequence == 0 ||
            sim.matrix_reads() == 0 || sim.matrix_writes() == 0 || original_delta == 0)
            throw std::runtime_error("workload result or hardware activity mismatch");
        std::cout << "{\"test\":\"qwen_partial_int8_hardware\",\"prompt_tokens\":" << count
            << ",\"decode_tokens\":1,\"hardware_stages\":" << probe.hardware_stages
            << ",\"hardware_commands\":" << probe.sequence << ",\"command_cycles\":" << probe.hardware_cycles
            << ",\"checked_integer_outputs\":" << probe.checked_products
            << ",\"replaced_projection_values\":" << probe.replaced_values
            << ",\"compared_logits\":" << compared_logits << ",\"max_abs_logit_error\":" << worst
            << ",\"original_model_logit_delta\":" << original_delta
            << ",\"matrix_reads\":" << sim.matrix_reads() << ",\"matrix_writes\":" << sim.matrix_writes()
            << ",\"stages\":[";
        for (size_t i = 0; i < probe.tensors.size(); ++i) {
            if (i) std::cout << ',';
            std::cout << "{\"tensor\":\"" << probe.tensors[i] << "\",\"K\":" << probe.inner_dimensions[i]
                      << ",\"M\":8,\"N\":" << probe.token_counts[i] << '}';
        }
        std::cout << "],\"pass\":true}\n";
        model.reset(); llama_backend_free();
        return 0;
    } catch (const std::exception &error) {
        std::cerr << error.what() << '\n'; return 1;
    }
}
