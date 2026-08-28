/* OTOMATIK URETILDI - tools/gen_tables.py */
#ifndef OPKIND_INC
#define OPKIND_INC

#define OPK_NONE    0
#define OPK_CODE    1
#define OPK_CONST   2
#define OPK_GLOBAL  3
#define OPK_LOCAL   4
#define OPK_COUNT   5
#define OPK_GG      6
#define OPK_LL      7
#define OPK_GC      8
#define OPK_LC      9
#define OPK_CG      10

    SECT_RODATA
    .p2align 4
    .globl SYM(op_opkind)
SYM(op_opkind):
    .byte 0,2,0,0,0,0,4,4,3,3,3,0,0,0,0,0
    .byte 0,0,0,0,0,0,0,0,1,1,1,1,0,5,0,5
    .byte 0,0,3,4,2,2,1,1,1,1,1,1,6,7,3,4
    .byte 10,8,1,8,9,4,2,6,0,0,0,0,0,0,0,0

#endif
