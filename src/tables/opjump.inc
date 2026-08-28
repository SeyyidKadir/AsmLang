/* OTOMATIK URETILDI - tools/gen_tables.py */
#ifndef OPJUMP_INC
#define OPJUMP_INC

    SECT_RODATA
    .p2align 4
    .globl SYM(op_isjump)
SYM(op_isjump):
    .byte 0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0
    .byte 0,0,0,0,0,0,0,0,1,1,1,1,0,0,0,0
    .byte 0,0,0,0,0,0,1,1,1,1,1,1,0,0,0,0
    .byte 0,0,1,0,0,0,0,0,0,0,0,0,0,0,0,0

#endif
