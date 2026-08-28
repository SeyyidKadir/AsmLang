/* codebuf.S - bytecode ve sabit havuzu: DERLEYICI ve YURUTUCU ortak
 *
 * Player ayrimi icin ayrildi: yurutucu lexer/parser/derleyiciye
 * ihtiyac duymadan bu tamponlara erisebilmeli.
 */
#include "../abi.inc"
#include "../tables/opcodes.inc"
#include "../tables/opjump.inc"

    .bss
    .p2align 3
    .globl SYM(g_code)
SYM(g_code):    .space 8
    .globl SYM(g_consts)
SYM(g_consts):  .space 8
    .globl SYM(g_ncode)
SYM(g_ncode):   .space 4
    .globl SYM(g_nconst)
SYM(g_nconst):  .space 4
    .globl SYM(g_nglob)
SYM(g_nglob):   .space 4
    .globl SYM(g_nfn)
SYM(g_nfn):     .space 4
    .globl SYM(g_fns)
SYM(g_fns):     .space (MAX_FRAMES * 8) + GUARD_PAD
/* Kaynak metin isaretcisi: derleme aninda lexer doldurur, yurutucu
 * kipinde bos kalir (dizgiler .bc icinde ham bayt olarak gelir). */
    .globl SYM(g_src)
SYM(g_src):     .space 8

    SECT_TEXT

/* code_at(A0 = indeks) -> RV = komut */
FUNC(code_at)
    ENTER(1)
    SHLI(A0, 2)
    LEA_SYM(A1, SYM(g_code))
    LD(A1, A1)
    ADD(A0, A1)
    LD32(RVW, A0)
    LEAVE_
    RET
ENDFUNC(code_at)

/* code_put(A0 = indeks, A1 = komut) */
FUNC(code_put)
    ENTER(1)
    SPILL(0, A1)
    SHLI(A0, 2)
    LEA_SYM(A1, SYM(g_code))
    LD(A1, A1)
    ADD(A0, A1)
    FILL(A1, 0)
    ST32_OFF(A0, 0, A1W)
    LEAVE_
    RET
ENDFUNC(code_put)
