/* heap.S - nesne yigini ve isaretle-sikistir cop toplayici
 *
 * Butun nesne basvurulari g_objs tutamak tablosundan gecer. Bu, cop
 * toplayicinin SIKISTIRMA yapmasini onemsizlestiriyor: nesneyi tasi,
 * tablodaki tek girdiyi guncelle. Deger yigininda, kuresellerde veya
 * sabitlerde duran hicbir seye dokunmak gerekmez.
 *
 * Bunun karsiliginda nesne erisiminde bir dolayli yukleme var.
 */
#include "../abi.inc"
#include "../tables/tokens.inc"
#include "../tables/opcodes.inc"

    .bss
    .p2align 3
    .globl SYM(g_hbase)
SYM(g_hbase):  .space 8
    .globl SYM(g_htop)
SYM(g_htop):   .space 8
    .globl SYM(g_hend)
SYM(g_hend):   .space 8
    .globl SYM(g_objs)
SYM(g_objs):   .space (MAX_OBJS * 8) + GUARD_PAD     /* tutamak -> isaretci */
    .globl SYM(g_nobj)
SYM(g_nobj):   .space 4                /* kullanilmis tutamak siniri */
    .globl SYM(g_hfree)
SYM(g_hfree):  .space (MAX_OBJS * 4) + GUARD_PAD     /* serbest tutamak yigini */
    .globl SYM(g_nhfree)
SYM(g_nhfree): .space 4
    .globl SYM(g_vstop)
SYM(g_vstop):  .space 8                /* GC icin deger yigini tepesi */
    .globl SYM(g_ngc)
SYM(g_ngc):    .space 4
/* Gecersiz tutamak icin kukla nesne: hep sifir.
 * 0 dondurmek yerine bunu donduruyoruz cunku bazi cagiranlar sonucu
 * denetlemeden dereference ediyor; sifir nesne "tur 0" gorunur ve
 * cagiranin kendi tur denetimine takilir. Null dereference yok. */
    .p2align 3
    .globl SYM(g_nullobj)
SYM(g_nullobj): .space 32
    .globl SYM(g_natres)
SYM(g_natres): .space 8
    .globl SYM(g_strbuf)
SYM(g_strbuf): .space (4096) + GUARD_PAD

    SECT_RODATA
he_oom:  .ascii "calisma hatasi: yigin doldu\n"
    .equ he_oom_len, . - he_oom
he_hnd:  .ascii "calisma hatasi: tutamak tablosu doldu\n"
    .equ he_hnd_len, . - he_hnd

    SECT_TEXT

/* obj_ptr(A0 = tutamak) -> RV = isaretci */
/* obj_ptr(A0 = tutamak) -> RV = isaretci
 * SINIR DENETIMI SART: denetimsizken bozuk bir tutamak g_objs
 * disindan ISARETCI okuyup dereference ediyordu - keyfi okuma/yazma. */
FUNC(obj_ptr)
    ENTER(1)
#if OPT_CFI
    CMPI(A0, MAX_OBJS)
    BHS(op_badh)
#endif
    SHLI(A0, 3)
    LEA_SYM(A1, SYM(g_objs))
    ADD(A0, A1)
    LD(RV, A0)
#if OPT_CFI
    BZ(RV, op_badh)                 /* bos yuva */
#endif
    LEAVE_
    RET
op_badh:
    LEA_SYM(RV, SYM(g_nullobj))
    LEAVE_
    RET
ENDFUNC(obj_ptr)

/* mem_copy(A0 = hedef, A1 = kaynak, A2 = bayt) - ileri yon, 4 bayt adim */
FUNC(mem_copy)
    ENTER(1)
    SPILL(0, A2)                    /* i386'da RV ile A0 ayni register:
                                       gecici olarak RV kullanilamaz,
                                       sayaci slota dokup A2'yi bosaltiyoruz */
mc_loop:
    FILL(A2, 0)
    BZ(A2, mc_done)
    SUBI(A2, 4)
    SPILL(0, A2)
    LD32(A2W, A1)
    ST32_OFF(A0, 0, A2W)
    ADDI(A0, 4)
    ADDI(A1, 4)
    B(mc_loop)
mc_done:
    LEAVE_
    RET
ENDFUNC(mem_copy)

/* ---------------- isaretleme ---------------- */

/* mark_obj(A0 = tutamak) */
FUNC(mark_obj)
    ENTER(3)
    SPILL(0, A0)
    LEA_SYM(A1, SYM(g_nobj))
    LD32(A1W, A1)
    CMPR(A0, A1)
    BHS(mo_end)                     /* gecersiz tutamak */
    CALL(obj_ptr)
    BZ(RV, mo_end)
    SPILL(1, RV)
    LD32_OFF(A0W, RV, OBJ_MARK)
    BNZ(A0, mo_end)                 /* zaten isaretli */
    MOVI(A0, 1)
    FILL(A1, 1)
    ST32_OFF(A1, OBJ_MARK, A0W)
    LD32_OFF(A0W, A1, OBJ_KIND)
    CMPI(A0, O_ARR)
    BNE(mo_end)
    /* dizi: elemanlari da isaretle */
    LD32_OFF(A0W, A1, OBJ_LEN)
    SPILL(2, A0)
mo_loop:
    FILL(A0, 2)
    BZ(A0, mo_end)
    DEC(A0)
    SPILL(2, A0)
    SHLI(A0, VAL_SHIFT)
    FILL(A1, 1)
    ADDI(A1, OBJ_DATA)
    ADD(A0, A1)
    CALL(mark_val)
    B(mo_loop)
mo_end:
    LEAVE_
    RET
ENDFUNC(mark_obj)

/* mark_val(A0 = slot isaretcisi) */
FUNC(mark_val)
    ENTER(1)
    LD32_OFF(A1W, A0, VAL_TAG)
    CMPI(A1, T_OBJ)
    BNE(mv_end)
    LD_OFF(A0, A0, VAL_PAY)
    CALL(mark_obj)
mv_end:
    LEAVE_
    RET
ENDFUNC(mark_val)

/* mark_range(A0 = baslangic, A1 = bitis) - 8 baytlik slotlar */
FUNC(mark_range)
    ENTER(2)
    SPILL(0, A0)
    SPILL(1, A1)
mr_loop:
    FILL(A0, 0)
    FILL(A1, 1)
    CMPR(A0, A1)
    BHS(mr_end)
    CALL(mark_val)
    FILL(A0, 0)
    ADDI(A0, VAL_SIZE)
    SPILL(0, A0)
    B(mr_loop)
mr_end:
    LEAVE_
    RET
ENDFUNC(mark_range)

/* free_handle(A0 = tutamak) */
FUNC(free_handle)
    ENTER(1)
    SPILL(0, A0)
    SHLI(A0, 3)
    LEA_SYM(A1, SYM(g_objs))
    ADD(A0, A1)
    MOVI(A1, 0)
    ST(A0, A1)
    LEA_SYM(A0, SYM(g_nhfree))
    LD32(A1W, A0)
    MOVR(A2, A1)
    INC(A2)
    ST32_OFF(A0, 0, A2W)
    SHLI(A1, 2)
    LEA_SYM(A0, SYM(g_hfree))
    ADD(A0, A1)
    FILL(A1, 0)
    ST32_OFF(A0, 0, A1W)
    LEAVE_
    RET
ENDFUNC(free_handle)

/* =====================================================================
 * gc() - isaretle, sonra yigini sikistir
 * Kokler: deger yigini, kuresel degiskenler, sabit havuzu.
 * ===================================================================== */
FUNC(gc)
    ENTER(4)
    LEA_SYM(A0, SYM(g_ngc))
    LD32(A1W, A0)
    INC(A1)
    ST32_OFF(A0, 0, A1W)

    /* --- kok: deger yigini --- */
    LEA_SYM(A0, SYM(g_stack))
    LEA_SYM(A1, SYM(g_vstop))
    LD(A1, A1)
    CALL(mark_range)
    /* --- kok: kuresel degiskenler --- */
    LEA_SYM(A0, SYM(g_nglob))
    LD32(A1W, A0)
    SHLI(A1, VAL_SHIFT)
    LEA_SYM(A0, SYM(g_gvals))
    ADD(A1, A0)
    CALL(mark_range)
    /* --- kok: sabit havuzu (dizgi degismezleri burada) --- */
    LEA_SYM(A0, SYM(g_nconst))
    LD32(A1W, A0)
    SHLI(A1, VAL_SHIFT)
    LEA_SYM(A0, SYM(g_consts))
    LD(A0, A0)
    MOVR(A2, A0)
    ADD(A1, A2)
    CALL(mark_range)

    /* --- sikistir: yigini dogrusal dolas --- */
    LEA_SYM(A0, SYM(g_hbase))
    LD(A0, A0)
    SPILL(0, A0)                    /* kaynak */
    SPILL(1, A0)                    /* hedef  */
gc_loop:
    LEA_SYM(A0, SYM(g_htop))
    LD(A0, A0)
    FILL(A1, 0)
    CMPR(A1, A0)
    BHS(gc_done)
    FILL(A0, 0)
    LD32_OFF(A1W, A0, OBJ_SIZE)
    SPILL(2, A1)                    /* boyut */
    LD32_OFF(A1W, A0, OBJ_MARK)
    BZ(A1, gc_dead)
    /* canli: gerekiyorsa tasi */
    FILL(A0, 1)
    FILL(A1, 0)
    CMPR(A0, A1)
    BEQ(gc_same)
    FILL(A2, 2)
    CALL(mem_copy)
gc_same:
    FILL(A0, 1)
    MOVI(A1, 0)
    ST32_OFF(A0, OBJ_MARK, A1W)
    LD32_OFF(A1W, A0, OBJ_HND)      /* tutamagi guncelle */
    SHLI(A1, 3)
    LEA_SYM(A2, SYM(g_objs))
    ADD(A1, A2)
    ST(A1, A0)
    FILL(A0, 1)
    FILL(A1, 2)
    ADD(A0, A1)
    SPILL(1, A0)
    B(gc_adv)
gc_dead:
    FILL(A0, 0)
    LD32_OFF(A0W, A0, OBJ_HND)
    CALL(free_handle)
gc_adv:
    FILL(A0, 0)
    FILL(A1, 2)
    ADD(A0, A1)
    SPILL(0, A0)
    B(gc_loop)
gc_done:
    FILL(A0, 1)
    LEA_SYM(A1, SYM(g_htop))
    ST(A1, A0)
    LEAVE_
    RET
ENDFUNC(gc)

/* =====================================================================
 * heap_alloc(A0 = nesne turu, A1 = uzunluk, A2 = veri bayti)
 *   -> RV = tutamak, yer yoksa 0
 * DIKKAT: bu cagri GC tetikleyebilir ve nesneleri TASIR. Cagrildiktan
 * sonra elde tutulan ham isaretciler gecersizdir; yeniden alinmalidir.
 * ===================================================================== */
FUNC(heap_alloc)
    ENTER(6)
    SPILL(0, A0)                    /* tur */
    SPILL(1, A1)                    /* uzunluk */
    MOVI(A0, 0)
    SPILL(5, A0)                    /* bu cagride gc denendi mi */
    FILL(A0, 0)
    ADDI(A2, 7)
    ANDI(A2, -8)                    /* 8'e hizala */
    ADDI(A2, OBJ_DATA)
    SPILL(2, A2)                    /* toplam boyut */

    LEA_SYM(A0, SYM(g_htop))
    LD(A0, A0)
    FILL(A1, 2)
    ADD(A0, A1)
    LEA_SYM(A1, SYM(g_hend))
    LD(A1, A1)
    CMPR(A0, A1)
    BLS(ha_room)
    CALL(gc)
    LEA_SYM(A0, SYM(g_htop))
    LD(A0, A0)
    FILL(A1, 2)
    ADD(A0, A1)
    LEA_SYM(A1, SYM(g_hend))
    LD(A1, A1)
    CMPR(A0, A1)
    BLS(ha_room)
    LEA_SYM(A0, he_oom)
    MOVI(A1, he_oom_len)
    CALL(print_str)
    MOVI(RV, 0)
    LEAVE_
    RET

ha_room:
    /* tutamak edin */
    LEA_SYM(A0, SYM(g_nhfree))
    LD32(A1W, A0)
    BZ(A1, ha_newhnd)
    DEC(A1)
    ST32_OFF(A0, 0, A1W)
    SHLI(A1, 2)
    LEA_SYM(A0, SYM(g_hfree))
    ADD(A0, A1)
    LD32(A0W, A0)
    SPILL(3, A0)
    B(ha_place)
ha_newhnd:
    LEA_SYM(A0, SYM(g_nobj))
    LD32(A1W, A0)
    CMPI(A1, MAX_OBJS)
    BHS(ha_hfull)
    MOVR(A2, A1)
    INC(A2)
    ST32_OFF(A0, 0, A2W)
    SPILL(3, A1)
    B(ha_place)
/* Tutamak tablosu doldu. ONCE cop topla: tutamaklar da tipki yigin
 * alani gibi geri kazanilabilir bir kaynak. Yigin buyutuldugunde
 * (64 KB -> 1 MB) GC yalniz yigin dolunca tetikleniyordu ve
 * tutamaklar once bitiyordu; demo programi sessizce hata veriyordu. */
ha_hfull:
    FILL(A0, 5)
    BNZ(A0, ha_hfull_real)
    MOVI(A0, 1)
    SPILL(5, A0)
    CALL(gc)
    B(ha_room)
ha_hfull_real:
    LEA_SYM(A0, he_hnd)
    MOVI(A1, he_hnd_len)
    CALL(print_str)
    MOVI(RV, 0)
    LEAVE_
    RET

ha_place:
    LEA_SYM(A0, SYM(g_htop))
    LD(A1, A0)
    SPILL(4, A1)                    /* nesne isaretcisi */
    FILL(A2, 2)
    ADD(A1, A2)
    ST(A0, A1)                      /* g_htop ilerlet */

    FILL(A0, 4)
    FILL(A1, 0); ST32_OFF(A0, OBJ_KIND, A1W)
    FILL(A1, 2); ST32_OFF(A0, OBJ_SIZE, A1W)
    FILL(A1, 3); ST32_OFF(A0, OBJ_HND,  A1W)
    MOVI(A1, 0); ST32_OFF(A0, OBJ_MARK, A1W)
    FILL(A1, 1); ST32_OFF(A0, OBJ_LEN,  A1W)
    /* tutamak tablosuna yaz */
    FILL(A1, 3)
    SHLI(A1, 3)
    LEA_SYM(A2, SYM(g_objs))
    ADD(A1, A2)
    ST(A1, A0)
    FILL(RV, 3)
    LEAVE_
    RET
ENDFUNC(heap_alloc)

/* str_new(A0 = kaynak isaretcisi, A1 = uzunluk) -> RV = tutamak */
FUNC(str_new)
    ENTER(3)
    SPILL(0, A0)
    SPILL(1, A1)
    MOVR(A2, A1)
    ADDI(A2, 1)
    MOVI(A0, O_STR)
    CALL(heap_alloc)
    BZ(RV, sn_end)
    SPILL(2, RV)
    MOVR(A0, RV)
    CALL(obj_ptr)
    MOVR(A0, RV)
    ADDI(A0, OBJ_DATA)
    FILL(A1, 0)
    FILL(A2, 1)
    ADDI(A2, 4)                     /* 4 bayt fazla kopyala: hizali ve
                                       zararsiz, uzunluk basligda tutulur */
    ANDI(A2, -4)
    CALL(mem_copy)
    /* Sonuna NUL koy: dizgiler artik C uyumlu, dolayisiyla dogrudan
     * open() gibi cagrilara yol olarak verilebiliyor. heap_alloc
     * uzunluk+1 bayt ayirdigi icin bu bayt sinirlar icinde. */
    FILL(A0, 2)
    CALL(obj_ptr)
    MOVR(A0, RV)
    ADDI(A0, OBJ_DATA)
    FILL(A1, 1)
    ADD(A0, A1)
    MOVI(A2, 0)
    STB(A0, A2B)
    FILL(RV, 2)
sn_end:
    LEAVE_
    RET
ENDFUNC(str_new)

#if !defined(MODE_PLAYER) || !MODE_PLAYER
/* str_from_tok(A0 = dizgi tokeni) -> RV = tutamak
 * Tirnaklar atilir, \n \t \\ \" \' kacislari cozulur.
 */
FUNC(str_from_tok)
    ENTER(7)
    SPILL(0, A0)
    MOVI(A1, TOK_OFF_START)
    CALL(tok_field)
    SPILL(1, RV)
    FILL(A0, 0)
    MOVI(A1, TOK_OFF_LEN)
    CALL(tok_field)
    MOVR(A0, RV)
    SUBI(A0, 2)                     /* tirnaklar */
    SPILL(2, A0)
    LEA_SYM(A0, SYM(g_src))
    LD(A0, A0)
    FILL(A1, 1)
    ADD(A0, A1)
    ADDI(A0, 1)
    SPILL(1, A0)                    /* icerik isaretcisi */
    /* kacis cozerek gecici tampona yaz */
    LEA_SYM(A0, SYM(g_strbuf))
    SPILL(3, A0)
    MOVI(A0, 0)
    SPILL(4, A0)                    /* okunan */
    SPILL(5, A0)                    /* yazilan */
    SPILL(6, A0)                    /* kirpildi mi */
sft_loop:
    FILL(A0, 4)
    FILL(A1, 2)
    CMPR(A0, A1)
    BHS(sft_done)
    FILL(A1, 1)
    LDB_IDX(A2W, A1, A0)
    CMPI(A2, 92)                    /* '\' */
    BNE(sft_put)
    FILL(A0, 4); INC(A0); SPILL(4, A0)
    FILL(A1, 2)
    CMPR(A0, A1)
    BHS(sft_done)
    FILL(A1, 1)
    LDB_IDX(A2W, A1, A0)
    CMPI(A2, 110); BEQ(sft_nl)      /* n */
    CMPI(A2, 116); BEQ(sft_tab)     /* t */
    B(sft_put)
sft_nl:  MOVI(A2, 10); B(sft_put)
sft_tab: MOVI(A2, 9)
sft_put:
    /* g_strbuf sinirini asma: 8000 baytlik bir dizgi degismezi
     * 4096'lik tampona sessizce tasiyordu */
    FILL(A0, 5)
    CMPI(A0, STRBUF_MAX)
    BLO(sft_room)
    MOVI(A0, 1)
    SPILL(6, A0)                    /* bir kez isaretle, her baytta degil */
    B(sft_adv)
sft_room:
    FILL(A0, 3)
    FILL(A1, 5)
    ADD(A0, A1)
    STB(A0, A2B)
    FILL(A0, 5); INC(A0); SPILL(5, A0)
sft_adv:
    FILL(A0, 4); INC(A0); SPILL(4, A0)
    B(sft_loop)
sft_done:
    FILL(A0, 6)
    BZ(A0, sft_ok)
    LEA_SYM(A0, SYM(g_nerr))
    LD32(A1W, A0)
    INC(A1)
    ST32_OFF(A0, 0, A1W)
sft_ok:
    FILL(A0, 3)
    FILL(A1, 5)
    CALL(str_new)
    LEAVE_
    RET
ENDFUNC(str_from_tok)
#endif


/* buf_new(A0 = bayt sayisi) -> RV = tutamak (sifirlanmis)
 * Icinde tutamak yok; GC yalnizca tasir, taramaz. */
FUNC(buf_new)
    ENTER(3)
    SPILL(0, A0)
    MOVR(A2, A0)
    MOVR(A1, A0)
    MOVI(A0, O_BUF)
    CALL(heap_alloc)
    BZ(RV, bn_end)
    SPILL(1, RV)
    MOVR(A0, RV)
    CALL(obj_ptr)
    MOVR(A0, RV)
    ADDI(A0, OBJ_DATA)
    SPILL(2, A0)
bn_zero:
    FILL(A0, 0)
    BZ(A0, bn_done)
    DEC(A0)
    SPILL(0, A0)
    FILL(A1, 2)
    ADD(A1, A0)
    MOVI(A2, 0)
    STB(A1, A2B)
    B(bn_zero)
bn_done:
    FILL(RV, 1)
bn_end:
    LEAVE_
    RET
ENDFUNC(buf_new)

/* arr_new(A0 = eleman sayisi) -> RV = tutamak (nil ile dolu) */
FUNC(arr_new)
    ENTER(4)
    SPILL(0, A0)
    MOVR(A2, A0)
    ADDI(A2, 4)                     /* kapasite payi: ekle() cogu zaman
                                       yeniden ayirma yapmasin */
    SPILL(3, A2)
    SHLI(A2, VAL_SHIFT)
    MOVR(A1, A0)
    MOVI(A0, O_ARR)
    CALL(heap_alloc)
    BZ(RV, an_end)
    SPILL(1, RV)
    MOVR(A0, RV)
    CALL(obj_ptr)
    FILL(A1, 3)
    ST32_OFF(RV, OBJ_CAP, A1W)
    MOVR(A0, RV)
    ADDI(A0, OBJ_DATA)
    SPILL(2, A0)
an_fill:
    FILL(A0, 0)
    BZ(A0, an_end2)
    DEC(A0)
    SPILL(0, A0)
    SHLI(A0, VAL_SHIFT)
    FILL(A1, 2)
    ADD(A0, A1)
    MOVI(A1, T_NIL)
    ST32_OFF(A0, VAL_TAG, A1W)
    MOVI(A1, 0)
    ST_OFF(A0, VAL_PAY, A1)
    B(an_fill)
an_end2:
    FILL(RV, 1)
an_end:
    LEAVE_
    RET
ENDFUNC(arr_new)

/* heap_init(A0 = taban, A1 = boyut) */
FUNC(heap_init)
    ENTER(1)
    LEA_SYM(A2, SYM(g_hbase)); ST(A2, A0)
    LEA_SYM(A2, SYM(g_htop));  ST(A2, A0)
    ADD(A0, A1)
    LEA_SYM(A2, SYM(g_hend));  ST(A2, A0)
    MOVI(A0, 0)
    LEA_SYM(A1, SYM(g_objs))
    ST(A1, A0)                      /* tutamak 0 = null nobetcisi */
    MOVI(A0, 1)
    LEA_SYM(A1, SYM(g_nobj));   ST32_OFF(A1, 0, A0W)
    MOVI(A0, 0)
    LEA_SYM(A1, SYM(g_nhfree)); ST32_OFF(A1, 0, A0W)
    LEA_SYM(A1, SYM(g_ngc));    ST32_OFF(A1, 0, A0W)
    LEA_SYM(A0, SYM(g_stack))
    LEA_SYM(A1, SYM(g_vstop))
    ST(A1, A0)
    LEAVE_
    RET
ENDFUNC(heap_init)

/* obj_len(A0 = tutamak) -> RV = uzunluk */
FUNC(obj_len)
    ENTER(1)
    CALL(obj_ptr)
    LD32_OFF(RVW, RV, OBJ_LEN)
    LEAVE_
    RET
ENDFUNC(obj_len)

/* str_concat(A0 = t1, A1 = t2) -> RV = tutamak (hata: 0)
 *
 * Kopyalama iki asamali: buyuk kismi KELIME kelime (4 bayt), artigi
 * bayt bayt. Bayt bayt kopyalama bayt basina ~6 islem yapiyordu ve
 * "s = s + x" dongusunde maliyetin tamami oradaydi.
 * Kaynak ve hedef ikisi de OBJ_DATA'da basliyor (8 hizali).
 *
 * Isaretciler heap_alloc'tan SONRA tazeleniyor: ayirma GC tetikleyip
 * nesneleri tasiyabilir.
 *
 * Slotlar: 0=t1 1=t2 2=len1 3=len2 4=hedef 5=kaynak1 6=yeni tutamak
 */
FUNC(str_concat)
    ENTER(8)
    SPILL(0, A0)
    SPILL(1, A1)
    CALL(obj_ptr)
    SPILL(2, RV)
    FILL(A1, 2)
    LD32_OFF(A0W, A1, OBJ_KIND)
    CMPI(A0, O_STR)
    BNE(sc_bad)
    FILL(A1, 2)
    LD32_OFF(A0W, A1, OBJ_LEN)
    SPILL(2, A0)                    /* len1 */

    FILL(A0, 1)
    CALL(obj_ptr)
    SPILL(3, RV)
    FILL(A1, 3)
    LD32_OFF(A0W, A1, OBJ_KIND)
    CMPI(A0, O_STR)
    BNE(sc_bad)
    FILL(A1, 3)
    LD32_OFF(A0W, A1, OBJ_LEN)
    SPILL(3, A0)                    /* len2 */

    FILL(A0, 2)
    FILL(A1, 3)
    ADD(A0, A1)
    MOVR(A2, A0)
    ADDI(A2, 1)
    MOVR(A1, A0)
    MOVI(A0, O_STR)
    CALL(heap_alloc)
    BZ(RV, sc_bad)
    SPILL(6, RV)

    FILL(A0, 6)
    CALL(obj_ptr)
    MOVR(A0, RV)
    ADDI(A0, OBJ_DATA)
    SPILL(4, A0)                    /* hedef */
    FILL(A0, 0)
    CALL(obj_ptr)
    MOVR(A0, RV)
    ADDI(A0, OBJ_DATA)
    SPILL(5, A0)                    /* kaynak1 */

    /* parca 1: kelime kismi */
#if !defined(OPT_WORDCOPY) || OPT_WORDCOPY
    FILL(A0, 4)
    FILL(A1, 5)
    FILL(A2, 2)
    ANDI(A2, -4)
    CALL(mem_copy)
#else
    FILL(A0, 4)
    FILL(A1, 5)
    FILL(A2, 2)
    ANDI(A2, -4)
    CALL(mem_copy_b)                /* olcum varyanti: bayt bayt */
#endif
    /* parca 1: artik baytlar */
    FILL(A0, 2)
    ANDI(A0, 3)
    BZ(A0, sc_p1done)
    FILL(A1, 2)
    ANDI(A1, -4)
    FILL(A0, 4); ADD(A0, A1)
    FILL(A2, 5); ADD(A2, A1)
    MOVR(A1, A2)
    FILL(A2, 2)
    ANDI(A2, 3)
    CALL(mem_copy_b)
sc_p1done:

    /* parca 2: hedef ofseti (len1) hizali olmayabilir -> bayt bayt */
    FILL(A0, 1)
    CALL(obj_ptr)
    MOVR(A1, RV)
    ADDI(A1, OBJ_DATA)
    FILL(A0, 4)
    FILL(A2, 2)
    ADD(A0, A2)
    FILL(A2, 3)
    CALL(mem_copy_b)

    FILL(RV, 6)
    LEAVE_
    RET
sc_bad:
    MOVI(RV, 0)
    LEAVE_
    RET
ENDFUNC(str_concat)

/* mem_copy_b(A0 = hedef, A1 = kaynak, A2 = bayt) - bayt bayt */
FUNC(mem_copy_b)
    ENTER(1)
    SPILL(0, A2)
mcb_loop:
    FILL(A2, 0)
    BZ(A2, mcb_done)
    DEC(A2)
    SPILL(0, A2)
    LDB(A2W, A1)
    STB(A0, A2B)
    ADDI(A0, 1)
    ADDI(A1, 1)
    B(mcb_loop)
mcb_done:
    LEAVE_
    RET
ENDFUNC(mem_copy_b)

/* obj_eq(A0 = t1, A1 = t2) -> RV = 1/0 */
FUNC(obj_eq)
    ENTER(5)
    CMPR(A0, A1)
    BEQ(oe_yes)
    SPILL(0, A0)
    SPILL(1, A1)
    CALL(obj_ptr)
    SPILL(2, RV)
    LD32_OFF(A0W, RV, OBJ_KIND)
    SPILL(4, A0)                    /* tur */
    CMPI(A0, O_ARR)
    BEQ(oe_no)                      /* dizi: yalniz tutamak esitligi */
    FILL(A0, 1)
    CALL(obj_ptr)
    SPILL(3, RV)
    LD32_OFF(A0W, RV, OBJ_KIND)
    FILL(A1, 4)
    CMPR(A0, A1)
    BNE(oe_no)                      /* turler ayni olmali */
    FILL(A0, 2)
    LD32_OFF(A0W, A0, OBJ_LEN)
    FILL(A1, 3)
    LD32_OFF(A1W, A1, OBJ_LEN)
    CMPR(A0, A1)
    BNE(oe_no)
    SPILL(4, A0)
oe_loop:
    FILL(A0, 4)
    BZ(A0, oe_yes)
    DEC(A0)
    SPILL(4, A0)
    FILL(A1, 2)
    ADDI(A1, OBJ_DATA)
    LDB_IDX(A2W, A1, A0)
    SPILL(1, A2)
    FILL(A1, 3)
    ADDI(A1, OBJ_DATA)
    LDB_IDX(A1W, A1, A0)
    FILL(A2, 1)
    CMPR(A1, A2)
    BEQ(oe_loop)
oe_no:
    MOVI(RV, 0)
    LEAVE_
    RET
oe_yes:
    MOVI(RV, 1)
    LEAVE_
    RET
ENDFUNC(obj_eq)

/* arr_grow(A0 = tutamak) -> RV = 1 tamam / 0 hata
 * Yeni nesne ayirir, veriyi tasir, sonra TUTAMAGI yeni nesneye yonlendirir
 * ve eskisini yetim (HND_ORPHAN) isaretler. Tutamak degismedigi icin
 * diziye yapilan butun basvurular gecerli kalir - ekle() yerinde buyutmus
 * gibi davranir.
 */
FUNC(arr_grow)
    ENTER(6)
    SPILL(0, A0)
    CALL(obj_ptr)
    SPILL(5, RV)
    FILL(A1, 5)
    LD32_OFF(A0W, A1, OBJ_LEN)
    SPILL(1, A0)
    FILL(A1, 5)
    LD32_OFF(A0W, A1, OBJ_CAP)
    SHLI(A0, 1)
    ADDI(A0, 4)
    SPILL(2, A0)                    /* yeni kapasite */
    MOVR(A2, A0)
    SHLI(A2, VAL_SHIFT)
    FILL(A1, 1)
    MOVI(A0, O_ARR)
    CALL(heap_alloc)
    BZ(RV, ag_bad)
    SPILL(3, RV)
    /* veriyi kopyala (isaretciler ayirmadan SONRA tazelendi) */
    MOVR(A0, RV)
    CALL(obj_ptr)
    SPILL(4, RV)
    FILL(A1, 2)
    ST32_OFF(RV, OBJ_CAP, A1W)
    FILL(A0, 0)
    CALL(obj_ptr)
    MOVR(A1, RV)
    ADDI(A1, OBJ_DATA)
    FILL(A0, 4)
    ADDI(A0, OBJ_DATA)
    FILL(A2, 1)
    SHLI(A2, VAL_SHIFT)
    CALL(mem_copy)
    /* tutamagi yeni nesneye bagla, eskisini yetim yap */
    FILL(A0, 0)
    CALL(obj_ptr)
    MOVI(A1, HND_ORPHAN)
    ST32_OFF(RV, OBJ_HND, A1W)
    FILL(A0, 0)
    SHLI(A0, 3)
    LEA_SYM(A1, SYM(g_objs))
    ADD(A0, A1)
    FILL(A1, 4)
    ST(A0, A1)
    FILL(A0, 4)
    FILL(A1, 0)
    ST32_OFF(A0, OBJ_HND, A1W)
    FILL(A0, 3)
    CALL(free_handle)               /* gecici tutamagi geri ver */
    MOVI(RV, 1)
    LEAVE_
    RET
ag_bad:
    MOVI(RV, 0)
    LEAVE_
    RET
ENDFUNC(arr_grow)

/* i32_to_str(A0 = deger) -> RV = tutamak */
FUNC(i32_to_str)
    ENTER(5)
    LEA_SYM(A1, SYM(g_strbuf))
    SPILL(1, A1)
    MOVI(A2, 0)
    SPILL(2, A2)                    /* yazilan */
    CMPI(A0, 0)
    BGE(its_pos)
    NEG(A0)
    SPILL(0, A0)
    FILL(A0, 1)
    MOVI(A1, 45)                    /* '-' */
    STB(A0, A1B)
    MOVI(A1, 1)
    SPILL(2, A1)
    FILL(A0, 0)
its_pos:
    SPILL(0, A0)
    MOVI(A0, 0)
    SPILL(3, A0)                    /* basladi */
    SPILL(4, A0)                    /* kuvvet indeksi */
its_loop:
    FILL(A0, 4)
    CMPI(A0, POW10_N)
    BHS(its_done)
    LEA_SYM(A1, SYM(pow10))
    LDW_IDX(A1, A1, A0)
    MOVI(A2, 0)
    FILL(A0, 0)
its_sub:
    CMPR(A0, A1)
    BLO(its_emit)
    SUB(A0, A1)
    INC(A2)
    B(its_sub)
its_emit:
    SPILL(0, A0)
    FILL(A0, 3)
    BNZ(A0, its_put)
    BNZ(A2, its_put)
    FILL(A0, 4)
    CMPI(A0, POW10_N - 1)
    BNE(its_adv)
its_put:
    MOVI(A0, 1)
    SPILL(3, A0)
    ADDI(A2, 48)
    FILL(A0, 1)
    FILL(A1, 2)
    ADD(A0, A1)
    STB(A0, A2B)
    FILL(A0, 2); INC(A0); SPILL(2, A0)
its_adv:
    FILL(A0, 4); INC(A0); SPILL(4, A0)
    B(its_loop)
its_done:
    FILL(A0, 1)
    FILL(A1, 2)
    CALL(str_new)
    LEAVE_
    RET
ENDFUNC(i32_to_str)
