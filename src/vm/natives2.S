/* natives2.S - genisletilmis govde fonksiyonlari
 *
 * Matematik, tur sorgusu, dizi ve dizgi islemleri.
 * natives.S'e yigmak yerine ayri dosya: o dosya cok buyudu ve
 * yama uzerine yama koymak bu projede birkac kez sessiz hataya
 * yol acti.
 *
 * Hepsi ayni sozlesme: A0 = arguman tabani, A1 = arguman sayisi,
 * sonuc SET_RES ile arguman tabanindan bir onceki yuvaya yazilir.
 */
#include "../abi.inc"
#include "../tables/opcodes.inc"

/* natives.S ile ayni yardimcilar */
/* natives.S ile AYNI olmali: yuk kelime genisliginde. */
#define SET_RES(tg, py) \
    LEA_SYM(A2, SYM(g_natres)); \
    ST32_OFF(A2, VAL_TAG, tg); \
    ST_OFF(A2, VAL_PAY, py)

    SECT_RODATA
ty_int: .ascii "tamsayi"
    .equ ty_int_len, . - ty_int
ty_nil: .ascii "bos"
    .equ ty_nil_len, . - ty_nil
ty_bol: .ascii "mantiksal"
    .equ ty_bol_len, . - ty_bol
ty_str: .ascii "dizgi"
    .equ ty_str_len, . - ty_str
ty_arr: .ascii "dizi"
    .equ ty_arr_len, . - ty_arr
ty_buf: .ascii "tampon"
    .equ ty_buf_len, . - ty_buf
ty_fn:  .ascii "fonksiyon"
    .equ ty_fn_len, . - ty_fn

    SECT_TEXT

/* arg_int(A0 = deger yuvasi) -> RV = 1 tamsayi ise, deger A1'de */
FUNC(arg_int)
    ENTER(1)
    LD32_OFF(A1W, A0, VAL_TAG)
    BNZ(A1, ai_no)
    LD_OFF(A1, A0, VAL_PAY)
    MOVI(RV, 1)
    LEAVE_
    RET
ai_no:
    MOVI(RV, 0)
    LEAVE_
    RET
ENDFUNC(arg_int)

/* ret_int(A0 = deger) */
FUNC(ret_int)
    ENTER(1)
    MOVR(A1, A0)
    MOVI(A0, T_INT)
    SET_RES(A0W, A1)
    LEAVE_
    RET
ENDFUNC(ret_int)

/* ================== matematik ================== */

FUNC(nat_abs)
    ENTER(1)
    CMPI(A1, 1)
    BNE(nab_nil)
    CALL(arg_int)
    BZ(RV, nab_nil)
    MOVR(A0, A1)
    CMPI(A0, 0)
    BGE(nab_ok)
    NEG(A0)
nab_ok:
    CALL(ret_int)
    LEAVE_
    RET
nab_nil:
    CALL(nat_ret_nil)
    LEAVE_
    RET
ENDFUNC(nat_abs)

/* nat_mm(A0, A1, A2 = 0 en kucuk / 1 en buyuk) */
FUNC(nat_mm)
    ENTER(3)
    SPILL(2, A2)
    CMPI(A1, 2)
    BNE(nmm_nil)
    SPILL(0, A0)
    CALL(arg_int)
    BZ(RV, nmm_nil)
    SPILL(1, A1)
    FILL(A0, 0)
    ADDI(A0, VAL_SIZE)
    CALL(arg_int)
    BZ(RV, nmm_nil)
    /* Mod ONCE okunmali: BNZ karsilastirma bayraklarini ezer,
     * sonraki BLE/BGE yanlis bayraga bakardi (max, min gibi
     * davraniyordu). */
    FILL(A2, 2)
    BNZ(A2, nmm_ismax)
    FILL(A0, 1)
    CMPR(A0, A1)
    BLE(nmm_take)
    MOVR(A0, A1)
    B(nmm_take)
nmm_ismax:
    FILL(A0, 1)
    CMPR(A0, A1)
    BGE(nmm_take)
    MOVR(A0, A1)
nmm_take:
    CALL(ret_int)
    LEAVE_
    RET
nmm_nil:
    CALL(nat_ret_nil)
    LEAVE_
    RET
ENDFUNC(nat_mm)

FUNC(nat_min)
    ENTER(1)
    MOVI(A2, 0)
    CALL(nat_mm)
    LEAVE_
    RET
ENDFUNC(nat_min)

FUNC(nat_max)
    ENTER(1)
    MOVI(A2, 1)
    CALL(nat_mm)
    LEAVE_
    RET
ENDFUNC(nat_max)

/* us(taban, us) - tasmada bos, negatif us -> 0 */
FUNC(nat_pow)
    ENTER(4)
    CMPI(A1, 2)
    BNE(npw_nil)
    SPILL(0, A0)
    CALL(arg_int)
    BZ(RV, npw_nil)
    SPILL(1, A1)
    FILL(A0, 0)
    ADDI(A0, VAL_SIZE)
    CALL(arg_int)
    BZ(RV, npw_nil)
    /* Us COK BUYUK olamaz: 2^62 kere donmek pratikte askida
     * kalmak demek (olculdu: zaman asimi). Tasma zaten 64 adimda
     * gerceklesir, dolayisiyla 64 ustu us anlamsiz. */
    CMPI(A1, 64)
    BHI(npw_nil)
    SPILL(2, A1)
    MOVI(A0, 1)
    SPILL(3, A0)
npw_loop:
    FILL(A0, 2)
    CMPI(A0, 0)
    BLE(npw_done)
    DEC(A0)
    SPILL(2, A0)
    FILL(A0, 3)
    FILL(A1, 1)
    /* Tasmada SESSIZCE SARMA: us(2,64) -> 0 uretiyordu.
     * Yorumlayicinin aritmetigiyle ayni ilke. */
    MULOV(A0, A1, npw_nil)
    SPILL(3, A0)
    B(npw_loop)
npw_done:
    FILL(A0, 3)
    CALL(ret_int)
    LEAVE_
    RET
npw_nil:
    CALL(nat_ret_nil)
    LEAVE_
    RET
ENDFUNC(nat_pow)

/* ================== tur ve cikti ================== */

FUNC(nat_type)
    ENTER(2)
    CMPI(A1, 1)
    BNE(nty_nil)
    LD32_OFF(A1W, A0, VAL_TAG)
    SPILL(0, A1)
    CMPI(A1, T_OBJ)
    BNE(nty_simple)
    LD_OFF(A0, A0, VAL_PAY)
    CALL(obj_ptr)
    LD32_OFF(A0W, RV, OBJ_KIND)
    CMPI(A0, O_STR); BEQ(nty_s)
    CMPI(A0, O_BUF); BEQ(nty_b)
    LEA_SYM(A0, ty_arr); MOVI(A1, ty_arr_len); B(nty_mk)
nty_s:
    LEA_SYM(A0, ty_str); MOVI(A1, ty_str_len); B(nty_mk)
nty_b:
    LEA_SYM(A0, ty_buf); MOVI(A1, ty_buf_len); B(nty_mk)
nty_simple:
    FILL(A0, 0)
    CMPI(A0, T_NIL);  BEQ(nty_n)
    CMPI(A0, T_BOOL); BEQ(nty_o)
    CMPI(A0, T_INT);  BEQ(nty_i)
    LEA_SYM(A0, ty_fn); MOVI(A1, ty_fn_len); B(nty_mk)
nty_n:
    LEA_SYM(A0, ty_nil); MOVI(A1, ty_nil_len); B(nty_mk)
nty_o:
    LEA_SYM(A0, ty_bol); MOVI(A1, ty_bol_len); B(nty_mk)
nty_i:
    LEA_SYM(A0, ty_int); MOVI(A1, ty_int_len)
nty_mk:
    CALL(str_new)
    BZ(RV, nty_nil)
    MOVR(A1, RV)
    MOVI(A0, T_OBJ)
    SET_RES(A0W, A1)
    LEAVE_
    RET
nty_nil:
    CALL(nat_ret_nil)
    LEAVE_
    RET
ENDFUNC(nat_type)

/* yaz(x) - yazdir gibi ama SATIR SONU KOYMAZ */
FUNC(nat_wr)
    ENTER(1)
    CMPI(A1, 1)
    BNE(nwr_end)
    CALL(print_val)
nwr_end:
    CALL(nat_ret_nil)
    LEAVE_
    RET
ENDFUNC(nat_wr)

/* ================== dizi ================== */

/* obj_of(A0 = deger yuvasi, A1 = beklenen tur) -> RV = isaretci / 0 */
FUNC(obj_of)
    ENTER(2)
    SPILL(1, A1)
    LD32_OFF(A1W, A0, VAL_TAG)
    CMPI(A1, T_OBJ)
    BNE(oo_no)
    LD_OFF(A0, A0, VAL_PAY)
    CALL(obj_ptr)
    SPILL(0, RV)
    FILL(A1, 0)
    LD32_OFF(A0W, A1, OBJ_KIND)
    FILL(A1, 1)
    CMPR(A0, A1)
    BNE(oo_no)
    FILL(RV, 0)
    LEAVE_
    RET
oo_no:
    MOVI(RV, 0)
    LEAVE_
    RET
ENDFUNC(obj_of)

/* cikar(dizi) -> son elemani cikarip dondurur */
FUNC(nat_pop)
    ENTER(3)
    CMPI(A1, 1)
    BNE(npo_nil)
    MOVI(A1, O_ARR)
    CALL(obj_of)
    BZ(RV, npo_nil)
    SPILL(0, RV)
    FILL(A0, 0)
    LD32_OFF(A0W, A0, OBJ_LEN)
    BZ(A0, npo_nil)
    DEC(A0)
    SPILL(1, A0)                    /* yeni uzunluk */
    FILL(A0, 0)
    FILL(A1, 1)
    ST32_OFF(A0, OBJ_LEN, A1W)
    FILL(A0, 1)
    SHLI(A0, VAL_SHIFT)
    FILL(A1, 0)
    ADD(A0, A1)
    ADDI(A0, OBJ_DATA)
    LD32_OFF(A1W, A0, VAL_TAG)
    LD_OFF(A2, A0, VAL_PAY)
    SPILL(2, A2)
    MOVR(A0, A1)
    FILL(A1, 2)
    SET_RES(A0W, A1)
    LEAVE_
    RET
npo_nil:
    CALL(nat_ret_nil)
    LEAVE_
    RET
ENDFUNC(nat_pop)

/* ters(dizi) - YERINDE tersler, diziyi dondurur */
FUNC(nat_rev)
    ENTER(6)
    CMPI(A1, 1)
    BNE(nrv_nil)
    SPILL(4, A0)
    MOVI(A1, O_ARR)
    CALL(obj_of)
    BZ(RV, nrv_nil)
    SPILL(0, RV)
    FILL(A0, 0)
    ADDI(A0, OBJ_DATA)
    SPILL(1, A0)                    /* veri */
    FILL(A0, 0)
    LD32_OFF(A0W, A0, OBJ_LEN)
    BZ(A0, nrv_ok)
    DEC(A0)
    SPILL(3, A0)                    /* sag */
    MOVI(A0, 0)
    SPILL(2, A0)                    /* sol */
nrv_loop:
    FILL(A0, 2)
    FILL(A1, 3)
    CMPR(A0, A1)
    BHS(nrv_ok)
    /* takas: iki yuvayi bastan sona kopyala (etiket + yuk).
     * DIKKAT: onceki surumde toplu donusum "FILL(A0, 3)" ifadesini
     * kaydirma sanip "FILL(A0, VAL_SHIFT)" yapmisti - slot numarasi
     * bozuldu ve fonksiyon cokuyordu. */
    FILL(A0, 2); SHLI(A0, VAL_SHIFT); FILL(A1, 1); ADD(A0, A1); SPILL(5, A0)
    FILL(A0, 3); SHLI(A0, VAL_SHIFT); FILL(A1, 1); ADD(A0, A1)
    /* etiket takasi */
    LD32(A1W, A0)
    FILL(A2, 5); LD32(A2W, A2)
    ST32_OFF(A0, VAL_TAG, A2W)
    FILL(A2, 5); ST32_OFF(A2, VAL_TAG, A1W)
    /* yuk takasi (KELIME genisliginde) */
    LD_OFF(A1, A0, VAL_PAY)
    FILL(A2, 5); LD_OFF(A2, A2, VAL_PAY)
    ST_OFF(A0, VAL_PAY, A2)
    FILL(A2, 5); ST_OFF(A2, VAL_PAY, A1)
    FILL(A0, 2); INC(A0); SPILL(2, A0)
    FILL(A0, 3); DEC(A0); SPILL(3, A0)
    B(nrv_loop)
nrv_ok:
    FILL(A0, 4)
    LD_OFF(A1, A0, VAL_PAY)
    MOVI(A0, T_OBJ)
    SET_RES(A0W, A1)
    LEAVE_
    RET
nrv_nil:
    CALL(nat_ret_nil)
    LEAVE_
    RET
ENDFUNC(nat_rev)

/* icerir(dizi, deger) -> dogru/yanlis */
FUNC(nat_has)
    ENTER(5)
    CMPI(A1, 2)
    BNE(nhs_no)
    SPILL(4, A0)
    MOVI(A1, O_ARR)
    CALL(obj_of)
    BZ(RV, nhs_no)
    SPILL(0, RV)
    FILL(A0, 0)
    LD32_OFF(A0W, A0, OBJ_LEN)
    SPILL(1, A0)
    MOVI(A0, 0)
    SPILL(2, A0)
nhs_loop:
    FILL(A0, 2)
    FILL(A1, 1)
    CMPR(A0, A1)
    BHS(nhs_no)
    FILL(A0, 2); SHLI(A0, VAL_SHIFT)
    FILL(A1, 0); ADD(A0, A1); ADDI(A0, OBJ_DATA)
    SPILL(3, A0)
    /* etiketler ayni mi */
    LD32(A0W, A0)
    FILL(A1, 4)
    LD32_OFF(A1W, A1, VAL_SIZE + VAL_TAG)
    CMPR(A0, A1)
    BNE(nhs_next)
    FILL(A0, 3)
    LD_OFF(A0, A0, VAL_PAY)
    FILL(A1, 4)
    LD32_OFF(A1W, A1, VAL_SIZE + VAL_PAY)
    CMPR(A0, A1)
    BEQ(nhs_yes)
nhs_next:
    FILL(A0, 2); INC(A0); SPILL(2, A0)
    B(nhs_loop)
nhs_yes:
    MOVI(A0, T_BOOL)
    MOVI(A1, 1)
    SET_RES(A0W, A1)
    LEAVE_
    RET
nhs_no:
    MOVI(A0, T_BOOL)
    MOVI(A1, 0)
    SET_RES(A0W, A1)
    LEAVE_
    RET
ENDFUNC(nat_has)

/* ================== dizgi ================== */

/* parca(dizgi, baslangic, uzunluk) */
FUNC(nat_sub)
    ENTER(6)
    CMPI(A1, 3)
    BNE(nsb_nil)
    SPILL(4, A0)
    MOVI(A1, O_STR)
    CALL(obj_of)
    BZ(RV, nsb_nil)
    LD32_OFF(A0W, RV, OBJ_LEN)
    SPILL(0, A0)                    /* kaynak uzunlugu */
    FILL(A0, 4); ADDI(A0, VAL_SIZE)
    CALL(arg_int)
    BZ(RV, nsb_nil)
    SPILL(1, A1)                    /* baslangic */
    FILL(A0, 4); ADDI(A0, 2 * VAL_SIZE)
    CALL(arg_int)
    BZ(RV, nsb_nil)
    SPILL(2, A1)                    /* istenen uzunluk */
    /* sinirla: 0 <= bas <= len, bas+uz <= len */
    FILL(A0, 1)
    CMPI(A0, 0)
    BLT(nsb_nil)
    FILL(A1, 0)
    CMPR(A0, A1)
    BHI(nsb_nil)
    FILL(A0, 2)
    CMPI(A0, 0)
    BLT(nsb_nil)
    FILL(A1, 1); ADD(A0, A1)
    FILL(A1, 0)
    CMPR(A0, A1)
    BLS(nsb_ok)
    FILL(A0, 0); FILL(A1, 1); SUB(A0, A1); SPILL(2, A0)
nsb_ok:
    /* isaretciyi TAZELE: str_new GC tetikleyebilir, once uzunluk al */
    FILL(A0, 4)
    MOVI(A1, O_STR)
    CALL(obj_of)
    MOVR(A0, RV)
    ADDI(A0, OBJ_DATA)
    FILL(A1, 1)
    ADD(A0, A1)
    FILL(A1, 2)
    CALL(str_new)
    BZ(RV, nsb_nil)
    MOVR(A1, RV)
    MOVI(A0, T_OBJ)
    SET_RES(A0W, A1)
    LEAVE_
    RET
nsb_nil:
    CALL(nat_ret_nil)
    LEAVE_
    RET
ENDFUNC(nat_sub)

/* bul(dizgi, aranan) -> indeks ya da -1 */
/* bul(x, aranan) -> indeks ya da -1
 * Dizgide alt dizgi, DIZIDE eleman arar. "indexOf" bu. */
FUNC(nat_find)
    ENTER(7)
    CMPI(A1, 2)
    BNE(nfd_no)
    SPILL(4, A0)
    MOVI(A1, O_ARR)
    CALL(obj_of)
    BNZ(RV, nfd_arr)
    FILL(A0, 4)
    MOVI(A1, O_STR)
    CALL(obj_of)
    BZ(RV, nfd_no)
    SPILL(0, RV)
    LD32_OFF(A0W, RV, OBJ_LEN)
    SPILL(1, A0)
    FILL(A0, 4); ADDI(A0, VAL_SIZE)
    MOVI(A1, O_STR)
    CALL(obj_of)
    BZ(RV, nfd_no)
    SPILL(2, RV)
    LD32_OFF(A0W, RV, OBJ_LEN)
    SPILL(3, A0)
    MOVI(A0, 0)
    SPILL(5, A0)                    /* i */
nfd_loop:
    FILL(A0, 5)
    FILL(A1, 3)
    ADD(A0, A1)
    FILL(A1, 1)
    CMPR(A0, A1)
    BHI(nfd_no)
    /* karsilastir */
    FILL(A0, 0); ADDI(A0, OBJ_DATA); FILL(A1, 5); ADD(A0, A1)
    FILL(A1, 2); ADDI(A1, OBJ_DATA)
    FILL(A2, 3)
    CALL(mem_eq)
    BNZ(RV, nfd_hit)
    FILL(A0, 5); INC(A0); SPILL(5, A0)
    B(nfd_loop)
nfd_hit:
    FILL(A0, 5)
    CALL(ret_int)
    LEAVE_
    RET
nfd_arr:
    /* dizide eleman ara: etiket + yuk esitligi */
    SPILL(0, RV)
    LD32_OFF(A0W, RV, OBJ_LEN)
    SPILL(1, A0)
    MOVI(A0, 0)
    SPILL(5, A0)
nfa_loop:
    FILL(A0, 5)
    FILL(A1, 1)
    CMPR(A0, A1)
    BHS(nfd_no)
    FILL(A0, 5); SHLI(A0, VAL_SHIFT)
    FILL(A1, 0); ADD(A0, A1); ADDI(A0, OBJ_DATA)
    SPILL(6, A0)
    LD32(A0W, A0)
    FILL(A1, 4)
    LD32_OFF(A1W, A1, VAL_SIZE + VAL_TAG)
    CMPR(A0, A1)
    BNE(nfa_next)
    FILL(A0, 6)
    LD_OFF(A0, A0, VAL_PAY)
    FILL(A1, 4)
    LD32_OFF(A1W, A1, VAL_SIZE + VAL_PAY)
    CMPR(A0, A1)
    BEQ(nfd_hit)
nfa_next:
    FILL(A0, 5); INC(A0); SPILL(5, A0)
    B(nfa_loop)

nfd_no:
    MOVI(A0, -1)
    CALL(ret_int)
    LEAVE_
    RET
ENDFUNC(nat_find)

/* mem_eq(A0, A1, A2 = uzunluk) -> RV = 1 esitse */
FUNC(mem_eq)
    ENTER(3)
    SPILL(0, A0)
    SPILL(1, A1)
    SPILL(2, A2)
me_loop:
    FILL(A0, 2)
    BZ(A0, me_yes)
    DEC(A0)
    SPILL(2, A0)
    FILL(A0, 0); FILL(A1, 2); LDB_IDX(A2W, A0, A1)
    SPILL(0, A0)
    FILL(A0, 1); FILL(A1, 2); LDB_IDX(A0W, A0, A1)
    CMPR(A0, A2)
    BNE(me_no)
    FILL(A0, 0)
    B(me_loop)
me_yes:
    MOVI(RV, 1)
    LEAVE_
    RET
me_no:
    MOVI(RV, 0)
    LEAVE_
    RET
ENDFUNC(mem_eq)

/* nat_case(A0, A1, A2 = 0 buyuk / 1 kucuk) - yalniz ASCII */
FUNC(nat_case)
    ENTER(5)
    SPILL(3, A2)
    CMPI(A1, 1)
    BNE(nca_nil)
    SPILL(4, A0)
    MOVI(A1, O_STR)
    CALL(obj_of)
    BZ(RV, nca_nil)
    LD32_OFF(A0W, RV, OBJ_LEN)
    SPILL(0, A0)
    /* once kopyala, sonra yerinde donustur */
    FILL(A0, 4)
    MOVI(A1, O_STR)
    CALL(obj_of)
    MOVR(A0, RV)
    ADDI(A0, OBJ_DATA)
    FILL(A1, 0)
    CALL(str_new)
    BZ(RV, nca_nil)
    SPILL(1, RV)
    FILL(A0, 1)
    CALL(obj_ptr)
    MOVR(A0, RV)
    ADDI(A0, OBJ_DATA)
    SPILL(2, A0)
    MOVI(A0, 0)
    SPILL(4, A0)
nca_loop:
    FILL(A0, 4)
    FILL(A1, 0)
    CMPR(A0, A1)
    BHS(nca_done)
    FILL(A1, 2)
    LDB_IDX(A2W, A1, A0)
    FILL(A1, 3)
    BNZ(A1, nca_low)
    CMPI(A2, 97);  BLO(nca_next)    /* 'a' */
    CMPI(A2, 122); BHI(nca_next)    /* 'z' */
    SUBI(A2, 32)
    B(nca_put)
nca_low:
    CMPI(A2, 65);  BLO(nca_next)    /* 'A' */
    CMPI(A2, 90);  BHI(nca_next)    /* 'Z' */
    ADDI(A2, 32)
nca_put:
    FILL(A0, 2); FILL(A1, 4); ADD(A0, A1)
    STB(A0, A2B)
nca_next:
    FILL(A0, 4); INC(A0); SPILL(4, A0)
    B(nca_loop)
nca_done:
    FILL(A1, 1)
    MOVI(A0, T_OBJ)
    SET_RES(A0W, A1)
    LEAVE_
    RET
nca_nil:
    CALL(nat_ret_nil)
    LEAVE_
    RET
ENDFUNC(nat_case)

FUNC(nat_upper)
    ENTER(1)
    MOVI(A2, 0)
    CALL(nat_case)
    LEAVE_
    RET
ENDFUNC(nat_upper)

FUNC(nat_lower)
    ENTER(1)
    MOVI(A2, 1)
    CALL(nat_case)
    LEAVE_
    RET
ENDFUNC(nat_lower)

/* ================== baslar / biter ==================
 * "indexOf" zaten bul()/find() olarak var; bunlar onun ozel halleri
 * ama ayri fonksiyon olarak daha okunakli ve daha ucuz (tarama yok).
 */

/* nat_be(A0, A1, A2 = 0 baslangic / 1 son) -> dogru/yanlis */
FUNC(nat_be)
    ENTER(5)
    SPILL(4, A2)
    CMPI(A1, 2)
    BNE(nbe_no)
    SPILL(3, A0)
    MOVI(A1, O_STR)
    CALL(obj_of)
    BZ(RV, nbe_no)
    SPILL(0, RV)
    LD32_OFF(A0W, RV, OBJ_LEN)
    SPILL(1, A0)                    /* kaynak uzunlugu */
    FILL(A0, 3); ADDI(A0, VAL_SIZE)
    MOVI(A1, O_STR)
    CALL(obj_of)
    BZ(RV, nbe_no)
    SPILL(2, RV)
    LD32_OFF(A0W, RV, OBJ_LEN)
    SPILL(3, A0)                    /* aranan uzunluk */
    FILL(A1, 1)
    CMPR(A0, A1)
    BHI(nbe_no)                     /* aranan daha uzunsa hayir */
    /* baslangic ofseti */
    FILL(A0, 4)
    BZ(A0, nbe_at0)
    FILL(A0, 1); FILL(A1, 3); SUB(A0, A1)
    B(nbe_go)
nbe_at0:
    MOVI(A0, 0)
nbe_go:
    FILL(A1, 0); ADDI(A1, OBJ_DATA); ADD(A0, A1)
    FILL(A1, 2); ADDI(A1, OBJ_DATA)
    FILL(A2, 3)
    CALL(mem_eq)
    BZ(RV, nbe_no)
    MOVI(A0, T_BOOL)
    MOVI(A1, 1)
    SET_RES(A0W, A1)
    LEAVE_
    RET
nbe_no:
    MOVI(A0, T_BOOL)
    MOVI(A1, 0)
    SET_RES(A0W, A1)
    LEAVE_
    RET
ENDFUNC(nat_be)

FUNC(nat_starts)
    ENTER(1)
    MOVI(A2, 0)
    CALL(nat_be)
    LEAVE_
    RET
ENDFUNC(nat_starts)

FUNC(nat_ends)
    ENTER(1)
    MOVI(A2, 1)
    CALL(nat_be)
    LEAVE_
    RET
ENDFUNC(nat_ends)

/* ================== konsol (ANSI) ==================
 * Terminal kontrolu ANSI kacis dizileriyle: her yerde ayni kod,
 * OS'a ozel cagri YOK. Bare-metal'de de UART'a aynen gider ve
 * terminal emulatoru anlar.
 */
    SECT_RODATA
esc_cls: .ascii "\033[2J\033[H"
    .equ esc_cls_len, . - esc_cls
esc_csi: .ascii "\033["
    .equ esc_csi_len, . - esc_csi
    SECT_TEXT

/* temizle() */
FUNC(nat_cls)
    ENTER(1)
    LEA_SYM(A0, esc_cls)
    MOVI(A1, esc_cls_len)
    CALL(print_str)
    CALL(nat_ret_nil)
    LEAVE_
    RET
ENDFUNC(nat_cls)

/* imlec(satir, sutun) -> ESC[satir;sutunH  (1 tabanli) */
FUNC(nat_curs)
    ENTER(3)
    CMPI(A1, 2)
    BNE(ncu_end)
    SPILL(0, A0)
    CALL(arg_int)
    BZ(RV, ncu_end)
    SPILL(1, A1)
    FILL(A0, 0); ADDI(A0, VAL_SIZE)
    CALL(arg_int)
    BZ(RV, ncu_end)
    SPILL(2, A1)
    LEA_SYM(A0, esc_csi); MOVI(A1, esc_csi_len); CALL(print_str)
    FILL(A0, 1); CALL(print_u32)
    MOVI(A0, 59); CALL(print_ch)    /* ';' */
    FILL(A0, 2); CALL(print_u32)
    MOVI(A0, 72); CALL(print_ch)    /* 'H' */
ncu_end:
    CALL(nat_ret_nil)
    LEAVE_
    RET
ENDFUNC(nat_curs)

/* renk(n) -> ESC[nm  (0 sifirla, 31 kirmizi, 32 yesil ...) */
FUNC(nat_color)
    ENTER(2)
    CMPI(A1, 1)
    BNE(nco_end)
    CALL(arg_int)
    BZ(RV, nco_end)
    SPILL(0, A1)
    LEA_SYM(A0, esc_csi); MOVI(A1, esc_csi_len); CALL(print_str)
    FILL(A0, 0); CALL(print_u32)
    MOVI(A0, 109); CALL(print_ch)   /* 'm' */
nco_end:
    CALL(nat_ret_nil)
    LEAVE_
    RET
ENDFUNC(nat_color)
