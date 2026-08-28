/* OTOMATIK URETILDI - tools/gen_tables.py */
#ifndef OPNAMES_INC
#define OPNAMES_INC

    SECT_RODATA
    .p2align 4
    .globl SYM(op_names)
SYM(op_names):
    .long 4; .ascii "HALT"; .balign 16
    .long 5; .ascii "CONST"; .balign 16
    .long 3; .ascii "NIL"; .balign 16
    .long 4; .ascii "TRUE"; .balign 16
    .long 5; .ascii "FALSE"; .balign 16
    .long 3; .ascii "POP"; .balign 16
    .long 8; .ascii "GETLOCAL"; .balign 16
    .long 8; .ascii "SETLOCAL"; .balign 16
    .long 9; .ascii "GETGLOBAL"; .balign 16
    .long 9; .ascii "SETGLOBAL"; .balign 16
    .long 9; .ascii "DEFGLOBAL"; .balign 16
    .long 3; .ascii "ADD"; .balign 16
    .long 3; .ascii "SUB"; .balign 16
    .long 3; .ascii "MUL"; .balign 16
    .long 3; .ascii "DIV"; .balign 16
    .long 3; .ascii "MOD"; .balign 16
    .long 3; .ascii "NEG"; .balign 16
    .long 3; .ascii "NOT"; .balign 16
    .long 2; .ascii "EQ"; .balign 16
    .long 2; .ascii "NE"; .balign 16
    .long 2; .ascii "LT"; .balign 16
    .long 2; .ascii "LE"; .balign 16
    .long 2; .ascii "GT"; .balign 16
    .long 2; .ascii "GE"; .balign 16
    .long 3; .ascii "JMP"; .balign 16
    .long 2; .ascii "JZ"; .balign 16
    .long 3; .ascii "JZP"; .balign 16
    .long 4; .ascii "JNZP"; .balign 16
    .long 5; .ascii "PRINT"; .balign 16
    .long 4; .ascii "CALL"; .balign 16
    .long 3; .ascii "RET"; .balign 16
    .long 5; .ascii "ARRAY"; .balign 16
    .long 5; .ascii "INDEX"; .balign 16
    .long 6; .ascii "SETIDX"; .balign 16
    .long 11; .ascii "SETGLOBAL_P"; .balign 16
    .long 10; .ascii "SETLOCAL_P"; .balign 16
    .long 4; .ascii "ADDK"; .balign 16
    .long 4; .ascii "SUBK"; .balign 16
    .long 3; .ascii "JEQ"; .balign 16
    .long 3; .ascii "JNE"; .balign 16
    .long 3; .ascii "JLT"; .balign 16
    .long 3; .ascii "JLE"; .balign 16
    .long 3; .ascii "JGT"; .balign 16
    .long 3; .ascii "JGE"; .balign 16
    .long 10; .ascii "GETGLOBAL2"; .balign 16
    .long 9; .ascii "GETLOCAL2"; .balign 16
    .long 8; .ascii "ADD_SETG"; .balign 16
    .long 8; .ascii "ADD_SETL"; .balign 16
    .long 9; .ascii "ADDK_SETG"; .balign 16
    .long 9; .ascii "INCGLOBAL"; .balign 16
    .long 3; .ascii "JNZ"; .balign 16
    .long 10; .ascii "GETG_CONST"; .balign 16
    .long 10; .ascii "GETL_CONST"; .balign 16
    .long 4; .ascii "RETL"; .balign 16
    .long 4; .ascii "RETK"; .balign 16
    .long 4; .ascii "ACCG"; .balign 16
/* op_isjump -> opjump.inc */
    .byte 0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0
    .byte 0,0,0,0,0,0,0,0,1,1,1,1,0,0,0,0
    .byte 0,0,0,0,0,0,1,1,1,1,1,1,0,0,0,0
    .byte 0,0,1,0,0,0,0,0,0,0,0,0,0,0,0,0

#endif
