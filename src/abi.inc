/* abi.inc - hedefe gore dogru mimari katmanini secer */
#ifndef ABI_INC
#define ABI_INC

#include "config.inc"

#if defined(ARCH_X86_64)
#  include "arch/x86_64/abi.inc"
#elif defined(ARCH_I386)
#  include "arch/i386/abi.inc"
#elif defined(ARCH_AARCH64)
#  include "arch/aarch64/abi.inc"
#elif defined(ARCH_ARM)
#  include "arch/arm/abi.inc"
#endif

/* Bolum makrolari: Mach-O ve ELF/PE ayni direktifleri kabul ediyor,
 * ancak ileride ayrismalari icin tek noktadan gecirilir. */
#define SECT_TEXT   .text
#define SECT_DATA   .data
#define SECT_RODATA .section .rodata
#if defined(OS_MACOS)
#  undef  SECT_RODATA
#  define SECT_RODATA .const
#endif

/* Standart dosya tanimlayicilari (Windows'ta handle tablosu indeksi) */
#define FD_STDOUT 1
#define FD_STDERR 2

#endif
