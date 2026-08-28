/* fare.S - PS/2 fare (yoklamali)
 *
 * Klavyeyle AYNI denetleyiciden (8042) gecer, ikinci kanaldan.
 * Kesme (IRQ12) yerine yokluyoruz: IDT gerekmiyor.
 *
 *   0x64 durum : bit 0 = okunacak veri var
 *                bit 1 = giris tamponu DOLU (yazmadan once bosalmali)
 *                bit 5 = veri FARE'den geliyor (klavyeden degil)
 *   0x64 komut : 0xA8 ikinci kanali ac
 *                0xD4 "sonraki bayti FAREYE gonder"
 *   0x60 veri
 *
 * PAKET (3 bayt):
 *   0: bayraklar  bit0 sol, bit1 sag, bit2 orta, bit3 HEP 1,
 *                 bit4 X isareti, bit5 Y isareti, bit6/7 tasma
 *   1: X farki
 *   2: Y farki (pozitif = YUKARI)
 *
 * bit3'un hep 1 olmasi paket HIZALAMASI icin kullaniliyor: ilk
 * bayt olmayan bir seyi ilk bayt sanmamak icin.
 *
 *   fare_kur()  -> baslat (bir kez)
 *   fare_var()  -> yeni paket geldi mi
 *   fare()      -> [x, y, dugmeler]
 *
 * SINIR: 3 baytlik standart paket. Tekerlek (4 bayt, IntelliMouse)
 * yok. Y ekranin yukarisi pozitif kabul ediliyor; grafik icin
 * ters cevrilmesi gerekebilir.
 */
#include "../abi.inc"
#include "../tables/opcodes.inc"

#define SET_RES(tg, py) \
    LEA_SYM(A2, SYM(g_natres)); \
    ST32_OFF(A2, VAL_TAG, tg); \
    ST_OFF(A2, VAL_PAY, py)

#if defined(OS_BARE) && OS_BARE
#  define HAVE_MOUSE 1
#else
#  define HAVE_MOUSE 0
#endif
#ifndef BARE_SIM
#  define BARE_SIM 0
#endif

    .bss
    .p2align 3
    .globl SYM(g_ms_x)
SYM(g_ms_x):    .space 8            /* biriken konum */
    .globl SYM(g_ms_y)
SYM(g_ms_y):    .space 8
    .globl SYM(g_ms_btn)
SYM(g_ms_btn):  .space 8
    .globl SYM(g_ms_buf)
SYM(g_ms_buf):  .space 8 * 3        /* toplanan paket */
    .globl SYM(g_ms_n)
SYM(g_ms_n):    .space 8            /* kac bayt toplandi */
    .globl SYM(g_ms_ok)
SYM(g_ms_ok):   .space 8            /* kuruldu mu */
    .globl SYM(g_ms_yeni)
SYM(g_ms_yeni): .space 8            /* okunmamis paket var mi */

    SECT_TEXT

#if HAVE_MOUSE && !BARE_SIM && (defined(ARCH_X86_64) || defined(ARCH_I386))

/* ms_bekle_yaz() - giris tamponu bosalana kadar bekle (bit 1 = 0) */
FUNC(ms_bekle_yaz)
    ENTER(1)
    MOVI(A0, 100000)
    SPILL(0, A0)
mbw_l:
    FILL(A0, 0)
    BZ(A0, mbw_d)
    DEC(A0)
    SPILL(0, A0)
    MOVI(A0, 0x64); MOVI(A1, 1); CALL(port_in)
    MOVR(A0, RV)
    ANDI(A0, 2)
    BNZ(A0, mbw_l)
mbw_d:
    LEAVE_
    RET
ENDFUNC(ms_bekle_yaz)

/* ms_bekle_oku() -> RV = 1 ise veri hazir (bit 0 = 1) */
FUNC(ms_bekle_oku)
    ENTER(1)
    MOVI(A0, 100000)
    SPILL(0, A0)
mbo_l:
    FILL(A0, 0)
    BZ(A0, mbo_yok)
    DEC(A0)
    SPILL(0, A0)
    MOVI(A0, 0x64); MOVI(A1, 1); CALL(port_in)
    MOVR(A0, RV)
    ANDI(A0, 1)
    BZ(A0, mbo_l)
    MOVI(RV, 1)
    LEAVE_
    RET
mbo_yok:
    MOVI(RV, 0)
    LEAVE_
    RET
ENDFUNC(ms_bekle_oku)

/* ms_komut(A0 = bayt) - FAREYE komut gonder, yanit (ACK) yut */
FUNC(ms_komut)
    ENTER(1)
    SPILL(0, A0)
    CALL(ms_bekle_yaz)
    MOVI(A0, 0x64); MOVI(A1, 0xD4); MOVI(A2, 1); CALL(port_out)
    CALL(ms_bekle_yaz)
    MOVI(A0, 0x60); FILL(A1, 0); MOVI(A2, 1); CALL(port_out)
    CALL(ms_bekle_oku)
    BZ(RV, mk_d)
    MOVI(A0, 0x60); MOVI(A1, 1); CALL(port_in)   /* ACK yut */
mk_d:
    LEAVE_
    RET
ENDFUNC(ms_komut)

/* ms_kur() -> RV = 1 */
FUNC(ms_kur)
    ENTER(2)
    /* ikinci kanali ac */
    CALL(ms_bekle_yaz)
    MOVI(A0, 0x64); MOVI(A1, 0xA8); MOVI(A2, 1); CALL(port_out)
    /* yapilandirma baytini oku, ikinci kanal saatini AC (bit 5 = 0) */
    CALL(ms_bekle_yaz)
    MOVI(A0, 0x64); MOVI(A1, 0x20); MOVI(A2, 1); CALL(port_out)
    CALL(ms_bekle_oku)
    BZ(RV, mkr_d)
    MOVI(A0, 0x60); MOVI(A1, 1); CALL(port_in)
    MOVR(A0, RV)
    ANDI(A0, 0xDF)                  /* bit 5 temizle: saat acik */
    ORI(A0, 0x02)                   /* bit 1: ikinci kanal kesmesi */
    SPILL(0, A0)
    CALL(ms_bekle_yaz)
    MOVI(A0, 0x64); MOVI(A1, 0x60); MOVI(A2, 1); CALL(port_out)
    CALL(ms_bekle_yaz)
    MOVI(A0, 0x60); FILL(A1, 0); MOVI(A2, 1); CALL(port_out)
mkr_d:
    MOVI(A0, 0xF6); CALL(ms_komut)  /* varsayilanlar */
    MOVI(A0, 0xF4); CALL(ms_komut)  /* veri bildirimini AC */
    MOVI(A0, 0)
    LEA_SYM(A1, SYM(g_ms_x));    ST(A1, A0)
    LEA_SYM(A1, SYM(g_ms_y));    ST(A1, A0)
    LEA_SYM(A1, SYM(g_ms_btn));  ST(A1, A0)
    LEA_SYM(A1, SYM(g_ms_n));    ST(A1, A0)
    LEA_SYM(A1, SYM(g_ms_yeni)); ST(A1, A0)
    MOVI(A0, 1)
    LEA_SYM(A1, SYM(g_ms_ok));   ST(A1, A0)
    MOVI(RV, 1)
    LEAVE_
    RET
ENDFUNC(ms_kur)

/* ms_yokla() - bekleyen fare baytlarini topla, paket tamamlaninca
 * konumu guncelle. Bloklamaz. */
FUNC(ms_yokla)
    ENTER(4)
my_loop:
    MOVI(A0, 0x64); MOVI(A1, 1); CALL(port_in)
    MOVR(A0, RV)
    SPILL(0, A0)
    ANDI(A0, 1)
    BZ(A0, my_d)                    /* veri yok */
    FILL(A0, 0)
    ANDI(A0, 0x20)
    BNZ(A0, my_fare)
    /* klavye baytiysa DOKUNMA: klavye surucusu okusun */
    B(my_d)
my_fare:
    MOVI(A0, 0x60); MOVI(A1, 1); CALL(port_in)
    SPILL(1, RV)
    LEA_SYM(A0, SYM(g_ms_n))
    LD(A0, A0)
    SPILL(2, A0)
    /* ilk bayt olmasi gereken yerde bit3 = 1 degilse HIZALAMA
     * bozuk: bayti at ve bastan basla. */
    BNZ(A0, my_koy)
    FILL(A0, 1)
    ANDI(A0, 0x08)
    BZ(A0, my_loop)
my_koy:
    FILL(A0, 2); SHLI(A0, 3)
    LEA_SYM(A1, SYM(g_ms_buf)); ADD(A0, A1)
    FILL(A1, 1)
    ST(A0, A1)
    FILL(A0, 2); INC(A0)
    LEA_SYM(A1, SYM(g_ms_n)); ST(A1, A0)
    CMPI(A0, 3)
    BLO(my_loop)
    CALL(ms_paket)
    MOVI(A0, 0)
    LEA_SYM(A1, SYM(g_ms_n)); ST(A1, A0)
    MOVI(A0, 1)
    LEA_SYM(A1, SYM(g_ms_yeni)); ST(A1, A0)
    B(my_loop)
my_d:
    LEAVE_
    RET
ENDFUNC(ms_yokla)

/* ms_paket() - tamamlanan 3 bayti konuma isle */
FUNC(ms_paket)
    ENTER(3)
    LEA_SYM(A0, SYM(g_ms_buf))
    LD(A1, A0)                      /* bayraklar */
    SPILL(0, A1)
    /* dugmeler: alt 3 bit */
    MOVR(A0, A1)
    ANDI(A0, 7)
    LEA_SYM(A1, SYM(g_ms_btn)); ST(A1, A0)
    /* X: isaret bit4'te, deger 8 bit */
    LEA_SYM(A0, SYM(g_ms_buf))
    LD_OFF(A0, A0, 8)
    ANDI(A0, 0xFF)
    FILL(A1, 0)
    ANDI(A1, 0x10)
    BZ(A1, mp_x_ok)
    SUBI(A0, 256)                   /* isaret genislet */
mp_x_ok:
    LEA_SYM(A1, SYM(g_ms_x))
    LD(A2, A1)
    ADD(A2, A0)
    ST(A1, A2)
    /* Y: isaret bit5'te; ekran icin TERS (asagi pozitif) */
    LEA_SYM(A0, SYM(g_ms_buf))
    LD_OFF(A0, A0, 16)
    ANDI(A0, 0xFF)
    FILL(A1, 0)
    ANDI(A1, 0x20)
    BZ(A1, mp_y_ok)
    SUBI(A0, 256)
mp_y_ok:
    LEA_SYM(A1, SYM(g_ms_y))
    LD(A2, A1)
    SUB(A2, A0)                     /* fare yukari = deger pozitif */
    ST(A1, A2)
    LEAVE_
    RET
ENDFUNC(ms_paket)

#else

FUNC(ms_kur)
    MOVI(RV, 0)
    RET
ENDFUNC(ms_kur)

FUNC(ms_yokla)
    RET
ENDFUNC(ms_yokla)

#endif

/* ---------------- govde fonksiyonlari ---------------- */

FUNC(nat_mouseinit)
    ENTER(1)
#if HAVE_MOUSE && !BARE_SIM
    CALL(ms_kur)
    MOVR(A1, RV)
    MOVI(A0, T_BOOL)
    SET_RES(A0W, A1)
    LEAVE_
    RET
#endif
    CALL(nat_ret_nil)
    LEAVE_
    RET
ENDFUNC(nat_mouseinit)

FUNC(nat_mousehit)
    ENTER(1)
#if HAVE_MOUSE && !BARE_SIM
    CALL(ms_yokla)
    LEA_SYM(A0, SYM(g_ms_yeni))
    LD(A1, A0)
    MOVI(A0, T_BOOL)
    SET_RES(A0W, A1)
    LEAVE_
    RET
#endif
    CALL(nat_ret_nil)
    LEAVE_
    RET
ENDFUNC(nat_mousehit)

/* fare() -> [x, y, dugmeler] */
FUNC(nat_mouse)
    ENTER(3)
#if HAVE_MOUSE && !BARE_SIM
    LEA_SYM(A0, SYM(g_ms_ok))
    LD(A0, A0)
    BZ(A0, nms_nil)
    CALL(ms_yokla)
    MOVI(A0, 0)
    LEA_SYM(A1, SYM(g_ms_yeni)); ST(A1, A0)
    MOVI(A0, 3)
    CALL(arr_new)
    BZ(RV, nms_nil)
    SPILL(0, RV)
    MOVI(A0, 0)
    SPILL(1, A0)
nms_f:
    FILL(A0, 1)
    CMPI(A0, 3)
    BHS(nms_d)
    FILL(A0, 0)
    CALL(obj_ptr)
    MOVR(A0, RV); ADDI(A0, OBJ_DATA)
    FILL(A1, 1); SHLI(A1, VAL_SHIFT); ADD(A0, A1)
    MOVI(A1, T_INT)
    ST32_OFF(A0, VAL_TAG, A1W)
    FILL(A1, 1)
    CMPI(A1, 0); BEQ(nms_x)
    CMPI(A1, 1); BEQ(nms_y)
    LEA_SYM(A1, SYM(g_ms_btn)); B(nms_st)
nms_x:
    LEA_SYM(A1, SYM(g_ms_x)); B(nms_st)
nms_y:
    LEA_SYM(A1, SYM(g_ms_y))
nms_st:
    LD(A1, A1)
    ST_OFF(A0, VAL_PAY, A1)
    FILL(A0, 1); INC(A0); SPILL(1, A0)
    B(nms_f)
nms_d:
    FILL(A1, 0)
    MOVI(A0, T_OBJ)
    SET_RES(A0W, A1)
    LEAVE_
    RET
#endif
nms_nil:
    CALL(nat_ret_nil)
    LEAVE_
    RET
ENDFUNC(nat_mouse)
