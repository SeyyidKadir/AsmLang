/* disasm.S - bytecode dokumu (dogrulama icin) */
#include "../abi.inc"
#include "../tables/opcodes.inc"
#include "../tables/opnames.inc"

    SECT_RODATA
ds_sp:  .ascii "  "
    .equ ds_sp_len, . - ds_sp

    SECT_TEXT

/* disasm() - g_code icindeki tum komutlari basar */
FUNC(disasm)
    ENTER(3)
    MOVI(A0, 0)
    SPILL(0, A0)
dis_loop:
    LEA_SYM(A0, SYM(g_ncode))
    LD32(A0W, A0)
    FILL(A1, 0)
    CMPR(A1, A0)
    BHS(dis_end)

    FILL(A0, 0)
    CALL(print_u32)
    LEA_SYM(A0, ds_sp); MOVI(A1, ds_sp_len); CALL(print_str)

    FILL(A0, 0)
    SHLI(A0, 2)
    LEA_SYM(A1, SYM(g_code))
    LD(A1, A1)
    ADD(A0, A1)
    LD32(A0W, A0)
    SPILL(1, A0)                    /* komut */
    ANDI(A0, 255)
    SHLI(A0, 4)
    LEA_SYM(A1, SYM(op_names))
    ADD(A0, A1)
    LD32(A1W, A0)
    ADDI(A0, 4)
    CALL(print_str)

    LEA_SYM(A0, ds_sp); MOVI(A1, ds_sp_len); CALL(print_str)
    FILL(A0, 1)
    SHRI(A0, OPD_SHIFT)
    CALL(print_u32)
    MOVI(A0, 10)
    CALL(print_ch)

    FILL(A0, 0); INC(A0); SPILL(0, A0)
    B(dis_loop)
dis_end:
    LEAVE_
    RET
ENDFUNC(disasm)
