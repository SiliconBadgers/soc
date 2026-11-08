OUTPUT_ARCH(riscv)
ENTRY(_start)
MEMORY { ram (rwx) : ORIGIN = 0x80, LENGTH = 0x3f80 }
SECTIONS {
    .text : { KEEP(*(.text.start)) *(.text .text.*) } > ram
    .rodata : { *(.rodata .rodata.*) } > ram
    .data : { *(.data .data.*) *(.sdata .sdata.*) } > ram
    .bss (NOLOAD) : {
        . = ALIGN(4);
        __bss_start = .;
        *(.bss .bss.*) *(.sbss .sbss.*) *(COMMON)
        . = ALIGN(4);
        __bss_end = .;
    } > ram
    __stack_top = 0x4000;
    ASSERT(__bss_end <= __stack_top - 0x400, "Firmware leaves less than 1 KiB stack")
}
