/* parser.S - Pratt (oncelik tirmanmali) ayristirici
 *
 * Oncelikler prec_table'da, dugum sekilleri kind_kids'te: motor yine
 * yalnizca tablo yurutur. Yeni bir operator eklemek icin gen_tables.py'de
 * tek satir yeter, buradaki koda dokunulmaz.
 *
 * Dugumlere indeksle erisilir (isaretciyle degil), boylece AST 32 ve
 * 64 bitte birebir ayni yerlesimi kullanir.
 *
 * Parser VP/VS/VF kullanmaz - tum durum kuresel degiskenlerde ve cerceve
 * slotlarinda. Ozyinelemeli oldugu icin bu, register kurtarma sorununu
 * tumden ortadan kaldiriyor (ozellikle i386'da kritik).
 */
#include "../abi.inc"
#include "../tables/tokens.inc"
#include "../tables/ast.inc"

    .bss
    .p2align 3
    .globl SYM(g_toks)
SYM(g_toks):   .space 8        /* token dizisi tabani */
    .globl SYM(g_nodes)
SYM(g_nodes):  .space 8        /* dugum arenasi tabani */
    .globl SYM(g_tpos)
SYM(g_tpos):   .space 4        /* gecerli token indeksi */
    .globl SYM(g_nnodes)
SYM(g_nnodes): .space 4
    .globl SYM(g_perr)
SYM(g_perr):   .space 4
/* Ayristirici ozyineleme derinligi. Sinirsizken 3000 ic ice parantez
 * MAKINE yigininini tasiriyordu - bu bizim tablolarimizdan biri degil,
 * dolayisiyla tablo denetimleri yakalamiyordu. */
    .globl SYM(g_pdepth)
SYM(g_pdepth): .space 4

#include "../tables/prec.inc"

    SECT_RODATA
pe_msg1:  .ascii "satir "
    .equ  pe_msg1_len, . - pe_msg1
pe_msg2:  .ascii ": beklenmeyen sozcuk '"
    .equ  pe_msg2_len, . - pe_msg2
pe_msg3:  .ascii "'\n"
    .equ  pe_msg3_len, . - pe_msg3

    SECT_TEXT

/* ===================== token erisimi ===================== */

/* tok_field(A0 = token indeksi, A1 = alan ofseti) -> RV */
FUNC(tok_field)
    ENTER(1)
    SHLI(A0, 4)                     /* * TOK_SIZE */
    ADD(A0, A1)
    LEA_SYM(A1, SYM(g_toks))
    LD(A1, A1)
    ADD(A0, A1)
    LD32(RVW, A0)
    LEAVE_
    RET
ENDFUNC(tok_field)

/* cur_type() -> RV */
FUNC(cur_type)
    ENTER(1)
    LEA_SYM(A0, SYM(g_tpos))
    LD32(A0W, A0)
    MOVI(A1, TOK_OFF_TYPE)
    CALL(tok_field)
    LEAVE_
    RET
ENDFUNC(cur_type)

/* cur_line() -> RV */
FUNC(cur_line)
    ENTER(1)
    LEA_SYM(A0, SYM(g_tpos))
    LD32(A0W, A0)
    MOVI(A1, TOK_OFF_LINE)
    CALL(tok_field)
    LEAVE_
    RET
ENDFUNC(cur_line)

/* advance() -> RV = tuketilen tokenin indeksi */
FUNC(advance)
    ENTER(1)
    LEA_SYM(A0, SYM(g_tpos))
    LD32(A1W, A0)
    MOVR(A2, A1)
    INC(A2)
    ST32_OFF(A0, 0, A2W)
    MOVR(RV, A1)
    LEAVE_
    RET
ENDFUNC(advance)

/* print_tok(A0 = token indeksi) - sozcugu kaynaktan basar */
FUNC(print_tok)
    ENTER(2)
    SPILL(0, A0)
    MOVI(A1, TOK_OFF_START)
    CALL(tok_field)
    SPILL(1, RV)
    FILL(A0, 0)
    MOVI(A1, TOK_OFF_LEN)
    CALL(tok_field)
    MOVR(A1, RV)                    /* uzunluk */
    LEA_SYM(A0, SYM(g_src))
    LD(A0, A0)
    FILL(A2, 1)
    ADD(A0, A2)
    CALL(print_str)
    LEAVE_
    RET
ENDFUNC(print_tok)

/* perr() - hata sayar, ilk 5 tanesini basar */
FUNC(perr)
    ENTER(2)
    LEA_SYM(A0, SYM(g_perr))
    LD32(A1W, A0)
    INC(A1)
    ST32_OFF(A0, 0, A1W)
    CMPI(A1, 5)
    BHI(pr_done)

    LEA_SYM(A0, pe_msg1)
    MOVI(A1, pe_msg1_len)
    CALL(print_str)
    CALL(cur_line)
    MOVR(A0, RV)
    CALL(print_u32)
    LEA_SYM(A0, pe_msg2)
    MOVI(A1, pe_msg2_len)
    CALL(print_str)
    LEA_SYM(A0, SYM(g_tpos))
    LD32(A0W, A0)
    CALL(print_tok)
    LEA_SYM(A0, pe_msg3)
    MOVI(A1, pe_msg3_len)
    CALL(print_str)
pr_done:
    LEAVE_
    RET
ENDFUNC(perr)

/* expect(A0 = beklenen tur) -> RV = 1 tamam / 0 hata */
FUNC(expect)
    ENTER(1)
    SPILL(0, A0)
    CALL(cur_type)
    MOVR(A1, RV)
    FILL(A0, 0)
    CMPR(A0, A1)
    BNE(ex_bad)
    CALL(advance)
    MOVI(RV, 1)
    LEAVE_
    RET
ex_bad:
    CALL(perr)
    MOVI(RV, 0)
    LEAVE_
    RET
ENDFUNC(expect)

/* opt_semi() - varsa ';' tuketir */
FUNC(opt_semi)
    ENTER(1)
    CALL(cur_type)
    MOVR(A0, RV)
    CMPI(A0, TOK_SEMI)
    BNE(os_done)
    CALL(advance)
os_done:
    LEAVE_
    RET
ENDFUNC(opt_semi)

/* ===================== dugum islemleri ===================== */

/* node_ptr(A0 = indeks) -> RV */
FUNC(node_ptr)
    ENTER(1)
    SHLI(A0, NODE_SHIFT)
    LEA_SYM(A1, SYM(g_nodes))
    LD(A1, A1)
    ADD(A0, A1)
    MOVR(RV, A0)
    LEAVE_
    RET
ENDFUNC(node_ptr)

/* node_set(A0 = indeks, A1 = alan ofseti, A2 = deger) */
FUNC(node_set)
    ENTER(2)
    SPILL(0, A1)
    SPILL(1, A2)
    CALL(node_ptr)
    MOVR(A0, RV)
    FILL(A1, 0)
    ADD(A0, A1)
    FILL(A1, 1)
    ST32_OFF(A0, 0, A1W)
    LEAVE_
    RET
ENDFUNC(node_set)

/* node_get(A0 = indeks, A1 = alan ofseti) -> RV */
FUNC(node_get)
    ENTER(1)
    SPILL(0, A1)
    CALL(node_ptr)
    MOVR(A0, RV)
    FILL(A1, 0)
    ADD(A0, A1)
    LD32(RVW, A0)
    LEAVE_
    RET
ENDFUNC(node_get)

/* node_new(A0 = tur) -> RV = yeni dugum indeksi */
FUNC(node_new)
    ENTER(3)
    SPILL(0, A0)
    LEA_SYM(A0, SYM(g_nnodes))
    LD32(A1W, A0)
    /* arena doldu mu: tasarsa komsu bellege dugum yazilirdi */
    CMPI(A1, MAX_NODES)
    BHS(nn_full)
    MOVR(A2, A1)
    INC(A2)
    ST32_OFF(A0, 0, A2W)
    SPILL(1, A1)                    /* indeks */
    MOVR(A0, A1)
    SHLI(A0, NODE_SHIFT)
    LEA_SYM(A1, SYM(g_nodes))
    LD(A1, A1)
    ADD(A0, A1)
    SPILL(2, A0)                    /* isaretci */
    MOVI(A1, 0)
    ST32_OFF(A0, 0, A1W)
    ST32_OFF(A0, 4, A1W)
    ST32_OFF(A0, 8, A1W)
    ST32_OFF(A0, 12, A1W)
    ST32_OFF(A0, 16, A1W)
    ST32_OFF(A0, 20, A1W)
    ST32_OFF(A0, 24, A1W)
    ST32_OFF(A0, 28, A1W)
    FILL(A1, 0)                     /* tur */
    ST32_OFF(A0, ND_KIND, A1W)
    CALL(cur_line)
    MOVR(A1, RV)
    FILL(A0, 2)
    ST32_OFF(A0, ND_LINE, A1W)
    FILL(RV, 1)
    LEAVE_
    RET
nn_full:
    LEA_SYM(A0, SYM(g_perr))
    LD32(A1W, A0)
    INC(A1)
    ST32_OFF(A0, 0, A1W)
    MOVI(RV, 0)                     /* null dugum: ayristirma guvenle sonlanir */
    LEAVE_
    RET
ENDFUNC(node_new)

/* ===================== ifadeler (Pratt) ===================== */

/* parse_prefix() -> RV = dugum
 * Slotlar: 0 = token turu, 1 = dugum
 */
FUNC(parse_prefix)
    ENTER(2)
    CALL(cur_type)
    MOVR(A0, RV)
    SPILL(0, A0)
    CMPI(A0, TOK_NUMBER); BEQ(pp_num)
    CMPI(A0, TOK_STRING); BEQ(pp_str)
    CMPI(A0, TOK_IDENT);  BEQ(pp_id)
    CMPI(A0, TOK_TRUE);   BEQ(pp_true)
    CMPI(A0, TOK_FALSE);  BEQ(pp_false)
    CMPI(A0, TOK_NIL);    BEQ(pp_nil)
    CMPI(A0, TOK_MINUS);  BEQ(pp_unary)
    CMPI(A0, TOK_NOT);    BEQ(pp_unary)
    CMPI(A0, TOK_BANG);   BEQ(pp_unary)
    CMPI(A0, TOK_TILDE);  BEQ(pp_unary)
    CMPI(A0, TOK_LPAREN); BEQ(pp_group)
    CMPI(A0, TOK_LBRACK); BEQ(pp_array)
    CALL(perr)
    CALL(advance)                   /* ilerleme garantisi */
    MOVI(RV, 0)
    LEAVE_
    RET

pp_num:   MOVI(A0, N_NUMBER); B(pp_lit)
pp_str:   MOVI(A0, N_STRING); B(pp_lit)
pp_id:    MOVI(A0, N_IDENT)
pp_lit:
    CALL(node_new)
    SPILL(1, RV)
    CALL(advance)
    MOVR(A2, RV)                    /* token indeksi */
    FILL(A0, 1)
    MOVI(A1, ND_A)
    CALL(node_set)
    FILL(RV, 1)
    LEAVE_
    RET

pp_true:  MOVI(A0, N_TRUE);  B(pp_simple)
pp_false: MOVI(A0, N_FALSE); B(pp_simple)
pp_nil:   MOVI(A0, N_NIL)
pp_simple:
    CALL(node_new)
    SPILL(1, RV)
    CALL(advance)
    FILL(RV, 1)
    LEAVE_
    RET

pp_unary:
    MOVI(A0, N_UNARY)
    CALL(node_new)
    SPILL(1, RV)
    CALL(advance)
    MOVR(A2, RV)                    /* operator token indeksi */
    FILL(A0, 1)
    MOVI(A1, ND_B)
    CALL(node_set)
    MOVI(A0, BP_UNARY)
    CALL(parse_expr)
    MOVR(A2, RV)
    FILL(A0, 1)
    MOVI(A1, ND_A)
    CALL(node_set)
    FILL(RV, 1)
    LEAVE_
    RET

pp_array:
    MOVI(A0, N_ARRAY)
    CALL(node_new)
    SPILL(1, RV)
    CALL(advance)
    MOVI(A0, TOK_RBRACK)
    CALL(parse_list)
    MOVR(A2, RV)
    FILL(A0, 1)
    MOVI(A1, ND_A)
    CALL(node_set)
    FILL(RV, 1)
    LEAVE_
    RET

pp_group:
    CALL(advance)
    MOVI(A0, 0)
    CALL(parse_expr)
    SPILL(1, RV)
    MOVI(A0, TOK_RPAREN)
    CALL(expect)
    FILL(RV, 1)
    LEAVE_
    RET
ENDFUNC(parse_prefix)

/* parse_list(A0 = bitirici token) -> RV = ilk dugum (next ile zincirli)
 * Hem cagri argumanlari hem dizi degismezleri icin. */
FUNC(parse_list)
    ENTER(4)
    SPILL(3, A0)
    MOVI(A0, 0)
    SPILL(0, A0)                    /* bas  */
    SPILL(1, A0)                    /* kuyruk */
    CALL(cur_type)
    MOVR(A0, RV)
    FILL(A1, 3)
    CMPR(A0, A1)
    BEQ(pa_end)
pa_loop:
    MOVI(A0, 0)
    CALL(parse_expr)
    SPILL(2, RV)
    FILL(A0, 1)
    BZ(A0, pa_first)
    FILL(A0, 1)
    MOVI(A1, ND_NEXT)
    FILL(A2, 2)
    CALL(node_set)
    B(pa_tail)
pa_first:
    FILL(A0, 2)
    SPILL(0, A0)
pa_tail:
    FILL(A0, 2)
    SPILL(1, A0)
    CALL(cur_type)
    MOVR(A0, RV)
    CMPI(A0, TOK_COMMA)
    BNE(pa_end)
    CALL(advance)
    B(pa_loop)
pa_end:
    FILL(A0, 3)
    CALL(expect)
    FILL(RV, 0)
    LEAVE_
    RET
ENDFUNC(parse_list)

/* parse_expr(A0 = en dusuk baglama gucu) -> RV = dugum
 * Slotlar: 0=minbp 1=sol 2=optok 3=lbp 4=tur 5=rassoc 6=sag 7=yeni
 */
FUNC(parse_expr)
    ENTER(10)
    SPILL(0, A0)
    LEA_SYM(A0, SYM(g_pdepth))
    LD32(A1W, A0)
    INC(A1)
    ST32_OFF(A0, 0, A1W)
    CMPI(A1, MAX_PARSE_DEPTH)
    BHS(pe_deep)
    CALL(parse_prefix)
    SPILL(1, RV)

pe_loop:
    CALL(cur_type)
    MOVR(A0, RV)
    SHLI(A0, 2)                     /* prec_table girdisi 4 bayt */
    LEA_SYM(A1, SYM(prec_table))
    ADD(A1, A0)
    LDB_OFF(A0W, A1, 0)
    SPILL(3, A0)                    /* lbp    */
    LDB_OFF(A0W, A1, 1)
    SPILL(4, A0)                    /* tur    */
    LDB_OFF(A0W, A1, 2)
    SPILL(5, A0)                    /* rassoc */

    FILL(A0, 3)
    FILL(A1, 0)
    CMPR(A0, A1)
    BLS(pe_done)                    /* lbp <= minbp -> dur */

    FILL(A0, 4)
    CMPI(A0, N_CALL)
    BEQ(pe_call)
    CMPI(A0, N_INDEX)
    BEQ(pe_index)

    FILL(A0, 4)
    SPILL(8, A0)                    /* dugum turu (ASSIGN mi) */
    CALL(cur_type)
    SPILL(9, RV)                    /* operator TOKEN turu */
    CALL(advance)
    SPILL(2, RV)                    /* operator token indeksi */
    FILL(A0, 3)
    FILL(A1, 5)
    SUB(A0, A1)                     /* sag birlesimde lbp-1 ile ozyinele */
    CALL(parse_expr)
    SPILL(6, RV)
    FILL(A0, 4)
    CALL(node_new)
    SPILL(7, RV)
    FILL(A0, 7); MOVI(A1, ND_A); FILL(A2, 1); CALL(node_set)
    /* --- bilesik atama: a += b  =>  a = (a + b) ---
     * ASSIGN(A=a, B=BINARY(A=a, B=b, C=oprtr)) kuruluyor. Operator
     * alaninda '+=' tokeni kaliyor; derleyici onu '+' gibi isliyor. */
    FILL(A0, 9)
    CMPI(A0, TOK_PLUSEQ);  BEQ(pe_cmpd)
    CMPI(A0, TOK_MINUSEQ); BEQ(pe_cmpd)
    CMPI(A0, TOK_STAREQ);  BEQ(pe_cmpd)
    CMPI(A0, TOK_SLASHEQ); BEQ(pe_cmpd)
    CMPI(A0, TOK_PCTEQ);   BEQ(pe_cmpd)
    FILL(A0, 7); MOVI(A1, ND_B); FILL(A2, 6); CALL(node_set)
    B(pe_bset)
pe_cmpd:
    MOVI(A0, N_BINARY)
    CALL(node_new)
    MOVR(A2, RV)
    SPILL(4, A2)
    FILL(A0, 4); MOVI(A1, ND_A); FILL(A2, 1); CALL(node_set)
    FILL(A0, 4); MOVI(A1, ND_B); FILL(A2, 6); CALL(node_set)
    FILL(A0, 4); MOVI(A1, ND_C); FILL(A2, 2); CALL(node_set)
    FILL(A0, 7); MOVI(A1, ND_B); FILL(A2, 4); CALL(node_set)
pe_bset:
    FILL(A0, 7); MOVI(A1, ND_C); FILL(A2, 2); CALL(node_set)
    FILL(A0, 7)
    SPILL(1, A0)
    B(pe_loop)

pe_call:
    CALL(advance)                   /* '(' */
    MOVI(A0, N_CALL)
    CALL(node_new)
    SPILL(7, RV)
    FILL(A0, 7); MOVI(A1, ND_A); FILL(A2, 1); CALL(node_set)
    MOVI(A0, TOK_RPAREN)
    CALL(parse_list)
    MOVR(A2, RV)
    FILL(A0, 7); MOVI(A1, ND_B); CALL(node_set)
    FILL(A0, 7)
    SPILL(1, A0)
    B(pe_loop)

pe_index:
    CALL(advance)                   /* '[' */
    MOVI(A0, N_INDEX)
    CALL(node_new)
    SPILL(7, RV)
    FILL(A0, 7); MOVI(A1, ND_A); FILL(A2, 1); CALL(node_set)
    MOVI(A0, 0)
    CALL(parse_expr)
    MOVR(A2, RV)
    FILL(A0, 7); MOVI(A1, ND_B); CALL(node_set)
    MOVI(A0, TOK_RBRACK)
    CALL(expect)
    FILL(A0, 7)
    SPILL(1, A0)
    B(pe_loop)

pe_done:
    LEA_SYM(A0, SYM(g_pdepth))
    LD32(A1W, A0)
    DEC(A1)
    ST32_OFF(A0, 0, A1W)
    FILL(RV, 1)
    LEAVE_
    RET

pe_deep:
    CALL(perr)
    CALL(advance)                   /* ilerleme garantisi */
    LEA_SYM(A0, SYM(g_pdepth))
    LD32(A1W, A0)
    DEC(A1)
    ST32_OFF(A0, 0, A1W)
    MOVI(RV, 0)
    LEAVE_
    RET
ENDFUNC(parse_expr)

/* ===================== deyimler ===================== */

/* parse_block() -> RV = N_BLOCK dugumu */
FUNC(parse_block)
    ENTER(1)
    MOVI(A0, N_BLOCK)
    CALL(node_new)
    SPILL(0, RV)
    MOVI(A0, TOK_LBRACE)
    CALL(expect)
    MOVI(A0, TOK_RBRACE)
    CALL(parse_stmts)
    MOVR(A2, RV)
    FILL(A0, 0)
    MOVI(A1, ND_A)
    CALL(node_set)
    MOVI(A0, TOK_RBRACE)
    CALL(expect)
    FILL(RV, 0)
    LEAVE_
    RET
ENDFUNC(parse_block)

/* parse_stmts(A0 = bitirici token) -> RV = ilk deyim (next ile zincirli)
 * Slotlar: 0=bitirici 1=bas 2=kuyruk 3=deyim 4=onceki tpos
 */
FUNC(parse_stmts)
    ENTER(5)
    SPILL(0, A0)
    MOVI(A0, 0)
    SPILL(1, A0)
    SPILL(2, A0)
ps_loop:
    CALL(cur_type)
    MOVR(A1, RV)
    CMPI(A1, TOK_EOF)
    BEQ(ps_end)
    FILL(A0, 0)
    CMPR(A1, A0)
    BEQ(ps_end)

    LEA_SYM(A0, SYM(g_tpos))        /* ilerleme kontrolu icin kaydet */
    LD32(A0W, A0)
    SPILL(4, A0)

    CALL(parse_stmt)
    SPILL(3, RV)

    LEA_SYM(A0, SYM(g_tpos))        /* hic ilerlemediyse zorla ilerle:
                                       sonsuz donguye karsi guvence */
    LD32(A0W, A0)
    FILL(A1, 4)
    CMPR(A0, A1)
    BNE(ps_link)
    CALL(advance)
ps_link:
    FILL(A0, 3)
    BZ(A0, ps_loop)                 /* bos deyim (';') */
    FILL(A0, 2)
    BZ(A0, ps_first)
    FILL(A0, 2)
    MOVI(A1, ND_NEXT)
    FILL(A2, 3)
    CALL(node_set)
    B(ps_tail)
ps_first:
    FILL(A0, 3)
    SPILL(1, A0)
ps_tail:
    FILL(A0, 3)
    SPILL(2, A0)
    B(ps_loop)
ps_end:
    FILL(RV, 1)
    LEAVE_
    RET
ENDFUNC(parse_stmts)

/* parse_params() -> RV = ilk N_PARAM dugumu */
FUNC(parse_params)
    ENTER(3)
    MOVI(A0, 0)
    SPILL(0, A0)
    SPILL(1, A0)
    CALL(cur_type)
    MOVR(A0, RV)
    CMPI(A0, TOK_RPAREN)
    BEQ(pm_end)
pm_loop:
    CALL(cur_type)
    MOVR(A0, RV)
    CMPI(A0, TOK_IDENT)
    BNE(pm_bad)
    MOVI(A0, N_PARAM)
    CALL(node_new)
    SPILL(2, RV)
    CALL(advance)
    MOVR(A2, RV)
    FILL(A0, 2)
    MOVI(A1, ND_A)
    CALL(node_set)
    FILL(A0, 1)
    BZ(A0, pm_first)
    FILL(A0, 1)
    MOVI(A1, ND_NEXT)
    FILL(A2, 2)
    CALL(node_set)
    B(pm_tail)
pm_first:
    FILL(A0, 2)
    SPILL(0, A0)
pm_tail:
    FILL(A0, 2)
    SPILL(1, A0)
    CALL(cur_type)
    MOVR(A0, RV)
    CMPI(A0, TOK_COMMA)
    BNE(pm_end)
    CALL(advance)
    B(pm_loop)
pm_bad:
    CALL(perr)
pm_end:
    FILL(RV, 0)
    LEAVE_
    RET
ENDFUNC(parse_params)

/* parse_stmt() -> RV = dugum (0 = bos deyim)
 * Slotlar: 0 = token turu, 1 = dugum
 */
FUNC(parse_stmt)
    ENTER(5)   /* her(;;) 4 slot kullaniyor */
    CALL(cur_type)
    MOVR(A0, RV)
    SPILL(0, A0)
    CMPI(A0, TOK_LET);      BEQ(st_let)
    CMPI(A0, TOK_CONST);    BEQ(st_let)
    CMPI(A0, TOK_IF);       BEQ(st_if)
    CMPI(A0, TOK_WHILE);    BEQ(st_while)
    CMPI(A0, TOK_FOR);      BEQ(st_for)
    CMPI(A0, TOK_RETURN);   BEQ(st_return)
    CMPI(A0, TOK_PRINT);    BEQ(st_print)
    CMPI(A0, TOK_BREAK);    BEQ(st_break)
    CMPI(A0, TOK_CONTINUE); BEQ(st_continue)
    CMPI(A0, TOK_FN);       BEQ(st_fn)
    CMPI(A0, TOK_LBRACE);   BEQ(st_blk)
    CMPI(A0, TOK_SEMI);     BEQ(st_semi)
    B(st_expr)

st_semi:
    CALL(advance)
    MOVI(RV, 0)
    LEAVE_
    RET

st_blk:
    CALL(parse_block)
    LEAVE_
    RET

/* tanim/sabit ad [= ifade] */
st_let:
    FILL(A0, 0)
    CMPI(A0, TOK_LET)
    BEQ(st_let_kind)
    MOVI(A0, N_CONST)
    B(st_let_new)
st_let_kind:
    MOVI(A0, N_LET)
st_let_new:
    CALL(node_new)
    SPILL(1, RV)
    CALL(advance)
    CALL(cur_type)
    MOVR(A0, RV)
    CMPI(A0, TOK_IDENT)
    BEQ(st_let_name)
    CALL(perr)
    B(st_let_done)
st_let_name:
    CALL(advance)
    MOVR(A2, RV)
    FILL(A0, 1)
    MOVI(A1, ND_A)
    CALL(node_set)
    CALL(cur_type)
    MOVR(A0, RV)
    CMPI(A0, TOK_ASSIGN)
    BNE(st_let_done)
    CALL(advance)
    MOVI(A0, 0)
    CALL(parse_expr)
    MOVR(A2, RV)
    FILL(A0, 1)
    MOVI(A1, ND_B)
    CALL(node_set)
st_let_done:
    CALL(opt_semi)
    FILL(RV, 1)
    LEAVE_
    RET

/* eger kosul { ... } [yoksa { ... } | yoksa eger ...] */
st_if:
    MOVI(A0, N_IF)
    CALL(node_new)
    SPILL(1, RV)
    CALL(advance)
    MOVI(A0, 0)
    CALL(parse_expr)
    MOVR(A2, RV)
    FILL(A0, 1); MOVI(A1, ND_A); CALL(node_set)
    CALL(parse_block)
    MOVR(A2, RV)
    FILL(A0, 1); MOVI(A1, ND_B); CALL(node_set)
    CALL(cur_type)
    MOVR(A0, RV)
    CMPI(A0, TOK_ELSE)
    BNE(st_if_done)
    CALL(advance)
    CALL(cur_type)
    MOVR(A0, RV)
    CMPI(A0, TOK_IF)
    BEQ(st_elif)                    /* "yoksa eger" zinciri */
    CALL(parse_block)
    B(st_if_else)
st_elif:
    CALL(parse_stmt)
st_if_else:
    MOVR(A2, RV)
    FILL(A0, 1); MOVI(A1, ND_C); CALL(node_set)
st_if_done:
    FILL(RV, 1)
    LEAVE_
    RET

/* iken kosul { ... } */
st_while:
    MOVI(A0, N_WHILE)
    CALL(node_new)
    SPILL(1, RV)
    CALL(advance)
    MOVI(A0, 0)
    CALL(parse_expr)
    MOVR(A2, RV)
    FILL(A0, 1); MOVI(A1, ND_A); CALL(node_set)
    CALL(parse_block)
    MOVR(A2, RV)
    FILL(A0, 1); MOVI(A1, ND_B); CALL(node_set)
    FILL(RV, 1)
    LEAVE_
    RET

/* her (baslangic; kosul; adim) { govde }
 *
 * BLOCK { baslangic ; FOR(kosul, govde, adim) } olarak kuruluyor:
 * baslangictaki "tanim i = 0" dongunun kendi kapsaminda kalsin diye.
 * Bos alanlar serbest: "her (;;) {}" sonsuz dongu.
 */
st_for:
    CALL(advance)
    MOVI(A0, TOK_LPAREN)
    CALL(expect)
    /* dis blok */
    MOVI(A0, N_BLOCK)
    CALL(node_new)
    SPILL(1, RV)
    /* --- baslangic --- */
    CALL(cur_type)
    MOVR(A0, RV)
    CMPI(A0, TOK_SEMI)
    BEQ(sf_noinit)
    CALL(parse_stmt)
    SPILL(2, RV)                    /* ONCE sakla: node_set RV'yi ezer */
    MOVR(A2, RV)
    FILL(A0, 1); MOVI(A1, ND_A); CALL(node_set)
    B(sf_initdone)
sf_noinit:
    /* ';' ayiraci sf_initdone'da tuketilir; burada ILERLETME.
     * Ilk surumde burada da ilerletiyordum ve "her (;;)" iki
     * noktali virguli birden yiyip ')' uzerinde ifade ariyordu. */
    MOVI(A0, 0)
    SPILL(2, A0)
sf_initdone:
    /* baslangic ";" tuketmediyse tuket */
    CALL(cur_type)
    MOVR(A0, RV)
    CMPI(A0, TOK_SEMI)
    BNE(sf_cond)
    CALL(advance)
sf_cond:
    MOVI(A0, N_FOR)
    CALL(node_new)
    SPILL(3, RV)
    /* --- kosul (bos ise "dogru") --- */
    CALL(cur_type)
    MOVR(A0, RV)
    CMPI(A0, TOK_SEMI)
    BNE(sf_haveC)
    MOVI(A0, N_TRUE)
    CALL(node_new)
    MOVR(A2, RV)
    B(sf_setC)
sf_haveC:
    MOVI(A0, 0)
    CALL(parse_expr)
    MOVR(A2, RV)
sf_setC:
    FILL(A0, 3); MOVI(A1, ND_A); CALL(node_set)
    MOVI(A0, TOK_SEMI)
    CALL(expect)
    /* --- adim --- */
    CALL(cur_type)
    MOVR(A0, RV)
    CMPI(A0, TOK_RPAREN)
    BEQ(sf_nostep)
    MOVI(A0, 0)
    CALL(parse_expr)
    MOVR(A2, RV)
    FILL(A0, 3); MOVI(A1, ND_C); CALL(node_set)
sf_nostep:
    MOVI(A0, TOK_RPAREN)
    CALL(expect)
    /* --- govde --- */
    CALL(parse_block)
    MOVR(A2, RV)
    FILL(A0, 3); MOVI(A1, ND_B); CALL(node_set)
    /* FOR'u baslangicin ardina zincirle (ya da blogun basina) */
    FILL(A0, 2)
    BZ(A0, sf_first)
    FILL(A0, 2); MOVI(A1, ND_NEXT); FILL(A2, 3); CALL(node_set)
    B(sf_done)
sf_first:
    FILL(A0, 1); MOVI(A1, ND_A); FILL(A2, 3); CALL(node_set)
sf_done:
    FILL(RV, 1)
    LEAVE_
    RET

/* dondur [ifade] */
st_return:
    MOVI(A0, N_RETURN)
    CALL(node_new)
    SPILL(1, RV)
    CALL(advance)
    CALL(cur_type)
    MOVR(A0, RV)
    CMPI(A0, TOK_RBRACE); BEQ(st_ret_done)
    CMPI(A0, TOK_SEMI);   BEQ(st_ret_done)
    CMPI(A0, TOK_EOF);    BEQ(st_ret_done)
    MOVI(A0, 0)
    CALL(parse_expr)
    MOVR(A2, RV)
    FILL(A0, 1); MOVI(A1, ND_A); CALL(node_set)
st_ret_done:
    CALL(opt_semi)
    FILL(RV, 1)
    LEAVE_
    RET

/* yazdir ifade   (parantezsiz deyim) */
st_print:
    MOVI(A0, N_PRINT)
    CALL(node_new)
    SPILL(1, RV)
    CALL(advance)
    MOVI(A0, 0)
    CALL(parse_expr)
    MOVR(A2, RV)
    FILL(A0, 1); MOVI(A1, ND_A); CALL(node_set)
    CALL(opt_semi)
    FILL(RV, 1)
    LEAVE_
    RET

st_break:    MOVI(A0, N_BREAK);    B(st_simple)
st_continue: MOVI(A0, N_CONTINUE)
st_simple:
    CALL(node_new)
    SPILL(1, RV)
    CALL(advance)
    CALL(opt_semi)
    FILL(RV, 1)
    LEAVE_
    RET

/* fonk ad(p1, p2) { ... } */
st_fn:
    MOVI(A0, N_FN)
    CALL(node_new)
    SPILL(1, RV)
    CALL(advance)
    CALL(cur_type)
    MOVR(A0, RV)
    CMPI(A0, TOK_IDENT)
    BNE(st_fn_noname)
    CALL(advance)
    MOVR(A2, RV)
    FILL(A0, 1); MOVI(A1, ND_A); CALL(node_set)
    B(st_fn_params)
st_fn_noname:
    CALL(perr)
st_fn_params:
    MOVI(A0, TOK_LPAREN)
    CALL(expect)
    CALL(parse_params)
    MOVR(A2, RV)
    FILL(A0, 1); MOVI(A1, ND_B); CALL(node_set)
    MOVI(A0, TOK_RPAREN)
    CALL(expect)
    CALL(parse_block)
    MOVR(A2, RV)
    FILL(A0, 1); MOVI(A1, ND_C); CALL(node_set)
    FILL(RV, 1)
    LEAVE_
    RET

st_expr:
    MOVI(A0, N_EXPRSTMT)
    CALL(node_new)
    SPILL(1, RV)
    MOVI(A0, 0)
    CALL(parse_expr)
    MOVR(A2, RV)
    FILL(A0, 1); MOVI(A1, ND_A); CALL(node_set)
    CALL(opt_semi)
    FILL(RV, 1)
    LEAVE_
    RET
ENDFUNC(parse_stmt)

/* =====================================================================
 * parse_program(A0 = token dizisi, A1 = dugum arenasi) -> RV = kok dugum
 * ===================================================================== */
FUNC(parse_program)
    ENTER(2)
    LEA_SYM(A2, SYM(g_toks))
    ST(A2, A0)
    LEA_SYM(A2, SYM(g_nodes))
    ST(A2, A1)
    MOVI(A0, 0)
    LEA_SYM(A1, SYM(g_tpos))
    ST32_OFF(A1, 0, A0W)
    LEA_SYM(A1, SYM(g_perr))
    ST32_OFF(A1, 0, A0W)
    LEA_SYM(A1, SYM(g_pdepth))
    ST32_OFF(A1, 0, A0W)
    MOVI(A0, 1)                     /* dugum 0 null nobetcisi */
    LEA_SYM(A1, SYM(g_nnodes))
    ST32_OFF(A1, 0, A0W)

    MOVI(A0, N_PROGRAM)
    CALL(node_new)
    SPILL(0, RV)
    MOVI(A0, TOK_EOF)
    CALL(parse_stmts)
    MOVR(A2, RV)
    FILL(A0, 0)
    MOVI(A1, ND_A)
    CALL(node_set)
    FILL(RV, 0)
    LEAVE_
    RET
ENDFUNC(parse_program)
