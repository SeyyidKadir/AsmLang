/* osprim.S - isletim sistemi primitifleri
 *
 * Su ana kadar OS isi yalnizca makinekod() + cagir() ile yapilabiliyordu:
 * her port erisimi, her CPUID icin ELLE bayt yazmak gerekiyordu. Bu
 * dosya o uc temeli dogrudan veriyor.
 *
 *   bellek_oku(adres, genislik)        1/2/4/8 bayt oku
 *   bellek_yaz(adres, deger, genislik) 1/2/4/8 bayt yaz
 *   port_oku(port, genislik)           x86 port G/C  (1/2/4)
 *   port_yaz(port, deger, genislik)
 *   cpuid(yaprak)                      -> [eax, ebx, ecx, edx]
 *
 * ================== SINIRLAR (bilinerek) ==================
 *
 * PORT G/C AYRICALIKLI bir islemdir. Barindirilan bir isletim
 * sisteminde (Linux/Windows/macOS) kullanici programi bunu yapamaz;
 * denerse islemci hata verir. Bu yuzden port islevleri YALNIZCA
 * bare-metal derlemede etkin; digerlerinde "bos" doner.
 * Cokmek yerine temiz "yapamiyorum" demek dogru davranis.
 *
 * BELLEK ERISIMI dogrulanmaz: verilen adres gecerli olmak zorunda.
 * Bu bilincli - amac tam da dogrulanamayan adreslere erismek.
 * cagir() ile ayni risk sinifinda.
 *
 * CPUID yalniz x86; diger mimarilerde "bos" doner.
 */
#include "../abi.inc"
#include "../tables/opcodes.inc"

#define SET_RES(tg, py) \
    LEA_SYM(A2, SYM(g_natres)); \
    ST32_OFF(A2, VAL_TAG, tg); \
    ST_OFF(A2, VAL_PAY, py)

/* bare-metal mi: port G/C yalniz orada anlamli */
#if defined(OS_BARE) && OS_BARE
#  define HAVE_PORTIO 1
#else
#  define HAVE_PORTIO 0
#endif

    SECT_TEXT

/* ---------------- bellek_oku(adres, genislik) ---------------- */
FUNC(nat_mrd)
    ENTER(3)
    CMPI(A1, 2)
    BNE(nmr_nil)
    SPILL(0, A0)
    CALL(arg_int)
    BZ(RV, nmr_nil)
    SPILL(1, A1)                    /* adres */
    FILL(A0, 0); ADDI(A0, VAL_SIZE)
    CALL(arg_int)
    BZ(RV, nmr_nil)
    SPILL(2, A1)                    /* genislik */
    FILL(A0, 1)
    FILL(A1, 2)
    CMPI(A1, 1); BEQ(nmr_1)
    CMPI(A1, 2); BEQ(nmr_2)
    CMPI(A1, 3); BEQ(nmr_3)     /* 24 bit cerceve tamponu icin */
    CMPI(A1, 4); BEQ(nmr_4)
#if WORD_SIZE == 8
    CMPI(A1, 8); BEQ(nmr_8)
#endif
    B(nmr_nil)
nmr_1:
    LDB(A0W, A0)
    CALL(ret_int)
    LEAVE_
    RET
nmr_2:
    LDH(A0W, A0)
    CALL(ret_int)
    LEAVE_
    RET
nmr_3:
    /* 24 bit: uc bayti kucuk-uctan birlestir */
    SPILL(1, A0)
    LDB(A1W, A0)
    SPILL(2, A1)
    FILL(A0, 1); ADDI(A0, 1); LDB(A1W, A0); SHLI(A1, 8)
    FILL(A2, 2); ORR(A1, A2); SPILL(2, A1)
    FILL(A0, 1); ADDI(A0, 2); LDB(A1W, A0); SHLI(A1, 16)
    FILL(A2, 2); ORR(A1, A2)
    MOVR(A0, A1)
    CALL(ret_int)
    LEAVE_
    RET
nmr_4:
    LD32(A0W, A0)
    CALL(ret_int)
    LEAVE_
    RET
#if WORD_SIZE == 8
nmr_8:
    LD(A0, A0)
    CALL(ret_int)
    LEAVE_
    RET
#endif
nmr_nil:
    CALL(nat_ret_nil)
    LEAVE_
    RET
ENDFUNC(nat_mrd)

/* ---------------- bellek_yaz(adres, deger, genislik) ---------------- */
FUNC(nat_mwr)
    ENTER(4)
    CMPI(A1, 3)
    BNE(nmw_nil)
    SPILL(0, A0)
    CALL(arg_int)
    BZ(RV, nmw_nil)
    SPILL(1, A1)                    /* adres */
    FILL(A0, 0); ADDI(A0, VAL_SIZE)
    CALL(arg_int)
    BZ(RV, nmw_nil)
    SPILL(2, A1)                    /* deger */
    FILL(A0, 0); ADDI(A0, 2*VAL_SIZE)
    CALL(arg_int)
    BZ(RV, nmw_nil)
    SPILL(3, A1)                    /* genislik */
    FILL(A0, 1)
    FILL(A2, 2)
    FILL(A1, 3)
    CMPI(A1, 1); BEQ(nmw_1)
    CMPI(A1, 2); BEQ(nmw_2)
    CMPI(A1, 3); BEQ(nmw_3)
    CMPI(A1, 4); BEQ(nmw_4)
#if WORD_SIZE == 8
    CMPI(A1, 8); BEQ(nmw_8)
#endif
    B(nmw_nil)
nmw_1:
    STB(A0, A2B)
    B(nmw_ok)
nmw_2:
    STH(A0, A2H)
    B(nmw_ok)
nmw_3:
    STB(A0, A2B)
    SHRI(A2, 8); ADDI(A0, 1); STB(A0, A2B)
    SHRI(A2, 8); ADDI(A0, 1); STB(A0, A2B)
    B(nmw_ok)
nmw_4:
    ST32_OFF(A0, 0, A2W)
    B(nmw_ok)
#if WORD_SIZE == 8
nmw_8:
    ST(A0, A2)
#endif
nmw_ok:
    MOVI(A0, T_BOOL)
    MOVI(A1, 1)
    SET_RES(A0W, A1)
    LEAVE_
    RET
nmw_nil:
    CALL(nat_ret_nil)
    LEAVE_
    RET
ENDFUNC(nat_mwr)

/* ---------------- port G/C ----------------
 * Ayricalikli islem: yalniz bare-metal derlemede etkin. */
FUNC(nat_prd)
    ENTER(3)
#if HAVE_PORTIO && (defined(ARCH_X86_64) || defined(ARCH_I386))
    CMPI(A1, 2)
    BNE(npr_nil)
    SPILL(0, A0)
    CALL(arg_int)
    BZ(RV, npr_nil)
    SPILL(1, A1)
    FILL(A0, 0); ADDI(A0, VAL_SIZE)
    CALL(arg_int)
    BZ(RV, npr_nil)
    SPILL(2, A1)
    FILL(A0, 1)
    CALL(port_in)
    CALL(ret_int)
    LEAVE_
    RET
#endif
npr_nil:
    CALL(nat_ret_nil)
    LEAVE_
    RET
ENDFUNC(nat_prd)

FUNC(nat_pwr)
    ENTER(4)
#if HAVE_PORTIO && (defined(ARCH_X86_64) || defined(ARCH_I386))
    CMPI(A1, 3)
    BNE(npw_nil)
    SPILL(0, A0)
    CALL(arg_int)
    BZ(RV, npw_nil)
    SPILL(1, A1)
    FILL(A0, 0); ADDI(A0, VAL_SIZE)
    CALL(arg_int)
    BZ(RV, npw_nil)
    SPILL(2, A1)
    FILL(A0, 0); ADDI(A0, 2*VAL_SIZE)
    CALL(arg_int)
    BZ(RV, npw_nil)
    SPILL(3, A1)
    FILL(A0, 1); FILL(A1, 2); FILL(A2, 3)
    CALL(port_out)
    MOVI(A0, T_BOOL)
    MOVI(A1, 1)
    SET_RES(A0W, A1)
    LEAVE_
    RET
#endif
npw_nil:
    CALL(nat_ret_nil)
    LEAVE_
    RET
ENDFUNC(nat_pwr)

/* ---------------- cpuid(yaprak) -> [eax, ebx, ecx, edx] ---------------- */
FUNC(nat_cpuid)
    ENTER(3)
#if defined(ARCH_X86_64) || defined(ARCH_I386)
    CMPI(A1, 1)
    BNE(ncp_nil)
    CALL(arg_int)
    BZ(RV, ncp_nil)
    MOVR(A0, A1)
    CALL(cpuid_raw)                 /* sonuc g_cpuid[0..3] */
    MOVI(A0, 4)
    CALL(arr_new)
    BZ(RV, ncp_nil)
    SPILL(0, RV)
    MOVI(A0, 0)
    SPILL(1, A0)
ncp_fill:
    FILL(A0, 1)
    CMPI(A0, 4)
    BHS(ncp_done)
    FILL(A0, 0)
    CALL(obj_ptr)
    MOVR(A0, RV); ADDI(A0, OBJ_DATA)
    FILL(A1, 1); SHLI(A1, VAL_SHIFT); ADD(A0, A1)
    MOVI(A1, T_INT)
    ST32_OFF(A0, VAL_TAG, A1W)
    LEA_SYM(A1, SYM(g_cpuid))
    FILL(A2, 1); SHLI(A2, 2); ADD(A1, A2)
    LD32(A1W, A1)
    ST_OFF(A0, VAL_PAY, A1)
    FILL(A0, 1); INC(A0); SPILL(1, A0)
    B(ncp_fill)
ncp_done:
    FILL(A1, 0)
    MOVI(A0, T_OBJ)
    SET_RES(A0W, A1)
    LEAVE_
    RET
#endif
ncp_nil:
    CALL(nat_ret_nil)
    LEAVE_
    RET
ENDFUNC(nat_cpuid)

/* ================== mimariye ozel ham islemler ================== */

#if defined(ARCH_X86_64) || defined(ARCH_I386)

    .bss
    .p2align 4
    .globl SYM(g_cpuid)
SYM(g_cpuid): .space 16
    SECT_TEXT

/* cpuid_raw(A0 = yaprak) - sonuc g_cpuid'e */
FUNC(cpuid_raw)
#if defined(ARCH_X86_64)
    pushq %rbx
    movl %edi, %eax
    xorl %ecx, %ecx
    cpuid
    leaq SYM(g_cpuid)(%rip), %rdi
    movl %eax, 0(%rdi)
    movl %ebx, 4(%rdi)
    movl %ecx, 8(%rdi)
    movl %edx, 12(%rdi)
    popq %rbx
    ret
#else
    pushl %ebx
    pushl %esi
    movl %eax, %esi
    movl %esi, %eax
    xorl %ecx, %ecx
    cpuid
    movl %eax, SYM(g_cpuid)+0
    movl %ebx, SYM(g_cpuid)+4
    movl %ecx, SYM(g_cpuid)+8
    movl %edx, SYM(g_cpuid)+12
    popl %esi
    popl %ebx
    ret
#endif
ENDFUNC(cpuid_raw)

#if HAVE_PORTIO
/* port_in(A0 = port, A1 = genislik) -> RV */
FUNC(port_in)
#if defined(BARE_SIM) && BARE_SIM
    /* Benzetimde gercek in/out kullanici kipinde hata verir. */
#if defined(ARCH_X86_64)
    movl $0xFF, %eax
    ret
#else
    movl $0xFF, %eax
    ret
#endif
#endif
#if defined(ARCH_X86_64)
    movl %edi, %edx
    xorl %eax, %eax
    cmpl $1, %esi
    je 1f
    cmpl $2, %esi
    je 2f
    inl %dx, %eax
    ret
1:  inb %dx, %al
    ret
2:  inw %dx, %ax
    ret
#else
    /* i386: A0=%eax port, A1=%edx genislik.
     * Once port numarasini %edx'e kopyalayip onu GENISLIK sanip
     * karsilastiriyordum: 1 ile eslesmiyor, hep 32-bit "inl"
     * yapiyordu. QEMU'da port 0x61 icin 0x20302030 dondu -
     * 8 bit degeri okumasi gerekirken. */
    movl %edx, %ecx                 /* ecx = genislik */
    movl %eax, %edx                 /* dx  = port */
    xorl %eax, %eax
    cmpl $1, %ecx
    je 1f
    cmpl $2, %ecx
    je 2f
    inl %dx, %eax
    ret
1:  inb %dx, %al
    ret
2:  inw %dx, %ax
    ret
#endif
ENDFUNC(port_in)

/* port_out(A0 = port, A1 = deger, A2 = genislik) */
FUNC(port_out)
#if defined(BARE_SIM) && BARE_SIM
    ret
#endif
#if defined(ARCH_X86_64)
    movl %edi, %edx
    movl %esi, %eax
    cmpl $1, %ecx
    je 1f
    cmpl $2, %ecx
    je 2f
    outl %eax, %dx
    ret
1:  outb %al, %dx
    ret
2:  outw %ax, %dx
    ret
#else
    pushl %ebx
    movl %eax, %ebx
    movl %edx, %eax
    movl %ebx, %edx
    cmpl $1, %ecx
    je 1f
    cmpl $2, %ecx
    je 2f
    outl %eax, %dx
    popl %ebx
    ret
1:  outb %al, %dx
    popl %ebx
    ret
2:  outw %ax, %dx
    popl %ebx
    ret
#endif
ENDFUNC(port_out)
#endif /* HAVE_PORTIO */

#endif /* x86 */
