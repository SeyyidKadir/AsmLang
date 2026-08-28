/* OTOMATIK URETILDI - tools/gen_tables.py, elle duzenleme */
#ifndef PREC_INC
#define PREC_INC

    SECT_RODATA

    .p2align 4
    .globl SYM(prec_table)
SYM(prec_table):
    .byte 0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0
    .byte 0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0
    .byte 0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0
    .byte 0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0
    .byte 0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0
    .byte 0,0,0,0,0,0,0,0,0,0,0,0,3,11,0,0
    .byte 2,11,0,0,0,0,0,0,0,0,0,0,0,0,0,0
    .byte 0,0,0,0,0,0,0,0,13,10,0,0,0,0,0,0
    .byte 0,0,0,0,0,0,0,0,13,13,0,0,0,0,0,0
    .byte 0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0
    .byte 10,8,0,0,10,8,0,0,11,8,0,0,11,8,0,0
    .byte 11,8,0,0,0,0,0,0,0,0,0,0,0,0,0,0
    .byte 0,0,0,0,0,0,0,0,1,9,1,0,7,8,0,0
    .byte 7,8,0,0,8,8,0,0,8,8,0,0,8,8,0,0
    .byte 8,8,0,0,0,0,0,0,1,9,1,0,1,9,1,0
    .byte 1,9,1,0,1,9,1,0,1,9,1,0,6,8,0,0
    .byte 4,8,0,0,5,8,0,0,0,0,0,0,9,8,0,0
    .byte 9,8,0,0,0,0,0,0,0,0,0,0,0,0,0,0
    .byte 0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0
    .byte 0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0
    .byte 0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0
    .byte 0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0
    .byte 0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0
    .byte 0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0
    .byte 0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0
    .byte 0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0
    .byte 0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0
    .byte 0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0
    .byte 0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0
    .byte 0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0
    .byte 0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0
    .byte 0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0

    .p2align 4
    .globl SYM(kind_kids)
SYM(kind_kids):
    .byte 0,0,0,0,0,0,0,1,3,3,3,3,1,3,0,0
    .byte 0,0,0,0,1,2,2,7,3,1,0,0,1,1,6,0
    .byte 1,7,0,0,0,0,0,0,0,0,0,0,0,0,0,0
    .byte 0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0

    .p2align 4
    .globl SYM(kind_tokfld)
SYM(kind_tokfld):
    .byte 255,8,8,8,255,255,255,12,16,255,255,16,255,255,255,255
    .byte 255,255,255,255,255,8,8,255,255,255,255,255,255,255,8,8
    .byte 255,255,255,255,255,255,255,255,255,255,255,255,255,255,255,255
    .byte 255,255,255,255,255,255,255,255,255,255,255,255,255,255,255,255

    .p2align 4
    .globl SYM(kind_names)
SYM(kind_names):
    .long 4; .ascii "NONE"; .balign 16
    .long 6; .ascii "NUMBER"; .balign 16
    .long 6; .ascii "STRING"; .balign 16
    .long 5; .ascii "IDENT"; .balign 16
    .long 4; .ascii "TRUE"; .balign 16
    .long 5; .ascii "FALSE"; .balign 16
    .long 3; .ascii "NIL"; .balign 16
    .long 5; .ascii "UNARY"; .balign 16
    .long 6; .ascii "BINARY"; .balign 16
    .long 6; .ascii "ASSIGN"; .balign 16
    .long 4; .ascii "CALL"; .balign 16
    .long 7; .ascii "LOGICAL"; .balign 16
    .long 5; .ascii "ARRAY"; .balign 16
    .long 5; .ascii "INDEX"; .balign 16
    .long 1; .ascii "?"; .balign 16
    .long 1; .ascii "?"; .balign 16
    .long 1; .ascii "?"; .balign 16
    .long 1; .ascii "?"; .balign 16
    .long 1; .ascii "?"; .balign 16
    .long 1; .ascii "?"; .balign 16
    .long 5; .ascii "BLOCK"; .balign 16
    .long 3; .ascii "LET"; .balign 16
    .long 5; .ascii "CONST"; .balign 16
    .long 2; .ascii "IF"; .balign 16
    .long 5; .ascii "WHILE"; .balign 16
    .long 6; .ascii "RETURN"; .balign 16
    .long 5; .ascii "BREAK"; .balign 16
    .long 8; .ascii "CONTINUE"; .balign 16
    .long 5; .ascii "PRINT"; .balign 16
    .long 8; .ascii "EXPRSTMT"; .balign 16
    .long 2; .ascii "FN"; .balign 16
    .long 5; .ascii "PARAM"; .balign 16
    .long 7; .ascii "PROGRAM"; .balign 16
    .long 3; .ascii "FOR"; .balign 16
    .long 1; .ascii "?"; .balign 16
    .long 1; .ascii "?"; .balign 16
    .long 1; .ascii "?"; .balign 16
    .long 1; .ascii "?"; .balign 16
    .long 1; .ascii "?"; .balign 16
    .long 1; .ascii "?"; .balign 16
    .long 1; .ascii "?"; .balign 16
    .long 1; .ascii "?"; .balign 16
    .long 1; .ascii "?"; .balign 16
    .long 1; .ascii "?"; .balign 16
    .long 1; .ascii "?"; .balign 16
    .long 1; .ascii "?"; .balign 16
    .long 1; .ascii "?"; .balign 16
    .long 1; .ascii "?"; .balign 16
    .long 1; .ascii "?"; .balign 16
    .long 1; .ascii "?"; .balign 16
    .long 1; .ascii "?"; .balign 16
    .long 1; .ascii "?"; .balign 16
    .long 1; .ascii "?"; .balign 16
    .long 1; .ascii "?"; .balign 16
    .long 1; .ascii "?"; .balign 16
    .long 1; .ascii "?"; .balign 16
    .long 1; .ascii "?"; .balign 16
    .long 1; .ascii "?"; .balign 16
    .long 1; .ascii "?"; .balign 16
    .long 1; .ascii "?"; .balign 16
    .long 1; .ascii "?"; .balign 16
    .long 1; .ascii "?"; .balign 16
    .long 1; .ascii "?"; .balign 16
    .long 1; .ascii "?"; .balign 16

#endif
