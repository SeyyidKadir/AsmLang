/* i386 ABI katmani
 * En dar hedef: 6 kullanilabilir GPR.
 * VC (sabit havuzu) ve TMP registera sigmaz; TMP = A2 ile paylasilir.
 */
#ifndef ABI_I386_INC
#define ABI_I386_INC

#define VP  %esi
#define VS  %edi
#define VF  %ebx
#define VA  %ebx        /* VF ile ayni: i386'da ayri scratch yok */

#define A0  %eax
#define A1  %edx
#define A2  %ecx
#define RV  %eax
#define TMP %ecx        /* DIKKAT: A2 ile ayni register */

#define A0W %eax
#define A1W %edx
#define A2W %ecx
#define RVW %eax
#define TMPW %ecx
#define A0B %al
#define A1B %dl
#define A2B %cl
#define RVB %al

#define FUNC(n)     .p2align 4; .globl SYM(n); SYM(n):
#define ENDFUNC(n)

#define PROLOGUE    pushl %ebp; movl %esp, %ebp
#define EPILOGUE    movl %ebp, %esp; popl %ebp
#define ENTER(n)    pushl %ebp; movl %esp, %ebp; \
                    subl $(((n)*4+15)&-16), %esp
#define LEAVE_      movl %ebp, %esp; popl %ebp
#define SPILL(i,r)  movl r, (-4-4*(i))(%ebp)
#define FILL(r,i)   movl (-4-4*(i))(%ebp), r
#define SAVE3(b)    SPILL(b, VP); SPILL((b)+1, VS); SPILL((b)+2, VF)
#define REST3(b)    FILL(VP, b); FILL(VS, (b)+1); FILL(VF, (b)+2)

#define RET         ret
#define CALL(n)     call SYM(n)
#define B(l)        jmp l
#define JMPR(r)     jmp *r
#define CALLR(r)    call *r

#define BZ(r,l)     testl r, r; jz l
#define BNZ(r,l)    testl r, r; jnz l
#define CMPR(a,b)   cmpl b, a
#define CMPI(r,i)   cmpl $(i), r
#define BEQ(l)      je l
#define BNE(l)      jne l
#define BLO(l)      jb l
#define BHS(l)      jae l
#define BHI(l)      ja l
#define BLS(l)      jbe l
#define BLT(l)      jl l
#define BGE(l)      jge l
#define BGT(l)      jg l
#define BLE(l)      jle l

#define MOVI(r,i)   movl $(i), r
#define MOVR(d,s)   movl s, d
#define LEA_SYM(r,s) movl $s, r
#define ADD(d,s)    addl s, d
#define SUB(d,s)    subl s, d
#define AND(d,s)    andl s, d
#define ANDI(r,i)   andl $(i), r
#define ORR(d,s)    orl s, d
#define ANDR(d,s)   andl s, d
#define XORR(d,s)   xorl s, d
#define NOTR(d)     notl d
#define SHLR(d,s)   pushl %ecx; movl s, %ecx; shll %cl, d; popl %ecx
#define SARR(d,s)   pushl %ecx; movl s, %ecx; sarl %cl, d; popl %ecx
#define ORI(d,i)    orl $(i), d
#define MUL(d,s)    imull s, d
#define NEG(r)      negl r
#define ADDOV(d,s)  addl s, d
#define SUBOV(d,s)  subl s, d
#define NEGOV(d)    negl d
#define MULOV(d,s,l) imull s, d; jo l
#define MUL32(d,s)  imull s, d
#define BOV(l)      jo l
#define ADDI(r,i)   addl $(i), r
#define SUBI(r,i)   subl $(i), r
#define INC(r)      incl r
#define DEC(r)      decl r
#define SHRI(r,i)   shrl $(i), r
#define SHLI(r,i)   shll $(i), r

#define LDB(dW,b)         movzbl (b), dW
#define LDH(dW,b)         movzwl (b), dW
#define STH(b,sH)         movw sH, (b)
#define A0H %ax
#define A1H %dx
#define A2H %cx
#define LDB_IDX(dW,b,i)   movzbl (b,i), dW
#define LDB_OFF(dW,b,o)   movzbl o(b), dW
#define STB(b,sB)         movb sB, (b)
#define LD32(dW,b)        movl (b), dW
#define LD32_OFF(dW,b,o)  movl o(b), dW
#define ST32_OFF(b,o,sW)  movl sW, o(b)
#define LD(d,b)           movl (b), d
#define LD_OFF(d,b,o)     movl o(b), d
#define ST_OFF(b,o,s)     movl s, o(b)
#define ST(b,s)           movl s, (b)
#define LDW_IDX(d,b,i)    movl (b,i,4), d
#define LD32_IDX(dW,b,i)  movl (b,i,4), dW

/* i386'da bos register yok: islenen komuttan yeniden okunur. */
#define GETOPD(dW)  movl -4(VP), dW; shrl $16, dW
/* 32-bitte tek erisimle kopyalanamaz: iki cift */

#define LD32S_OFF(d,b,o)  movl o(b), d
#define SHR_R(d,s)  movl s, %ecx; shrl %cl, d
#define SHL_R(d,s)  movl s, %ecx; shll %cl, d
#define PTR .long

/* ---- Dagitim cekirdegi ---- (bkz. x86_64 aciklamasi) */
#if OPT_COUNT
#  define TICK incl SYM(g_ninstr);
#else
#  define TICK
#endif
#define NEXT \
    TICK \
    movl (VP), %eax; \
    addl $4, VP; \
    movzbl %al, %eax; \
    movl $SYM(optable), %ecx; \
    movl (%ecx,%eax,4), %eax; \
    addl %ecx, %eax; \
    jmp *%eax

#endif
