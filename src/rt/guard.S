/* guard.S - tampon kanaryalari
 *
 * Her sabit tamponun sonundaki GUARD_PAD bolgesine sihirli deger
 * yazilir; kontrol noktalarinda dogrulanir. Amac tasmayi onlemek
 * degil, SESSIZ bozulmayi gorunur kilmak.
 */
#include "../abi.inc"
#include "../tables/opcodes.inc"
#include "../tables/ast.inc"

    SECT_RODATA
gd_pre:  .ascii "GUARD BOZULDU: "
    .equ gd_pre_len, . - gd_pre
gd_at:   .ascii " (kontrol noktasi "
    .equ gd_at_len, . - gd_at
gd_end:  .ascii ")\n"
    .equ gd_end_len, . - gd_end

#define GNAME(n) n_##n: .ascii #n; .byte 0
    GNAME(g_numbuf)
    GNAME(g_chbuf)
    GNAME(g_objs)
    GNAME(g_hfree)
    GNAME(g_strbuf)
    GNAME(g_joinbuf)
    GNAME(g_inbuf)
    GNAME(g_filebuf)
    GNAME(g_stack)
    GNAME(g_gvals)
    GNAME(g_frames)
    GNAME(g_fns)

/* Tablo .rodata'da MUTLAK ADRES tutamaz: bu, Asama 2'den beri
 * korunan "sifir yer degistirme kaydi" degismezini kirar ve
 * static-pie baglamayi bozar (Android/Termux ve ileride cekirdek
 * imaji icin sart). Bu yuzden tablo .bss'te ve guard_init tarafindan
 * PC-goreli LEA_SYM ile CALISMA ANINDA dolduruluyor. */
#define GUARD_N 12

    .bss
    .p2align 3
    .globl SYM(g_guards)
SYM(g_guards): .space GUARD_N * 8
    .globl SYM(g_gnames)
SYM(g_gnames): .space GUARD_N * 8
    .p2align 2
    .globl SYM(g_gderr)
SYM(g_gderr): .space 4

    SECT_TEXT

/* guard_init() - butun kanaryalari yaz */
/* Bir tamponu kaydet: adres ve ad PC-goreli hesaplanir */
#define GREG(i, n, sz) \
    LEA_SYM(A0, SYM(n)); ADDI(A0, (sz)); \
    LEA_SYM(A1, SYM(g_guards)); ADDI(A1, (i) * WORD_SIZE); ST(A1, A0); \
    MOVI(A2, GUARD_MAGIC); ST32_OFF(A0, 0, A2W); \
    LEA_SYM(A0, n_##n); \
    LEA_SYM(A1, SYM(g_gnames)); ADDI(A1, (i) * WORD_SIZE); ST(A1, A0)

FUNC(guard_init)
    ENTER(1)
    MOVI(A0, 0)
    LEA_SYM(A1, SYM(g_gderr))
    ST32_OFF(A1, 0, A0W)
    GREG(0, g_numbuf, 32)
    GREG(1, g_chbuf, 8)
    GREG(2, g_objs, MAX_OBJS * 8)
    GREG(3, g_hfree, MAX_OBJS * 4)
    GREG(4, g_strbuf, 4096)
    GREG(11, g_joinbuf, 4096)
    GREG(5, g_inbuf, 4096)
    GREG(6, g_filebuf, FILE_BUF_SIZE)
    GREG(7, g_stack, VM_STACK_BYTES)
    GREG(8, g_gvals, MAX_GLOBALS * VAL_SIZE)
    GREG(9, g_frames, MAX_FRAMES * 8)
    GREG(10, g_fns, MAX_FRAMES * 8)
    LEAVE_
    RET
ENDFUNC(guard_init)

/* guard_check(A0 = kontrol noktasi no) -> RV = bozulan sayisi */
FUNC(guard_check)
    ENTER(3)
    SPILL(1, A0)                    /* kontrol noktasi */
    MOVI(A0, 0)
    SPILL(0, A0)                    /* i */
    SPILL(2, A0)                    /* bozulan */
gc_loop:
    FILL(A0, 0)
    CMPI(A0, GUARD_N)
    BHS(gc_done)
    SHLI(A0, WORD_SHIFT)
    LEA_SYM(A1, SYM(g_guards))
    ADD(A0, A1)
    LD(A1, A0)
    LD32(A2W, A1)
    CMPI(A2, GUARD_MAGIC)
    BEQ(gc_next)
    FILL(A0, 2); INC(A0); SPILL(2, A0)
    LEA_SYM(A0, SYM(g_gderr))
    LD32(A1W, A0)
    INC(A1)
    ST32_OFF(A0, 0, A1W)
    LEA_SYM(A0, gd_pre); MOVI(A1, gd_pre_len); CALL(print_str)
    FILL(A0, 0)
    SHLI(A0, WORD_SHIFT)
    LEA_SYM(A1, SYM(g_gnames))
    ADD(A0, A1)
    LD(A0, A0)
    CALL(print_cstr)
    LEA_SYM(A0, gd_at); MOVI(A1, gd_at_len); CALL(print_str)
    FILL(A0, 1); CALL(print_u32)
    LEA_SYM(A0, gd_end); MOVI(A1, gd_end_len); CALL(print_str)
    /* yeniden yaz: ayni hata her kontrol noktasinda tekrarlanmasin */
    FILL(A0, 0)
    SHLI(A0, WORD_SHIFT)
    LEA_SYM(A1, SYM(g_guards))
    ADD(A0, A1)
    LD(A1, A0)
    MOVI(A2, GUARD_MAGIC)
    ST32_OFF(A1, 0, A2W)
gc_next:
    FILL(A0, 0)
    INC(A0)
    SPILL(0, A0)
    B(gc_loop)
gc_done:
    FILL(RV, 2)
    LEAVE_
    RET
ENDFUNC(guard_check)

/* print_cstr(A0 = NUL ile biten dizgi) */
FUNC(print_cstr)
    ENTER(2)
    SPILL(0, A0)
    MOVI(A1, 0)
    SPILL(1, A1)
pc_len:
    FILL(A0, 0)
    FILL(A1, 1)
    LDB_IDX(A2W, A0, A1)
    BZ(A2, pc_out)
    FILL(A1, 1); INC(A1); SPILL(1, A1)
    B(pc_len)
pc_out:
    FILL(A0, 0)
    FILL(A1, 1)
    CALL(print_str)
    LEAVE_
    RET
ENDFUNC(print_cstr)
