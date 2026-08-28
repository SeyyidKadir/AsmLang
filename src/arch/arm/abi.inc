/* ARM32 (AAPCS) ABI katmani - yalnizca Linux.
 * r7 syscall numarasi, r9 platform registeri, r12 (ip) linker veneer: kullanilmaz.
 */
#ifndef ABI_ARM_INC
#define ABI_ARM_INC

#define VP  r4
#define VS  r5
#define VF  r6
#define VC  r8
#define VA  r10

#define A0  r0
#define A1  r1
#define A2  r2
#define A3  r3
#define RV  r0
#define TMP r11
#define HAVE_VC 1   /* VK icin bos register YOK */

#define A0W r0
#define A1W r1
#define A2W r2
#define RVW r0
#define TMPW r11
#define A0B r0
#define A1B r1
#define A2B r2
#define RVB r0

#define FUNC(n)     .p2align 2; .globl SYM(n); .type SYM(n), %function; SYM(n):
#define ENDFUNC(n)  .size SYM(n), . - SYM(n)

#define PROLOGUE    push {fp, lr}; mov fp, sp
#define EPILOGUE    mov sp, fp; pop {fp, lr}
#define ENTER(n)    push {fp, lr}; mov fp, sp; \
                    sub sp, sp, #(((n)*4+7)&-8)
#define LEAVE_      mov sp, fp; pop {fp, lr}
#define SPILL(i,r)  str r, [fp, #(-4-4*(i))]
#define FILL(r,i)   ldr r, [fp, #(-4-4*(i))]
#define SAVE3(b)    SPILL(b, VP); SPILL((b)+1, VS); SPILL((b)+2, VF)
#define REST3(b)    FILL(VP, b); FILL(VS, (b)+1); FILL(VF, (b)+2)

#define RET         bx lr
#define CALL(n)     bl SYM(n)
#define B(l)        b l
#define JMPR(r)     bx r
#define CALLR(r)    blx r

#define BZ(r,l)     cmp r, #0; beq l
#define BNZ(r,l)    cmp r, #0; bne l
#define CMPR(a,b)   cmp a, b
#define CMPI(r,i)   cmp r, #(i)
#define BEQ(l)      beq l
#define BNE(l)      bne l
#define BLO(l)      blo l
#define BHS(l)      bhs l
#define BHI(l)      bhi l
#define BLS(l)      bls l
#define BLT(l)      blt l
#define BGE(l)      bge l
#define BGT(l)      bgt l
#define BLE(l)      ble l

/* ldr =imm literal havuzu kullanir: her sabit kodlanabilir */
#define MOVI(r,i)   ldr r, =(i)
#define MOVR(d,s)   mov d, s
#define LEA_SYM(r,s) ldr r, =s
#define ADD(d,s)    add d, d, s
#define SUB(d,s)    sub d, d, s
#define AND(d,s)    and d, d, s
#define ANDI(r,i)   and r, r, #(i)
#define ORR(d,s)    orr d, d, s
#define ANDR(d,s)   and d, d, s
#define XORR(d,s)   eor d, d, s
#define NOTR(d)     mvn d, d
#define SHLR(d,s)   lsl d, d, s
#define SARR(d,s)   asr d, d, s
#define ORI(d,i)    orr d, d, #(i)
#define MUL(d,s)    mul d, d, s
#define NEG(r)      rsb r, r, #0
#define ADDOV(d,s)  adds d, d, s
#define SUBOV(d,s)  subs d, d, s
#define NEGOV(d)    rsbs d, d, #0
#define MULOV(d,s,l) smull r11, r12, d, s; cmp r12, r11, asr #31; bne l; mov d, r11
#define MUL32(d,s)  mul d, d, s
#define BOV(l)      bvs l
#define ADDI(r,i)   add r, r, #(i)
#define SUBI(r,i)   sub r, r, #(i)
#define INC(r)      add r, r, #1
#define DEC(r)      sub r, r, #1
#define SHRI(r,i)   lsr r, r, #(i)
#define SHLI(r,i)   lsl r, r, #(i)

#define LDB(dW,b)         ldrb dW, [b]
#define LDH(dW,b)         ldrh dW, [b]
#define STH(b,sH)         strh sH, [b]
#define A0H r0
#define A1H r1
#define A2H r2
#define LDB_IDX(dW,b,i)   ldrb dW, [b, i]
#define LDB_OFF(dW,b,o)   ldrb dW, [b, #(o)]
#define STB(b,sB)         strb sB, [b]
#define LD32(dW,b)        ldr dW, [b]
#define LD32_OFF(dW,b,o)  ldr dW, [b, #(o)]
#define ST32_OFF(b,o,sW)  str sW, [b, #(o)]
#define LD(d,b)           ldr d, [b]
#define LD_OFF(d,b,o)     ldr d, [b, #(o)]
#define ST_OFF(b,o,s)     str s, [b, #(o)]
#define ST(b,s)           str s, [b]
#define LDW_IDX(d,b,i)    ldr d, [b, i, lsl #2]
#define LD32_IDX(dW,b,i)  ldr dW, [b, i, lsl #2]

#define INS  r10
#define INSW r10
#define GETOPD(dW)  lsr dW, INS, #16

#define LD32S_OFF(d,b,o)  ldr d, [b, #(o)]
#define SHR_R(d,s)  lsr d, d, s
#define SHL_R(d,s)  lsl d, d, s
#define PTR .long

/* ---- Dagitim cekirdegi ----
 * ARM kipinde pc'ye add yazmak dogrudan dallanmadir.
 */
#if OPT_COUNT
#  define TICK ldr r12, =SYM(g_ninstr); ldr r11, [r12]; add r11, r11, #1; str r11, [r12];
#else
#  define TICK
#endif
#define NEXT \
    TICK \
    ldr INS, [VP], #4; \
    and r11, INS, #255; \
    ldr r12, =SYM(optable); \
    ldr r11, [r12, r11, lsl #2]; \
    add pc, r12, r11

#endif
