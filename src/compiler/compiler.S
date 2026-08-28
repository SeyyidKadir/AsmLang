/* compiler.S - AST -> bytecode
 *
 * Tek gecis, geriye yama (backpatching) ile. Yerel degiskenler yigin
 * uzerinde, kuresel degiskenler ada gore ic ice gecirilmis (interned)
 * bir tabloda.
 *
 * Derinlik 0'daki bildirimler kuresel, derinlik > 0 yereldir.
 */
#include "../abi.inc"
#include "../tables/tokens.inc"
#include "../tables/ast.inc"
#include "../tables/opcodes.inc"

    .bss
    .p2align 3
    .globl SYM(g_cerr)
SYM(g_cerr):    .space 4
    .globl SYM(g_depth)
SYM(g_depth):   .space 4
/* Fonksiyon govdesindeyken kusatan kapsamdaki yerel sayisi.
 * 0 = fonksiyon disindayiz. */
    .globl SYM(g_encl)
SYM(g_encl):    .space 4
    .globl SYM(g_nloc)
SYM(g_nloc):    .space 4
    .globl SYM(g_nintern)
SYM(g_nintern): .space 4
    .globl SYM(g_nloop)
SYM(g_nloop):   .space 4
    .globl SYM(g_nbrk)
SYM(g_nbrk):    .space 4
/* yerel: {u32 token, u32 derinlik} */
    .globl SYM(g_loc)
SYM(g_loc):     .space (MAX_LOCALS * 8) + GUARD_PAD
/* kuresel ad tablosu: u32 token */
    .globl SYM(g_gname)
SYM(g_gname):   .space (MAX_GLOBALS * 4) + GUARD_PAD
/* fonksiyon tablosu: {u32 giris, u32 arite} */
    .globl SYM(g_loopst)
SYM(g_loopst):  .space (MAX_LOOPS * 4) + GUARD_PAD
    .globl SYM(g_loopbb)
SYM(g_loopbb):  .space (MAX_LOOPS * 4) + GUARD_PAD
    .globl SYM(g_brk)
SYM(g_brk):     .space (MAX_BREAKS * 4) + GUARD_PAD
    .globl SYM(g_cont)
SYM(g_cont):    .space (MAX_CONTS * 4) + GUARD_PAD
    .globl SYM(g_ncont)
SYM(g_ncont):   .space 4
    .globl SYM(g_loopcb)
SYM(g_loopcb):  .space (MAX_LOOPS * 4) + GUARD_PAD

    SECT_RODATA
ce_m1:  .ascii "derleyici hatasi (satir "
    .equ ce_m1_len, . - ce_m1
ce_m2:  .ascii "): "
    .equ ce_m2_len, . - ce_m2
ce_undef: .ascii "tanimsiz ad\n"
    .equ ce_undef_len, . - ce_undef
ce_target: .ascii "atama hedefi degisken olmali\n"
    .equ ce_target_len, . - ce_target
ce_full: .ascii "tablo doldu\n"
    .equ ce_full_len, . - ce_full
ce_code: .ascii "bytecode tamponu doldu\n"
    .equ ce_code_len, . - ce_code
ce_pool: .ascii "sabit havuzu doldu\n"
    .equ ce_pool_len, . - ce_pool
ce_encl: .ascii "fonksiyon disaridaki yerel degiskene erisemez (kapanis yok)\n"
    .equ ce_encl_len, . - ce_encl
ce_numov: .ascii "sayi degismezi sigmiyor\n"
    .equ ce_numov_len, . - ce_numov
ce_glob: .ascii "cok fazla kuresel degisken\n"
    .equ ce_glob_len, . - ce_glob
ce_brk:  .ascii "cok fazla kir/devam\n"
    .equ ce_brk_len, . - ce_brk
ce_loop: .ascii "dongu ic ice gecme sinirin asti\n"
    .equ ce_loop_len, . - ce_loop
ce_fn:   .ascii "cok fazla fonksiyon\n"
    .equ ce_fn_len, . - ce_fn

    SECT_TEXT

/* cerr(A0 = ileti, A1 = uzunluk) */
FUNC(cerr)
    ENTER(2)
    SPILL(0, A0)
    SPILL(1, A1)
    LEA_SYM(A0, SYM(g_cerr))
    LD32(A1W, A0)
    INC(A1)
    ST32_OFF(A0, 0, A1W)
    CMPI(A1, 5)
    BHI(cerr_quiet)                 /* perr gibi: ilk 5 hatayi bas */
    LEA_SYM(A0, ce_m1)
    MOVI(A1, ce_m1_len)
    CALL(print_str)
    CALL(cur_line)
    MOVR(A0, RV)
    CALL(print_u32)
    LEA_SYM(A0, ce_m2)
    MOVI(A1, ce_m2_len)
    CALL(print_str)
    FILL(A0, 0)
    FILL(A1, 1)
    CALL(print_str)
cerr_quiet:
    LEAVE_
    RET
ENDFUNC(cerr)

/* emit(A0 = islem kodu, A1 = islenen) -> RV = komut indeksi */
FUNC(emit)
    ENTER(2)
    SHLI(A1, OPD_SHIFT)
    ORR(A0, A1)
    SPILL(0, A0)                    /* kodlanmis komut */
    LEA_SYM(A0, SYM(g_ncode))
    LD32(A1W, A0)
    CMPI(A1, MAX_CODE)
    BHS(em_full)
    MOVR(A2, A1)
    INC(A2)
    ST32_OFF(A0, 0, A2W)
    SPILL(1, A1)                    /* indeks */
    MOVR(A0, A1)
    SHLI(A0, 2)
    LEA_SYM(A1, SYM(g_code))
    LD(A1, A1)
    ADD(A0, A1)
    FILL(A1, 0)
    ST32_OFF(A0, 0, A1W)
    FILL(RV, 1)
    LEAVE_
    RET
em_full:
    LEA_SYM(A0, ce_code)
    MOVI(A1, ce_code_len)
    CALL(cerr)
    MOVI(RV, 0)
    LEAVE_
    RET
ENDFUNC(emit)

/* patch(A0 = komut indeksi, A1 = yeni islenen) */
FUNC(patch)
    ENTER(2)
    SPILL(1, A1)
    SHLI(A0, 2)
    LEA_SYM(A1, SYM(g_code))
    LD(A1, A1)
    ADD(A0, A1)
    LD32(A1W, A0)
    ANDI(A1, 0xFFFF)                /* islem kodunu koru */
    FILL(A2, 1)
    SHLI(A2, OPD_SHIFT)
    ORR(A1, A2)
    ST32_OFF(A0, 0, A1W)
    LEAVE_
    RET
ENDFUNC(patch)

/* here() -> RV = siradaki komut indeksi */
FUNC(here)
    ENTER(1)
    LEA_SYM(A0, SYM(g_ncode))
    LD32(RVW, A0)
    LEAVE_
    RET
ENDFUNC(here)

/* add_const(A0 = etiket, A1 = yuk) -> RV = sabit indeksi */
FUNC(add_const)
    ENTER(4)
    SPILL(0, A0)
    SPILL(1, A1)
#if OPT_INTERN
    /* --- ic ice gecirme (interning) ---
     * Ayni degismez ikinci kez sabit havuzuna girmez. Havuz indeksi
     * superkomutlarin 8-bit alanini tiketen asil darbogaz; onu
     * kucultmek GETG_CONST / ADDK kapsamini dogrudan artiriyor.
     * Tarama O(n^2); birkac yuz sabit icin sorun degil, buyurse
     * ilk-bayt kovali bir hash gerekir. */
    MOVI(A0, 0)
    SPILL(2, A0)
ac_scan:
    LEA_SYM(A0, SYM(g_nconst))
    LD32(A0W, A0)
    FILL(A1, 2)
    CMPR(A1, A0)
    BHS(ac_new)
    FILL(A0, 2)
    SHLI(A0, VAL_SHIFT)
    LEA_SYM(A1, SYM(g_consts))
    LD(A1, A1)
    ADD(A0, A1)
    SPILL(3, A0)
    LD32(A1W, A0)                   /* mevcut etiket */
    FILL(A2, 0)
    CMPR(A1, A2)
    BNE(ac_next)
    FILL(A0, 0)
    CMPI(A0, T_OBJ)
    BEQ(ac_obj)
    FILL(A0, 3)
    LD_OFF(A0, A0, VAL_PAY)
    FILL(A1, 1)
    CMPR(A0, A1)
    BEQ(ac_hit)
    B(ac_next)
ac_obj:
    /* dizgiler icerik olarak karsilastirilir; ayni metin iki kez
     * yazilsa da tek havuz girdisi kullanir */
    FILL(A0, 3)
    LD_OFF(A0, A0, VAL_PAY)
    FILL(A1, 1)
    CALL(obj_eq)
    BNZ(RV, ac_hit)
ac_next:
    FILL(A0, 2)
    INC(A0)
    SPILL(2, A0)
    B(ac_scan)
ac_hit:
    LEA_SYM(A0, SYM(g_nintern))
    LD32(A1W, A0)
    INC(A1)
    ST32_OFF(A0, 0, A1W)
    FILL(RV, 2)
    LEAVE_
    RET
ac_new:
#endif
    LEA_SYM(A0, SYM(g_nconst))
    LD32(A0W, A0)
    CMPI(A0, MAX_CONSTS)
    BLO(ac_room)
    LEA_SYM(A0, ce_pool)
    MOVI(A1, ce_pool_len)
    CALL(cerr)
    MOVI(RV, 0)
    LEAVE_
    RET
ac_room:
    LEA_SYM(A0, SYM(g_nconst))
    LD32(A1W, A0)
    MOVR(A2, A1)
    INC(A2)
    ST32_OFF(A0, 0, A2W)
    SPILL(2, A1)
    MOVR(A0, A1)
    SHLI(A0, VAL_SHIFT)                     /* * VAL_SIZE */
    LEA_SYM(A1, SYM(g_consts))
    LD(A1, A1)
    ADD(A0, A1)
    FILL(A1, 0)
    ST32_OFF(A0, VAL_TAG, A1W)
    FILL(A1, 1)
    ST_OFF(A0, VAL_PAY, A1)
    FILL(RV, 2)
    LEAVE_
    RET
ENDFUNC(add_const)

/* tok_to_int(A0 = token indeksi) -> RV
 * Yalnizca tamsayi kismi; '.' gorulunce durur (Asama 3 tamsayi VM'i).
 */
FUNC(tok_to_int)
    ENTER(4)
    SPILL(0, A0)
    MOVI(A1, TOK_OFF_START)
    CALL(tok_field)
    SPILL(1, RV)
    FILL(A0, 0)
    MOVI(A1, TOK_OFF_LEN)
    CALL(tok_field)
    SPILL(2, RV)
    LEA_SYM(A0, SYM(g_src))
    LD(A0, A0)
    FILL(A1, 1)
    ADD(A0, A1)
    SPILL(1, A0)                    /* sozcuk isaretcisi */
    MOVI(A0, 0)
    SPILL(3, A0)                    /* biriken deger */
tti_loop:
    FILL(A0, 2)
    BZ(A0, tti_done)
    FILL(A0, 1)
    LDB(A1W, A0)
    CMPI(A1, 48)
    BLO(tti_done)
    CMPI(A1, 57)
    BHI(tti_done)
    SUBI(A1, 48)
    /* Sigmayan sayi degismezi SESSIZCE SARMAMALI.
     * 32-bit hedefte "4611686018427387903" yazinca -1 uretiyordu.
     * Carpma ve toplamada tasma bayragina bakiyoruz; tasarsa
     * derleme hatasi. */
    FILL(A0, 3)
    MOVI(A2, 10)
    MULOV(A0, A2, tti_ovf)
    ADDOV(A0, A1)
    BOV(tti_ovf)
    SPILL(3, A0)
    FILL(A0, 1); INC(A0); SPILL(1, A0)
    FILL(A0, 2); DEC(A0); SPILL(2, A0)
    B(tti_loop)
tti_done:
    FILL(RV, 3)
    LEAVE_
    RET
tti_ovf:
    LEA_SYM(A0, ce_numov)
    MOVI(A1, ce_numov_len)
    CALL(cerr)
    MOVI(RV, 0)
    LEAVE_
    RET
ENDFUNC(tok_to_int)

/* tok_eq(A0 = token a, A1 = token b) -> RV = 1/0 (sozcukleri esit mi) */
FUNC(tok_eq)
    ENTER(6)
    SPILL(0, A0)
    SPILL(1, A1)
    MOVI(A1, TOK_OFF_LEN)
    CALL(tok_field)
    SPILL(2, RV)
    FILL(A0, 1)
    MOVI(A1, TOK_OFF_LEN)
    CALL(tok_field)
    MOVR(A1, RV)
    FILL(A0, 2)
    CMPR(A0, A1)
    BNE(te_no)
    FILL(A0, 0)
    MOVI(A1, TOK_OFF_START)
    CALL(tok_field)
    SPILL(3, RV)
    FILL(A0, 1)
    MOVI(A1, TOK_OFF_START)
    CALL(tok_field)
    SPILL(4, RV)
    MOVI(A0, 0)
    SPILL(5, A0)
te_loop:
    FILL(A0, 5)
    FILL(A1, 2)
    CMPR(A0, A1)
    BHS(te_yes)
    LEA_SYM(A1, SYM(g_src))
    LD(A1, A1)
    FILL(A2, 3)
    ADD(A1, A2)
    LDB_IDX(A2W, A1, A0)            /* a[i] */
    LEA_SYM(A1, SYM(g_src))
    LD(A1, A1)
    SPILL(1, A2)                    /* a[i] gecici */
    FILL(A2, 4)
    ADD(A1, A2)
    LDB_IDX(A1W, A1, A0)            /* b[i] */
    FILL(A2, 1)
    CMPR(A1, A2)
    BNE(te_no)
    FILL(A0, 5); INC(A0); SPILL(5, A0)
    B(te_loop)
te_yes:
    MOVI(RV, 1)
    LEAVE_
    RET
te_no:
    MOVI(RV, 0)
    LEAVE_
    RET
ENDFUNC(tok_eq)

/* global_index(A0 = ad tokeni) -> RV = kuresel yuva (yoksa olusturur) */
/* global_find(A0 = ad tokeni) -> RV = yuva ya da -1
 * global_index'ten farki: BULAMAZSA yeni yuva ACMAZ.
 * Ad cozumlemede "kullanici tanimi gövde fonksiyonunu golgelesin"
 * kurali icin gerekli - yoksa "tanim buyuk = 5" yazan biri
 * degiskenini kaybediyor ve gomulu buyuk()/upper() kazaniyor. */
FUNC(global_find)
    ENTER(3)
    SPILL(0, A0)
    MOVI(A0, 0)
    SPILL(1, A0)
gf_loop:
    LEA_SYM(A0, SYM(g_nglob))
    LD32(A0W, A0)
    FILL(A1, 1)
    CMPR(A1, A0)
    BHS(gf_no)
    LEA_SYM(A0, SYM(g_gname))
    LD32_IDX(A0W, A0, A1)
    FILL(A1, 0)
    CALL(tok_eq)
    BNZ(RV, gf_hit)
    FILL(A0, 1); INC(A0); SPILL(1, A0)
    B(gf_loop)
gf_hit:
    FILL(RV, 1)
    LEAVE_
    RET
gf_no:
    MOVI(RV, -1)
    LEAVE_
    RET
ENDFUNC(global_find)

FUNC(global_index)
    ENTER(3)
    SPILL(0, A0)
    MOVI(A0, 0)
    SPILL(1, A0)
gi_loop:
    LEA_SYM(A0, SYM(g_nglob))
    LD32(A0W, A0)
    FILL(A1, 1)
    CMPR(A1, A0)
    BHS(gi_new)
    LEA_SYM(A0, SYM(g_gname))
    LD32_IDX(A0W, A0, A1)
    FILL(A1, 0)
    SPILL(2, A0)
    CALL(tok_eq)
    BNZ(RV, gi_hit)
    FILL(A0, 1); INC(A0); SPILL(1, A0)
    B(gi_loop)
gi_hit:
    FILL(RV, 1)
    LEAVE_
    RET
gi_new:
    LEA_SYM(A0, SYM(g_nglob))
    LD32(A1W, A0)
    CMPI(A1, MAX_GLOBALS)
    BHS(gi_full)
    MOVR(A2, A1)
    INC(A2)
    ST32_OFF(A0, 0, A2W)
    MOVR(A0, A1)
    SHLI(A0, 2)
    LEA_SYM(A2, SYM(g_gname))
    ADD(A0, A2)
    FILL(A2, 0)
    ST32_OFF(A0, 0, A2W)
    MOVR(RV, A1)
    LEAVE_
    RET
gi_full:
    LEA_SYM(A0, ce_glob)
    MOVI(A1, ce_glob_len)
    CALL(cerr)
    MOVI(RV, 0)
    LEAVE_
    RET
ENDFUNC(global_index)

/* resolve_local(A0 = ad tokeni) -> RV = yuva, bulunamazsa -1 */
FUNC(resolve_local)
    ENTER(3)
    SPILL(0, A0)
    LEA_SYM(A0, SYM(g_nloc))
    LD32(A0W, A0)
    SPILL(1, A0)
rl_loop:
    FILL(A0, 1)
    BZ(A0, rl_no)
    DEC(A0)
    SPILL(1, A0)
    SHLI(A0, 3)
    LEA_SYM(A1, SYM(g_loc))
    ADD(A0, A1)
    LD32(A0W, A0)                   /* saklanan token */
    FILL(A1, 0)
    CALL(tok_eq)
    BZ(RV, rl_loop)
    FILL(RV, 1)
    LEAVE_
    RET
rl_no:
    /* Bulunamadi. Fonksiyon govdesindeysek KUSATAN kapsamdaki
     * yerellere de bak: orada VARSA bu bir KAPANIS ihtiyacidir
     * ve bizde kapanis YOK. Sessizce kuresel sanip 0 okumak
     * yerine derleme hatasi veriyoruz.
     * (Blok icinde "tanim G", fonksiyon icinden G -> 0 geliyordu.) */
    LEA_SYM(A0, SYM(g_encl))
    LD32(A0W, A0)
    BZ(A0, rl_yok)
    SPILL(1, A0)
rl_enc:
    FILL(A0, 1)
    BZ(A0, rl_yok)
    DEC(A0)
    SPILL(1, A0)
    SHLI(A0, 3)
    LEA_SYM(A1, SYM(g_loc))
    ADD(A0, A1)
    LD32(A0W, A0)
    FILL(A1, 0)
    CALL(tok_eq)
    BZ(RV, rl_enc)
    MOVI(RV, -2)                    /* kusatan kapsamda VAR ama erisilemez */
    LEAVE_
    RET
rl_yok:
    MOVI(RV, -1)
    LEAVE_
    RET
ENDFUNC(resolve_local)

/* add_local(A0 = ad tokeni) */
FUNC(add_local)
    ENTER(2)
    SPILL(0, A0)
    LEA_SYM(A0, SYM(g_nloc))
    LD32(A1W, A0)
    CMPI(A1, MAX_LOCALS)
    BHS(al_full)
    MOVR(A2, A1)
    INC(A2)
    ST32_OFF(A0, 0, A2W)
    MOVR(A0, A1)
    SHLI(A0, 3)
    LEA_SYM(A1, SYM(g_loc))
    ADD(A0, A1)
    FILL(A1, 0)
    ST32_OFF(A0, 0, A1W)
    LEA_SYM(A1, SYM(g_depth))
    LD32(A1W, A1)
    ST32_OFF(A0, 4, A1W)
    LEAVE_
    RET
al_full:
    LEA_SYM(A0, ce_full)
    MOVI(A1, ce_full_len)
    CALL(cerr)
    LEAVE_
    RET
ENDFUNC(add_local)

/* begin_scope() / end_scope() */
FUNC(begin_scope)
    ENTER(1)
    LEA_SYM(A0, SYM(g_depth))
    LD32(A1W, A0)
    INC(A1)
    ST32_OFF(A0, 0, A1W)
    LEAVE_
    RET
ENDFUNC(begin_scope)

FUNC(end_scope)
    ENTER(1)
    LEA_SYM(A0, SYM(g_depth))
    LD32(A1W, A0)
    DEC(A1)
    ST32_OFF(A0, 0, A1W)
es_loop:
    LEA_SYM(A0, SYM(g_nloc))
    LD32(A0W, A0)
    BZ(A0, es_done)
    DEC(A0)
    SHLI(A0, 3)
    LEA_SYM(A1, SYM(g_loc))
    ADD(A0, A1)
    LD32_OFF(A0W, A0, 4)            /* saklanan derinlik */
    LEA_SYM(A1, SYM(g_depth))
    LD32(A1W, A1)
    CMPR(A0, A1)
    BLS(es_done)
    LEA_SYM(A0, SYM(g_nloc))
    LD32(A1W, A0)
    DEC(A1)
    ST32_OFF(A0, 0, A1W)
    MOVI(A0, OP_POP)
    MOVI(A1, 0)
    CALL(emit)
    B(es_loop)
es_done:
    LEAVE_
    RET
ENDFUNC(end_scope)

/* =====================================================================
 * compile_expr(A0 = dugum)
 * Slotlar: 0=dugum 1=tur 2,3,4=gecici
 * ===================================================================== */
FUNC(compile_expr)
    ENTER(6)
    SPILL(0, A0)
    BZ(A0, ce_nilpush)
    MOVI(A1, ND_KIND)
    CALL(node_get)
    MOVR(A0, RV)
    SPILL(1, A0)
    CMPI(A0, N_NUMBER);  BEQ(ce_num)
    CMPI(A0, N_STRING);  BEQ(ce_str)
    CMPI(A0, N_IDENT);   BEQ(ce_ident)
    CMPI(A0, N_TRUE);    BEQ(ce_true)
    CMPI(A0, N_FALSE);   BEQ(ce_false)
    CMPI(A0, N_NIL);     BEQ(ce_nilpush)
    CMPI(A0, N_UNARY);   BEQ(ce_unary)
    CMPI(A0, N_BINARY);  BEQ(ce_binary)
    CMPI(A0, N_LOGICAL); BEQ(ce_logical)
    CMPI(A0, N_ASSIGN);  BEQ(ce_assign)
    CMPI(A0, N_CALL);    BEQ(ce_call)
    CMPI(A0, N_ARRAY);   BEQ(ce_array)
    CMPI(A0, N_INDEX);   BEQ(ce_index)
ce_nilpush:
    MOVI(A0, OP_NIL); MOVI(A1, 0); CALL(emit)
    LEAVE_
    RET

ce_true:
    MOVI(A0, OP_TRUE); MOVI(A1, 0); CALL(emit)
    LEAVE_
    RET
ce_false:
    MOVI(A0, OP_FALSE); MOVI(A1, 0); CALL(emit)
    LEAVE_
    RET

ce_num:
    FILL(A0, 0); MOVI(A1, ND_A); CALL(node_get)
    MOVR(A0, RV)
    CALL(tok_to_int)
    MOVR(A1, RV)
    MOVI(A0, T_INT)
    CALL(add_const)
    MOVR(A1, RV)
    MOVI(A0, OP_CONST)
    CALL(emit)
    LEAVE_
    RET

ce_str:
    FILL(A0, 0); MOVI(A1, ND_A); CALL(node_get)
    MOVR(A0, RV)
    CALL(str_from_tok)              /* derleme aninda yigin nesnesi */
    MOVR(A1, RV)
    MOVI(A0, T_OBJ)
    CALL(add_const)
    MOVR(A1, RV)
    MOVI(A0, OP_CONST)
    CALL(emit)
    LEAVE_
    RET

ce_ident:
    FILL(A0, 0); MOVI(A1, ND_A); CALL(node_get)
    SPILL(2, RV)
    MOVR(A0, RV)
    CALL(resolve_local)
    SPILL(3, RV)
    MOVI(A0, -2)
    FILL(A1, 3)
    CMPR(A1, A0)
    BEQ(ce_id_encl)
    MOVI(A0, -1)
    FILL(A1, 3)
    CMPR(A1, A0)
    BEQ(ce_id_glob)
    FILL(A1, 3)
    MOVI(A0, OP_GETLOCAL)
    CALL(emit)
    LEAVE_
    RET
ce_id_encl:
    LEA_SYM(A0, ce_encl)
    MOVI(A1, ce_encl_len)
    CALL(cerr)
    MOVI(A0, OP_NIL); MOVI(A1, 0); CALL(emit)
    LEAVE_
    RET

ce_id_glob:
    /* Once VAR OLAN kuresele bak: kullanici tanimi gomulu adi
     * GOLGELER. Aksi halde "tanim buyuk = 5" sessizce gomulu
     * buyuk()'e cozuluyordu. */
    FILL(A0, 2)
    CALL(global_find)
    MOVI(A1, -1)
    CMPR(RV, A1)
    BEQ(ce_id_nat)
    MOVR(A1, RV)
    MOVI(A0, OP_GETGLOBAL)
    CALL(emit)
    LEAVE_
    RET
ce_id_nat:
    FILL(A0, 2)
    CALL(native_index)              /* govde fonksiyon mu? */
    SPILL(4, RV)
    MOVI(A0, -1)
    FILL(A1, 4)
    CMPR(A1, A0)
    BEQ(ce_id_glob2)
    MOVI(A0, T_NAT)
    FILL(A1, 4)
    CALL(add_const)
    MOVR(A1, RV)
    MOVI(A0, OP_CONST)
    CALL(emit)
    LEAVE_
    RET
ce_id_glob2:
    FILL(A0, 2)
    CALL(global_index)
    MOVR(A1, RV)
    MOVI(A0, OP_GETGLOBAL)
    CALL(emit)
    LEAVE_
    RET

ce_unary:
    FILL(A0, 0); MOVI(A1, ND_A); CALL(node_get)
    MOVR(A0, RV)
    CALL(compile_expr)
    FILL(A0, 0); MOVI(A1, ND_B); CALL(node_get)
    MOVR(A0, RV)
    MOVI(A1, TOK_OFF_TYPE)
    CALL(tok_field)
    MOVR(A0, RV)
    CMPI(A0, TOK_MINUS)
    BEQ(ce_un_neg)
    CMPI(A0, TOK_TILDE)
    BEQ(ce_un_bnot)
    MOVI(A0, OP_NOT); B(ce_un_emit)
ce_un_bnot:
    MOVI(A0, OP_BNOT); B(ce_un_emit)
ce_un_neg:
    MOVI(A0, OP_NEG)
ce_un_emit:
    MOVI(A1, 0)
    CALL(emit)
    LEAVE_
    RET

ce_binary:
    FILL(A0, 0); MOVI(A1, ND_A); CALL(node_get)
    MOVR(A0, RV); CALL(compile_expr)
    FILL(A0, 0); MOVI(A1, ND_B); CALL(node_get)
    MOVR(A0, RV); CALL(compile_expr)
    FILL(A0, 0); MOVI(A1, ND_C); CALL(node_get)
    MOVR(A0, RV)
    MOVI(A1, TOK_OFF_TYPE)
    CALL(tok_field)
    MOVR(A0, RV)
    /* Bilesik atamada ayristirici BINARY dugumunun operator alanina
     * '+=' tokenini birakiyor; aritmetik anlami '+' ile ayni. */
    CMPI(A0, TOK_PLUSEQ);  BEQ(cb_add)
    CMPI(A0, TOK_MINUSEQ); BEQ(cb_sub)
    CMPI(A0, TOK_STAREQ);  BEQ(cb_mul)
    CMPI(A0, TOK_SLASHEQ); BEQ(cb_div)
    CMPI(A0, TOK_PCTEQ);   BEQ(cb_mod)
    CMPI(A0, TOK_AMP);     BEQ(cb_band)
    CMPI(A0, TOK_PIPE);    BEQ(cb_bor)
    CMPI(A0, TOK_CARET);   BEQ(cb_bxor)
    CMPI(A0, TOK_SHL);     BEQ(cb_shl)
    CMPI(A0, TOK_SHR);     BEQ(cb_shr)
    CMPI(A0, TOK_PLUS);    BEQ(cb_add)
    CMPI(A0, TOK_MINUS);   BEQ(cb_sub)
    CMPI(A0, TOK_STAR);    BEQ(cb_mul)
    CMPI(A0, TOK_SLASH);   BEQ(cb_div)
    CMPI(A0, TOK_PERCENT); BEQ(cb_mod)
    CMPI(A0, TOK_EQ);      BEQ(cb_eq)
    CMPI(A0, TOK_NE);      BEQ(cb_ne)
    CMPI(A0, TOK_LT);      BEQ(cb_lt)
    CMPI(A0, TOK_LE);      BEQ(cb_le)
    CMPI(A0, TOK_GT);      BEQ(cb_gt)
    MOVI(A0, OP_GE);  B(cb_emit)
cb_band: MOVI(A0, OP_BAND); B(cb_emit)
cb_bor:  MOVI(A0, OP_BOR);  B(cb_emit)
cb_bxor: MOVI(A0, OP_BXOR); B(cb_emit)
cb_shl:  MOVI(A0, OP_SHL);  B(cb_emit)
cb_shr:  MOVI(A0, OP_SHR);  B(cb_emit)
cb_add: MOVI(A0, OP_ADD); B(cb_emit)
cb_sub: MOVI(A0, OP_SUB); B(cb_emit)
cb_mul: MOVI(A0, OP_MUL); B(cb_emit)
cb_div: MOVI(A0, OP_DIV); B(cb_emit)
cb_mod: MOVI(A0, OP_MOD); B(cb_emit)
cb_eq:  MOVI(A0, OP_EQ);  B(cb_emit)
cb_ne:  MOVI(A0, OP_NE);  B(cb_emit)
cb_lt:  MOVI(A0, OP_LT);  B(cb_emit)
cb_le:  MOVI(A0, OP_LE);  B(cb_emit)
cb_gt:  MOVI(A0, OP_GT)
cb_emit:
    MOVI(A1, 0)
    CALL(emit)
    LEAVE_
    RET

/* ve/veya: kisa devre. Deger yigininda birakilarak atlanir. */
ce_logical:
    FILL(A0, 0); MOVI(A1, ND_A); CALL(node_get)
    MOVR(A0, RV); CALL(compile_expr)
    FILL(A0, 0); MOVI(A1, ND_C); CALL(node_get)
    MOVR(A0, RV)
    MOVI(A1, TOK_OFF_TYPE)
    CALL(tok_field)
    MOVR(A0, RV)
    CMPI(A0, TOK_AND)
    BEQ(cl_and)
    MOVI(A0, OP_JNZP); B(cl_jump)
cl_and:
    MOVI(A0, OP_JZP)
cl_jump:
    MOVI(A1, 0)
    CALL(emit)
    SPILL(2, RV)                    /* yamalanacak atlama */
    MOVI(A0, OP_POP); MOVI(A1, 0); CALL(emit)
    FILL(A0, 0); MOVI(A1, ND_B); CALL(node_get)
    MOVR(A0, RV); CALL(compile_expr)
    CALL(here)
    MOVR(A1, RV)
    FILL(A0, 2)
    CALL(patch)
    LEAVE_
    RET

ce_assign:
    FILL(A0, 0); MOVI(A1, ND_A); CALL(node_get)
    SPILL(2, RV)                    /* hedef dugum */
    MOVR(A0, RV)
    MOVI(A1, ND_KIND)
    CALL(node_get)
    MOVR(A0, RV)
    CMPI(A0, N_IDENT)
    BEQ(ca_ok)
    CMPI(A0, N_INDEX)
    BEQ(ca_index)
    LEA_SYM(A0, ce_target)
    MOVI(A1, ce_target_len)
    CALL(cerr)
    LEAVE_
    RET
ca_ok:
    FILL(A0, 0); MOVI(A1, ND_B); CALL(node_get)
    MOVR(A0, RV); CALL(compile_expr)
    FILL(A0, 2); MOVI(A1, ND_A); CALL(node_get)
    SPILL(3, RV)
    MOVR(A0, RV)
    CALL(resolve_local)
    SPILL(4, RV)
    MOVI(A0, -1)
    FILL(A1, 4)
    CMPR(A1, A0)
    BEQ(ca_glob)
    FILL(A1, 4)
    MOVI(A0, OP_SETLOCAL)
    CALL(emit)
    LEAVE_
    RET
ca_glob:
    FILL(A0, 3)
    CALL(global_index)
    MOVR(A1, RV)
    MOVI(A0, OP_SETGLOBAL)
    CALL(emit)
    LEAVE_
    RET

ca_index:
    FILL(A0, 2); MOVI(A1, ND_A); CALL(node_get)
    MOVR(A0, RV); CALL(compile_expr)        /* nesne */
    FILL(A0, 2); MOVI(A1, ND_B); CALL(node_get)
    MOVR(A0, RV); CALL(compile_expr)        /* indeks */
    FILL(A0, 0); MOVI(A1, ND_B); CALL(node_get)
    MOVR(A0, RV); CALL(compile_expr)        /* deger  */
    MOVI(A0, OP_SETIDX); MOVI(A1, 0); CALL(emit)
    LEAVE_
    RET

ce_array:
    FILL(A0, 0); MOVI(A1, ND_A); CALL(node_get)
    SPILL(2, RV)
    MOVI(A0, 0)
    SPILL(3, A0)
cea_loop:
    FILL(A0, 2)
    BZ(A0, cea_done)
    CALL(compile_expr)
    FILL(A0, 3); INC(A0); SPILL(3, A0)
    FILL(A0, 2); MOVI(A1, ND_NEXT); CALL(node_get)
    SPILL(2, RV)
    B(cea_loop)
cea_done:
    FILL(A1, 3)
    MOVI(A0, OP_ARRAY)
    CALL(emit)
    LEAVE_
    RET

ce_index:
    FILL(A0, 0); MOVI(A1, ND_A); CALL(node_get)
    MOVR(A0, RV); CALL(compile_expr)
    FILL(A0, 0); MOVI(A1, ND_B); CALL(node_get)
    MOVR(A0, RV); CALL(compile_expr)
    MOVI(A0, OP_INDEX); MOVI(A1, 0); CALL(emit)
    LEAVE_
    RET

ce_call:
    FILL(A0, 0); MOVI(A1, ND_A); CALL(node_get)
    MOVR(A0, RV); CALL(compile_expr)
    FILL(A0, 0); MOVI(A1, ND_B); CALL(node_get)
    SPILL(2, RV)
    MOVI(A0, 0)
    SPILL(3, A0)                    /* arguman sayaci */
cc_args:
    FILL(A0, 2)
    BZ(A0, cc_done)
    FILL(A0, 2)
    CALL(compile_expr)
    FILL(A0, 3); INC(A0); SPILL(3, A0)
    FILL(A0, 2); MOVI(A1, ND_NEXT); CALL(node_get)
    SPILL(2, RV)
    B(cc_args)
cc_done:
    FILL(A1, 3)
    MOVI(A0, OP_CALL)
    CALL(emit)
    LEAVE_
    RET
ENDFUNC(compile_expr)

/* =====================================================================
 * compile_stmt(A0 = dugum)  - kardesleri de dolasir
 * Slotlar: 0=dugum 1=tur 2..5=gecici
 * ===================================================================== */
FUNC(compile_stmt)
    ENTER(7)
    SPILL(0, A0)
cs_sib:
    FILL(A0, 0)
    BZ(A0, cs_end)
    MOVI(A1, ND_KIND)
    CALL(node_get)
    MOVR(A0, RV)
    SPILL(1, A0)
    CMPI(A0, N_PROGRAM);  BEQ(cs_prog)
    CMPI(A0, N_BLOCK);    BEQ(cs_block)
    CMPI(A0, N_LET);      BEQ(cs_let)
    CMPI(A0, N_CONST);    BEQ(cs_let)
    CMPI(A0, N_IF);       BEQ(cs_if)
    CMPI(A0, N_WHILE);    BEQ(cs_while)
    CMPI(A0, N_FOR);      BEQ(cs_for)
    CMPI(A0, N_PRINT);    BEQ(cs_print)
    CMPI(A0, N_EXPRSTMT); BEQ(cs_expr)
    CMPI(A0, N_RETURN);   BEQ(cs_ret)
    CMPI(A0, N_BREAK);    BEQ(cs_break)
    CMPI(A0, N_CONTINUE); BEQ(cs_cont)
    CMPI(A0, N_FN);       BEQ(cs_fn)
    B(cs_next)

cs_prog:
    FILL(A0, 0); MOVI(A1, ND_A); CALL(node_get)
    MOVR(A0, RV); CALL(compile_stmt)
    B(cs_next)

cs_block:
    CALL(begin_scope)
    FILL(A0, 0); MOVI(A1, ND_A); CALL(node_get)
    MOVR(A0, RV); CALL(compile_stmt)
    CALL(end_scope)
    B(cs_next)

cs_let:
    FILL(A0, 0); MOVI(A1, ND_B); CALL(node_get)
    MOVR(A0, RV)
    CALL(compile_expr)              /* dugum 0 ise NIL basar */
    LEA_SYM(A0, SYM(g_depth))
    LD32(A0W, A0)
    BNZ(A0, cs_let_local)
    FILL(A0, 0); MOVI(A1, ND_A); CALL(node_get)
    MOVR(A0, RV)
    CALL(global_index)
    MOVR(A1, RV)
    MOVI(A0, OP_DEFGLOBAL)
    CALL(emit)
    B(cs_next)
cs_let_local:
    FILL(A0, 0); MOVI(A1, ND_A); CALL(node_get)
    MOVR(A0, RV)
    CALL(add_local)                 /* deger yiginda kalir = yuva */
    B(cs_next)

cs_if:
    FILL(A0, 0); MOVI(A1, ND_A); CALL(node_get)
    MOVR(A0, RV); CALL(compile_expr)
    MOVI(A0, OP_JZ); MOVI(A1, 0); CALL(emit)
    SPILL(2, RV)                    /* yanlis dali atlamasi */
    FILL(A0, 0); MOVI(A1, ND_B); CALL(node_get)
    MOVR(A0, RV); CALL(compile_stmt_one)
    MOVI(A0, OP_JMP); MOVI(A1, 0); CALL(emit)
    SPILL(3, RV)                    /* yoksa dalini atlama */
    CALL(here)
    MOVR(A1, RV)
    FILL(A0, 2)
    CALL(patch)
    FILL(A0, 0); MOVI(A1, ND_C); CALL(node_get)
    MOVR(A0, RV); CALL(compile_stmt_one)
    CALL(here)
    MOVR(A1, RV)
    FILL(A0, 3)
    CALL(patch)
    B(cs_next)

#if OPT_ROTATE
/* --- iken: DONGU ROTASYONU ---
 * Duz derleme her turda bir fazla JMP yurutur:
 *     basla: kosul ; JZ cikis ; govde ; JMP basla
 * Rotasyonlu hali kosulu dibe alir, geri kenar dogrudan dallanir:
 *     JMP kosul ; govde: govde ; kosul: kosul ; JNZ govde
 * Giriste bir kerelik JMP maliyeti var, HER TURDA bir dagitim kazanci.
 */
cs_while:
    LEA_SYM(A0, SYM(g_nloop))
    LD32(A0W, A0)
    CMPI(A0, MAX_LOOPS)
    BLO(cs_wh_ok)
    LEA_SYM(A0, ce_loop)
    MOVI(A1, ce_loop_len)
    CALL(cerr)
    B(cs_next)
cs_wh_ok:
    LEA_SYM(A0, SYM(g_nloop))
    LD32(A1W, A0)
    MOVR(A2, A1)
    INC(A2)
    ST32_OFF(A0, 0, A2W)
    SPILL(4, A1)                    /* dongu yuvasi */
    /* break tabani */
    LEA_SYM(A0, SYM(g_nbrk))
    LD32(A2W, A0)
    FILL(A0, 4)
    SHLI(A0, 2)
    LEA_SYM(A1, SYM(g_loopbb))
    ADD(A0, A1)
    ST32_OFF(A0, 0, A2W)
    /* devam tabani */
    LEA_SYM(A0, SYM(g_ncont))
    LD32(A2W, A0)
    FILL(A0, 4)
    SHLI(A0, 2)
    LEA_SYM(A1, SYM(g_loopcb))
    ADD(A0, A1)
    ST32_OFF(A0, 0, A2W)

    MOVI(A0, OP_JMP); MOVI(A1, 0); CALL(emit)
    SPILL(2, RV)                    /* kosula atlama (yamalanacak) */
    CALL(here)
    SPILL(3, RV)                    /* govde basi */
    FILL(A0, 0); MOVI(A1, ND_B); CALL(node_get)
    MOVR(A0, RV); CALL(compile_stmt_one)
    CALL(here)
    SPILL(5, RV)                    /* kosul yeri = devam hedefi */
    MOVR(A1, RV)
    FILL(A0, 2)
    CALL(patch)
    FILL(A0, 0); MOVI(A1, ND_A); CALL(node_get)
    MOVR(A0, RV); CALL(compile_expr)
    MOVI(A0, OP_JNZ); FILL(A1, 3); CALL(emit)
    CALL(patch_breaks)
    FILL(A0, 5)
    CALL(patch_conts)
    LEA_SYM(A0, SYM(g_nloop))
    LD32(A1W, A0)
    DEC(A1)
    ST32_OFF(A0, 0, A1W)
    B(cs_next)

#else
/* --- iken: DUZ (rotasyonsuz) derleme ---
 *     basla: kosul ; JZ cikis ; govde ; JMP basla
 * Tur basina iki dallanma. Karsilastirma icin OPT_ROTATE=0 ile secilir.
 */
cs_while:
    LEA_SYM(A0, SYM(g_nloop))
    LD32(A0W, A0)
    CMPI(A0, MAX_LOOPS)
    BLO(cs_wh_ok)
    LEA_SYM(A0, ce_loop)
    MOVI(A1, ce_loop_len)
    CALL(cerr)
    B(cs_next)
cs_wh_ok:
    LEA_SYM(A0, SYM(g_nloop))
    LD32(A1W, A0)
    MOVR(A2, A1)
    INC(A2)
    ST32_OFF(A0, 0, A2W)
    SPILL(4, A1)
    LEA_SYM(A0, SYM(g_nbrk))
    LD32(A2W, A0)
    FILL(A0, 4); SHLI(A0, 2)
    LEA_SYM(A1, SYM(g_loopbb)); ADD(A0, A1)
    ST32_OFF(A0, 0, A2W)
    LEA_SYM(A0, SYM(g_ncont))
    LD32(A2W, A0)
    FILL(A0, 4); SHLI(A0, 2)
    LEA_SYM(A1, SYM(g_loopcb)); ADD(A0, A1)
    ST32_OFF(A0, 0, A2W)

    CALL(here)
    SPILL(5, RV)                    /* dongu basi = kosul */
    FILL(A0, 0); MOVI(A1, ND_A); CALL(node_get)
    MOVR(A0, RV); CALL(compile_expr)
    MOVI(A0, OP_JZ); MOVI(A1, 0); CALL(emit)
    SPILL(3, RV)                    /* cikis atlamasi */
    FILL(A0, 0); MOVI(A1, ND_B); CALL(node_get)
    MOVR(A0, RV); CALL(compile_stmt_one)
    MOVI(A0, OP_JMP); FILL(A1, 5); CALL(emit)
    CALL(here)
    MOVR(A1, RV)
    FILL(A0, 3)
    CALL(patch)
    CALL(patch_breaks)
    FILL(A0, 5)
    CALL(patch_conts)
    LEA_SYM(A0, SYM(g_nloop))
    LD32(A1W, A0)
    DEC(A1)
    ST32_OFF(A0, 0, A1W)
    B(cs_next)

#endif

/* --- her (baslangic; kosul; adim) ---
 * A = kosul, B = govde, C = adim.
 *
 *     JMP kosul
 * govde: <govde>
 * adim:  <adim>            <- "devam" BURAYA gider, kosula degil.
 * kosul: <kosul> ; JNZ govde
 * cikis:                   <- "kir" buraya
 *
 * "devam"in adima gitmesi sart: yoksa dongu degiskeni artmaz ve
 * sonsuz donguye girer. iken (while) icin devam kosula gidiyordu;
 * ikisi ayni kod olamaz.
 */
cs_for:
    LEA_SYM(A0, SYM(g_nloop))
    LD32(A0W, A0)
    CMPI(A0, MAX_LOOPS)
    BLO(cs_for_ok)
    LEA_SYM(A0, ce_loop)
    MOVI(A1, ce_loop_len)
    CALL(cerr)
    B(cs_next)
cs_for_ok:
    LEA_SYM(A0, SYM(g_nloop))
    LD32(A1W, A0)
    MOVR(A2, A1)
    INC(A2)
    ST32_OFF(A0, 0, A2W)
    SPILL(4, A1)
    LEA_SYM(A0, SYM(g_nbrk))
    LD32(A2W, A0)
    FILL(A0, 4); SHLI(A0, 2)
    LEA_SYM(A1, SYM(g_loopbb)); ADD(A0, A1)
    ST32_OFF(A0, 0, A2W)
    LEA_SYM(A0, SYM(g_ncont))
    LD32(A2W, A0)
    FILL(A0, 4); SHLI(A0, 2)
    LEA_SYM(A1, SYM(g_loopcb)); ADD(A0, A1)
    ST32_OFF(A0, 0, A2W)

    MOVI(A0, OP_JMP); MOVI(A1, 0); CALL(emit)
    SPILL(2, RV)                    /* kosula atlama */
    CALL(here)
    SPILL(3, RV)                    /* govde basi */
    FILL(A0, 0); MOVI(A1, ND_B); CALL(node_get)
    MOVR(A0, RV); CALL(compile_stmt_one)
    /* --- adim: devam hedefi --- */
    CALL(here)
    SPILL(5, RV)
    FILL(A0, 0); MOVI(A1, ND_C); CALL(node_get)
    BZ(RV, cf_nostep)
    MOVR(A0, RV); CALL(compile_expr)
    MOVI(A0, OP_POP); MOVI(A1, 0); CALL(emit)
cf_nostep:
    /* --- kosul --- */
    CALL(here)
    MOVR(A1, RV)
    FILL(A0, 2)
    CALL(patch)
    FILL(A0, 0); MOVI(A1, ND_A); CALL(node_get)
    MOVR(A0, RV); CALL(compile_expr)
    MOVI(A0, OP_JNZ); FILL(A1, 3); CALL(emit)
    CALL(patch_breaks)
    FILL(A0, 5)
    CALL(patch_conts)
    LEA_SYM(A0, SYM(g_nloop))
    LD32(A1W, A0)
    DEC(A1)
    ST32_OFF(A0, 0, A1W)
    B(cs_next)

cs_print:
    FILL(A0, 0); MOVI(A1, ND_A); CALL(node_get)
    MOVR(A0, RV); CALL(compile_expr)
    MOVI(A0, OP_PRINT); MOVI(A1, 0); CALL(emit)
    B(cs_next)

cs_expr:
    FILL(A0, 0); MOVI(A1, ND_A); CALL(node_get)
    MOVR(A0, RV); CALL(compile_expr)
    MOVI(A0, OP_POP); MOVI(A1, 0); CALL(emit)
    B(cs_next)

cs_ret:
    FILL(A0, 0); MOVI(A1, ND_A); CALL(node_get)
    MOVR(A0, RV); CALL(compile_expr)
    MOVI(A0, OP_RET); MOVI(A1, 0); CALL(emit)
    B(cs_next)

cs_break:
    LEA_SYM(A0, SYM(g_nbrk))
    LD32(A0W, A0)
    CMPI(A0, MAX_BREAKS)
    BHS(cs_brk_full)
    MOVI(A0, OP_JMP); MOVI(A1, 0); CALL(emit)
    SPILL(2, RV)
    LEA_SYM(A0, SYM(g_nbrk))
    LD32(A1W, A0)
    MOVR(A2, A1)
    INC(A2)
    ST32_OFF(A0, 0, A2W)
    MOVR(A0, A1)
    SHLI(A0, 2)
    LEA_SYM(A1, SYM(g_brk))
    ADD(A0, A1)
    FILL(A1, 2)
    ST32_OFF(A0, 0, A1W)
    B(cs_next)

cs_brk_full:
    LEA_SYM(A0, ce_brk)
    MOVI(A1, ce_brk_len)
    CALL(cerr)
    B(cs_next)

cs_cont:
    LEA_SYM(A0, SYM(g_ncont))
    LD32(A0W, A0)
    CMPI(A0, MAX_CONTS)
    BHS(cs_brk_full)
    MOVI(A0, OP_JMP); MOVI(A1, 0); CALL(emit)
    SPILL(2, RV)
    LEA_SYM(A0, SYM(g_ncont))
    LD32(A1W, A0)
    MOVR(A2, A1)
    INC(A2)
    ST32_OFF(A0, 0, A2W)
    MOVR(A0, A1)
    SHLI(A0, 2)
    LEA_SYM(A1, SYM(g_cont))
    ADD(A0, A1)
    FILL(A1, 2)
    ST32_OFF(A0, 0, A1W)
    B(cs_next)

/* fonk ad(p...) { ... }  - govde JMP ile atlanir, sonra sabit + DEFGLOBAL */
cs_fn:
    MOVI(A0, OP_JMP); MOVI(A1, 0); CALL(emit)
    SPILL(2, RV)                    /* govdeyi atlama */
    CALL(here)
    SPILL(3, RV)                    /* giris noktasi */
    LEA_SYM(A0, SYM(g_nloc))
    LD32(A0W, A0)
    SPILL(5, A0)                    /* eski yerel sayisi */
    /* KUSATAN yerel sayisini kaydet: fonksiyon govdesinde bu
     * adlara erisim KAPANIS gerektirir, bizde yok. Sessizce
     * kuresel sanip 0 okumak yerine DERLEME HATASI vermeliyiz.
     * (Blok icinde tanimli G'yi fonksiyon icinden okuyunca 0
     * geliyordu - fare imleci ornegi bu yuzden calismadi.) */
    LEA_SYM(A1, SYM(g_encl))
    ST32_OFF(A1, 0, A0W)
    MOVI(A0, 0)
    LEA_SYM(A1, SYM(g_nloc))
    ST32_OFF(A1, 0, A0W)
    CALL(begin_scope)
    /* parametreler */
    MOVI(A0, 0)
    SPILL(4, A0)
    FILL(A0, 0); MOVI(A1, ND_B); CALL(node_get)
    SPILL(6, RV)
cs_fn_p:
    FILL(A0, 6)
    BZ(A0, cs_fn_pdone)
    MOVI(A1, ND_A)
    CALL(node_get)
    MOVR(A0, RV)
    CALL(add_local)
    FILL(A0, 4); INC(A0); SPILL(4, A0)
    FILL(A0, 6); MOVI(A1, ND_NEXT); CALL(node_get)
    SPILL(6, RV)
    B(cs_fn_p)
cs_fn_pdone:
    FILL(A0, 0); MOVI(A1, ND_C); CALL(node_get)
    MOVR(A0, RV); CALL(compile_stmt_one)
    MOVI(A0, OP_NIL); MOVI(A1, 0); CALL(emit)
    MOVI(A0, OP_RET); MOVI(A1, 0); CALL(emit)
    CALL(end_scope_quiet)
    FILL(A0, 5)
    LEA_SYM(A1, SYM(g_nloc))
    ST32_OFF(A1, 0, A0W)
    MOVI(A0, 0)
    LEA_SYM(A1, SYM(g_encl))
    ST32_OFF(A1, 0, A0W)
    CALL(here)
    MOVR(A1, RV)
    FILL(A0, 2)
    CALL(patch)
    /* fonksiyon tablosu girdisi */
    LEA_SYM(A0, SYM(g_nfn))
    LD32(A1W, A0)
    CMPI(A1, MAX_FRAMES)
    BLO(cs_fn_ok)
    LEA_SYM(A0, ce_fn)
    MOVI(A1, ce_fn_len)
    CALL(cerr)
    B(cs_next)
cs_fn_ok:
    LEA_SYM(A0, SYM(g_nfn))
    LD32(A1W, A0)
    MOVR(A2, A1)
    INC(A2)
    ST32_OFF(A0, 0, A2W)
    SPILL(6, A1)                    /* fonksiyon indeksi */
    MOVR(A0, A1)
    SHLI(A0, 3)
    LEA_SYM(A1, SYM(g_fns))
    ADD(A0, A1)
    FILL(A1, 3)
    ST32_OFF(A0, 0, A1W)            /* giris */
    FILL(A1, 4)
    ST32_OFF(A0, 4, A1W)            /* arite */
    MOVI(A0, T_FN)
    FILL(A1, 6)
    CALL(add_const)
    MOVR(A1, RV)
    MOVI(A0, OP_CONST)
    CALL(emit)
    FILL(A0, 0); MOVI(A1, ND_A); CALL(node_get)
    MOVR(A0, RV)
    CALL(global_index)
    MOVR(A1, RV)
    MOVI(A0, OP_DEFGLOBAL)
    CALL(emit)
    B(cs_next)

cs_next:
    FILL(A0, 0)
    MOVI(A1, ND_NEXT)
    CALL(node_get)
    MOVR(A0, RV)
    SPILL(0, A0)
    B(cs_sib)
cs_end:
    LEAVE_
    RET
ENDFUNC(compile_stmt)

/* compile_stmt_one(A0 = dugum) - kardesleri IZLEMEZ (dal govdeleri icin) */
FUNC(compile_stmt_one)
    ENTER(2)
    BZ(A0, cso_end)
    SPILL(0, A0)
    MOVI(A1, ND_NEXT)
    CALL(node_get)
    SPILL(1, RV)                    /* kardesi gecici olarak kopar */
    FILL(A0, 0); MOVI(A1, ND_NEXT); MOVI(A2, 0); CALL(node_set)
    FILL(A0, 0)
    CALL(compile_stmt)
    FILL(A0, 0); MOVI(A1, ND_NEXT); FILL(A2, 1); CALL(node_set)
cso_end:
    LEAVE_
    RET
ENDFUNC(compile_stmt_one)

/* end_scope_quiet() - POP uretmez (RET zaten cerceveyi atar) */
FUNC(end_scope_quiet)
    ENTER(1)
    LEA_SYM(A0, SYM(g_depth))
    LD32(A1W, A0)
    DEC(A1)
    ST32_OFF(A0, 0, A1W)
    LEAVE_
    RET
ENDFUNC(end_scope_quiet)

/* patch_breaks() - gecerli dongunun break atlamalarini buraya yamalar */
FUNC(patch_breaks)
    ENTER(3)
    LEA_SYM(A0, SYM(g_nloop))
    LD32(A0W, A0)
    DEC(A0)
    SHLI(A0, 2)
    LEA_SYM(A1, SYM(g_loopbb))
    ADD(A0, A1)
    LD32(A0W, A0)
    SPILL(0, A0)                    /* taban */
    CALL(here)
    SPILL(1, RV)
pb_loop:
    LEA_SYM(A0, SYM(g_nbrk))
    LD32(A0W, A0)
    FILL(A1, 0)
    CMPR(A0, A1)
    BLS(pb_done)
    DEC(A0)
    LEA_SYM(A1, SYM(g_nbrk))
    ST32_OFF(A1, 0, A0W)
    SHLI(A0, 2)
    LEA_SYM(A1, SYM(g_brk))
    ADD(A0, A1)
    LD32(A0W, A0)
    FILL(A1, 1)
    CALL(patch)
    B(pb_loop)
pb_done:
    LEAVE_
    RET
ENDFUNC(patch_breaks)

/* patch_conts(A0 = hedef komut indeksi)
 * "devam" atlamalari dongu KOSULUNA gider. Rotasyonlu duzende kosul
 * govdeden SONRA geldigi icin hedef disaridan verilmek zorunda -
 * patch_breaks gibi here() kullanilamaz.
 */
FUNC(patch_conts)
    ENTER(3)
    SPILL(2, A0)
    LEA_SYM(A0, SYM(g_nloop))
    LD32(A0W, A0)
    DEC(A0)
    SHLI(A0, 2)
    LEA_SYM(A1, SYM(g_loopcb))
    ADD(A0, A1)
    LD32(A0W, A0)
    SPILL(0, A0)
pc_loop:
    LEA_SYM(A0, SYM(g_ncont))
    LD32(A0W, A0)
    FILL(A1, 0)
    CMPR(A0, A1)
    BLS(pc_done)
    DEC(A0)
    LEA_SYM(A1, SYM(g_ncont))
    ST32_OFF(A1, 0, A0W)
    SHLI(A0, 2)
    LEA_SYM(A1, SYM(g_cont))
    ADD(A0, A1)
    LD32(A0W, A0)
    FILL(A1, 2)
    CALL(patch)
    B(pc_loop)
pc_done:
    LEAVE_
    RET
ENDFUNC(patch_conts)

/* compile(A0 = kok dugum, A1 = kod tamponu, A2 = sabit tamponu) */
FUNC(compile)
    ENTER(2)
    SPILL(0, A0)
    LEA_SYM(A0, SYM(g_code))
    ST(A0, A1)
    LEA_SYM(A0, SYM(g_consts))
    ST(A0, A2)
    MOVI(A0, 0)
    LEA_SYM(A1, SYM(g_ncode));  ST32_OFF(A1, 0, A0W)
    LEA_SYM(A1, SYM(g_nconst)); ST32_OFF(A1, 0, A0W)
    LEA_SYM(A1, SYM(g_cerr));   ST32_OFF(A1, 0, A0W)
    LEA_SYM(A1, SYM(g_depth));  ST32_OFF(A1, 0, A0W)
    LEA_SYM(A1, SYM(g_nloc));   ST32_OFF(A1, 0, A0W)
    LEA_SYM(A1, SYM(g_nglob));  ST32_OFF(A1, 0, A0W)
    LEA_SYM(A1, SYM(g_nfn));    ST32_OFF(A1, 0, A0W)
    LEA_SYM(A1, SYM(g_nintern)); ST32_OFF(A1, 0, A0W)
    LEA_SYM(A1, SYM(g_nloop));  ST32_OFF(A1, 0, A0W)
    LEA_SYM(A1, SYM(g_nbrk));   ST32_OFF(A1, 0, A0W)
    LEA_SYM(A1, SYM(g_ncont));  ST32_OFF(A1, 0, A0W)
    FILL(A0, 0)
    CALL(compile_stmt)
    MOVI(A0, OP_HALT)
    MOVI(A1, 0)
    CALL(emit)
#if OPT_PEEPHOLE
    /* Gozetleme deligini SABIT NOKTAYA kadar dondur: bir turda olusan
     * birlesik komut bir sonraki turda tekrar birlesebiliyor.
     * ornek: CONST+ADD -> ADDK, sonra ADDK+SETGLOBAL_P -> ADDK_SETG,
     *        sonra GETGLOBAL+ADDK_SETG -> INCGLOBAL   (3 komut -> 1) */
    MOVI(A0, 0)
    LEA_SYM(A1, SYM(g_phase))
    ST32_OFF(A1, 0, A0W)
    MOVI(A0, 8)
    SPILL(1, A0)
cp_round:
    CALL(peephole)
    LEA_SYM(A0, SYM(g_nfuse))
    LD32(A0W, A0)
    BZ(A0, cp_settled)
    FILL(A0, 1)
    DEC(A0)
    SPILL(1, A0)
    BNZ(A0, cp_round)
cp_settled:
#if OPT_SUPER
    /* Asama 1: acgozlu kurallari ac, tekrar sabit noktaya kadar dondur */
    MOVI(A0, 1)
    LEA_SYM(A1, SYM(g_phase))
    ST32_OFF(A1, 0, A0W)
    MOVI(A0, 4)
    SPILL(1, A0)
cp_round2:
    CALL(peephole)
    LEA_SYM(A0, SYM(g_nfuse))
    LD32(A0W, A0)
    BZ(A0, cp_done)
    FILL(A0, 1)
    DEC(A0)
    SPILL(1, A0)
    BNZ(A0, cp_round2)
#endif

cp_done:
#endif

#if defined(TEST_CORRUPT) && TEST_CORRUPT
    /* KASITLI BOZMA: dogrulama pass'inin gercekten atesledigini kanitlar.
     * Hic atesmeyen bir denetleyici test edilmemis demektir. */
    LEA_SYM(A0, SYM(g_nfn))
    LD32(A0W, A0)
    BZ(A0, tc_skip)
    LEA_SYM(A0, SYM(g_fns))
    MOVI(A1, 99999)
    ST32_OFF(A0, 0, A1W)
tc_skip:
#endif
#if !defined(OPT_VERIFY) || OPT_VERIFY
    CALL(verify_meta)
#endif
    LEAVE_
    RET
ENDFUNC(compile)
