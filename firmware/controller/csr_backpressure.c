#include "controller_regs.h"

_Static_assert(CONTROLLER_PAYLOAD_WIDTH == 512, "Test uses complete 512-bit records");
_Static_assert(CONTROLLER_COUNTER_WIDTH == 32, "Test uses 32-bit milestones");
static volatile uint32_t initialized_cookie = 0x87654321u;
static volatile uint32_t zero_cookie;

// Keep pointer-based accesses visible to the compiler's alignment analysis.
__attribute__((noinline)) void submit(
    uintptr_t base, uint32_t queue_offset, unsigned serial,
    uint32_t dependency_0, uint32_t dependency_1) {
    controller_write32(base, queue_offset, dependency_0);
    controller_write32(base, queue_offset + 4, dependency_1);
    for (unsigned word = 0; word < CONTROLLER_PAYLOAD_WIDTH / 32; ++word) {
        controller_write32(base, queue_offset + 0x20 + word * 4,
                           0xc1000000u + (serial << 8) + word);
    }
    controller_write32(base, queue_offset + 8, 1);
}

__attribute__((noinline)) int run(uintptr_t base) {
    volatile uint32_t scratch[4] = {1, 2, 3, 4};
    if (controller_read32(base, CONTROLLER_ABI_VERSION_OFFSET) != 1 ||
        controller_read32(base, CONTROLLER_JOB_ARG_OFFSET) != 0x13579bdfu ||
        initialized_cookie != 0x87654321u || zero_cookie != 0 ||
        scratch[0] + scratch[1] + scratch[2] + scratch[3] != 10) {
        controller_write32(base, CONTROLLER_RESULT_OFFSET, 0xbad00001u);
        return 1;
    }
    // With depth two and the engine stalled, the third COMMIT waits for capacity.
    submit(base, CONTROLLER_QUEUE_0_DEPENDENCY_0_OFFSET, 1, 0, 0);
    submit(base, CONTROLLER_QUEUE_0_DEPENDENCY_0_OFFSET, 2, 0, 0);
    submit(base, CONTROLLER_QUEUE_0_DEPENDENCY_0_OFFSET, 3, 0, 0);
    submit(base, CONTROLLER_QUEUE_1_DEPENDENCY_0_OFFSET, 4, 3, 1);
    submit(base, CONTROLLER_QUEUE_2_DEPENDENCY_0_OFFSET, 5, 3, 0);
    controller_write32(base, CONTROLLER_WAIT_TARGET_0_OFFSET, 3);
    controller_write32(base, CONTROLLER_WAIT_TARGET_1_OFFSET, 1);
    controller_write32(base, CONTROLLER_WAIT_TARGET_2_OFFSET, 1);
    controller_write32(base, CONTROLLER_WAIT_ARM_OFFSET, 7);
    while ((controller_read32(base, CONTROLLER_WAIT_STATUS_OFFSET) & 2) == 0) {
    }
    controller_write32(base, CONTROLLER_RESULT_OFFSET, 0x600dc0deu);
    controller_write32(base, CONTROLLER_FINISH_OFFSET, 1);
    return 0;
}

int main(void) {
    return run(0x40000000u);
}
