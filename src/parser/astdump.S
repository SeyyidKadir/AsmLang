/* astdump.S - AST'yi girintili agac olarak basar
 *
 * Hangi alanin cocuk dugum, hangisinin token indeksi oldugunu kod
 * bilmiyor: kind_kids ve kind_tokfld tablolarindan okuyor. Yeni bir
 * dugum turu eklemek icin gen_tables.py'de tek satir yeter.
 */
#include "../abi.inc"
#include "../tables/tokens.inc"
#include "../tables/ast.inc"

    SECT_RODATA
ad_indent:  .ascii "  "
    .equ    ad_indent_len, . - ad_indent
ad_sp:      .ascii " "
    .equ    ad_sp_len, . - ad_sp

    SECT_TEXT

/* print_kind(A0 = tur) */
FUNC(print_kind)
    ENTER(1)
    SHLI(A0, 4)                     /* kind_names girdisi 16 bayt */
    LEA_SYM(A1, SYM(kind_names))
    ADD(A0, A1)
    LD32(A1W, A0)                   /* uzunluk */
    ADDI(A0, 4)
    CALL(print_str)
    LEAVE_
    RET
ENDFUNC(print_kind)

/* dump_node(A0 = dugum indeksi, A1 = derinlik)
 * Kardesleri de dolasir (next zinciri).
 * Slotlar: 0=dugum 1=derinlik 2=tur 3=maske 4=gecici
 */
FUNC(dump_node)
    ENTER(5)
    SPILL(0, A0)
    SPILL(1, A1)

ad_sib:
    FILL(A0, 0)
    BZ(A0, ad_end)

    /* girinti */
    FILL(A0, 1)
    SPILL(4, A0)
ad_ind:
    FILL(A0, 4)
    BZ(A0, ad_ind_done)
    LEA_SYM(A0, ad_indent)
    MOVI(A1, ad_indent_len)
    CALL(print_str)
    FILL(A0, 4)
    DEC(A0)
    SPILL(4, A0)
    B(ad_ind)
ad_ind_done:

    /* tur adi */
    FILL(A0, 0)
    MOVI(A1, ND_KIND)
    CALL(node_get)
    SPILL(2, RV)
    MOVR(A0, RV)
    CALL(print_kind)

    /* token indeksi tutan alan varsa sozcugu yaz */
    FILL(A0, 2)
    LEA_SYM(A1, SYM(kind_tokfld))
    LDB_IDX(A0W, A1, A0)
    CMPI(A0, 255)
    BEQ(ad_notok)
    SPILL(4, A0)
    LEA_SYM(A0, ad_sp)
    MOVI(A1, ad_sp_len)
    CALL(print_str)
    FILL(A0, 0)
    FILL(A1, 4)
    CALL(node_get)
    MOVR(A0, RV)
    CALL(print_tok)
ad_notok:
    MOVI(A0, 10)
    CALL(print_ch)

    /* cocuk maskesi: bit0=a bit1=b bit2=c */
    FILL(A0, 2)
    LEA_SYM(A1, SYM(kind_kids))
    LDB_IDX(A0W, A1, A0)
    SPILL(3, A0)

    MOVI(A1, 1)
    FILL(A0, 3)
    AND(A0, A1)
    BZ(A0, ad_nob)
    FILL(A0, 0)
    MOVI(A1, ND_A)
    CALL(node_get)
    MOVR(A0, RV)
    FILL(A1, 1)
    INC(A1)
    CALL(dump_node)
ad_nob:
    MOVI(A1, 2)
    FILL(A0, 3)
    AND(A0, A1)
    BZ(A0, ad_noc)
    FILL(A0, 0)
    MOVI(A1, ND_B)
    CALL(node_get)
    MOVR(A0, RV)
    FILL(A1, 1)
    INC(A1)
    CALL(dump_node)
ad_noc:
    MOVI(A1, 4)
    FILL(A0, 3)
    AND(A0, A1)
    BZ(A0, ad_next)
    FILL(A0, 0)
    MOVI(A1, ND_C)
    CALL(node_get)
    MOVR(A0, RV)
    FILL(A1, 1)
    INC(A1)
    CALL(dump_node)

ad_next:
    FILL(A0, 0)
    MOVI(A1, ND_NEXT)
    CALL(node_get)
    MOVR(A0, RV)
    SPILL(0, A0)
    B(ad_sib)

ad_end:
    LEAVE_
    RET
ENDFUNC(dump_node)
