/* natives.S - govde (native) fonksiyonlar
 * Imza: nat_xxx(A0 = ilk arguman adresi, A1 = arguman sayisi)
 * Sonuc g_natres slotuna yazilir.
 */
#include "../abi.inc"
#include "../tables/opcodes.inc"
#include "../tables/tokens.inc"
#include "../tables/natives.inc"

    SECT_TEXT

/* --- govde fonksiyon adres tablosu ---
 * Tablo fonksiyonlardan ONCE geliyor: ofsetler pozitif kalsin diye.
 * (optable'da da ayni sira var. Negatif ofset + sifir genisleten
 *  indeksli yukleme = cop adres; bu tuzaga bir kez dusuldu.)
 */
    .p2align 4
    .globl SYM(nat_fns)
SYM(nat_fns):
    .long SYM(nat_len)  - SYM(nat_fns)
    .long SYM(nat_push) - SYM(nat_fns)
    .long SYM(nat_str)  - SYM(nat_fns)
    .long SYM(nat_read) - SYM(nat_fns)
    .long SYM(nat_num)  - SYM(nat_fns)
    .long SYM(nat_rdf)  - SYM(nat_fns)
    .long SYM(nat_wrf)  - SYM(nat_fns)
    .long SYM(nat_buf)  - SYM(nat_fns)
    .long SYM(nat_rdb)  - SYM(nat_fns)
    .long SYM(nat_wrb)  - SYM(nat_fns)
    .long SYM(nat_tos)  - SYM(nat_fns)
    .long SYM(nat_save) - SYM(nat_fns)
    .long SYM(nat_argc) - SYM(nat_fns)
    .long SYM(nat_arg)  - SYM(nat_fns)
    .long SYM(nat_tobuf) - SYM(nat_fns)
    .long SYM(nat_abs) - SYM(nat_fns)
    .long SYM(nat_min) - SYM(nat_fns)
    .long SYM(nat_max) - SYM(nat_fns)
    .long SYM(nat_pow) - SYM(nat_fns)
    .long SYM(nat_type) - SYM(nat_fns)
    .long SYM(nat_wr) - SYM(nat_fns)
    .long SYM(nat_pop) - SYM(nat_fns)
    .long SYM(nat_rev) - SYM(nat_fns)
    .long SYM(nat_has) - SYM(nat_fns)
    .long SYM(nat_sub) - SYM(nat_fns)
    .long SYM(nat_find) - SYM(nat_fns)
    .long SYM(nat_upper) - SYM(nat_fns)
    .long SYM(nat_lower) - SYM(nat_fns)
    .long SYM(nat_starts) - SYM(nat_fns)
    .long SYM(nat_ends) - SYM(nat_fns)
    .long SYM(nat_curs) - SYM(nat_fns)
    .long SYM(nat_cls) - SYM(nat_fns)
    .long SYM(nat_color) - SYM(nat_fns)
    .long SYM(nat_ffi)   - SYM(nat_fns)
    .long SYM(nat_addr)  - SYM(nat_fns)
    .long SYM(nat_mkc)   - SYM(nat_fns)
    .long SYM(nat_tobase) - SYM(nat_fns)
    .long SYM(nat_frbase) - SYM(nat_fns)
    .long SYM(nat_join) - SYM(nat_fns)
    .long SYM(nat_split) - SYM(nat_fns)
    .long SYM(nat_slice) - SYM(nat_fns)
    .long SYM(nat_sort) - SYM(nat_fns)
    .long SYM(nat_hex)  - SYM(nat_fns)
    .long SYM(nat_bin)  - SYM(nat_fns)
    .long SYM(nat_mrd) - SYM(nat_fns)
    .long SYM(nat_mwr) - SYM(nat_fns)
    .long SYM(nat_prd) - SYM(nat_fns)
    .long SYM(nat_pwr) - SYM(nat_fns)
    .long SYM(nat_cpuid) - SYM(nat_fns)
    .long SYM(nat_screen) - SYM(nat_fns)
    .long SYM(nat_pixel) - SYM(nat_fns)
    .long SYM(nat_clsfb) - SYM(nat_fns)
    .long SYM(nat_vga) - SYM(nat_fns)
    .long SYM(nat_beep) - SYM(nat_fns)
    .long SYM(nat_beepoff) - SYM(nat_fns)
    .long SYM(nat_diskrd) - SYM(nat_fns)
    .long SYM(nat_cbul) - SYM(nat_fns)
    .long SYM(nat_c)    - SYM(nat_fns)
    .long SYM(nat_boot) - SYM(nat_fns)
    .long SYM(nat_keyhit) - SYM(nat_fns)
    .long SYM(nat_scancode) - SYM(nat_fns)
    .long SYM(nat_key)  - SYM(nat_fns)
    .long SYM(nat_mouseinit) - SYM(nat_fns)
    .long SYM(nat_mousehit) - SYM(nat_fns)
    .long SYM(nat_mouse) - SYM(nat_fns)
    /* optable ile ayni sinif: govde indeksi bir sabitin YUKUNDEN
     * geliyor ve dogrulayici yuk degerini denetlemiyordu. Doldurma
     * gecersiz indeksi temiz hataya cevirir, sifir maliyetle. */
    .rept 256 - NAT_COUNT
    .long SYM(nat_bad)  - SYM(nat_fns)
    .endr

/* g_natres = {etiket, yuk} */
/* Govde fonksiyonu sonucu. YUK KELIME GENISLIGINDE yazilmali:
 * 32-bit yazip 64-bit okuyunca ust yari cop kaliyordu ve arg(1)
 * gibi nesne donduren fonksiyonlar bozuk tutamak veriyordu. */
#define SET_RES(tagR, payR) \
    LEA_SYM(A2, SYM(g_natres)); \
    ST32_OFF(A2, VAL_TAG, tagR); \
    ST_OFF(A2, VAL_PAY, payR)

/* gecersiz govde indeksi */
FUNC(nat_bad)
    ENTER(1)
    CALL(nat_ret_nil)
    LEAVE_
    RET
ENDFUNC(nat_bad)

FUNC(nat_ret_nil)
    ENTER(1)
    MOVI(A0, T_NIL)
    MOVI(A1, 0)
    SET_RES(A0W, A1)
    LEAVE_
    RET
ENDFUNC(nat_ret_nil)

/* uzunluk(x) - dizgi veya dizi */
FUNC(nat_len)
    ENTER(2)
    CMPI(A1, 1)
    BNE(nl_bad)
    LD32_OFF(A1W, A0, VAL_TAG)
    CMPI(A1, T_OBJ)
    BNE(nl_bad)
    LD_OFF(A0, A0, VAL_PAY)
    CALL(obj_len)
    MOVR(A1, RV)
    MOVI(A0, T_INT)
    SET_RES(A0W, A1)
    LEAVE_
    RET
nl_bad:
    CALL(nat_ret_nil)
    LEAVE_
    RET
ENDFUNC(nat_len)

/* ekle(dizi, deger) -> diziyi dondurur */
FUNC(nat_push)
    ENTER(4)
    CMPI(A1, 2)
    BNE(np_bad)
    SPILL(0, A0)
    LD32_OFF(A1W, A0, VAL_TAG)
    CMPI(A1, T_OBJ)
    BNE(np_bad)
    LD_OFF(A0, A0, VAL_PAY)
    SPILL(1, A0)                    /* tutamak */
    CALL(obj_ptr)
    SPILL(3, RV)
    FILL(A1, 3)
    LD32_OFF(A0W, A1, OBJ_KIND)
    CMPI(A0, O_ARR)
    BNE(np_bad)
    FILL(A1, 3)
    LD32_OFF(A0W, A1, OBJ_LEN)
    SPILL(2, A0)
    FILL(A1, 3)
    LD32_OFF(A1W, A1, OBJ_CAP)
    CMPR(A0, A1)
    BLO(np_fits)
    FILL(A0, 1)
    CALL(arr_grow)
    BZ(RV, np_bad)
np_fits:
    FILL(A0, 1)
    CALL(obj_ptr)
    SPILL(3, RV)
    FILL(A0, 2)
    SHLI(A0, VAL_SHIFT)
    FILL(A1, 3)
    ADDI(A1, OBJ_DATA)
    ADD(A0, A1)                     /* hedef slot */
    FILL(A1, 0)
    ADDI(A1, VAL_SIZE)              /* ikinci arguman */
    LD32_OFF(A2W, A1, VAL_TAG)
    ST32_OFF(A0, VAL_TAG, A2W)
    LD_OFF(A2, A1, VAL_PAY)
    ST_OFF(A0, VAL_PAY, A2)
    FILL(A0, 2)
    INC(A0)
    FILL(A1, 3)
    ST32_OFF(A1, OBJ_LEN, A0W)
    MOVI(A0, T_OBJ)
    FILL(A1, 1)
    SET_RES(A0W, A1)
    LEAVE_
    RET
np_bad:
    CALL(nat_ret_nil)
    LEAVE_
    RET
ENDFUNC(nat_push)

/* yazi(x) - tamsayiyi dizgiye cevirir */
FUNC(nat_str)
    ENTER(2)
    CMPI(A1, 1)
    BNE(ns_bad)
    LD32_OFF(A1W, A0, VAL_TAG)
    CMPI(A1, T_OBJ)
    BEQ(ns_pass)
    CMPI(A1, T_INT)
    BNE(ns_bad)
    LD_OFF(A0, A0, VAL_PAY)
    CALL(i32_to_str)
    BZ(RV, ns_bad)
    MOVR(A1, RV)
    MOVI(A0, T_OBJ)
    SET_RES(A0W, A1)
    LEAVE_
    RET
ns_pass:
    LD_OFF(A1, A0, VAL_PAY)
    MOVI(A0, T_OBJ)
    SET_RES(A0W, A1)
    LEAVE_
    RET
ns_bad:
    CALL(nat_ret_nil)
    LEAVE_
    RET
ENDFUNC(nat_str)

/* oku() -> satiri dizgi olarak dondurur; dosya sonunda bos
 * Satir sonu ve CR atilir. Cok uzun satirin fazlasi atilir. */
FUNC(nat_read)
    ENTER(3)
    MOVI(A0, 0)
    SPILL(0, A0)                    /* yazilan */
    SPILL(1, A0)                    /* hic bayt goruldu mu */
nr_loop:
    CALL(in_getc)
    MOVR(A0, RV)
    CMPI(A0, 0)
    BLT(nr_eof)
    MOVI(A1, 1)
    SPILL(1, A1)
    CMPI(A0, 10)
    BEQ(nr_done)
    CMPI(A0, 13)
    BEQ(nr_loop)
    FILL(A1, 0)
    CMPI(A1, 4000)
    BHS(nr_loop)                    /* tampon doldu: fazlasini at */
    SPILL(2, A0)
    LEA_SYM(A0, SYM(g_strbuf))
    FILL(A1, 0)
    ADD(A0, A1)
    FILL(A2, 2)
    STB(A0, A2B)
    FILL(A0, 0)
    INC(A0)
    SPILL(0, A0)
    B(nr_loop)
nr_eof:
    FILL(A0, 1)
    BZ(A0, nr_nil)                  /* hic bayt yok -> gercek EOF */
nr_done:
    LEA_SYM(A0, SYM(g_strbuf))
    FILL(A1, 0)
    CALL(str_new)
    BZ(RV, nr_nil)
    MOVR(A1, RV)
    MOVI(A0, T_OBJ)
    SET_RES(A0W, A1)
    LEAVE_
    RET
nr_nil:
    CALL(nat_ret_nil)
    LEAVE_
    RET
ENDFUNC(nat_read)

/* sayi(dizgi) -> tamsayi; cozulemezse bos */
FUNC(nat_num)
    ENTER(7)
    CMPI(A1, 1)
    BNE(nu_bad)
    LD32_OFF(A1W, A0, VAL_TAG)
    CMPI(A1, T_OBJ)
    BNE(nu_bad)
    LD_OFF(A0, A0, VAL_PAY)
    CALL(obj_ptr)
    SPILL(0, RV)
    FILL(A1, 0)
    LD32_OFF(A0W, A1, OBJ_KIND)
    CMPI(A0, O_STR)
    BNE(nu_bad)
    FILL(A1, 0)
    LD32_OFF(A0W, A1, OBJ_LEN)
    SPILL(1, A0)                    /* uzunluk */
    FILL(A0, 0)
    ADDI(A0, OBJ_DATA)
    SPILL(2, A0)                    /* veri */
    MOVI(A0, 0)
    SPILL(3, A0)                    /* i     */
    SPILL(4, A0)                    /* deger */
    SPILL(5, A0)                    /* isaret */
nu_sp:
    FILL(A0, 3); FILL(A1, 1); CMPR(A0, A1); BHS(nu_bad)
    FILL(A1, 2); LDB_IDX(A2W, A1, A0)
    CMPI(A2, 32); BNE(nu_sign)
    FILL(A0, 3); INC(A0); SPILL(3, A0); B(nu_sp)
nu_sign:
    FILL(A0, 3); FILL(A1, 2); LDB_IDX(A2W, A1, A0)
    CMPI(A2, 45); BNE(nu_start)     /* '-' */
    MOVI(A1, 1); SPILL(5, A1)
    FILL(A0, 3); INC(A0); SPILL(3, A0)
nu_start:
    /* rakam bolumunun baslangici: hic rakam okunmazsa "0" degil
     * BOS donmeli. sayi("abc") -> 0 sessiz yanlis cevap olurdu. */
    FILL(A0, 3)
    SPILL(6, A0)
nu_digits:
    FILL(A0, 3); FILL(A1, 1); CMPR(A0, A1); BHS(nu_fin)
    FILL(A1, 2); LDB_IDX(A2W, A1, A0)
    CMPI(A2, 48); BLO(nu_fin)
    CMPI(A2, 57); BHI(nu_fin)
    SUBI(A2, 48)
    FILL(A0, 4); MOVI(A1, 10); MUL(A0, A1); ADD(A0, A2); SPILL(4, A0)
    FILL(A0, 3); INC(A0); SPILL(3, A0)
    B(nu_digits)
nu_fin:
    FILL(A0, 3)
    FILL(A1, 6)
    CMPR(A0, A1)
    BEQ(nu_bad)                     /* hic rakam yok */
    FILL(A0, 5); BZ(A0, nu_pos)
    FILL(A0, 4); NEG(A0); SPILL(4, A0)
nu_pos:
    FILL(A1, 4)
    MOVI(A0, T_INT)
    SET_RES(A0W, A1)
    LEAVE_
    RET
nu_bad:
    CALL(nat_ret_nil)
    LEAVE_
    RET
ENDFUNC(nat_num)

/* str_data(A0 = deger slotu) -> RV = veri isaretcisi, dizgi degilse 0 */
FUNC(str_data)
    ENTER(2)
    LD32_OFF(A1W, A0, VAL_TAG)
    CMPI(A1, T_OBJ)
    BNE(sd_no)
    LD_OFF(A0, A0, VAL_PAY)
    CALL(obj_ptr)
    SPILL(0, RV)
    FILL(A1, 0)
    LD32_OFF(A0W, A1, OBJ_KIND)
    CMPI(A0, O_STR)
    BNE(sd_no)
    FILL(A0, 0)
    ADDI(A0, OBJ_DATA)
    MOVR(RV, A0)
    LEAVE_
    RET
sd_no:
    MOVI(RV, 0)
    LEAVE_
    RET
ENDFUNC(str_data)

/* dosya(yol) -> dosyanin tamamini dizgi olarak dondurur, hata: bos
 * Sinir FILE_BUF_SIZE; asani kirpar. */
FUNC(nat_rdf)
    ENTER(3)
    CMPI(A1, 1)
    BNE(rf_nil)
    CALL(str_data)
    BZ(RV, rf_nil)
    MOVR(A0, RV)
    MOVI(A1, 0)                     /* kip 0 = oku */
    CALL(os_open)
    MOVR(A0, RV)
    CMPI(A0, 0)
    BLT(rf_nil)
    SPILL(0, A0)                    /* fd */
    MOVI(A0, 0)
    SPILL(1, A0)                    /* toplam */
rf_loop:
    FILL(A0, 1)
    CMPI(A0, FILE_BUF_SIZE)
    BHS(rf_done)
    LEA_SYM(A1, SYM(g_filebuf))
    ADD(A1, A0)
    MOVI(A2, FILE_BUF_SIZE)
    FILL(A0, 1)
    SUB(A2, A0)
    FILL(A0, 0)
    CALL(os_read)
    MOVR(A0, RV)
    CMPI(A0, 0)
    BLE(rf_done)
    FILL(A1, 1)
    ADD(A1, A0)
    SPILL(1, A1)
    B(rf_loop)
rf_done:
    FILL(A0, 0)
    CALL(os_close)
    LEA_SYM(A0, SYM(g_filebuf))
    FILL(A1, 1)
    CALL(str_new)
    BZ(RV, rf_nil)
    MOVR(A1, RV)
    MOVI(A0, T_OBJ)
    SET_RES(A0W, A1)
    LEAVE_
    RET
rf_nil:
    CALL(nat_ret_nil)
    LEAVE_
    RET
ENDFUNC(nat_rdf)

/* yazf(yol, metin) -> dogru/yanlis */
FUNC(nat_wrf)
    ENTER(4)
    CMPI(A1, 2)
    BNE(wf_no)
    SPILL(0, A0)                    /* arguman tabani */
    CALL(str_data)
    BZ(RV, wf_no)
    SPILL(1, RV)                    /* yol verisi */
    FILL(A0, 0)
    ADDI(A0, VAL_SIZE)
    SPILL(2, A0)                    /* metin slotu */
    CALL(str_data)
    BZ(RV, wf_no)
    SPILL(3, RV)                    /* metin verisi */
    FILL(A0, 1)
    MOVI(A1, 1)                     /* kip 1 = yaz */
    CALL(os_open)
    MOVR(A0, RV)
    CMPI(A0, 0)
    BLT(wf_no)
    SPILL(1, A0)                    /* fd */
    FILL(A0, 2)
    LD_OFF(A0, A0, VAL_PAY)
    CALL(obj_ptr)
    LD32_OFF(A2W, RV, OBJ_LEN)
    FILL(A1, 3)
    FILL(A0, 1)
    CALL(os_write)
    FILL(A0, 1)
    CALL(os_close)
    MOVI(A0, T_BOOL)
    MOVI(A1, 1)
    SET_RES(A0W, A1)
    LEAVE_
    RET
wf_no:
    MOVI(A0, T_BOOL)
    MOVI(A1, 0)
    SET_RES(A0W, A1)
    LEAVE_
    RET
ENDFUNC(nat_wrf)

/* tampon(n) -> n baytlik sifirlanmis tampon */
FUNC(nat_buf)
    ENTER(2)
    CMPI(A1, 1)
    BNE(nb_nil)
    LD32_OFF(A1W, A0, VAL_TAG)
    BNZ(A1, nb_nil)                 /* tamsayi olmali */
    LD_OFF(A0, A0, VAL_PAY)
    CMPI(A0, 0)
    BLT(nb_nil)
    CMPI(A0, FILE_BUF_SIZE)
    BHI(nb_nil)
    CALL(buf_new)
    BZ(RV, nb_nil)
    MOVR(A1, RV)
    MOVI(A0, T_OBJ)
    SET_RES(A0W, A1)
    LEAVE_
    RET
nb_nil:
    CALL(nat_ret_nil)
    LEAVE_
    RET
ENDFUNC(nat_buf)

/* ikili(yol) -> dosyanin tamamini TAMPON olarak dondurur */
FUNC(nat_rdb)
    ENTER(4)
    CMPI(A1, 1)
    BNE(rb_nil)
    CALL(str_data)
    BZ(RV, rb_nil)
    MOVR(A0, RV)
    MOVI(A1, 0)
    CALL(os_open)
    MOVR(A0, RV)
    CMPI(A0, 0)
    BLT(rb_nil)
    SPILL(0, A0)
    MOVI(A0, 0)
    SPILL(1, A0)
rb_loop:
    FILL(A0, 1)
    CMPI(A0, FILE_BUF_SIZE)
    BHS(rb_done)
    LEA_SYM(A1, SYM(g_filebuf))
    ADD(A1, A0)
    MOVI(A2, FILE_BUF_SIZE)
    FILL(A0, 1)
    SUB(A2, A0)
    FILL(A0, 0)
    CALL(os_read)
    MOVR(A0, RV)
    CMPI(A0, 0)
    BLE(rb_done)
    FILL(A1, 1)
    ADD(A1, A0)
    SPILL(1, A1)
    B(rb_loop)
rb_done:
    FILL(A0, 0)
    CALL(os_close)
    FILL(A0, 1)
    CALL(buf_new)
    BZ(RV, rb_nil)
    SPILL(2, RV)
    MOVR(A0, RV)
    CALL(obj_ptr)
    MOVR(A0, RV)
    ADDI(A0, OBJ_DATA)
    LEA_SYM(A1, SYM(g_filebuf))
    FILL(A2, 1)
    CALL(mem_copy_b)
    FILL(A1, 2)
    MOVI(A0, T_OBJ)
    SET_RES(A0W, A1)
    LEAVE_
    RET
rb_nil:
    CALL(nat_ret_nil)
    LEAVE_
    RET
ENDFUNC(nat_rdb)

/* yazikl(yol, tampon) -> dogru/yanlis */
FUNC(nat_wrb)
    ENTER(4)
    CMPI(A1, 2)
    BNE(wb_no)
    SPILL(0, A0)
    CALL(str_data)
    BZ(RV, wb_no)
    SPILL(1, RV)                    /* yol */
    FILL(A0, 0)
    ADDI(A0, VAL_SIZE)
    LD32_OFF(A1W, A0, VAL_TAG)
    CMPI(A1, T_OBJ)
    BNE(wb_no)
    LD_OFF(A0, A0, VAL_PAY)
    CALL(obj_ptr)
    SPILL(2, RV)
    FILL(A1, 2)
    LD32_OFF(A0W, A1, OBJ_KIND)
    CMPI(A0, O_BUF)
    BNE(wb_no)
    FILL(A0, 1)
    MOVI(A1, 1)
    CALL(os_open)
    MOVR(A0, RV)
    CMPI(A0, 0)
    BLT(wb_no)
    SPILL(1, A0)                    /* fd */
    FILL(A1, 2)
    LD32_OFF(A2W, A1, OBJ_LEN)
    ADDI(A1, OBJ_DATA)
    FILL(A0, 1)
    CALL(os_write)
    FILL(A0, 1)
    CALL(os_close)
    MOVI(A0, T_BOOL)
    MOVI(A1, 1)
    SET_RES(A0W, A1)
    LEAVE_
    RET
wb_no:
    MOVI(A0, T_BOOL)
    MOVI(A1, 0)
    SET_RES(A0W, A1)
    LEAVE_
    RET
ENDFUNC(nat_wrb)

/* metin(tampon) -> dizgi (tamponun icerigini kopyalar) */
FUNC(nat_tos)
    ENTER(3)
    CMPI(A1, 1)
    BNE(ts_nil)
    LD32_OFF(A1W, A0, VAL_TAG)
    CMPI(A1, T_OBJ)
    BNE(ts_nil)
    LD_OFF(A0, A0, VAL_PAY)
    CALL(obj_ptr)
    SPILL(0, RV)
    FILL(A1, 0)
    LD32_OFF(A0W, A1, OBJ_KIND)
    CMPI(A0, O_STR)
    BEQ(ts_pass)
    CMPI(A0, O_BUF)
    BNE(ts_nil)
    FILL(A1, 0)
    LD32_OFF(A0W, A1, OBJ_LEN)
    SPILL(1, A0)
    FILL(A0, 0)
    ADDI(A0, OBJ_DATA)
    FILL(A1, 1)
    CALL(str_new)
    BZ(RV, ts_nil)
    MOVR(A1, RV)
    MOVI(A0, T_OBJ)
    SET_RES(A0W, A1)
    LEAVE_
    RET
ts_pass:
    /* zaten dizgi: oldugu gibi dondur */
    FILL(A0, 0)
    LD32_OFF(A1W, A0, OBJ_HND)
    MOVI(A0, T_OBJ)
    SET_RES(A0W, A1)
    LEAVE_
    RET
ts_nil:
    CALL(nat_ret_nil)
    LEAVE_
    RET
ENDFUNC(nat_tos)

/* kaydet(yol) -> derlenmis bytecode'u .bc olarak yazar */
FUNC(nat_save)
    ENTER(2)
    CMPI(A1, 1)
    BNE(nsv_no)
    CALL(str_data)
    BZ(RV, nsv_no)
    MOVR(A0, RV)
    CALL(bc_save)
    MOVR(A1, RV)
    MOVI(A0, T_BOOL)
    SET_RES(A0W, A1)
    LEAVE_
    RET
nsv_no:
    MOVI(A0, T_BOOL)
    MOVI(A1, 0)
    SET_RES(A0W, A1)
    LEAVE_
    RET
ENDFUNC(nat_save)

/* argsay() -> arguman sayisi */
FUNC(nat_argc)
    ENTER(1)
    LEA_SYM(A0, SYM(g_argc))
    LD32(A1W, A0)
    MOVI(A0, T_INT)
    SET_RES(A0W, A1)
    LEAVE_
    RET
ENDFUNC(nat_argc)

/* arg(i) -> i. arguman dizgi olarak, yoksa bos */
FUNC(nat_arg)
    ENTER(2)
    CMPI(A1, 1)
    BNE(na_nil)
    LD32_OFF(A1W, A0, VAL_TAG)
    BNZ(A1, na_nil)                 /* tamsayi olmali */
    LD_OFF(A0, A0, VAL_PAY)
    CMPI(A0, 0)
    BLT(na_nil)
    CALL(arg_ptr)
    BZ(RV, na_nil)
    SPILL(0, RV)
    MOVR(A0, RV)
    CALL(cstr_len)
    MOVR(A1, RV)
    FILL(A0, 0)
    CALL(str_new)
    BZ(RV, na_nil)
    MOVR(A1, RV)
    MOVI(A0, T_OBJ)
    SET_RES(A0W, A1)
    LEAVE_
    RET
na_nil:
    CALL(nat_ret_nil)
    LEAVE_
    RET
ENDFUNC(nat_arg)

/* tampona(dizgi) -> bayt tamponu (icerik kopyalanir)
 * metin()'in tersi; ikisi birlikte dizgi <-> ikili donusumu tamamliyor.
 * DIKKAT: buf_new GC tetikleyebilir, bu yuzden kaynak ISARETCI degil
 * TUTAMAK olarak saklaniyor ve ayirmadan sonra tazeleniyor. */
FUNC(nat_tobuf)
    ENTER(5)
    CMPI(A1, 1)
    BNE(tb_nil)
    LD32_OFF(A1W, A0, VAL_TAG)
    CMPI(A1, T_OBJ)
    BNE(tb_nil)
    LD_OFF(A0, A0, VAL_PAY)
    SPILL(0, A0)                    /* kaynak tutamagi */
    CALL(obj_ptr)
    MOVR(A1, RV)
    LD32_OFF(A0W, A1, OBJ_KIND)
    CMPI(A0, O_STR); BEQ(tb_go)
    CMPI(A0, O_BUF); BNE(tb_nil)
tb_go:
    FILL(A0, 0); CALL(obj_ptr); MOVR(A1, RV)
    LD32_OFF(A0W, A1, OBJ_LEN)
    SPILL(1, A0)                    /* uzunluk */
    CALL(buf_new)
    BZ(RV, tb_nil)
    SPILL(2, RV)                    /* yeni tampon tutamagi */
    FILL(A0, 2); CALL(obj_ptr); MOVR(A0, RV); ADDI(A0, OBJ_DATA)
    SPILL(3, A0)                    /* hedef */
    FILL(A0, 0); CALL(obj_ptr); MOVR(A1, RV); ADDI(A1, OBJ_DATA)
    FILL(A0, 3)
    FILL(A2, 1)
    CALL(mem_copy_b)
    FILL(A1, 2)
    MOVI(A0, T_OBJ)
    SET_RES(A0W, A1)
    LEAVE_
    RET
tb_nil:
    CALL(nat_ret_nil)
    LEAVE_
    RET
ENDFUNC(nat_tobuf)

#if !defined(MODE_PLAYER) || !MODE_PLAYER
/* native_index(A0 = token) -> RV = govde indeksi, yoksa -1
 * kw_lookup ile ayni sekil: uzunluk on elemesi + bayt karsilastirmasi.
 */
FUNC(native_index)
    ENTER(4)
    SPILL(0, A0)
    MOVI(A1, TOK_OFF_LEN)
    CALL(tok_field)
    SPILL(1, RV)
    CMPI(RV, 24)                    /* kayit 32 bayt: ada 24 bayt yer var.
                                     * Sinir 8'de kalmisti ve uzun adlar
                                     * (makinekod, startswith) aranmadan
                                     * reddediliyordu. */
    BHI(ni_no)
    FILL(A0, 0)
    MOVI(A1, TOK_OFF_START)
    CALL(tok_field)
    MOVR(A1, RV)
    LEA_SYM(A0, SYM(g_src))
    LD(A0, A0)
    ADD(A0, A1)
    SPILL(0, A0)                    /* sozcuk isaretcisi */
    LEA_SYM(A0, SYM(nat_table))
    SPILL(2, A0)
ni_next:
    FILL(A0, 2)
    LD32(A1W, A0)
    BZ(A1, ni_no)
    FILL(A2, 1)
    CMPR(A1, A2)
    BNE(ni_adv)
    MOVI(A0, 0)
    SPILL(3, A0)
ni_cmp:
    FILL(A0, 3)
    FILL(A1, 1)
    CMPR(A0, A1)
    BHS(ni_hit)
    FILL(A1, 0)
    LDB_IDX(A2W, A1, A0)
    FILL(A1, 2)
    ADDI(A1, 8)
    LDB_IDX(A1W, A1, A0)
    CMPR(A1, A2)
    BNE(ni_adv)
    FILL(A0, 3)
    INC(A0)
    SPILL(3, A0)
    B(ni_cmp)
ni_hit:
    FILL(A0, 2)
    LD32_OFF(RVW, A0, 4)
    LEAVE_
    RET
ni_adv:
    FILL(A0, 2)
    ADDI(A0, 32)
    SPILL(2, A0)
    B(ni_next)
ni_no:
    MOVI(RV, -1)
    LEAVE_
    RET
ENDFUNC(native_index)
#endif


