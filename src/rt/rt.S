/* rt.S - calisma zamani yardimcilari (mimariden bagimsiz)
 *
 * print_u32 bolme komutu KULLANMAZ: ARMv7'nin bir kisminda udiv yok ve
 * x86'da div'in register kisitlari makro katmanini kirlietiyor. Onun
 * yerine onluk kuvvetlerinden tekrarli cikarma yapilir - basamak basina
 * en fazla 9 dongu, tam tasinabilir.
 */
#include "../abi.inc"
#include "../tables/tokens.inc"

    .bss
    .p2align 3
    .globl SYM(g_numbuf)
SYM(g_numbuf): .space (32) + GUARD_PAD
    .globl SYM(g_chbuf)
SYM(g_chbuf):  .space (8) + GUARD_PAD

    SECT_RODATA
    .p2align 4/* 10'un kuvvetleri, buyukten kucuge.
 * Tamsayi 64 bite cikinca 10 girdi (10^9) yetmiyor: 10^12 gibi
 * degerler basilamiyordu. 32-bit hedefte ust girdiler zaten
 * kelimeye sigmaz, bu yuzden tablo boyu kelime genisligine bagli. */

    .globl SYM(pow10)
SYM(pow10):
#if WORD_SIZE == 8
    PTR 10000000000000000000
    PTR 1000000000000000000
    PTR 100000000000000000
    PTR 10000000000000000
    PTR 1000000000000000
    PTR 100000000000000
    PTR 10000000000000
    PTR 1000000000000
    PTR 100000000000
    PTR 10000000000
#endif
    PTR 1000000000
    PTR 100000000
    PTR 10000000
    PTR 1000000
    PTR 100000
    PTR 10000
    PTR 1000
    PTR 100
    PTR 10
    PTR 1

    SECT_TEXT

/* print_str(A0 = isaretci, A1 = uzunluk) */
FUNC(print_str)
    ENTER(1)
    MOVR(A2, A1)
    MOVR(A1, A0)
    MOVI(A0, FD_STDOUT)
    CALL(os_write)
    LEAVE_
    RET
ENDFUNC(print_str)

/* print_ch(A0 = karakter) */
FUNC(print_ch)
    ENTER(1)
    LEA_SYM(A1, SYM(g_chbuf))
    STB(A1, A0B)
    MOVR(A0, A1)
    MOVI(A1, 1)
    CALL(print_str)
    LEAVE_
    RET
ENDFUNC(print_ch)

/* print_u32(A0 = deger)
 * Slotlar: 0=deger 1=basladi 2=cikti indeksi 3=kuvvet indeksi
 */
FUNC(print_u32)
    ENTER(4)
    SPILL(0, A0)
    MOVI(A0, 0)
    SPILL(1, A0)
    SPILL(2, A0)
    SPILL(3, A0)

pu_loop:
    FILL(A0, 3)
    CMPI(A0, POW10_N)
    BHS(pu_done)
    LEA_SYM(A1, SYM(pow10))
    LDW_IDX(A1, A1, A0)             /* bolen */
    MOVI(A2, 0)                     /* basamak */
    FILL(A0, 0)                     /* deger */
pu_sub:
    CMPR(A0, A1)
    BLO(pu_emit)
    SUB(A0, A1)
    INC(A2)
    B(pu_sub)

pu_emit:
    SPILL(0, A0)                    /* kalan deger */
    FILL(A0, 1)
    BNZ(A0, pu_put)                 /* zaten basladiysa yaz */
    BNZ(A2, pu_put)                 /* sifirdan farkliysa yaz */
    FILL(A0, 3)
    CMPI(A0, POW10_N - 1)
    BNE(pu_adv)                     /* son basamak degilse bastaki sifiri at */
pu_put:
    MOVI(A0, 1)
    SPILL(1, A0)
    ADDI(A2, 48)                    /* '0' */
    LEA_SYM(A0, SYM(g_numbuf))
    FILL(A1, 2)
    ADD(A0, A1)
    STB(A0, A2B)
    FILL(A0, 2)
    INC(A0)
    SPILL(2, A0)
pu_adv:
    FILL(A0, 3)
    INC(A0)
    SPILL(3, A0)
    B(pu_loop)

pu_done:
    LEA_SYM(A0, SYM(g_numbuf))
    FILL(A1, 2)
    CALL(print_str)
    LEAVE_
    RET
ENDFUNC(print_u32)

/* dump_tokens(A0 = token dizisi, A1 = adet)
 * Bicim:  <satir> <tur> '<sozcuk>'
 */
FUNC(dump_tokens)
    ENTER(2)
    SPILL(0, A0)
    SPILL(1, A1)
dmp_loop:
    FILL(A0, 1)
    BZ(A0, dmp_end)

    FILL(A0, 0)
    LD32_OFF(A1W, A0, TOK_OFF_LINE)
    MOVR(A0, A1)
    CALL(print_u32)
    MOVI(A0, 32)
    CALL(print_ch)

    FILL(A0, 0)
    LD32_OFF(A1W, A0, TOK_OFF_TYPE)
    MOVR(A0, A1)
    CALL(print_u32)
    MOVI(A0, 32)
    CALL(print_ch)
    MOVI(A0, 39)
    CALL(print_ch)

    LEA_SYM(A0, SYM(g_src))
    LD(A0, A0)
    FILL(A1, 0)
    LD32_OFF(A2W, A1, TOK_OFF_START)
    ADD(A0, A2)
    LD32_OFF(A1W, A1, TOK_OFF_LEN)
    CALL(print_str)

    MOVI(A0, 39)
    CALL(print_ch)
    MOVI(A0, 10)
    CALL(print_ch)

    FILL(A0, 0)
    ADDI(A0, TOK_SIZE)
    SPILL(0, A0)
    FILL(A0, 1)
    DEC(A0)
    SPILL(1, A0)
    B(dmp_loop)
dmp_end:
    LEAVE_
    RET
ENDFUNC(dump_tokens)
