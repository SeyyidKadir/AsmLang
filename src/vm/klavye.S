/* klavye.S - PS/2 klavye (yoklamali)
 *
 * Kesme tablosu (IDT) GEREKMEZ: denetleyicinin durum kaydini
 * yokluyoruz. Gercek bir cekirdek icin kesme daha iyi ama
 * bootloader/tanilama icin bu yeterli ve cok daha basit.
 *
 *   0x64 durum kaydi : bit 0 = cikis tamponu dolu (okunacak veri var)
 *   0x60 veri        : tarama kodu
 *
 * TARAMA KODU KUMESI 1 (XT). QEMU varsayilan olarak cevirici kipte
 * calisiyor ve bu kumeyi veriyor. Basma kodu 0x01-0x58;
 * BIRAKMA kodu = basma | 0x80.
 *
 *   tus_var()   -> okunacak tus var mi (bloklamaz)
 *   tus()       -> ASCII bekle ve dondur (bloklar)
 *   tuskod()    -> ham tarama kodu (bloklamaz, yoksa bos)
 *
 * Ayrica os_read'e baglaniyor: bare-metal'de oku() hem seri porttan
 * hem klavyeden okuyor.
 *
 * SINIR: Turkce duzen yok, US duzeni. Shift destekleniyor;
 * CapsLock, Ctrl, Alt yok.
 */
#include "../abi.inc"
#include "../tables/opcodes.inc"

#define SET_RES(tg, py) \
    LEA_SYM(A2, SYM(g_natres)); \
    ST32_OFF(A2, VAL_TAG, tg); \
    ST_OFF(A2, VAL_PAY, py)

#if defined(OS_BARE) && OS_BARE
#  define HAVE_KBD 1
#else
#  define HAVE_KBD 0
#endif
#ifndef BARE_SIM
#  define BARE_SIM 0
#endif

    SECT_RODATA
    .p2align 4
/* Tarama kodu -> ASCII, kume 1. Indeks 0x00..0x39.
 * 0 = eslesme yok (islev tuslari, degistiriciler). */
    .globl SYM(kbd_map)
SYM(kbd_map):
    .byte 0,    27,  '1', '2', '3', '4', '5', '6'    /* 00-07 */
    .byte '7',  '8', '9', '0', '-', '=', 8,   9      /* 08-0F */
    .byte 'q',  'w', 'e', 'r', 't', 'y', 'u', 'i'    /* 10-17 */
    .byte 'o',  'p', '[', ']', 10,  0,   'a', 's'    /* 18-1F */
    .byte 'd',  'f', 'g', 'h', 'j', 'k', 'l', ';'    /* 20-27 */
    .byte 39,   '`', 0,   92,  'z', 'x', 'c', 'v'    /* 28-2F */
    .byte 'b',  'n', 'm', ',', '.', '/', 0,   '*'    /* 30-37 */
    .byte 0,    ' '                                  /* 38-39 */

/* Shift basiliyken */
    .p2align 4
    .globl SYM(kbd_map_shift)
SYM(kbd_map_shift):
    .byte 0,    27,  '!', '@', '#', '$', '%', '^'
    .byte '&',  '*', '(', ')', '_', '+', 8,   9
    .byte 'Q',  'W', 'E', 'R', 'T', 'Y', 'U', 'I'
    .byte 'O',  'P', '{', '}', 10,  0,   'A', 'S'
    .byte 'D',  'F', 'G', 'H', 'J', 'K', 'L', ':'
    .byte '"',  '~', 0,   '|', 'Z', 'X', 'C', 'V'
    .byte 'B',  'N', 'M', '<', '>', '?', 0,   '*'
    .byte 0,    ' '

    .bss
    .p2align 2
    .globl SYM(g_kbd_shift)
SYM(g_kbd_shift): .space 4

    SECT_TEXT

#if HAVE_KBD && !BARE_SIM && (defined(ARCH_X86_64) || defined(ARCH_I386))

/* kbd_hazir() -> RV = 1 ise okunacak veri var */
FUNC(kbd_hazir)
    ENTER(1)
    MOVI(A0, 0x64); MOVI(A1, 1); CALL(port_in)
    MOVR(A0, RV)
    ANDI(A0, 1)
    MOVR(RV, A0)
    LEAVE_
    RET
ENDFUNC(kbd_hazir)

/* kbd_ham() -> RV = tarama kodu, yoksa -1 */
FUNC(kbd_ham)
    ENTER(1)
    CALL(kbd_hazir)
    BZ(RV, kh_yok)
    MOVI(A0, 0x60); MOVI(A1, 1); CALL(port_in)
    LEAVE_
    RET
kh_yok:
    MOVI(RV, -1)
    LEAVE_
    RET
ENDFUNC(kbd_ham)

/* kbd_ascii() -> RV = ASCII, yoksa 0
 * Degistirici tuslari izler, birakma kodlarini yutar. */
FUNC(kbd_ascii)
    ENTER(2)
    CALL(kbd_ham)
    /* i386'da RV == A0 == %eax. "MOVI(A0, -1)" donus degerini
     * EZIYORDU: karsilastirma hep esit cikiyor, hicbir tus
     * gorulmuyordu. Bu projede bu sinifin YEDINCI ornegi;
     * once slota dokup sonra karsilastiriyoruz. */
    SPILL(0, RV)
    MOVI(A0, -1)
    FILL(A1, 0)
    CMPR(A1, A0)
    BEQ(ka_yok)
    /* birakma kodu mu (bit 7) */
    FILL(A0, 0)
    ANDI(A0, 0x80)
    BZ(A0, ka_basma)
    /* birakma: yalniz shift'i takip et */
    FILL(A0, 0)
    ANDI(A0, 0x7F)
    CMPI(A0, 0x2A); BEQ(ka_shift_off)
    CMPI(A0, 0x36); BEQ(ka_shift_off)
    B(ka_yok)
ka_shift_off:
    MOVI(A0, 0)
    LEA_SYM(A1, SYM(g_kbd_shift)); ST32_OFF(A1, 0, A0W)
    B(ka_yok)
ka_basma:
    FILL(A0, 0)
    CMPI(A0, 0x2A); BEQ(ka_shift_on)
    CMPI(A0, 0x36); BEQ(ka_shift_on)
    CMPI(A0, 0x3A); BEQ(ka_yok)     /* CapsLock: yok sayiliyor */
    CMPI(A0, 0x39)
    BHI(ka_yok)                     /* tablo disi */
    LEA_SYM(A1, SYM(g_kbd_shift))
    LD32(A1W, A1)
    BZ(A1, ka_normal)
    LEA_SYM(A1, SYM(kbd_map_shift))
    B(ka_look)
ka_normal:
    LEA_SYM(A1, SYM(kbd_map))
ka_look:
    LDB_IDX(A0W, A1, A0)
    MOVR(RV, A0)
    LEAVE_
    RET
ka_shift_on:
    MOVI(A0, 1)
    LEA_SYM(A1, SYM(g_kbd_shift)); ST32_OFF(A1, 0, A0W)
ka_yok:
    MOVI(RV, 0)
    LEAVE_
    RET
ENDFUNC(kbd_ascii)

#else

FUNC(kbd_hazir)
    MOVI(RV, 0)
    RET
ENDFUNC(kbd_hazir)

FUNC(kbd_ham)
    MOVI(RV, -1)
    RET
ENDFUNC(kbd_ham)

FUNC(kbd_ascii)
    MOVI(RV, 0)
    RET
ENDFUNC(kbd_ascii)

#endif

/* ---------------- govde fonksiyonlari ---------------- */

/* tus_var() -> dogru/yanlis */
FUNC(nat_keyhit)
    ENTER(1)
#if HAVE_KBD && !BARE_SIM
    CALL(kbd_hazir)
    MOVR(A1, RV)
    MOVI(A0, T_BOOL)
    SET_RES(A0W, A1)
    LEAVE_
    RET
#endif
    CALL(nat_ret_nil)
    LEAVE_
    RET
ENDFUNC(nat_keyhit)

/* tuskod() -> ham tarama kodu ya da bos */
FUNC(nat_scancode)
    ENTER(2)
#if HAVE_KBD && !BARE_SIM
    CALL(kbd_ham)
    SPILL(0, RV)                    /* RV == A0: once sakla */
    MOVI(A0, -1)
    FILL(A1, 0)
    CMPR(A1, A0)
    BEQ(nsc_nil)
    FILL(A0, 0)
    CALL(ret_int)
    LEAVE_
    RET
#endif
nsc_nil:
    CALL(nat_ret_nil)
    LEAVE_
    RET
ENDFUNC(nat_scancode)

/* tus() -> ASCII bekle. Argumansiz BLOKLAR; bir argumanla
 * (herhangi bir deger) BLOKLAMAZ, tus yoksa bos doner. */
FUNC(nat_key)
    ENTER(2)
#if HAVE_KBD && !BARE_SIM
    SPILL(0, A1)
nk_loop:
    CALL(kbd_ascii)
    BNZ(RV, nk_var)
    FILL(A0, 0)
    BNZ(A0, nk_nil)                 /* bloklamayan kip */
    B(nk_loop)
nk_var:
    MOVR(A0, RV)
    CALL(ret_int)
    LEAVE_
    RET
#endif
nk_nil:
    CALL(nat_ret_nil)
    LEAVE_
    RET
ENDFUNC(nat_key)
