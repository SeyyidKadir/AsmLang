/* natives3.S - taban donusumu, dizi/dizgi donusturucu
 *
 * NOT: tamsayi <-> dizgi donusumu ZATEN VARDI (yazi/str ve sayi/num).
 * Bu dosya eksik olanlari ekliyor: taban donusumu (16'lik, 2'lik,
 * genel), dizi <-> dizgi (birlestir/bol), dilim, sirala.
 *
 * natives.S ve natives2.S cok buyudu; ayri dosya.
 */
#include "../abi.inc"
#include "../tables/opcodes.inc"

#define SET_RES(tg, py) \
    LEA_SYM(A2, SYM(g_natres)); \
    ST32_OFF(A2, VAL_TAG, tg); \
    ST_OFF(A2, VAL_PAY, py)

/* bol() durumu: yardimci islevler cagiranin cerceve slotlarini
 * GOREMEZ (bu projede uc kez hata oldu). Global uzerinden. */
    .bss
    .p2align 3
SYM(g_nsp_src):    .space 8
SYM(g_nsp_sep):    .space 8
SYM(g_nsp_seplen): .space 8
SYM(g_nsp_arr):    .space 8
SYM(g_nsp_i):      .space 8
SYM(g_nsp_k):      .space 8

/* birlestir() kendi tamponu: i32_to_str da g_strbuf'a yaziyor ve
 * birikimi EZIYORDU ([1,2,3] -> "3, 2, 3"). Ayri tampon sart. */
    .globl SYM(g_joinbuf)
SYM(g_joinbuf):    .space (4096) + GUARD_PAD

    SECT_RODATA
    .p2align 4
/* 0-9 a-z : 36 tabana kadar */
nb_digits:
    .ascii "0123456789abcdefghijklmnopqrstuvwxyz"
    SECT_TEXT

/* ---------- taban(sayi, taban) -> dizgi ----------
 * taban 2..36. Negatif sayida basa '-' konur.
 * Ad ikinci argumani belirlemiyorsa: hex -> 16, bin -> 2.
 * Bunu jenerik tutup ikinci argumani ZORUNLU yapmak yerine,
 * tek argumanla cagrilirsa hangi ADIN kullanildigina bakmak
 * gerekirdi - govde tablosu bunu tasimiyor. Bu yuzden:
 *   taban(n, b)  iki arguman
 *   hex(n)       tek arguman -> 16 varsayilir
 *   bin(n)       tek arguman -> 2 varsayilir
 * Ayirt etmek icin arguman SAYISINA bakiyoruz; tek argumanli
 * cagride varsayilan 16'dir ve bin() icin taban(n,2) yazilmali.
 * ---- Bu bir KAPSAM KARARI: ad basina ayri govde indeksi
 * vermek daha temiz olurdu ama tablo buyur. hex/bin ayri
 * indeksle cozuldu (asagida). */
/* tobase_impl(A0 = sayi, A1 = taban) -> RV = dizgi tutamagi / 0 */
FUNC(tobase_impl)
    ENTER(5)
    SPILL(0, A0)                    /* sayi */
    SPILL(1, A1)                    /* taban */
    CMPI(A1, 2)
    BLO(tbi_no)
    CMPI(A1, 36)
    BHI(tbi_no)
    MOVI(A0, 0)
    SPILL(2, A0)                    /* negatif mi */
    SPILL(3, A0)                    /* yazilan */
    FILL(A0, 0)
    CMPI(A0, 0)
    BGE(tbi_pos)
    NEG(A0)
    SPILL(0, A0)
    MOVI(A0, 1)
    SPILL(2, A0)
tbi_pos:
    FILL(A0, 0)
    BNZ(A0, tbi_loop)
    LEA_SYM(A0, SYM(g_strbuf))
    MOVI(A1, 48)
    STB(A0, A1B)
    MOVI(A0, 1)
    SPILL(3, A0)
    B(tbi_sign)
tbi_loop:
    FILL(A0, 0)
    BZ(A0, tbi_sign)
    FILL(A1, 1)
    CALL(udivmod)
    SPILL(0, RV)
    LEA_SYM(A0, SYM(g_rem))
    LD(A0, A0)
    LEA_SYM(A1, nb_digits)
    LDB_IDX(A2W, A1, A0)
    FILL(A0, 3)
    CMPI(A0, 250)
    BHS(tbi_no)
    LEA_SYM(A1, SYM(g_strbuf))
    ADD(A1, A0)
    STB(A1, A2B)
    FILL(A0, 3); INC(A0); SPILL(3, A0)
    B(tbi_loop)
tbi_sign:
    FILL(A0, 2)
    BZ(A0, tbi_rev)
    FILL(A0, 3)
    LEA_SYM(A1, SYM(g_strbuf))
    ADD(A1, A0)
    MOVI(A2, 45)
    STB(A1, A2B)
    FILL(A0, 3); INC(A0); SPILL(3, A0)
tbi_rev:
    MOVI(A0, 0)
    SPILL(4, A0)
tbi_rl:
    FILL(A0, 4)
    FILL(A1, 3); DEC(A1); SUB(A1, A0)
    CMPR(A0, A1)
    BHS(tbi_mk)
    LEA_SYM(A2, SYM(g_strbuf))
    LDB_IDX(A0W, A2, A0)
    SPILL(0, A0)
    FILL(A0, 3); DEC(A0); FILL(A1, 4); SUB(A0, A1)
    LEA_SYM(A2, SYM(g_strbuf))
    LDB_IDX(A1W, A2, A0)
    SPILL(1, A1)
    LEA_SYM(A2, SYM(g_strbuf))
    FILL(A1, 4); ADD(A2, A1)
    FILL(A1, 1)
    STB(A2, A1B)
    LEA_SYM(A2, SYM(g_strbuf))
    ADD(A2, A0)
    FILL(A1, 0)
    STB(A2, A1B)
    FILL(A0, 4); INC(A0); SPILL(4, A0)
    B(tbi_rl)
tbi_mk:
    LEA_SYM(A0, SYM(g_strbuf))
    FILL(A1, 3)
    CALL(str_new)
    LEAVE_
    RET
tbi_no:
    MOVI(RV, 0)
    LEAVE_
    RET
ENDFUNC(tobase_impl)

/* nat_base2(A0 = args, A1 = argc, A2 = varsayilan taban)
 * Ikinci arguman varsa onu kullanir. */
/* nat_base2(A0 = args, A1 = argc, A2 = varsayilan taban)
 * slot 0 = args, 1 = argc, 2 = varsayilan/secilen taban, 3 = sayi */
FUNC(nat_base2)
    ENTER(4)
    SPILL(0, A0)
    SPILL(1, A1)
    SPILL(2, A2)
    CMPI(A1, 1)
    BLO(nb2_nil)
    CALL(arg_int)
    BZ(RV, nb2_nil)
    SPILL(3, A1)                    /* sayi */
    FILL(A0, 1)
    CMPI(A0, 2)
    BLO(nb2_go)
    FILL(A0, 0); ADDI(A0, VAL_SIZE)
    CALL(arg_int)
    BZ(RV, nb2_nil)
    SPILL(2, A1)                    /* acikca verilen taban */
nb2_go:
    FILL(A0, 3)
    FILL(A1, 2)
    CALL(tobase_impl)
    BZ(RV, nb2_nil)
    MOVR(A1, RV)
    MOVI(A0, T_OBJ)
    SET_RES(A0W, A1)
    LEAVE_
    RET
nb2_nil:
    CALL(nat_ret_nil)
    LEAVE_
    RET
ENDFUNC(nat_base2)

/* taban(n, b) : ikinci arguman zorunlu degil, varsayilan 10 */
FUNC(nat_tobase)
    ENTER(1)
    MOVI(A2, 10)
    CALL(nat_base2)
    LEAVE_
    RET
ENDFUNC(nat_tobase)

/* onaltilik(n) / hex(n) */
FUNC(nat_hex)
    ENTER(1)
    MOVI(A2, 16)
    CALL(nat_base2)
    LEAVE_
    RET
ENDFUNC(nat_hex)

/* ikilik(n) / bin(n) */
FUNC(nat_bin)
    ENTER(1)
    MOVI(A2, 2)
    CALL(nat_base2)
    LEAVE_
    RET
ENDFUNC(nat_bin)

/* ---------- tabandan(dizgi, taban) -> tamsayi ----------
 * Cozulemezse bos. Bastaki '-' isaret. */
FUNC(nat_frbase)
    ENTER(6)
    CMPI(A1, 2)
    BNE(nfb_nil)
    SPILL(4, A0)
    MOVI(A1, O_STR)
    CALL(obj_of)
    BZ(RV, nfb_nil)
    SPILL(0, RV)
    LD32_OFF(A0W, RV, OBJ_LEN)
    SPILL(1, A0)                    /* uzunluk */
    BZ(A0, nfb_nil)
    FILL(A0, 4); ADDI(A0, VAL_SIZE)
    CALL(arg_int)
    BZ(RV, nfb_nil)
    SPILL(2, A1)                    /* taban */
    FILL(A0, 2)
    CMPI(A0, 2);  BLO(nfb_nil)
    CMPI(A0, 36); BHI(nfb_nil)
    MOVI(A0, 0)
    SPILL(3, A0)                    /* deger */
    SPILL(5, A0)                    /* i */
    /* isaret */
    FILL(A0, 0); ADDI(A0, OBJ_DATA)
    LDB(A0W, A0)
    CMPI(A0, 45)
    BNE(nfb_loop)
    MOVI(A0, 1); SPILL(5, A0)
nfb_loop:
    FILL(A0, 5)
    FILL(A1, 1)
    CMPR(A0, A1)
    BHS(nfb_fin)
    FILL(A1, 0); ADDI(A1, OBJ_DATA)
    LDB_IDX(A2W, A1, A0)
    /* karakteri basamaga cevir */
    MOVR(A0, A2)
    CMPI(A0, 48); BLO(nfb_nil)
    CMPI(A0, 57); BHI(nfb_alpha)
    SUBI(A0, 48)
    B(nfb_have)
nfb_alpha:
    CMPI(A0, 65); BLO(nfb_nil)
    CMPI(A0, 90); BHI(nfb_lower)
    SUBI(A0, 55)                    /* 'A' -> 10 */
    B(nfb_have)
nfb_lower:
    CMPI(A0, 97);  BLO(nfb_nil)
    CMPI(A0, 122); BHI(nfb_nil)
    SUBI(A0, 87)                    /* 'a' -> 10 */
nfb_have:
    FILL(A1, 2)
    CMPR(A0, A1)
    BHS(nfb_nil)                    /* basamak tabandan buyuk */
    SPILL(4, A0)                    /* basamak */
    FILL(A0, 3)
    FILL(A1, 2)
    MULOV(A0, A1, nfb_nil)
    FILL(A1, 4)
    ADDOV(A0, A1)
    BOV(nfb_nil)
    SPILL(3, A0)
    FILL(A0, 5); INC(A0); SPILL(5, A0)
    B(nfb_loop)
nfb_fin:
    /* isaret uygula */
    FILL(A0, 0); ADDI(A0, OBJ_DATA)
    LDB(A0W, A0)
    CMPI(A0, 45)
    BNE(nfb_ok)
    FILL(A0, 3); NEG(A0); SPILL(3, A0)
nfb_ok:
    FILL(A0, 3)
    CALL(ret_int)
    LEAVE_
    RET
nfb_nil:
    CALL(nat_ret_nil)
    LEAVE_
    RET
ENDFUNC(nat_frbase)

/* ---------- birlestir(dizi, ayirac) -> dizgi ---------- */
FUNC(nat_join)
    ENTER(7)
    CMPI(A1, 2)
    BNE(njn_nil)
    SPILL(4, A0)
    MOVI(A1, O_ARR)
    CALL(obj_of)
    BZ(RV, njn_nil)
    LD32_OFF(A0W, RV, OBJ_LEN)
    SPILL(1, A0)                    /* eleman sayisi */
    FILL(A0, 4); ADDI(A0, VAL_SIZE)
    MOVI(A1, O_STR)
    CALL(obj_of)
    BZ(RV, njn_nil)
    LD32_OFF(A0W, RV, OBJ_LEN)
    SPILL(2, A0)                    /* ayirac uzunlugu */
    MOVI(A0, 0)
    SPILL(3, A0)                    /* yazilan */
    SPILL(5, A0)                    /* i */
njn_loop:
    FILL(A0, 5)
    FILL(A1, 1)
    CMPR(A0, A1)
    BHS(njn_mk)
    /* ayirac (ilk elemandan sonra) */
    FILL(A0, 5)
    BZ(A0, njn_elem)
    FILL(A0, 4); ADDI(A0, VAL_SIZE)
    MOVI(A1, O_STR)
    CALL(obj_of)
    MOVR(A1, RV); ADDI(A1, OBJ_DATA)
    LEA_SYM(A0, SYM(g_joinbuf))
    FILL(A2, 3); ADD(A0, A2)
    FILL(A2, 2)
    CALL(mem_copy_b)
    FILL(A0, 3); FILL(A1, 2); ADD(A0, A1); SPILL(3, A0)
njn_elem:
    /* eleman: yalniz DIZGI ve TAMSAYI destekleniyor */
    FILL(A0, 4)
    MOVI(A1, O_ARR)
    CALL(obj_of)
    MOVR(A0, RV); ADDI(A0, OBJ_DATA)
    FILL(A1, 5); SHLI(A1, VAL_SHIFT); ADD(A0, A1)
    SPILL(6, A0)                    /* eleman yuvasi */
    LD32(A1W, A0)
    CMPI(A1, T_INT)
    BEQ(njn_int)
    CMPI(A1, T_OBJ)
    BNE(njn_nil)
    FILL(A0, 6)
    MOVI(A1, O_STR)
    CALL(obj_of)
    BZ(RV, njn_nil)
    SPILL(0, RV)
    LD32_OFF(A0W, RV, OBJ_LEN)
    B(njn_copy)
njn_int:
    FILL(A0, 6)
    LD_OFF(A0, A0, VAL_PAY)
    CALL(i32_to_str)
    BZ(RV, njn_nil)
    MOVR(A0, RV)
    CALL(obj_ptr)
    SPILL(0, RV)
    LD32_OFF(A0W, RV, OBJ_LEN)
njn_copy:
    SPILL(6, A0)                    /* parca uzunlugu */
    FILL(A0, 3); FILL(A1, 6); ADD(A0, A1)
    CMPI(A0, 4000)
    BHS(njn_nil)
    LEA_SYM(A0, SYM(g_joinbuf))
    FILL(A2, 3); ADD(A0, A2)
    FILL(A1, 0); ADDI(A1, OBJ_DATA)
    FILL(A2, 6)
    CALL(mem_copy_b)
    FILL(A0, 3); FILL(A1, 6); ADD(A0, A1); SPILL(3, A0)
    FILL(A0, 5); INC(A0); SPILL(5, A0)
    B(njn_loop)
njn_mk:
    LEA_SYM(A0, SYM(g_joinbuf))
    FILL(A1, 3)
    CALL(str_new)
    BZ(RV, njn_nil)
    MOVR(A1, RV)
    MOVI(A0, T_OBJ)
    SET_RES(A0W, A1)
    LEAVE_
    RET
njn_nil:
    CALL(nat_ret_nil)
    LEAVE_
    RET
ENDFUNC(nat_join)

/* ---------- bol(dizgi, ayirac) -> dizgi dizisi ----------
 * Ayirac BOS ise karakterlere boler. */
/* bol(dizgi, ayirac) -> dizgi dizisi
 * Ayirac BOS ise karakterlere boler.
 *
 * DIKKAT: str_new GC tetikleyebilir ve nesneleri TASIYABILIR.
 * Bu yuzden isaretci saklanmaz; her adimda TUTAMAKTAN yeniden
 * cozulur. (Bu sinif hata projede daha once str_concat'te cikmisti.)
 *
 * slot: 0=args 1=src tutamak 2=sep tutamak 3=srclen 4=seplen
 *       5=sayac 6=dizi tutamak 7=i 8=bas 9=k
 */
FUNC(nat_split)
    ENTER(10)
    CMPI(A1, 2)
    BNE(nsp_nil)
    SPILL(0, A0)
    MOVI(A1, O_STR)
    CALL(obj_of)
    BZ(RV, nsp_nil)
    LD32_OFF(A0W, RV, OBJ_LEN)
    SPILL(3, A0)
    FILL(A0, 0); LD_OFF(A0, A0, VAL_PAY); SPILL(1, A0)
    LEA_SYM(A1, SYM(g_nsp_src)); ST(A1, A0)
    FILL(A0, 0); ADDI(A0, VAL_SIZE)
    MOVI(A1, O_STR)
    CALL(obj_of)
    BZ(RV, nsp_nil)
    LD32_OFF(A0W, RV, OBJ_LEN)
    SPILL(4, A0)
    LEA_SYM(A1, SYM(g_nsp_seplen)); ST(A1, A0)
    FILL(A0, 0); ADDI(A0, VAL_SIZE); LD_OFF(A0, A0, VAL_PAY); SPILL(2, A0)
    LEA_SYM(A1, SYM(g_nsp_sep)); ST(A1, A0)

    /* --- 1. gecis: parca sayisini bul --- */
    FILL(A0, 4)
    BNZ(A0, nsp_cnt)
    FILL(A0, 3)
    SPILL(5, A0)                    /* bos ayirac: karakter sayisi */
    B(nsp_mk)
nsp_cnt:
    MOVI(A0, 1); SPILL(5, A0)
    MOVI(A0, 0); SPILL(7, A0)
    LEA_SYM(A1, SYM(g_nsp_i)); ST(A1, A0)
nsp_cl:
    FILL(A0, 7); FILL(A1, 4); ADD(A0, A1)
    FILL(A1, 3)
    CMPR(A0, A1)
    BHI(nsp_mk)
    CALL(nsp_match)
    BZ(RV, nsp_c1)
    FILL(A0, 5); INC(A0); SPILL(5, A0)
    FILL(A0, 7); FILL(A1, 4); ADD(A0, A1); SPILL(7, A0)
    LEA_SYM(A1, SYM(g_nsp_i)); ST(A1, A0)
    B(nsp_cl)
nsp_c1:
    FILL(A0, 7); INC(A0); SPILL(7, A0)
    LEA_SYM(A1, SYM(g_nsp_i)); ST(A1, A0)
    B(nsp_cl)

nsp_mk:
    FILL(A0, 5)
    CALL(arr_new)
    BZ(RV, nsp_nil)
    SPILL(6, RV)
    LEA_SYM(A1, SYM(g_nsp_arr)); ST(A1, RV)
    MOVI(A0, 0); SPILL(7, A0); SPILL(8, A0); SPILL(9, A0)
    LEA_SYM(A1, SYM(g_nsp_i)); ST(A1, A0)
    LEA_SYM(A1, SYM(g_nsp_k)); ST(A1, A0)
    FILL(A0, 4)
    BZ(A0, nsp_chars)

    /* --- 2. gecis: ayiraca gore --- */
nsp_pl:
    FILL(A0, 7); FILL(A1, 4); ADD(A0, A1)
    FILL(A1, 3)
    CMPR(A0, A1)
    BHI(nsp_last)
    CALL(nsp_match)
    BZ(RV, nsp_p1)
    FILL(A0, 8)
    FILL(A1, 7); FILL(A2, 8); SUB(A1, A2)
    CALL(nsp_emit)
    BZ(RV, nsp_nil)
    FILL(A0, 7); FILL(A1, 4); ADD(A0, A1); SPILL(7, A0); SPILL(8, A0)
    LEA_SYM(A1, SYM(g_nsp_i)); ST(A1, A0)
    B(nsp_pl)
nsp_p1:
    FILL(A0, 7); INC(A0); SPILL(7, A0)
    LEA_SYM(A1, SYM(g_nsp_i)); ST(A1, A0)
    B(nsp_pl)
nsp_last:
    FILL(A0, 8)
    FILL(A1, 3); FILL(A2, 8); SUB(A1, A2)
    CALL(nsp_emit)
    BZ(RV, nsp_nil)
    B(nsp_done)

    /* --- bos ayirac: her karakter ayri parca --- */
nsp_chars:
    LEA_SYM(A0, SYM(g_nsp_k)); LD(A0, A0)
    FILL(A1, 3)
    CMPR(A0, A1)
    BHS(nsp_done)
    MOVI(A1, 1)
    CALL(nsp_emit)
    BZ(RV, nsp_nil)
    B(nsp_chars)

nsp_done:
    FILL(A1, 6)
    MOVI(A0, T_OBJ)
    SET_RES(A0W, A1)
    LEAVE_
    RET
nsp_nil:
    CALL(nat_ret_nil)
    LEAVE_
    RET
ENDFUNC(nat_split)

/* nsp_match() -> RV = 1 ise slot7 konumunda ayirac var.
 * Isaretciler her cagride tutamaktan yeniden cozuluyor. */
FUNC(nsp_match)
    ENTER(3)
    LEA_SYM(A0, SYM(g_nsp_src)); LD(A0, A0)
    CALL(obj_ptr)
    MOVR(A0, RV); ADDI(A0, OBJ_DATA)
    LEA_SYM(A1, SYM(g_nsp_i)); LD(A1, A1)
    ADD(A0, A1)
    SPILL(0, A0)
    LEA_SYM(A0, SYM(g_nsp_sep)); LD(A0, A0)
    CALL(obj_ptr)
    MOVR(A1, RV); ADDI(A1, OBJ_DATA)
    FILL(A0, 0)
    LEA_SYM(A2, SYM(g_nsp_seplen)); LD(A2, A2)
    CALL(mem_eq)
    LEAVE_
    RET
ENDFUNC(nsp_match)

/* nsp_emit(A0 = bas, A1 = uzunluk) -> RV = 1 tamam
 * Parcayi olusturup diziye yerlestirir, k'yi arttirir. */
FUNC(nsp_emit)
    ENTER(3)
    SPILL(0, A0)
    SPILL(1, A1)
    LEA_SYM(A0, SYM(g_nsp_src)); LD(A0, A0)
    CALL(obj_ptr)
    MOVR(A0, RV); ADDI(A0, OBJ_DATA)
    FILL(A1, 0); ADD(A0, A1)
    FILL(A1, 1)
    CALL(str_new)                   /* GC tetikleyebilir */
    BZ(RV, nse_no)
    SPILL(2, RV)
    LEA_SYM(A0, SYM(g_nsp_arr)); LD(A0, A0)
    CALL(obj_ptr)                   /* dizi TASINMIS olabilir: yeniden coz */
    MOVR(A0, RV); ADDI(A0, OBJ_DATA)
    LEA_SYM(A1, SYM(g_nsp_k)); LD(A1, A1)
    SHLI(A1, VAL_SHIFT); ADD(A0, A1)
    MOVI(A1, T_OBJ)
    ST32_OFF(A0, VAL_TAG, A1W)
    FILL(A1, 2)
    ST_OFF(A0, VAL_PAY, A1)
    LEA_SYM(A0, SYM(g_nsp_k)); LD(A1, A0); INC(A1); ST(A0, A1)
    MOVI(RV, 1)
    LEAVE_
    RET
nse_no:
    MOVI(RV, 0)
    LEAVE_
    RET
ENDFUNC(nsp_emit)

/* ---------- dilim(x, bas, uzunluk) ---------- */
FUNC(nat_slice)
    ENTER(7)
    CMPI(A1, 3)
    BNE(nsl_nil)
    SPILL(4, A0)
    MOVI(A1, O_ARR)
    CALL(obj_of)
    BNZ(RV, nsl_arr)
    FILL(A0, 4)
    MOVI(A1, O_STR)
    CALL(obj_of)
    BZ(RV, nsl_nil)
    /* dizgi dilimi = parca() */
    FILL(A0, 4)
    MOVI(A1, 3)
    CALL(nat_sub)
    LEAVE_
    RET
nsl_arr:
    LD32_OFF(A0W, RV, OBJ_LEN)
    SPILL(0, A0)                    /* kaynak uzunlugu */
    FILL(A0, 4); ADDI(A0, VAL_SIZE)
    CALL(arg_int)
    BZ(RV, nsl_nil)
    SPILL(1, A1)                    /* bas */
    FILL(A0, 4); ADDI(A0, 2*VAL_SIZE)
    CALL(arg_int)
    BZ(RV, nsl_nil)
    SPILL(2, A1)                    /* uzunluk */
    FILL(A0, 1); CMPI(A0, 0); BLT(nsl_nil)
    FILL(A1, 0); CMPR(A0, A1); BHI(nsl_nil)
    FILL(A0, 2); CMPI(A0, 0); BLT(nsl_nil)
    FILL(A1, 1); ADD(A0, A1)
    FILL(A1, 0); CMPR(A0, A1); BLS(nsl_ok)
    FILL(A0, 0); FILL(A1, 1); SUB(A0, A1); SPILL(2, A0)
nsl_ok:
    FILL(A0, 2)
    CALL(arr_new)
    BZ(RV, nsl_nil)
    SPILL(3, RV)
    MOVI(A0, 0); SPILL(5, A0)
nsl_loop:
    FILL(A0, 5)
    FILL(A1, 2)
    CMPR(A0, A1)
    BHS(nsl_fin)
    FILL(A0, 4)
    MOVI(A1, O_ARR)
    CALL(obj_of)
    MOVR(A0, RV); ADDI(A0, OBJ_DATA)
    FILL(A1, 5); FILL(A2, 1); ADD(A1, A2)
    SHLI(A1, VAL_SHIFT); ADD(A0, A1)
    SPILL(6, A0)
    FILL(A0, 3)
    CALL(obj_ptr)
    MOVR(A0, RV); ADDI(A0, OBJ_DATA)
    FILL(A1, 5); SHLI(A1, VAL_SHIFT); ADD(A0, A1)
    FILL(A1, 6)
    LD32(A2W, A1)
    ST32_OFF(A0, VAL_TAG, A2W)
    FILL(A1, 6)
    LD_OFF(A2, A1, VAL_PAY)
    ST_OFF(A0, VAL_PAY, A2)
    FILL(A0, 5); INC(A0); SPILL(5, A0)
    B(nsl_loop)
nsl_fin:
    FILL(A1, 3)
    MOVI(A0, T_OBJ)
    SET_RES(A0W, A1)
    LEAVE_
    RET
nsl_nil:
    CALL(nat_ret_nil)
    LEAVE_
    RET
ENDFUNC(nat_slice)

/* ---------- sirala(dizi) -> YERINDE siralar, diziyi dondurur ----------
 * Yalniz TAMSAYI dizisi. Kabarcik siralama: dizi kucuk olur
 * varsayimi; buyuk diziler icin yetersiz ama dogru. */
FUNC(nat_sort)
    ENTER(6)
    CMPI(A1, 1)
    BNE(nso_nil)
    SPILL(4, A0)
    MOVI(A1, O_ARR)
    CALL(obj_of)
    BZ(RV, nso_nil)
    SPILL(0, RV)
    LD32_OFF(A0W, RV, OBJ_LEN)
    SPILL(1, A0)
    /* butun elemanlar tamsayi mi */
    MOVI(A0, 0); SPILL(2, A0)
nso_chk:
    FILL(A0, 2); FILL(A1, 1); CMPR(A0, A1); BHS(nso_go)
    FILL(A1, 0); ADDI(A1, OBJ_DATA)
    FILL(A0, 2); SHLI(A0, VAL_SHIFT); ADD(A0, A1)
    LD32(A0W, A0)
    BNZ(A0, nso_nil)
    FILL(A0, 2); INC(A0); SPILL(2, A0)
    B(nso_chk)
nso_go:
    MOVI(A0, 0); SPILL(2, A0)       /* dis dongu */
nso_out:
    FILL(A0, 2); FILL(A1, 1); CMPR(A0, A1); BHS(nso_fin)
    MOVI(A0, 0); SPILL(3, A0)
nso_in:
    FILL(A0, 3); FILL(A1, 1); DEC(A1); FILL(A2, 2); SUB(A1, A2)
    CMPR(A0, A1); BHS(nso_onext)
    FILL(A1, 0); ADDI(A1, OBJ_DATA)
    FILL(A0, 3); SHLI(A0, VAL_SHIFT); ADD(A0, A1)
    SPILL(5, A0)
    LD_OFF(A0, A0, VAL_PAY)
    FILL(A1, 5); ADDI(A1, VAL_SIZE)
    LD_OFF(A1, A1, VAL_PAY)
    CMPR(A0, A1)
    BLE(nso_inext)
    /* takas (yalniz yuk; etiketler zaten T_INT) */
    FILL(A2, 5)
    ST_OFF(A2, VAL_PAY, A1)
    FILL(A2, 5); ADDI(A2, VAL_SIZE)
    ST_OFF(A2, VAL_PAY, A0)
nso_inext:
    FILL(A0, 3); INC(A0); SPILL(3, A0)
    B(nso_in)
nso_onext:
    FILL(A0, 2); INC(A0); SPILL(2, A0)
    B(nso_out)
nso_fin:
    FILL(A0, 4)
    LD_OFF(A1, A0, VAL_PAY)
    MOVI(A0, T_OBJ)
    SET_RES(A0W, A1)
    LEAVE_
    RET
nso_nil:
    CALL(nat_ret_nil)
    LEAVE_
    RET
ENDFUNC(nat_sort)
