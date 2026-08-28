/* AArch64 ABI katmani. x18 kullanilmaz (Windows TEB / macOS rezerve). */
#ifndef ABI_AARCH64_INC
#define ABI_AARCH64_INC

#define VP  x19
#define VS  x20
#define VF  x21
#define VC  x22
#define VA  x23

#define A0  x0
#define A1  x1
#define A2  x2
#define A3  x3
#define RV  x0
#define TMP x25
#define HAVE_VC 1
#define VK  x27      /* sabit havuzu tabani */
#define HAVE_VK 1

#define A0W w0
#define A1W w1
#define A2W w2
#define RVW w0
#define TMPW w25
#define A0B w0
#define A1B w1
#define A2B w2
#define RVB w0

#define FUNC(n)     .p2align 2; .globl SYM(n); SYM(n):
#define ENDFUNC(n)

#define PROLOGUE    stp x29, x30, [sp, #-16]!; mov x29, sp
#define EPILOGUE    ldp x29, x30, [sp], #16
#define ENTER(n)    stp x29, x30, [sp, #-16]!; mov x29, sp; \
                    sub sp, sp, #(((n)*8+15)&-16)
#define LEAVE_      mov sp, x29; ldp x29, x30, [sp], #16
#define SPILL(i,r)  str r, [x29, #(-8-8*(i))]
#define FILL(r,i)   ldr r, [x29, #(-8-8*(i))]
#define SAVE3(b)    SPILL(b, VP); SPILL((b)+1, VS); SPILL((b)+2, VF)
#define REST3(b)    FILL(VP, b); FILL(VS, (b)+1); FILL(VF, (b)+2)

#define RET         ret
#define CALL(n)     bl SYM(n)
#define B(l)        b l
#define JMPR(r)     br r
#define CALLR(r)    blr r

#define BZ(r,l)     cbz r, l
#define BNZ(r,l)    cbnz r, l
#define CMPR(a,b)   cmp a, b
#define CMPI(r,i)   cmp r, #(i)
#define BEQ(l)      b.eq l
#define BNE(l)      b.ne l
#define BLO(l)      b.lo l
#define BHS(l)      b.hs l
#define BHI(l)      b.hi l
#define BLS(l)      b.ls l
#define BLT(l)      b.lt l
#define BGE(l)      b.ge l
#define BGT(l)      b.gt l
#define BLE(l)      b.le l

#define MOVI(r,i)   mov r, #(i)
#define MOVR(d,s)   mov d, s
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
#define NEG(r)      neg r, r
#define ADDOV(d,s)  adds d, d, s
#define SUBOV(d,s)  subs d, d, s
#define NEGOV(d)    negs d, d
/* smull bayrak uretmez: 64-bit carpimi 32-bite isaret genisletilmis
 * haliyle karsilastiriyoruz. Esit degilse tasma var. */
/* 64-bit: tam carpim ust yarisi isaret uzantisiyla uyusmali */
#define MULOV(d,s,l) mul x26, d, s; smulh x27, d, s; cmp x27, x26, asr #63; b.ne l; mov d, x26
#define MUL32(d,s)  mul d, d, s
#define BOV(l)      b.vs l
#define ADDI(r,i)   add r, r, #(i)
#define SUBI(r,i)   sub r, r, #(i)
#define INC(r)      add r, r, #1
#define DEC(r)      sub r, r, #1
#define SHRI(r,i)   lsr r, r, #(i)
#define SHLI(r,i)   lsl r, r, #(i)

#define LDB(dW,b)         ldrb dW, [b]
#define LDH(dW,b)         ldrh dW, [b]
#define STH(b,sH)         strh sH, [b]
#define A0H w0
#define A1H w1
#define A2H w2
#define LDB_IDX(dW,b,i)   ldrb dW, [b, i]
#define LDB_OFF(dW,b,o)   ldrb dW, [b, #(o)]
#define STB(b,sB)         strb sB, [b]
#define LD32(dW,b)        ldr dW, [b]
#define LD32_OFF(dW,b,o)  ldur dW, [b, #(o)]
#define ST32_OFF(b,o,sW)  stur sW, [b, #(o)]
#define LD(d,b)           ldr d, [b]
#define LD_OFF(d,b,o)     ldr d, [b, #(o)]
#define ST_OFF(b,o,s)     str s, [b, #(o)]
#define ST(b,s)           str s, [b]
#define LDW_IDX(d,b,i)    ldr d, [b, i, lsl #3]
#define LD32_IDX(dW,b,i)  ldr dW, [b, i, lsl #2]

#if defined(OS_MACOS)
#  define LEA_SYM(r,s) adrp r, s@PAGE; add r, r, s@PAGEOFF
#else
#  define LEA_SYM(r,s) adrp r, s; add r, r, :lo12:s
/* ---- Dagitim cekirdegi ----
 * ldr ile son-artirim tek komutta pc'yi ilerletiyor.
 */
#if defined(OS_MACOS)
#define NEXT \
    ldr w24, [VP], #4; \
    and w24, w24, #0xff; \
    adrp x25, SYM(optable)@PAGE; \
    add x25, x25, SYM(optable)@PAGEOFF; \
    ldrsw x24, [x25, x24, lsl #2]; \
    add x25, x25, x24; \
    br x25
#else
#if OPT_COUNT
#  define TICK LEA_SYM(x26, SYM(g_ninstr)); ldr x25, [x26]; add x25, x25, #1; str x25, [x26];
#else
#  define TICK
#endif
#define NEXT \
    TICK \
    ldr INSW, [VP], #4; \
    and w25, INSW, #0xff; \
    adrp x26, SYM(optable); \
    add x26, x26, :lo12:SYM(optable); \
    ldrsw x25, [x26, x25, lsl #2]; \
    add x26, x26, x25; \
    br x26
#endif

#endif

#define INS  x24
#define INSW w24
#define GETOPD(dW)  lsr dW, INSW, #16
#if OPT_VCOPY64

#else

                        ldur A1W, [s, #4]; stur A1W, [d, #4]
#endif
#define LD32S_OFF(d,b,o)  ldursw d, [b, #(o)]
#define SHR_R(d,s)  lsr d, d, s
#define SHL_R(d,s)  lsl d, d, s
#define PTR .quad

/* ---- Dagitim cekirdegi ----
 * ldr ile son-artirim tek komutta pc'yi ilerletiyor.
 */
#if defined(OS_MACOS)
#define NEXT \
    ldr w24, [VP], #4; \
    and w24, w24, #0xff; \
    adrp x25, SYM(optable)@PAGE; \
    add x25, x25, SYM(optable)@PAGEOFF; \
    ldrsw x24, [x25, x24, lsl #2]; \
    add x25, x25, x24; \
    br x25
#else
#define NEXT \
    ldr INSW, [VP], #4; \
    and w25, INSW, #0xff; \
    adrp x26, SYM(optable); \
    add x26, x26, :lo12:SYM(optable); \
    ldrsw x25, [x26, x25, lsl #2]; \
    add x26, x26, x25; \
    br x26
#endif

#endif
