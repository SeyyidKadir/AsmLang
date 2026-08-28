/* osdev.S - ekran, ses, disk
 *
 * Bare-metal'de gercekten kullanilabilir bir katman. Hepsi
 * ayricalikli ya da fiziksel bellege dokundugu icin BARINDIRILAN
 * sistemlerde etkin degil; orada temiz "bos" doner.
 *
 *   EKRAN (multiboot dogrusal cerceve tamponu)
 *     ekran()                 -> [adres, genislik, yukseklik, satir, bpp]
 *     piksel(x, y, renk)      -> tek piksel
 *     dikdortgen(x,y,g,y,renk)
 *     ekran_temizle(renk)
 *
 *   METIN EKRANI (VGA 0xB8000, video kurulmadiysa)
 *     vga(x, y, karakter, renk)
 *
 *   SES (PC hoparloru: PIT kanal 2 + port 0x61)
 *     ses(frekans)            -> caldir
 *     ses_kapat()
 *
 *   DISK (ATA PIO, birincil usta)
 *     disk_oku(lba, sektor_sayisi, tampon) -> okunan sektor / bos
 *
 * ================== SINIRLAR ==================
 * - Cerceve tamponu YUKLEYICI tarafindan kurulur. GRUB ya da
 *   "qemu -kernel" video istegimizi karsilamazsa ekran() sifirlar
 *   doner ve piksel() bos verir. Sessizce yanlis yere yazmaz.
 * - ATA PIO YOKLAMALI (polling): kesme yok, DMA yok. Yavas ama
 *   surucu yazmadan calisir. Gercek bir cekirdek icin yeterli degil,
 *   bootloader icin yeterli.
 * - Ses PC hoparloru; ses karti yok.
 */
#include "../abi.inc"
#include "../tables/opcodes.inc"

#define SET_RES(tg, py) \
    LEA_SYM(A2, SYM(g_natres)); \
    ST32_OFF(A2, VAL_TAG, tg); \
    ST_OFF(A2, VAL_PAY, py)

#if defined(OS_BARE) && OS_BARE
#  define HAVE_HW 1
#else
#  define HAVE_HW 0
#endif

/* BARE_SIM: bare kod yolunu emulator olmadan calistirmak icin.
 * FIZIKSEL adrese yazan islevler (VGA 0xB8000, cerceve tamponu)
 * kullanici kipinde cokerdi; benzetimde "bos" donerler.
 * Bu, o islevlerin QEMU'da DENENMEDIGI anlamina gelir. */
#ifndef BARE_SIM
#  define BARE_SIM 0
#endif

    SECT_TEXT

/* ---------------- ekran() -> [adres, gen, yuk, satir, bpp] ---------------- */
FUNC(nat_screen)
    ENTER(3)
#if HAVE_HW && (defined(ARCH_X86_64) || defined(ARCH_I386))
    MOVI(A0, 5)
    CALL(arr_new)
    BZ(RV, nsc_nil)
    SPILL(0, RV)
    MOVI(A0, 0)
    SPILL(1, A0)
nsc_fill:
    FILL(A0, 1)
    CMPI(A0, 5)
    BHS(nsc_done)
    FILL(A0, 0)
    CALL(obj_ptr)
    MOVR(A0, RV); ADDI(A0, OBJ_DATA)
    FILL(A1, 1); SHLI(A1, VAL_SHIFT); ADD(A0, A1)
    MOVI(A1, T_INT)
    ST32_OFF(A0, VAL_TAG, A1W)
    LEA_SYM(A1, SYM(g_fb))
    FILL(A2, 1); SHLI(A2, 3); ADD(A1, A2)
    LD(A1, A1)
    ST_OFF(A0, VAL_PAY, A1)
    FILL(A0, 1); INC(A0); SPILL(1, A0)
    B(nsc_fill)
nsc_done:
    FILL(A1, 0)
    MOVI(A0, T_OBJ)
    SET_RES(A0W, A1)
    LEAVE_
    RET
#endif
nsc_nil:
    CALL(nat_ret_nil)
    LEAVE_
    RET
ENDFUNC(nat_screen)

/* ---------------- piksel(x, y, renk) ----------------
 * Yalniz 32 bit/piksel destekleniyor. Sinir disi koordinat sessizce
 * atlanmaz, "bos" doner: yanlis yere yazmaktansa hata bildir. */
FUNC(nat_pixel)
    ENTER(6)
#if HAVE_HW && !BARE_SIM && (defined(ARCH_X86_64) || defined(ARCH_I386))
    CMPI(A1, 3)
    BNE(npx_nil)
    SPILL(0, A0)
    CALL(arg_int)
    BZ(RV, npx_nil)
    SPILL(1, A1)                    /* x */
    FILL(A0, 0); ADDI(A0, VAL_SIZE)
    CALL(arg_int)
    BZ(RV, npx_nil)
    SPILL(2, A1)                    /* y */
    FILL(A0, 0); ADDI(A0, 2*VAL_SIZE)
    CALL(arg_int)
    BZ(RV, npx_nil)
    SPILL(3, A1)                    /* renk */
    CALL(fb_check)
    BZ(RV, npx_nil)
    /* sinirlar */
    LEA_SYM(A0, SYM(g_fb))
    FILL(A1, 1)
    CMPI(A1, 0); BLT(npx_nil)
    LD_OFF(A2, A0, 8)
    CMPR(A1, A2); BHS(npx_nil)
    FILL(A1, 2)
    CMPI(A1, 0); BLT(npx_nil)
    LD_OFF(A2, A0, 16)
    CMPR(A1, A2); BHS(npx_nil)
    /* adres = taban + y*satir + x*(bpp/8) */
    LD_OFF(A2, A0, 24)              /* satir bayti */
    FILL(A1, 2)
    MUL(A1, A2)
    LD_OFF(A2, A0, 32); SHRI(A2, 3) /* bayt/piksel */
    SPILL(4, A2)
    LD(A0, A0)
    ADD(A0, A1)
    FILL(A1, 1); FILL(A2, 4); MUL(A1, A2)
    ADD(A0, A1)
    FILL(A2, 3)
    FILL(A1, 4)
    CMPI(A1, 4)
    BEQ(npx_32)
    /* 24 bit: uc bayt ayri yazilir */
    STB(A0, A2B)
    SHRI(A2, 8); ADDI(A0, 1); STB(A0, A2B)
    SHRI(A2, 8); ADDI(A0, 1); STB(A0, A2B)
    B(npx_done)
npx_32:
    ST32_OFF(A0, 0, A2W)
npx_done:
    MOVI(A0, T_BOOL)
    MOVI(A1, 1)
    SET_RES(A0W, A1)
    LEAVE_
    RET
#endif
npx_nil:
    CALL(nat_ret_nil)
    LEAVE_
    RET
ENDFUNC(nat_pixel)

/* ---------------- ekran_temizle(renk) ---------------- */
FUNC(nat_clsfb)
    ENTER(5)
#if HAVE_HW && !BARE_SIM && (defined(ARCH_X86_64) || defined(ARCH_I386))
    CMPI(A1, 1)
    BNE(ncf_nil)
    CALL(arg_int)
    BZ(RV, ncf_nil)
    SPILL(0, A1)                    /* renk */
    CALL(fb_check)
    BZ(RV, ncf_nil)
    LEA_SYM(A0, SYM(g_fb))
    LD_OFF(A1, A0, 16)
    SPILL(1, A1)                    /* yukseklik */
    MOVI(A0, 0)
    SPILL(2, A0)                    /* y */
ncf_row:
    FILL(A0, 2); FILL(A1, 1)
    CMPR(A0, A1)
    BHS(ncf_done)
    LEA_SYM(A1, SYM(g_fb))
    LD_OFF(A2, A1, 24)
    FILL(A0, 2)
    MUL(A0, A2)
    LD(A1, A1)
    ADD(A0, A1)
    SPILL(3, A0)                    /* satir basi */
    MOVI(A0, 0)
    SPILL(4, A0)                    /* x */
ncf_col:
    LEA_SYM(A0, SYM(g_fb))
    LD_OFF(A1, A0, 8)
    FILL(A0, 4)
    CMPR(A0, A1)
    BHS(ncf_next)
    LEA_SYM(A1, SYM(g_fb)); LD_OFF(A1, A1, 32); SHRI(A1, 3)
    FILL(A0, 4); MUL(A0, A1)
    FILL(A1, 3); ADD(A0, A1)
    FILL(A2, 0)
    LEA_SYM(A1, SYM(g_fb)); LD_OFF(A1, A1, 32)
    CMPI(A1, 32)
    BEQ(ncf_32)
    STB(A0, A2B)
    SHRI(A2, 8); ADDI(A0, 1); STB(A0, A2B)
    SHRI(A2, 8); ADDI(A0, 1); STB(A0, A2B)
    B(ncf_step)
ncf_32:
    ST32_OFF(A0, 0, A2W)
ncf_step:
    FILL(A0, 4); INC(A0); SPILL(4, A0)
    B(ncf_col)
ncf_next:
    FILL(A0, 2); INC(A0); SPILL(2, A0)
    B(ncf_row)
ncf_done:
    MOVI(A0, T_BOOL)
    MOVI(A1, 1)
    SET_RES(A0W, A1)
    LEAVE_
    RET
#endif
ncf_nil:
    CALL(nat_ret_nil)
    LEAVE_
    RET
ENDFUNC(nat_clsfb)

/* ---------------- vga(x, y, karakter, renk) ----------------
 * 80x25 metin ekrani, 0xB8000. Video kurulmasa da calisir. */
FUNC(nat_vga)
    ENTER(5)
#if HAVE_HW && !BARE_SIM && (defined(ARCH_X86_64) || defined(ARCH_I386))
    CMPI(A1, 4)
    BNE(nvg_nil)
    SPILL(0, A0)
    CALL(arg_int); BZ(RV, nvg_nil); SPILL(1, A1)
    FILL(A0, 0); ADDI(A0, VAL_SIZE)
    CALL(arg_int); BZ(RV, nvg_nil); SPILL(2, A1)
    FILL(A0, 0); ADDI(A0, 2*VAL_SIZE)
    CALL(arg_int); BZ(RV, nvg_nil); SPILL(3, A1)
    FILL(A0, 0); ADDI(A0, 3*VAL_SIZE)
    CALL(arg_int); BZ(RV, nvg_nil); SPILL(4, A1)
    FILL(A0, 1); CMPI(A0, 0); BLT(nvg_nil); CMPI(A0, 80); BHS(nvg_nil)
    FILL(A0, 2); CMPI(A0, 0); BLT(nvg_nil); CMPI(A0, 25); BHS(nvg_nil)
    /* adres = 0xB8000 + (y*80 + x)*2 */
    FILL(A0, 2)
    MOVI(A1, 80)
    MUL(A0, A1)
    FILL(A1, 1)
    ADD(A0, A1)
    SHLI(A0, 1)
    MOVI(A1, 0xB8000)
    ADD(A0, A1)
    /* deger = karakter | renk<<8 */
    FILL(A1, 3); ANDI(A1, 255)
    FILL(A2, 4); ANDI(A2, 255); SHLI(A2, 8)
    ORR(A1, A2)
    STH(A0, A1H)
    MOVI(A0, T_BOOL)
    MOVI(A1, 1)
    SET_RES(A0W, A1)
    LEAVE_
    RET
#endif
nvg_nil:
    CALL(nat_ret_nil)
    LEAVE_
    RET
ENDFUNC(nat_vga)

/* ---------------- ses(frekans) / ses_kapat() ----------------
 * PIT kanal 2'yi kare dalga uretecek sekilde kurup hoparlore baglar.
 * bolen = 1193182 / frekans */
FUNC(nat_beep)
    ENTER(3)
#if HAVE_HW && (defined(ARCH_X86_64) || defined(ARCH_I386))
    CMPI(A1, 1)
    BNE(nbp_nil)
    CALL(arg_int)
    BZ(RV, nbp_nil)
    MOVR(A0, A1)
    CMPI(A0, 19)                    /* cok dusuk: bolen tasar */
    BLO(nbp_nil)
    CMPI(A0, 20000)
    BHI(nbp_nil)
    SPILL(0, A0)
    MOVI(A0, 1193182)
    FILL(A1, 0)
    CALL(udivmod)
    SPILL(1, RV)                    /* bolen */
    /* PIT komutu: kanal 2, once dusuk sonra yuksek, mod 3 (kare) */
    MOVI(A0, 0x43); MOVI(A1, 0xB6); MOVI(A2, 1); CALL(port_out)
    MOVI(A0, 0x42); FILL(A1, 1); ANDI(A1, 255); MOVI(A2, 1); CALL(port_out)
    MOVI(A0, 0x42); FILL(A1, 1); SHRI(A1, 8); ANDI(A1, 255); MOVI(A2, 1)
    CALL(port_out)
    /* hoparloru ac: port 0x61'in 0 ve 1. bitleri */
    MOVI(A0, 0x61); MOVI(A1, 1); CALL(port_in)
    MOVR(A1, RV); ORI(A1, 3)
    MOVI(A0, 0x61); MOVI(A2, 1); CALL(port_out)
    MOVI(A0, T_BOOL)
    MOVI(A1, 1)
    SET_RES(A0W, A1)
    LEAVE_
    RET
#endif
nbp_nil:
    CALL(nat_ret_nil)
    LEAVE_
    RET
ENDFUNC(nat_beep)

FUNC(nat_beepoff)
    ENTER(2)
#if HAVE_HW && (defined(ARCH_X86_64) || defined(ARCH_I386))
    MOVI(A0, 0x61); MOVI(A1, 1); CALL(port_in)
    MOVR(A1, RV)
    ANDI(A1, 0xFC)                  /* alt iki bit: hoparlor kapali */
    MOVI(A0, 0x61); MOVI(A2, 1); CALL(port_out)
    MOVI(A0, T_BOOL)
    MOVI(A1, 1)
    SET_RES(A0W, A1)
    LEAVE_
    RET
#endif
    CALL(nat_ret_nil)
    LEAVE_
    RET
ENDFUNC(nat_beepoff)

/* ---------------- disk_oku(lba, sayi, tampon) ----------------
 * ATA PIO, birincil kanal usta aygit. Yoklamali.
 * Tampon en az sayi*512 bayt olmali. */
FUNC(nat_diskrd)
    ENTER(8)
#if HAVE_HW && !BARE_SIM && (defined(ARCH_X86_64) || defined(ARCH_I386))
    CMPI(A1, 3)
    BNE(ndr_nil)
    SPILL(0, A0)
    CALL(arg_int); BZ(RV, ndr_nil); SPILL(1, A1)    /* lba */
    FILL(A0, 0); ADDI(A0, VAL_SIZE)
    CALL(arg_int); BZ(RV, ndr_nil); SPILL(2, A1)    /* sektor sayisi */
    FILL(A0, 0); ADDI(A0, 2*VAL_SIZE)
    MOVI(A1, O_BUF)
    CALL(obj_of)
    BZ(RV, ndr_nil)
    SPILL(3, RV)
    LD32_OFF(A0W, RV, OBJ_LEN)
    SPILL(4, A0)
    /* sinirlar */
    FILL(A0, 2); CMPI(A0, 1); BLO(ndr_nil); CMPI(A0, 255); BHI(ndr_nil)
    FILL(A0, 1); CMPI(A0, 0); BLT(ndr_nil)
    FILL(A0, 2); SHLI(A0, 9)
    FILL(A1, 4)
    CMPR(A0, A1)
    BHI(ndr_nil)                    /* tampon yetersiz */
    /* aygit secimi: 0xE0 | LBA[27:24] */
    FILL(A0, 1); SHRI(A0, 24); ANDI(A0, 0x0F); ORI(A0, 0xE0)
    MOVR(A1, A0); MOVI(A0, 0x1F6); MOVI(A2, 1); CALL(port_out)
    MOVI(A0, 0x1F2); FILL(A1, 2); ANDI(A1, 255); MOVI(A2, 1); CALL(port_out)
    MOVI(A0, 0x1F3); FILL(A1, 1); ANDI(A1, 255); MOVI(A2, 1); CALL(port_out)
    MOVI(A0, 0x1F4); FILL(A1, 1); SHRI(A1, 8);  ANDI(A1, 255); MOVI(A2, 1); CALL(port_out)
    MOVI(A0, 0x1F5); FILL(A1, 1); SHRI(A1, 16); ANDI(A1, 255); MOVI(A2, 1); CALL(port_out)
    MOVI(A0, 0x1F7); MOVI(A1, 0x20); MOVI(A2, 1); CALL(port_out)  /* READ SECTORS */
    MOVI(A0, 0); SPILL(5, A0)       /* okunan sektor */
ndr_sec:
    FILL(A0, 5); FILL(A1, 2)
    CMPR(A0, A1)
    BHS(ndr_ok)
    CALL(ata_wait)
    BZ(RV, ndr_err)
    /* 256 kelime oku */
    MOVI(A0, 0); SPILL(6, A0)
ndr_word:
    FILL(A0, 6)
    CMPI(A0, 256)
    BHS(ndr_snext)
    MOVI(A0, 0x1F0); MOVI(A1, 2); CALL(port_in)
    SPILL(7, RV)
    FILL(A0, 3); ADDI(A0, OBJ_DATA)
    FILL(A1, 5); SHLI(A1, 9); ADD(A0, A1)
    FILL(A1, 6); SHLI(A1, 1); ADD(A0, A1)
    FILL(A1, 7)
    STH(A0, A1H)
    FILL(A0, 6); INC(A0); SPILL(6, A0)
    B(ndr_word)
ndr_snext:
    FILL(A0, 5); INC(A0); SPILL(5, A0)
    B(ndr_sec)
ndr_ok:
    FILL(A0, 5)
    CALL(ret_int)
    LEAVE_
    RET
ndr_err:
    CALL(nat_ret_nil)
    LEAVE_
    RET
#endif
ndr_nil:
    CALL(nat_ret_nil)
    LEAVE_
    RET
ENDFUNC(nat_diskrd)

#if HAVE_HW && (defined(ARCH_X86_64) || defined(ARCH_I386))

/* fb_check() -> RV = 1 ise cerceve tamponu kurulu ve 32 bpp */
/* fb_check() -> RV = 1 ise kullanilabilir cerceve tamponu var.
 * 24 VE 32 bit destekleniyor: VESA'nin 1024x768 kipi (0x118)
 * 24 bit veriyor ve yalniz 32'yi kabul edince cizim sessizce
 * atlaniyordu - rapor "CIZILDI" diyordu ama ekran bostu. */
FUNC(fb_check)
    ENTER(1)
    LEA_SYM(A0, SYM(g_fb))
    LD(A1, A0)
    BZ(A1, fbc_no)
    LD_OFF(A1, A0, 32)
    CMPI(A1, 24)
    BEQ(fbc_ok)
    CMPI(A1, 32)
    BNE(fbc_no)
fbc_ok:
    MOVI(RV, 1)
    LEAVE_
    RET
fbc_no:
    MOVI(RV, 0)
    LEAVE_
    RET
ENDFUNC(fb_check)

/* ata_wait() -> RV = 1 hazir / 0 hata
 * Durum: bit 7 BSY, bit 3 DRQ, bit 0 ERR. BSY dusup DRQ kalkmali.
 * Sonsuz beklememek icin sayaç: bozuk aygitta asilmayalim. */
FUNC(ata_wait)
    ENTER(2)
    MOVI(A0, 4000000)
    SPILL(0, A0)
aw_loop:
    FILL(A0, 0)
    BZ(A0, aw_no)
    DEC(A0)
    SPILL(0, A0)
    MOVI(A0, 0x1F7); MOVI(A1, 1); CALL(port_in)
    MOVR(A0, RV)
    SPILL(1, A0)
    ANDI(A0, 0x01)
    BNZ(A0, aw_no)                  /* ERR */
    FILL(A0, 1)
    ANDI(A0, 0x80)
    BNZ(A0, aw_loop)                /* hala mesgul */
    FILL(A0, 1)
    ANDI(A0, 0x08)
    BZ(A0, aw_loop)                 /* veri hazir degil */
    MOVI(RV, 1)
    LEAVE_
    RET
aw_no:
    MOVI(RV, 0)
    LEAVE_
    RET
ENDFUNC(ata_wait)

#endif

/* ---------------- acilis() -> [sihir_dogru, bayraklar] ----------------
 * Cekirdegin bir multiboot yukleyicisi tarafindan mi baslatildigini
 * ve hangi bilgileri aldigini dile acar. Tanilama icin sart:
 * "video yok" ile "yukleyici yok" ayirt edilebilsin. */
FUNC(nat_boot)
    ENTER(3)
#if HAVE_HW && (defined(ARCH_X86_64) || defined(ARCH_I386))
    MOVI(A0, 2)
    CALL(arr_new)
    BZ(RV, nbt_nil)
    SPILL(0, RV)
    MOVI(A0, 0)
    SPILL(1, A0)
nbt_fill:
    FILL(A0, 1)
    CMPI(A0, 2)
    BHS(nbt_done)
    FILL(A0, 0)
    CALL(obj_ptr)
    MOVR(A0, RV); ADDI(A0, OBJ_DATA)
    FILL(A1, 1); SHLI(A1, VAL_SHIFT); ADD(A0, A1)
    MOVI(A1, T_INT)
    ST32_OFF(A0, VAL_TAG, A1W)
    FILL(A1, 1)
    BNZ(A1, nbt_flags)
    LEA_SYM(A1, SYM(g_mbmagic))
    B(nbt_st)
nbt_flags:
    LEA_SYM(A1, SYM(g_mbflags))
nbt_st:
    LD(A1, A1)
    ST_OFF(A0, VAL_PAY, A1)
    FILL(A0, 1); INC(A0); SPILL(1, A0)
    B(nbt_fill)
nbt_done:
    FILL(A1, 0)
    MOVI(A0, T_OBJ)
    SET_RES(A0W, A1)
    LEAVE_
    RET
#endif
nbt_nil:
    CALL(nat_ret_nil)
    LEAVE_
    RET
ENDFUNC(nat_boot)
