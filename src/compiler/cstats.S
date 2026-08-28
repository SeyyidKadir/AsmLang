/* cstats.S - uretilen bytecode'un istatistigi
 *
 * "Superinstruction coverage" gibi iddialarin olculebilmesi icin.
 * Disassembly'den elle saymak yerine derleyici kendi ciktisini sayiyor.
 */
#include "../abi.inc"
#include "../tables/opcodes.inc"

    .bss
    .p2align 2
    .globl SYM(g_st_super)
SYM(g_st_super):  .space 4        /* birlesik/superkomut sayisi */
    .globl SYM(g_st_gc)
SYM(g_st_gc):     .space 4        /* GETG_CONST + GETL_CONST */
    .globl SYM(g_st_addk)
SYM(g_st_addk):   .space 4        /* ADDK + SUBK + ADDK_SETG + INCGLOBAL */

    SECT_TEXT

/* code_stats() - g_code'u dolasip sayaclari doldurur
 * Slotlar: 0=i 1=n 2=op
 */
FUNC(code_stats)
    ENTER(3)
    MOVI(A0, 0)
    LEA_SYM(A1, SYM(g_st_super)); ST32_OFF(A1, 0, A0W)
    LEA_SYM(A1, SYM(g_st_gc));    ST32_OFF(A1, 0, A0W)
    LEA_SYM(A1, SYM(g_st_addk));  ST32_OFF(A1, 0, A0W)
    SPILL(0, A0)
    LEA_SYM(A0, SYM(g_ncode))
    LD32(A0W, A0)
    SPILL(1, A0)

cs_loop:
    FILL(A0, 0)
    FILL(A1, 1)
    CMPR(A0, A1)
    BHS(cs_done)
    CALL(code_at)
    MOVR(A0, RV)
    ANDI(A0, 255)
    SPILL(2, A0)

    /* OP_SETGLOBAL_P ve sonrasi: hepsi gozetleme deligi urunu */
    CMPI(A0, OP_SETGLOBAL_P)
    BLO(cs_kinds)
    LEA_SYM(A1, SYM(g_st_super))
    LD32(A0W, A1)
    INC(A0)
    ST32_OFF(A1, 0, A0W)

cs_kinds:
    FILL(A0, 2)
    CMPI(A0, OP_GETG_CONST); BEQ(cs_gc)
    CMPI(A0, OP_GETL_CONST); BEQ(cs_gc)
    CMPI(A0, OP_ADDK);       BEQ(cs_ak)
    CMPI(A0, OP_SUBK);       BEQ(cs_ak)
    CMPI(A0, OP_ADDK_SETG);  BEQ(cs_ak)
    CMPI(A0, OP_INCGLOBAL);  BEQ(cs_ak)
    B(cs_next)
cs_gc:
    LEA_SYM(A1, SYM(g_st_gc))
    LD32(A0W, A1); INC(A0); ST32_OFF(A1, 0, A0W)
    B(cs_next)
cs_ak:
    LEA_SYM(A1, SYM(g_st_addk))
    LD32(A0W, A1); INC(A0); ST32_OFF(A1, 0, A0W)

cs_next:
    FILL(A0, 0)
    INC(A0)
    SPILL(0, A0)
    B(cs_loop)

cs_done:
    LEAVE_
    RET
ENDFUNC(code_stats)
