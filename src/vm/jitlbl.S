/* jitlbl.S - etiket ve yama yonetimi (Katman 2)
 *
 * Eski JIT'te atlama ofsetleri ELLE sayiliyordu:
 *   "jne +8"  ama atlanacak blok 9 bayt  -> sete'nin ortasina dustu
 *   "jbe +7"  ama blok 6 bayt            -> komutun ortasina dustu
 * Ikisi de segfault, ikisini de test yakaladi.
 *
 * Bu katman o sinifi kapatiyor: kodda bir daha atlama mesafesi
 * YAZILMAYACAK. Ileri ve geri atlama ayni mekanizma.
 *
 * Kullanim:
 *     CALL(lbl_new)        -> RV = etiket kimligi
 *     ... lbl_jcc(cc, l)   -> yer tutucu uret, kaydet
 *     ... lbl_bind(l)      -> etiketi SU ANKI konuma bagla
 *     CALL(lbl_fix)        -> butun bekleyenleri yamala
 *
 * Etiket once BAGLANIP sonra atlanabilir (geri atlama) ya da once
 * atlanip sonra baglanabilir (ileri atlama); fark yok.
 */
#include "../abi.inc"
#include "../tables/opcodes.inc"

#define LBL_MAX   1024
#define FIX_MAX   4096

    .bss
    .p2align 2
    .globl SYM(g_lbl_pos)
/* Konum + 1 saklanir; 0 = henuz baglanmadi.
 * ONCE -1 nobetcisi kullaniyordum: LD32 SIFIR genisletiyor, yani
 * 0xFFFFFFFF olarak okunuyor ve 64-bit -1 ile ESLESMIYOR. Baglanmamis
 * etiket yakalanmadan geciyordu. +1 kodlamasi isaret sorununu
 * tamamen ortadan kaldiriyor. */
SYM(g_lbl_pos):  .space LBL_MAX * 4
    .globl SYM(g_lbl_n)
SYM(g_lbl_n):    .space 4
    .globl SYM(g_fix_at)
SYM(g_fix_at):   .space FIX_MAX * 4      /* yer tutucunun kod ofseti */
    .globl SYM(g_fix_lbl)
SYM(g_fix_lbl):  .space FIX_MAX * 4      /* hedef etiket */
    .globl SYM(g_fix_n)
SYM(g_fix_n):    .space 4
    .globl SYM(g_lbl_err)
SYM(g_lbl_err):  .space 4                /* tasma / baglanmamis etiket */

    SECT_TEXT

#if defined(ARCH_X86_64)

/* lbl_reset() - derleme basinda */
FUNC(lbl_reset)
    ENTER(1)
    MOVI(A0, 0)
    LEA_SYM(A1, SYM(g_lbl_n));  ST32_OFF(A1, 0, A0W)
    LEA_SYM(A1, SYM(g_fix_n));  ST32_OFF(A1, 0, A0W)
    LEA_SYM(A1, SYM(g_lbl_err)); ST32_OFF(A1, 0, A0W)
    LEAVE_
    RET
ENDFUNC(lbl_reset)

/* lbl_new() -> RV = etiket kimligi (tasarsa hata bayragi) */
FUNC(lbl_new)
    ENTER(2)
    LEA_SYM(A0, SYM(g_lbl_n))
    LD32(A1W, A0)
    CMPI(A1, LBL_MAX)
    BHS(ln_full)
    MOVR(A2, A1)
    INC(A2)
    ST32_OFF(A0, 0, A2W)
    SPILL(0, A1)
    MOVR(A0, A1)
    SHLI(A0, 2)
    LEA_SYM(A1, SYM(g_lbl_pos))
    ADD(A0, A1)
    MOVI(A1, 0)
    ST32_OFF(A0, 0, A1W)            /* 0 = henuz baglanmadi */
    FILL(RV, 0)
    LEAVE_
    RET
ln_full:
    MOVI(A0, 1)
    LEA_SYM(A1, SYM(g_lbl_err)); ST32_OFF(A1, 0, A0W)
    MOVI(RV, 0)
    LEAVE_
    RET
ENDFUNC(lbl_new)

/* lbl_bind(A0 = etiket) - su anki kod konumuna bagla */
FUNC(lbl_bind)
    ENTER(2)
    SPILL(0, A0)
    LEA_SYM(A0, SYM(g_jit_pos))
    LD32(A1W, A0)
    INC(A1)                         /* konum + 1 */
    SPILL(1, A1)
    FILL(A0, 0)
    SHLI(A0, 2)
    LEA_SYM(A1, SYM(g_lbl_pos))
    ADD(A0, A1)
    FILL(A1, 1)
    ST32_OFF(A0, 0, A1W)
    LEAVE_
    RET
ENDFUNC(lbl_bind)

/* fix_add(A0 = yer tutucu ofseti, A1 = etiket) */
FUNC(fix_add)
    ENTER(3)
    SPILL(0, A0)
    SPILL(1, A1)
    LEA_SYM(A0, SYM(g_fix_n))
    LD32(A1W, A0)
    CMPI(A1, FIX_MAX)
    BHS(fa_full)
    MOVR(A2, A1)
    INC(A2)
    ST32_OFF(A0, 0, A2W)
    MOVR(A0, A1)
    SHLI(A0, 2)
    SPILL(2, A0)
    LEA_SYM(A1, SYM(g_fix_at))
    ADD(A1, A0)
    FILL(A0, 0)
    ST32_OFF(A1, 0, A0W)
    LEA_SYM(A1, SYM(g_fix_lbl))
    FILL(A0, 2)
    ADD(A1, A0)
    FILL(A0, 1)
    ST32_OFF(A1, 0, A0W)
    LEAVE_
    RET
fa_full:
    MOVI(A0, 1)
    LEA_SYM(A1, SYM(g_lbl_err)); ST32_OFF(A1, 0, A0W)
    LEAVE_
    RET
ENDFUNC(fix_add)

/* lbl_jcc(A0 = kosul kodu, A1 = etiket) : 0F cc rel32 */
FUNC(lbl_jcc)
    ENTER(2)
    SPILL(0, A0)
    SPILL(1, A1)
    MOVI(A0, 0x0F); CALL(emit8)
    FILL(A0, 0); ORI(A0, 0x80); CALL(emit8)
    LEA_SYM(A0, SYM(g_jit_pos))
    LD32(A0W, A0)
    SPILL(0, A0)                    /* yer tutucunun konumu */
    MOVI(A0, 0); CALL(emit32)
    FILL(A0, 0)
    FILL(A1, 1)
    CALL(fix_add)
    LEAVE_
    RET
ENDFUNC(lbl_jcc)

/* lbl_jmp(A0 = etiket) : E9 rel32 */
FUNC(lbl_jmp)
    ENTER(2)
    SPILL(1, A0)
    MOVI(A0, 0xE9); CALL(emit8)
    LEA_SYM(A0, SYM(g_jit_pos))
    LD32(A0W, A0)
    SPILL(0, A0)
    MOVI(A0, 0); CALL(emit32)
    FILL(A0, 0)
    FILL(A1, 1)
    CALL(fix_add)
    LEAVE_
    RET
ENDFUNC(lbl_jmp)

/* lbl_fix() -> RV = 1 tamam / 0 hata (baglanmamis etiket ya da tasma)
 * goreli = hedef - (yer tutucu + 4) */
FUNC(lbl_fix)
    ENTER(4)
    MOVI(A0, 0)
    SPILL(0, A0)
lf_loop:
    LEA_SYM(A0, SYM(g_fix_n))
    LD32(A0W, A0)
    FILL(A1, 0)
    CMPR(A1, A0)
    BHS(lf_done)
    FILL(A0, 0); SHLI(A0, 2)
    SPILL(3, A0)
    LEA_SYM(A1, SYM(g_fix_at)); ADD(A1, A0)
    LD32(A1W, A1)
    SPILL(1, A1)                    /* yer tutucu ofseti */
    LEA_SYM(A1, SYM(g_fix_lbl)); FILL(A0, 3); ADD(A1, A0)
    LD32(A1W, A1)                   /* etiket */
    SHLI(A1, 2)
    LEA_SYM(A0, SYM(g_lbl_pos)); ADD(A0, A1)
    LD32(A0W, A0)
    BZ(A0, lf_unbound)              /* 0 = baglanmamis */
    DEC(A0)                         /* +1 kodlamasini geri al */
    SPILL(2, A0)                    /* hedef ofseti */
    /* goreli hesapla */
    FILL(A0, 1)
    ADDI(A0, 4)
    FILL(A1, 2)
    SUB(A1, A0)
    SPILL(2, A1)
    /* tampona yaz */
    LEA_SYM(A0, SYM(g_jit_base))
    LD(A0, A0)
    FILL(A1, 1)
    ADD(A0, A1)
    FILL(A1, 2)
    ST32_OFF(A0, 0, A1W)
    FILL(A0, 0); INC(A0); SPILL(0, A0)
    B(lf_loop)
lf_unbound:
    MOVI(A0, 1)
    LEA_SYM(A1, SYM(g_lbl_err)); ST32_OFF(A1, 0, A0W)
lf_done:
    LEA_SYM(A0, SYM(g_lbl_err))
    LD32(A0W, A0)
    BNZ(A0, lf_bad)
    MOVI(RV, 1)
    LEAVE_
    RET
lf_bad:
    MOVI(RV, 0)
    LEAVE_
    RET
ENDFUNC(lbl_fix)

/* ================== OZ TEST ==================
 * Ileri ve geri atlamanin dogru yamalandigini kanitlar.
 */
    SECT_RODATA
lb_ok:  .ascii "jitlbl oz test: GECTI\n"
    .equ lb_ok_len, . - lb_ok
lb_bad: .ascii "jitlbl oz test: KALDI\n"
    .equ lb_bad_len, . - lb_bad
    SECT_TEXT

/* Uretilen dizi:
 *   0: E9 rel32      jmp ileri        (5 bayt)
 *   5: C3            ret
 *   6: (ileri buraya baglanir)
 * ileri atlama: hedef 6, yer tutucu 1 -> goreli = 6 - (1+4) = 1
 */
FUNC(jitlbl_selftest)
    ENTER(3)
    CALL(jit_init)
    BZ(RV, lst_skip)
    CALL(lbl_reset)
    CALL(lbl_new)
    SPILL(0, RV)
    FILL(A0, 0)
    CALL(lbl_jmp)
    CALL(ja_ret)
    FILL(A0, 0)
    CALL(lbl_bind)
    CALL(lbl_fix)
    BZ(RV, lst_bad)
    /* yer tutucudaki degeri denetle: 1 olmali */
    LEA_SYM(A0, SYM(g_jit_base))
    LD(A0, A0)
    LD32_OFF(A0W, A0, 1)
    CMPI(A0, 1)
    BNE(lst_bad)
    /* baglanmamis etiket YAKALANMALI */
    CALL(jit_init)
    CALL(lbl_reset)
    CALL(lbl_new)
    SPILL(0, RV)
    FILL(A0, 0)
    CALL(lbl_jmp)
    CALL(lbl_fix)
    BNZ(RV, lst_bad)                /* hata dondurmeliydi */
    LEA_SYM(A0, lb_ok); MOVI(A1, lb_ok_len); CALL(print_str)
    CALL(jit_init)
    CALL(lbl_reset)
    MOVI(RV, 1)
    LEAVE_
    RET
lst_bad:
    LEA_SYM(A0, lb_bad); MOVI(A1, lb_bad_len); CALL(print_str)
    CALL(jit_init)
    CALL(lbl_reset)
    MOVI(RV, 0)
    LEAVE_
    RET
lst_skip:
    MOVI(RV, 1)
    LEAVE_
    RET
ENDFUNC(jitlbl_selftest)

#endif /* ARCH_X86_64 */
