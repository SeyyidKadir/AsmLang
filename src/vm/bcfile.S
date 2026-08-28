/* bcfile.S - bytecode dosyasi (.bc) yazma ve yukleme
 *
 * Player mimarisinin temeli: derleyici .bc uretir, yurutucu okur.
 *
 * TASARIM NOTU - dizgi sabitleri:
 * Sabit havuzunda dizgiler T_OBJ + TUTAMAK tutuyor. Tutamak calisma
 * zamani durumudur, dosyaya yazilamaz. Bu yuzden serilestirmede
 * dizgiler HAM BAYT olarak gomuluyor ve yuklemede yeniden nesne
 * olusturuluyor.
 *
 * Kuresel ADLARI yazilmiyor: indeksli oldugumuz icin gerekmiyor.
 *
 * Butun alanlar u32 ve dokuz hedef de little-endian, yani x86_64'te
 * uretilen .bc aarch64 yurutucude calisir.
 *
 * GUVENLIK: yuklenen .bc GUVENILMEYEN girdidir. bc_load yalnizca
 * bicimsel denetim yapar; anlamsal denetimi verify_meta yapar ve
 * cagiran onu CALISTIRMADAN ONCE kosmak zorundadir.
 */
#include "../abi.inc"
#include "../tables/opcodes.inc"
#define NAT_COUNT_ONLY 1   /* tabloyu degil yalniz sabitleri al */
#include "../tables/natives.inc"

#define BC_MAGIC    0x424D5341      /* "ASMB" (little-endian) */
#define BC_VERSION  2   /* 64-bit yuk: bicim degisti */
#define BC_HDR      8               /* baslik u32 sayisi */

    .bss
    .p2align 2
    .globl SYM(g_bc_len)
SYM(g_bc_len): .space 4
/* Cozumlenecek verinin kaynagi: dosyadan okunduysa g_filebuf,
 * ikiliye gomulduyse dogrudan .rodata blogu. Yukleyici ikisini de
 * ayni kodla isler - gomulu kipte dosya sistemi HIC gerekmiyor
 * (bare-metal / ISO icin dogru kip). */
    .p2align 3
    .globl SYM(g_bc_ptr)
SYM(g_bc_ptr): .space 8

    SECT_RODATA
bc_e1: .ascii "bc: dosya acilamadi\n"
    .equ bc_e1_len, . - bc_e1
bc_e2: .ascii "bc: gecersiz imza ya da surum\n"
    .equ bc_e2_len, . - bc_e2
bc_e3: .ascii "bc: govde tablosu uyusmuyor (derleyici/yurutucu surumu farkli)\n"
    .equ bc_e3_len, . - bc_e3
bc_e4: .ascii "bc: bolum boyutu sinir disinda\n"
    .equ bc_e4_len, . - bc_e4
bc_e5: .ascii "bc: dosya kesik\n"
    .equ bc_e5_len, . - bc_e5
bc_e6: .ascii "bc: kelime genisligi uyusmuyor (32/64 bit)\n"
    .equ bc_e6_len, . - bc_e6

    SECT_TEXT

/* bcw(A0 = ofset, A1 = deger) -> RV = ofset + 4   (g_filebuf'a u32 yaz) */
FUNC(bcw)
    ENTER(2)
    SPILL(0, A0)
    SPILL(1, A1)
    LEA_SYM(A0, SYM(g_filebuf))
    FILL(A1, 0)
    ADD(A0, A1)
    FILL(A1, 1)
    ST32_OFF(A0, 0, A1W)
    FILL(A0, 0)
    ADDI(A0, 4)
    MOVR(RV, A0)
    LEAVE_
    RET
ENDFUNC(bcw)

/* bcww(A0 = ofset, A1 = deger) -> RV = ofset + 8
 * Yuk artik KELIME genisliginde; dosyada her zaman 8 bayt yer
 * kapliyor ki 32-bit uretici ile 64-bit okuyucunun ofsetleri
 * kaymasin (uyusmazlik zaten damgayla reddediliyor, ama bicim
 * sabit kalsin). */
FUNC(bcww)
    ENTER(2)
    SPILL(0, A0)
    SPILL(1, A1)
    CALL(bcw)
    SPILL(0, RV)
    FILL(A0, 1)
#if WORD_SIZE == 8
    SHRI(A0, 32)
#else
    SHRI(A0, 31)                    /* 32-bit: yalniz isaret biti kalir;
                                     * ust kelime 0 ya da 1 olur, yeterli
                                     * cunku uyusmazlik damgayla reddedilir */
#endif
    MOVR(A1, A0)
    FILL(A0, 0)
    CALL(bcw)
    LEAVE_
    RET
ENDFUNC(bcww)

/* bcrw(A0 = ofset) -> RV = kelime genisliginde deger */
FUNC(bcrw)
    ENTER(2)
    SPILL(0, A0)
    CALL(bcr)
    SPILL(1, RV)
#if WORD_SIZE == 8
    FILL(A0, 0); ADDI(A0, 4)
    CALL(bcr)
    MOVR(A0, RV)
    SHLI(A0, 32)
    FILL(A1, 1)
    ORR(A0, A1)
    MOVR(RV, A0)
#else
    FILL(RV, 1)
#endif
    LEAVE_
    RET
ENDFUNC(bcrw)

/* bcr(A0 = ofset) -> RV = u32   (g_filebuf'tan oku) */
FUNC(bcr)
    ENTER(1)
    LEA_SYM(A1, SYM(g_bc_ptr))
    LD(A1, A1)
    ADD(A0, A1)
    LD32(RVW, A0)
    LEAVE_
    RET
ENDFUNC(bcr)

/* bc_addc(A0 = etiket, A1 = yuk) - havuza dogrudan ekler
 * add_const KULLANILMIYOR: o derleyici tarafinda ve ic ice gecirme
 * (interning) yapiyor. .bc havuzu zaten dedup edilmis; ayrica
 * yurutucunun derleyiciye bagimli olmamasi gerekiyor. */
FUNC(bc_addc)
    ENTER(2)
    SPILL(0, A0)
    SPILL(1, A1)
    LEA_SYM(A0, SYM(g_nconst))
    LD32(A1W, A0)
    MOVR(A2, A1)
    INC(A2)
    ST32_OFF(A0, 0, A2W)
    MOVR(A0, A1)
    SHLI(A0, VAL_SHIFT)
    LEA_SYM(A1, SYM(g_consts))
    LD(A1, A1)
    ADD(A0, A1)
    FILL(A1, 0); ST32_OFF(A0, VAL_TAG, A1W)
    FILL(A1, 1); ST_OFF(A0, VAL_PAY, A1)
    LEAVE_
    RET
ENDFUNC(bc_addc)

/* =====================================================================
 * bc_save(A0 = yol) -> RV = 1 tamam / 0 hata
 * Slotlar: 0=yol 1=ofset 2=i 3=n 4=gecici 5=gecici
 * ===================================================================== */
FUNC(bc_save)
    ENTER(6)
    SPILL(0, A0)
    MOVI(A0, 0)
    SPILL(1, A0)

    /* --- baslik --- */
    FILL(A0, 1); MOVI(A1, BC_MAGIC);   CALL(bcw); SPILL(1, RV)
    FILL(A0, 1); MOVI(A1, BC_VERSION); CALL(bcw); SPILL(1, RV)
    FILL(A0, 1); MOVI(A1, NAT_COUNT);  CALL(bcw); SPILL(1, RV)
    /* Kelime genisligi damgasi: .bc artik yuk genisligine BAGLI.
     * 64-bit uretilip 32-bit yurutucude calistirilirsa butun
     * sabitler kayar. Sessizce yanlis calismasindansa REDDET. */
    FILL(A0, 1); MOVI(A1, WORD_SIZE);  CALL(bcw); SPILL(1, RV)
    LEA_SYM(A0, SYM(g_ncode));  LD32(A1W, A0); FILL(A0, 1); CALL(bcw); SPILL(1, RV)
    LEA_SYM(A0, SYM(g_nconst)); LD32(A1W, A0); FILL(A0, 1); CALL(bcw); SPILL(1, RV)
    LEA_SYM(A0, SYM(g_nglob));  LD32(A1W, A0); FILL(A0, 1); CALL(bcw); SPILL(1, RV)
    LEA_SYM(A0, SYM(g_nfn));    LD32(A1W, A0); FILL(A0, 1); CALL(bcw); SPILL(1, RV)

    /* --- kod --- */
    MOVI(A0, 0); SPILL(2, A0)
    LEA_SYM(A0, SYM(g_ncode)); LD32(A0W, A0); SPILL(3, A0)
bs_code:
    FILL(A0, 2); FILL(A1, 3); CMPR(A0, A1); BHS(bs_fns)
    FILL(A0, 2); CALL(code_at); MOVR(A1, RV)
    FILL(A0, 1); CALL(bcw); SPILL(1, RV)
    FILL(A0, 2); INC(A0); SPILL(2, A0)
    B(bs_code)

    /* --- fonksiyon tablosu --- */
bs_fns:
    MOVI(A0, 0); SPILL(2, A0)
    LEA_SYM(A0, SYM(g_nfn)); LD32(A0W, A0); SPILL(3, A0)
bs_fn:
    FILL(A0, 2); FILL(A1, 3); CMPR(A0, A1); BHS(bs_consts)
    FILL(A0, 2); SHLI(A0, 3); LEA_SYM(A1, SYM(g_fns)); ADD(A0, A1); SPILL(4, A0)
    LD32(A1W, A0); FILL(A0, 1); CALL(bcw); SPILL(1, RV)
    FILL(A0, 4); LD32_OFF(A1W, A0, 4); FILL(A0, 1); CALL(bcw); SPILL(1, RV)
    FILL(A0, 2); INC(A0); SPILL(2, A0)
    B(bs_fn)

    /* --- sabitler --- */
bs_consts:
    MOVI(A0, 0); SPILL(2, A0)
    LEA_SYM(A0, SYM(g_nconst)); LD32(A0W, A0); SPILL(3, A0)
bs_c:
    FILL(A0, 2); FILL(A1, 3); CMPR(A0, A1); BHS(bs_write)
    FILL(A0, 2); SHLI(A0, VAL_SHIFT)
    LEA_SYM(A1, SYM(g_consts)); LD(A1, A1); ADD(A0, A1); SPILL(4, A0)
    LD32(A1W, A0)                   /* etiket */
    SPILL(5, A1)
    FILL(A0, 1); CALL(bcw); SPILL(1, RV)
    FILL(A0, 5)
    CMPI(A0, T_OBJ)
    BEQ(bs_str)
    /* duz yuk: KELIME genisliginde (dosyada 8 bayt) */
    FILL(A0, 4); LD_OFF(A1, A0, VAL_PAY)
    FILL(A0, 1); CALL(bcww); SPILL(1, RV)
    B(bs_cnext)
bs_str:
    /* T_OBJ: yuk yerine UZUNLUK, ardindan ham baytlar */
    FILL(A0, 4); LD_OFF(A0, A0, VAL_PAY)
    CALL(obj_ptr)
    SPILL(4, RV)
    FILL(A0, 4); LD32_OFF(A1W, A0, OBJ_LEN)
    SPILL(5, A1)                    /* uzunluk */
    FILL(A0, 1); CALL(bcww); SPILL(1, RV)
    /* baytlar (4'e hizali doldurulur) */
    LEA_SYM(A0, SYM(g_filebuf)); FILL(A1, 1); ADD(A0, A1)
    FILL(A1, 4); ADDI(A1, OBJ_DATA)
    FILL(A2, 5)
    CALL(mem_copy_b)
    FILL(A0, 5); ADDI(A0, 3); ANDI(A0, -4)
    FILL(A1, 1); ADD(A0, A1); SPILL(1, A0)
bs_cnext:
    FILL(A0, 2); INC(A0); SPILL(2, A0)
    B(bs_c)

    /* --- dosyaya yaz --- */
bs_write:
    FILL(A0, 1)
    LEA_SYM(A1, SYM(g_bc_len))
    ST32_OFF(A1, 0, A0W)
    FILL(A0, 0)
    MOVI(A1, 1)
    CALL(os_open)
    MOVR(A0, RV)
    CMPI(A0, 0)
    BLT(bs_bad)
    SPILL(0, A0)
    LEA_SYM(A1, SYM(g_filebuf))
    FILL(A2, 1)
    FILL(A0, 0)
    CALL(os_write)
    FILL(A0, 0)
    CALL(os_close)
    MOVI(RV, 1)
    LEAVE_
    RET
bs_bad:
    LEA_SYM(A0, bc_e1); MOVI(A1, bc_e1_len); CALL(print_str)
    MOVI(RV, 0)
    LEAVE_
    RET
ENDFUNC(bc_save)

/* =====================================================================
 * bc_load(A0 = yol) -> RV = 1/0     (dosyadan oku, sonra cozumle)
 * ===================================================================== */
FUNC(bc_load)
    ENTER(3)
    MOVI(A1, 0)
    CALL(os_open)
    MOVR(A0, RV)
    CMPI(A0, 0)
    BLT(bl_e1)
    SPILL(0, A0)
    MOVI(A0, 0)
    SPILL(1, A0)
blf_read:
    FILL(A0, 1)
    CMPI(A0, FILE_BUF_SIZE)
    BHS(blf_done)
    LEA_SYM(A1, SYM(g_filebuf)); ADD(A1, A0)
    MOVI(A2, FILE_BUF_SIZE); FILL(A0, 1); SUB(A2, A0)
    FILL(A0, 0)
    CALL(os_read)
    MOVR(A0, RV)
    CMPI(A0, 0)
    BLE(blf_done)
    FILL(A1, 1); ADD(A1, A0); SPILL(1, A1)
    B(blf_read)
blf_done:
    FILL(A0, 0)
    CALL(os_close)
    LEA_SYM(A0, SYM(g_filebuf))
    FILL(A1, 1)
    CALL(bc_parse)
    LEAVE_
    RET
bl_e1: LEA_SYM(A0, bc_e1); MOVI(A1, bc_e1_len); CALL(print_str)
    MOVI(RV, 0)
    LEAVE_
    RET
ENDFUNC(bc_load)

/* =====================================================================
 * bc_parse(A0 = veri, A1 = uzunluk) -> RV = 1/0
 * Kaynak dosya da olabilir gomulu blok da; ikisi de ayni kod.
 * DIKKAT: cagiran, calistirmadan ONCE verify_meta kosmak zorunda.
 * Slotlar: 1=ofset 2=i 3=n 4=gecici 5=uzunluk
 * ===================================================================== */
FUNC(bc_parse)
    ENTER(6)
    LEA_SYM(A2, SYM(g_bc_ptr))
    ST(A2, A0)
    SPILL(5, A1)
    /* --- baslik dogrula --- */
    FILL(A0, 5)
    CMPI(A0, BC_HDR * 4)
    BLO(bl_e5)
    MOVI(A0, 0);  CALL(bcr); MOVR(A1, RV); MOVI(A0, BC_MAGIC)
    CMPR(A1, A0); BNE(bl_e2)
    MOVI(A0, 4);  CALL(bcr); CMPI(RV, BC_VERSION); BNE(bl_e2)
    MOVI(A0, 8);  CALL(bcr); CMPI(RV, NAT_COUNT);  BNE(bl_e3)
    MOVI(A0, 12); CALL(bcr); CMPI(RV, WORD_SIZE);  BNE(bl_e6)
    MOVI(A0, 16); CALL(bcr); MOVR(A0, RV)
    CMPI(A0, MAX_CODE);   BHI(bl_e4)
    LEA_SYM(A1, SYM(g_ncode)); ST32_OFF(A1, 0, A0W)
    MOVI(A0, 20); CALL(bcr); MOVR(A0, RV)
    CMPI(A0, MAX_CONSTS); BHI(bl_e4)
    LEA_SYM(A1, SYM(g_nconst)); ST32_OFF(A1, 0, A0W)
    MOVI(A0, 24); CALL(bcr); MOVR(A0, RV)
    CMPI(A0, MAX_GLOBALS); BHI(bl_e4)
    LEA_SYM(A1, SYM(g_nglob)); ST32_OFF(A1, 0, A0W)
    MOVI(A0, 28); CALL(bcr); MOVR(A0, RV)
    CMPI(A0, MAX_FRAMES); BHI(bl_e4)
    LEA_SYM(A1, SYM(g_nfn)); ST32_OFF(A1, 0, A0W)

    MOVI(A0, BC_HDR * 4)
    SPILL(1, A0)

    /* --- kod --- */
    MOVI(A0, 0); SPILL(2, A0)
    LEA_SYM(A0, SYM(g_ncode)); LD32(A0W, A0); SPILL(3, A0)
bl_code:
    FILL(A0, 2); FILL(A1, 3); CMPR(A0, A1); BHS(bl_fns)
    FILL(A0, 1); FILL(A1, 5); ADDI(A0, 4); CMPR(A0, A1); BHI(bl_e5)
    FILL(A0, 1); CALL(bcr); MOVR(A1, RV)
    FILL(A0, 2); CALL(code_put)
    FILL(A0, 1); ADDI(A0, 4); SPILL(1, A0)
    FILL(A0, 2); INC(A0); SPILL(2, A0)
    B(bl_code)

    /* --- fonksiyon tablosu --- */
bl_fns:
    MOVI(A0, 0); SPILL(2, A0)
    LEA_SYM(A0, SYM(g_nfn)); LD32(A0W, A0); SPILL(3, A0)
bl_fn:
    FILL(A0, 2); FILL(A1, 3); CMPR(A0, A1); BHS(bl_consts)
    FILL(A0, 1); FILL(A1, 5); ADDI(A0, 12); CMPR(A0, A1); BHI(bl_e5)
    FILL(A0, 2); SHLI(A0, 3)                  /* g_fns 8 baytlik AYRI yapi */; LEA_SYM(A1, SYM(g_fns)); ADD(A0, A1); SPILL(4, A0)
    FILL(A0, 1); CALL(bcr); MOVR(A1, RV); FILL(A0, 4); ST32_OFF(A0, 0, A1W)
    FILL(A0, 1); ADDI(A0, 4); CALL(bcr); MOVR(A1, RV)
    FILL(A0, 4); ST32_OFF(A0, 4, A1W)
    FILL(A0, 1); ADDI(A0, 8); SPILL(1, A0)
    FILL(A0, 2); INC(A0); SPILL(2, A0)
    B(bl_fn)

    /* --- sabitler --- */
bl_consts:
    MOVI(A0, 0); SPILL(2, A0)
    LEA_SYM(A0, SYM(g_nconst)); LD32(A0W, A0); SPILL(3, A0)
    /* havuzu sifirdan kur */
    MOVI(A0, 0); LEA_SYM(A1, SYM(g_nconst)); ST32_OFF(A1, 0, A0W)
bl_c:
    FILL(A0, 2); FILL(A1, 3); CMPR(A0, A1); BHS(bl_ok)
    FILL(A0, 1); FILL(A1, 5); ADDI(A0, 12); CMPR(A0, A1); BHI(bl_e5)
    FILL(A0, 1); CALL(bcr); SPILL(4, RV)          /* etiket */
    FILL(A0, 1); ADDI(A0, 4); CALL(bcrw); MOVR(A1, RV)  /* yuk / uzunluk */
    FILL(A0, 4)
    CMPI(A0, T_OBJ)
    BEQ(bl_str)
    CALL(bc_addc)
    FILL(A0, 1); ADDI(A0, 12); SPILL(1, A0)   /* etiket 4 + yuk 8 */
    B(bl_cnext)
bl_str:
    SPILL(4, A1)                    /* uzunluk */
    FILL(A0, 1); ADDI(A0, 12)
    FILL(A1, 4); ADD(A0, A1)
    FILL(A1, 5); CMPR(A0, A1); BHI(bl_e5)
    LEA_SYM(A0, SYM(g_bc_ptr)); LD(A0, A0)
    FILL(A1, 1); ADD(A0, A1); ADDI(A0, 12)
    FILL(A1, 4)
    CALL(str_new)
    BZ(RV, bl_e4)
    MOVR(A1, RV)
    MOVI(A0, T_OBJ)
    CALL(bc_addc)
    FILL(A0, 4); ADDI(A0, 3); ANDI(A0, -4); ADDI(A0, 12)
    FILL(A1, 1); ADD(A0, A1); SPILL(1, A0)
bl_cnext:
    FILL(A0, 2); INC(A0); SPILL(2, A0)
    B(bl_c)

bl_ok:
    MOVI(RV, 1)
    LEAVE_
    RET
bl_e2: LEA_SYM(A0, bc_e2); MOVI(A1, bc_e2_len); B(bl_fail)
bl_e3: LEA_SYM(A0, bc_e3); MOVI(A1, bc_e3_len); B(bl_fail)
bl_e4: LEA_SYM(A0, bc_e4); MOVI(A1, bc_e4_len); B(bl_fail)
bl_e6: LEA_SYM(A0, bc_e6); MOVI(A1, bc_e6_len); B(bl_fail)
bl_e5: LEA_SYM(A0, bc_e5); MOVI(A1, bc_e5_len)
bl_fail:
    CALL(print_str)
    MOVI(RV, 0)
    LEAVE_
    RET
ENDFUNC(bc_parse)

/* =====================================================================
 * bc_load_self() -> RV = 1 / 0
 *
 * Kip B: .bc yurutucunun SONUNA eklenmis. PE ve ELF yukleyicileri
 * dosya sonundaki fazlaligi yok saydigi icin ayni yontem uc OS'ta da
 * calisiyor - tek kod yolu.
 *
 * Bicim (dosya sonunda):  [ ...bytecode... ][ u32 uzunluk ][ u32 imza ]
 *
 * Kendi yolunu argv[0]'dan aliyor (Asama 26).
 * ===================================================================== */
#define BC_TRAILER  0x544D5341      /* "ASMT" */

FUNC(bc_load_self)
    ENTER(4)
    MOVI(A0, 0)
    CALL(arg_ptr)
    BZ(RV, bs_no)
    MOVR(A0, RV)
    MOVI(A1, 0)
    CALL(os_open)
    MOVR(A0, RV)
    CMPI(A0, 0)
    BLT(bs_no)
    SPILL(0, A0)                    /* fd */
    /* dosya sonuna git */
    MOVI(A1, 0)
    MOVI(A2, 2)                     /* SEEK_END */
    CALL(os_seek)
    MOVR(A0, RV)
    CMPI(A0, 8)
    BLT(bs_close_no)
    SPILL(1, A0)                    /* dosya boyu */
    /* son 8 bayti oku */
    FILL(A0, 1)
    SUBI(A0, 8)
    MOVR(A1, A0)
    FILL(A0, 0)
    MOVI(A2, 0)
    CALL(os_seek)
    FILL(A0, 0)
    LEA_SYM(A1, SYM(g_filebuf))
    MOVI(A2, 8)
    CALL(os_read)
    CMPI(RV, 8)
    BNE(bs_close_no)
    LEA_SYM(A0, SYM(g_filebuf))
    LD32_OFF(A1W, A0, 4)
    MOVI(A2, BC_TRAILER)
    CMPR(A1, A2)
    BNE(bs_close_no)
    LEA_SYM(A0, SYM(g_filebuf))
    LD32(A0W, A0)                   /* bytecode uzunlugu */
    SPILL(2, A0)
    BZ(A0, bs_close_no)
    CMPI(A0, FILE_BUF_SIZE)
    BHI(bs_close_no)
    /* bytecode'un basina git */
    FILL(A0, 1)
    SUBI(A0, 8)
    FILL(A1, 2)
    SUB(A0, A1)
    MOVR(A1, A0)
    FILL(A0, 0)
    MOVI(A2, 0)
    CALL(os_seek)
    MOVI(A0, 0)
    SPILL(3, A0)                    /* okunan */
bs_rd:
    FILL(A0, 3)
    FILL(A1, 2)
    CMPR(A0, A1)
    BHS(bs_rdone)
    LEA_SYM(A1, SYM(g_filebuf))
    ADD(A1, A0)
    FILL(A2, 2)
    FILL(A0, 3)
    SUB(A2, A0)
    FILL(A0, 0)
    CALL(os_read)
    MOVR(A0, RV)
    CMPI(A0, 0)
    BLE(bs_rdone)
    FILL(A1, 3)
    ADD(A1, A0)
    SPILL(3, A1)
    B(bs_rd)
bs_rdone:
    FILL(A0, 3)
    FILL(A1, 2)
    CMPR(A0, A1)
    BNE(bs_close_no)
    FILL(A0, 0)
    CALL(os_close)
    LEA_SYM(A0, SYM(g_filebuf))
    FILL(A1, 2)
    CALL(bc_parse)
    LEAVE_
    RET
bs_close_no:
    FILL(A0, 0)
    CALL(os_close)
bs_no:
    MOVI(RV, 0)
    LEAVE_
    RET
ENDFUNC(bc_load_self)
