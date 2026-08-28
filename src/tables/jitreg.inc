/* jitreg.inc - x86-64 register numaralari ve kosul kodlari
 * Hem kodlayici (jitasm.S) hem derleyici (jitcomp.S) kullaniyor.
 * TEK yerde tutulmali: iki yerde tutulan numaralar bu projede
 * uc kez cakismaya yol acti. */
#ifndef JITREG_INC
#define JITREG_INC

/* --- register numaralari (x86-64 kodlamasi) --- */
#define R_AX  0
#define R_CX  1
#define R_DX  2
#define R_BX  3
#define R_SP  4
#define R_BP  5
#define R_SI  6
#define R_DI  7
#define R_8   8
#define R_9   9
#define R_10 10
#define R_11 11
#define R_12 12
#define R_13 13
#define R_14 14
#define R_15 15

/* --- kosul kodlari (jcc'nin ikinci baytindaki dusuk yarim) --- */
#define CC_O   0x0
#define CC_NO  0x1
#define CC_B   0x2
#define CC_AE  0x3
#define CC_E   0x4
#define CC_NE  0x5
#define CC_BE  0x6
#define CC_A   0x7
#define CC_S   0x8
#define CC_NS  0x9
#define CC_L   0xC
#define CC_GE  0xD
#define CC_LE  0xE
#define CC_G   0xF

#endif
