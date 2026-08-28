/* input.S - tamponlu konsol girdisi
 *
 * os_read blok okur, satir degil. Bayt basina bir syscall atmak
 * dogru ama yavas (4 KB'lik bir satir = 4096 syscall). Bu yuzden
 * 4 KB'lik bir tampon tutulup bosaldikca doldurulur.
 */
#include "../abi.inc"
#include "../tables/opcodes.inc"

#define IN_BUF_SIZE  4096

    .bss
    .p2align 3
    .globl SYM(g_inbuf)
SYM(g_inbuf):  .space (IN_BUF_SIZE) + GUARD_PAD
    .globl SYM(g_inpos)
SYM(g_inpos):  .space 4
    .globl SYM(g_inlen)
SYM(g_inlen):  .space 4
    .globl SYM(g_ineof)
SYM(g_ineof):  .space 4
/* Dosya okuma tamponu. Sabit boyut bilincli: buyuyen tamponla
 * O(n^2) birlestirme yapmak yerine sinir belli ve ongorulebilir. */
    .globl SYM(g_filebuf)
SYM(g_filebuf): .space (FILE_BUF_SIZE) + GUARD_PAD

    SECT_TEXT

/* in_getc() -> RV = bayt (0..255), dosya sonunda -1 */
FUNC(in_getc)
    ENTER(2)
ig_retry:
    LEA_SYM(A0, SYM(g_inpos))
    LD32(A0W, A0)
    LEA_SYM(A1, SYM(g_inlen))
    LD32(A1W, A1)
    CMPR(A0, A1)
    BLO(ig_have)

    /* tampon bos: doldur */
    LEA_SYM(A0, SYM(g_ineof))
    LD32(A0W, A0)
    BNZ(A0, ig_eof)
    MOVI(A0, 0)                     /* fd 0 = stdin */
    LEA_SYM(A1, SYM(g_inbuf))
    MOVI(A2, IN_BUF_SIZE)
    CALL(os_read)
    MOVR(A1, RV)
    /* n <= 0 ISARETLI karsilastirilmali: hata -errno doner ve
     * isaretsiz bakilirsa devasa pozitif gorunur */
    CMPI(A1, 0)
    BLE(ig_seteof)
    LEA_SYM(A0, SYM(g_inlen))
    ST32_OFF(A0, 0, A1W)
    MOVI(A1, 0)
    LEA_SYM(A0, SYM(g_inpos))
    ST32_OFF(A0, 0, A1W)
    B(ig_retry)

ig_seteof:
    MOVI(A1, 1)
    LEA_SYM(A0, SYM(g_ineof))
    ST32_OFF(A0, 0, A1W)
ig_eof:
    MOVI(RV, -1)
    LEAVE_
    RET

ig_have:
    LEA_SYM(A1, SYM(g_inbuf))
    LDB_IDX(A2W, A1, A0)            /* c = inbuf[pos] */
    MOVR(A1, A0)
    INC(A1)
    LEA_SYM(A0, SYM(g_inpos))
    ST32_OFF(A0, 0, A1W)
    MOVR(RV, A2)
    LEAVE_
    RET
ENDFUNC(in_getc)
