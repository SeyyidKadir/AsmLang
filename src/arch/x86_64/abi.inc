/* x86_64 ABI katmani */
#ifndef ABI_X86_64_INC
#define ABI_X86_64_INC

/* Sanal registerlar (callee-saved) */
#define VP  %rbx        /* bytecode / kaynak imleci */
#define VS  %r12        /* VM yigin tepesi / kaynak sonu */
#define VF  %r13        /* cerceve / cikti imleci */
#define VC  %r14        /* sabit havuzu */
#define VA  %r15        /* kalici scratch */

/* Ic cagri kurali */
#define A0  %rdi
#define A1  %rsi
#define A2  %rdx
#define A3  %rcx
#define RV  %rax
#define TMP %r11
#define HAVE_VC 1
#define VK  %r8      /* sabit havuzu tabani */
#define HAVE_VK 1        /* makro ici gecici */

/* 32-bit ve 8-bit takma adlar */
#define A0W %edi
#define A1W %esi
#define A2W %edx
#define RVW %eax
#define TMPW %r11d
#define A0B %dil
#define A1B %sil
#define A2B %dl
#define RVB %al

#define FUNC(n)     .p2align 4; .globl SYM(n); SYM(n):
#define ENDFUNC(n)

#define PROLOGUE    pushq %rbp; movq %rsp, %rbp
#define EPILOGUE    movq %rbp, %rsp; popq %rbp
#define ENTER(n)    pushq %rbp; movq %rsp, %rbp; \
                    subq $(((n)*8+15)&-16), %rsp
#define LEAVE_      movq %rbp, %rsp; popq %rbp
#define SPILL(i,r)  movq r, (-8-8*(i))(%rbp)
#define FILL(r,i)   movq (-8-8*(i))(%rbp), r
#define SAVE3(b)    SPILL(b, VP); SPILL((b)+1, VS); SPILL((b)+2, VF)
#define REST3(b)    FILL(VP, b); FILL(VS, (b)+1); FILL(VF, (b)+2)

#define RET         ret
#define CALL(n)     call SYM(n)
#define B(l)        jmp l
#define JMPR(r)     jmp *r
#define CALLR(r)    call *r

/* register tabanli sifir testi */
#define BZ(r,l)     testq r, r; jz l
#define BNZ(r,l)    testq r, r; jnz l
/* bayrak uretimi + dallanma (isaretsiz) */
#define CMPR(a,b)   cmpq b, a
#define CMPI(r,i)   cmpq $(i), r
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

#define MOVI(r,i)   movq $(i), r
#define MOVR(d,s)   movq s, d
#define LEA_SYM(r,s) leaq s(%rip), r
#define ADD(d,s)    addq s, d
#define SUB(d,s)    subq s, d
#define AND(d,s)    andq s, d
#define ANDI(r,i)   andq $(i), r
#define ORR(d,s)    orq s, d
/* Bit islemleri. Kaydirmada sayac x86'da CL olmak ZORUNDA;
 * cagiran A2'yi (rdx) kullaniyor, o yuzden once rcx'e tasinir. */
#define ANDR(d,s)   andq s, d
#define XORR(d,s)   xorq s, d
#define NOTR(d)     notq d
#define SHLR(d,s)   pushq %rcx; movq s, %rcx; shlq %cl, d; popq %rcx
#define SARR(d,s)   pushq %rcx; movq s, %rcx; sarq %cl, d; popq %rcx
#define ORI(d,i)    orq $(i), d
#define MUL(d,s)    imulq s, d
#define NEG(r)      negq r
/* 32-bit BAYRAK URETEN aritmetik: tasma denetimi icin.
 * 64-bit registerda 64-bit toplama yapilirsa 32-bit tasma gorulmez;
 * bu yuzden islem bilerek 32-bit yapiliyor. */
#define ADDOV(d,s)  addq s, d
#define SUBOV(d,s)  subq s, d
#define NEGOV(d)    negq d
#define MULOV(d,s,l) imulq s, d; jo l
#define MUL32(d,s)  imulq s, d
#define BOV(l)      jo l
#define ADDI(r,i)   addq $(i), r
#define SUBI(r,i)   subq $(i), r
#define INC(r)      incq r
#define DEC(r)      decq r
#define SHRI(r,i)   shrq $(i), r
#define SHLI(r,i)   shlq $(i), r

/* bellek erisimi; W ekli isimler 32-bit, sifir genisletir */
#define LDB(dW,b)         movzbl (b), dW
/* 16 bit: MMIO ve port G/C icin */
#define LDH(dW,b)         movzwl (b), dW
#define STH(b,sH)         movw sH, (b)
#define A0H %di
#define A1H %si
#define A2H %dx
#define LDB_IDX(dW,b,i)   movzbl (b,i), dW
#define LDB_OFF(dW,b,o)   movzbl o(b), dW
#define STB(b,sB)         movb sB, (b)
#define LD32(dW,b)        movl (b), dW
#define LD32_OFF(dW,b,o)  movl o(b), dW
#define ST32_OFF(b,o,sW)  movl sW, o(b)
#define LD(d,b)           movq (b), d
/* Kelime genisliginde ofsetli erisim: deger YUKU icin.
 * 64-bit hedefte tek komut, 32-bit hedefte de tek komut - genislik
 * makine kelimesiyle ayni oldugu icin emulasyon gerekmiyor. */
#define LD_OFF(d,b,o)     movq o(b), d
#define ST_OFF(b,o,s)     movq s, o(b)
#define ST(b,s)           movq s, (b)
#define LDW_IDX(d,b,i)    movq (b,i,8), d
#define LD32_IDX(dW,b,i)  movl (b,i,4), dW

/* Islenen artik NEXT'in yukledigi komut kelimesinden geliyor:
 * bellek erisimi yok. i386 disinda her mimaride bos register vardi. */
#define INS  %r15
#define INSW %r15d
#define GETOPD(dW)  movl INSW, dW; shrl $16, dW
/* 8 baytlik deger slotunu TEK erisimle kopyala (64-bit kazanci) */
#if OPT_VCOPY64

#else
   /* OLCUM YOLU: gecici register her cagri yerinde A1 oldugu icin
    * dogrudan A1W kullaniliyor. Yalniz karsilastirma amacli. */
#endif
/* isaretli 32-bit yukleme: negatif tamsayilar 64-bit registerda bozulmasin */
#define LD32S_OFF(d,b,o)  movslq o(b), d
/* register sayisiyla kaydirma: x86 sayaci %cl'de ister */
#define SHR_R(d,s)  movq s, %rcx; shrq %cl, d
#define SHL_R(d,s)  movq s, %rcx; shlq %cl, d
#define PTR .quad

/* ---- Dagitim cekirdegi ----
 * optable .text icinde ve ofsetleri kendi tabanina gore, boylece
 * "handler - optable" derleme aninda katlanir: sifir yer degistirme
 * kaydi, ASLR ve PIE altinda sorunsuz.
 * Her isleyicinin SONUNA kopyalanir (merkezi donguye donulmez) -
 * dallanma tahmincisi icin asil kazanc burada.
 */
/* OPT_COUNT: her dagitimda sayac. Olcum icin; kendisi yavaslatir. */
#if OPT_COUNT
#  define TICK incq SYM(g_ninstr)(%rip);
#else
#  define TICK
#endif
#define NEXT \
    TICK \
    movl (VP), INSW; \
    addq $4, VP; \
    movzbl %r15b, %r11d; \
    leaq SYM(optable)(%rip), %r10; \
    movslq (%r10,%r11,4), %r11; \
    addq %r11, %r10; \
    jmp *%r10

#endif
