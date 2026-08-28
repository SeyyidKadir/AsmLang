/* ffi.S - ham cagri (raw indirect call)
 *
 * FFI IKIYE AYRILIR:
 *
 *   1) HAM CAGRI  - verilen adrese, verilen argumanlarla atla.
 *      Yukleyici gerektirmez, HER hedefte calisir (bare-metal dahil).
 *      OS gelistirmede lazim olacak parca budur: BIOS/UEFI cagrilari,
 *      surucu giris noktalari, aygit yazilimi tablolari.
 *
 *   2) KUTUPHANE YUKLEME - dlopen/LoadLibrary ile ad cozme.
 *      Isletim sistemi hizmeti; bizim statik + nostdlib Linux
 *      ikilimizde dlopen YOK ve bare-metal'de kavram olarak yok.
 *      Ayri dosyada, ayri sinirlarla.
 *
 * Bu dosya YALNIZ (1)'i saglar.
 *
 * ffi_call(A0 = adres, A1 = arguman dizisi, A2 = arguman sayisi) -> RV
 * Argumanlar makine kelimesi genisliginde tamsayi olarak gecirilir.
 *
 * UYARI: cagrilan adres DOGRULANMAZ. Yanlis adres cokme demektir.
 * Bu bilincli: amac tam da dogrulanamayan seyleri cagirabilmek.
 */
#include "../abi.inc"
#include "../tables/opcodes.inc"

    SECT_TEXT

#if defined(ARCH_X86_64)
/* SysV: rdi rsi rdx rcx r8 r9 - alti arguman */
FUNC(ffi_call)
    pushq %rbp
    movq %rsp, %rbp
    pushq %rbx
    movq %rdi, %rax                 /* adres */
    movq %rsi, %rbx                 /* dizi  */
    movq %rdx, %r11                 /* sayi  */
    xorl %edi, %edi
    xorl %esi, %esi
    xorl %edx, %edx
    xorl %ecx, %ecx
    xorl %r8d, %r8d
    xorl %r9d, %r9d
    cmpq $1, %r11; jb 1f
    movq 0(%rbx), %rdi
    cmpq $2, %r11; jb 1f
    movq 8(%rbx), %rsi
    cmpq $3, %r11; jb 1f
    movq 16(%rbx), %rdx
    cmpq $4, %r11; jb 1f
    movq 24(%rbx), %rcx
    cmpq $5, %r11; jb 1f
    movq 32(%rbx), %r8
    cmpq $6, %r11; jb 1f
    movq 40(%rbx), %r9
1:  call *%rax
    popq %rbx
    movq %rbp, %rsp
    popq %rbp
    ret
ENDFUNC(ffi_call)

#elif defined(ARCH_I386)
/* cdecl: butun argumanlar yiginda, TERS sirada; cagiran temizler */
FUNC(ffi_call)                      /* eax=adres edx=dizi ecx=sayi */
    pushl %ebp
    movl %esp, %ebp
    pushl %ebx
    pushl %esi
    movl %eax, %ebx                 /* adres */
    movl %edx, %esi                 /* dizi  */
    movl %ecx, %eax                 /* sayi  */
2:  testl %eax, %eax
    jz 3f
    decl %eax
    pushl (%esi,%eax,4)
    jmp 2b
3:  call *%ebx
    /* cdecl'de yigini CAGIRAN temizler. Once %ecx'e (arguman sayisi)
     * guveniyordum ama %ecx cdecl'de CAGRILAN-BOZAR: C islevi onu
     * ezince yigin isaretcisi cop kadar kaydiriliyordu ve donusde
     * cokuyordu. %ebp'den geri sarmak hem dogru hem daha basit. */
    leal -8(%ebp), %esp             /* esi/ebx'in oldugu yere don */
    popl %esi
    popl %ebx
    movl %ebp, %esp
    popl %ebp
    ret
ENDFUNC(ffi_call)

#elif defined(ARCH_AARCH64)
/* AAPCS64: x0-x7 */
FUNC(ffi_call)
    PROLOGUE
    mov x9, x0                      /* adres */
    mov x10, x1                     /* dizi  */
    mov x11, x2                     /* sayi  */
    mov x0, xzr
    mov x1, xzr
    mov x2, xzr
    mov x3, xzr
    mov x4, xzr
    mov x5, xzr
    cmp x11, #1; b.lt 1f
    ldr x0, [x10, #0]
    cmp x11, #2; b.lt 1f
    ldr x1, [x10, #8]
    cmp x11, #3; b.lt 1f
    ldr x2, [x10, #16]
    cmp x11, #4; b.lt 1f
    ldr x3, [x10, #24]
    cmp x11, #5; b.lt 1f
    ldr x4, [x10, #32]
    cmp x11, #6; b.lt 1f
    ldr x5, [x10, #40]
1:  blr x9
    EPILOGUE
    ret
ENDFUNC(ffi_call)

#else
/* AAPCS32: r0-r3 (dorde kadar; fazlasi yigina gider, desteklenmiyor) */
FUNC(ffi_call)
    push {r4, r5, lr}
    mov r4, r0                      /* adres */
    mov r5, r1                      /* dizi  */
    mov r12, r2                     /* sayi  */
    mov r0, #0
    mov r1, #0
    mov r2, #0
    mov r3, #0
    cmp r12, #1
    blt 1f
    ldr r0, [r5, #0]
    cmp r12, #2
    blt 1f
    ldr r1, [r5, #4]
    cmp r12, #3
    blt 1f
    ldr r2, [r5, #8]
    cmp r12, #4
    blt 1f
    ldr r3, [r5, #12]
1:  blx r4
    pop {r4, r5, pc}
ENDFUNC(ffi_call)
#endif

    .bss
    .p2align 3
SYM(g_ffi_args): .space 8 * 8

    SECT_TEXT

/* cagir(adres, a0..a5) -> tamsayi
 * Argumanlarin hepsi tamsayi olmali; tampon adresi gerekiyorsa
 * adres(tampon) ile alinir. */
FUNC(nat_ffi)
    ENTER(4)
    CMPI(A1, 1)
    BLO(nff_nil)
    SPILL(0, A0)
    SPILL(1, A1)
    CALL(arg_int)
    BZ(RV, nff_nil)
    SPILL(2, A1)                    /* adres */
    MOVI(A0, 0)
    SPILL(3, A0)
nff_l:
    FILL(A0, 3)
    FILL(A1, 1)
    DEC(A1)
    CMPR(A0, A1)
    BHS(nff_go)
    CMPI(A0, 6)
    BHS(nff_go)
    FILL(A0, 3)
    INC(A0)
    SHLI(A0, VAL_SHIFT)             /* deger yuvasi adimi (8 degil) */
    FILL(A1, 0)
    ADD(A0, A1)
    CALL(arg_int)
    BZ(RV, nff_nil)
    FILL(A0, 3)
    SHLI(A0, WORD_SHIFT)
    LEA_SYM(A2, SYM(g_ffi_args))
    ADD(A0, A2)
    ST(A0, A1)
    FILL(A0, 3)
    INC(A0)
    SPILL(3, A0)
    B(nff_l)
nff_go:
    FILL(A0, 2)
    LEA_SYM(A1, SYM(g_ffi_args))
    FILL(A2, 3)
    CALL(ffi_call)
    MOVR(A0, RV)
    CALL(ret_int)
    LEAVE_
    RET
nff_nil:
    CALL(nat_ret_nil)
    LEAVE_
    RET
ENDFUNC(nat_ffi)

/* adres(x) -> nesnenin VERI adresi (tampon/dizgi), tamsayi olarak
 * FFI ile tampon gecirmek icin. */
FUNC(nat_addr)
    ENTER(2)
    CMPI(A1, 1)
    BNE(nad_nil)
    LD32_OFF(A1W, A0, VAL_TAG)
    CMPI(A1, T_OBJ)
    BNE(nad_nil)
    LD_OFF(A0, A0, VAL_PAY)
    CALL(obj_ptr)
    MOVR(A0, RV)
    ADDI(A0, OBJ_DATA)
    CALL(ret_int)
    LEAVE_
    RET
nad_nil:
    CALL(nat_ret_nil)
    LEAVE_
    RET
ENDFUNC(nat_addr)

/* makinekod(tampon) -> tamponu CALISTIRILABILIR bellege kopyalar,
 * baslangic adresini dondurur.
 *
 * Bu, "saf makine kodu" ihtiyacinin dil tarafindaki karsiligi:
 * bayt tamponuna komutlari yazip burada calistirilabilir hale
 * getiriyorsun, sonra cagir() ile atliyorsun. Disk okuma, CPUID gibi
 * seyler icin gereken sey tam olarak bu - yukleyici de OS de gerekmiyor.
 *
 * W^X uygulayan sistemde os_alloc_exec 0 doner ve bu da bos doner.
 */
FUNC(nat_mkc)
    ENTER(4)
    CMPI(A1, 1)
    BNE(nmk_nil)
    MOVI(A1, O_BUF)
    CALL(obj_of)
    BZ(RV, nmk_nil)
    SPILL(0, RV)
    LD32_OFF(A0W, RV, OBJ_LEN)
    BZ(A0, nmk_nil)
    SPILL(1, A0)
    CALL(os_alloc_exec)
    BZ(RV, nmk_nil)
    SPILL(2, RV)
    MOVR(A0, RV)
    FILL(A1, 0)
    ADDI(A1, OBJ_DATA)
    FILL(A2, 1)
    CALL(mem_copy_b)
    FILL(A0, 2)
    CALL(ret_int)
    LEAVE_
    RET
nmk_nil:
    CALL(nat_ret_nil)
    LEAVE_
    RET
ENDFUNC(nat_mkc)

/* JIT hata yardimcilari - jitcomp.S kullaniyor */
    SECT_RODATA
jx_e_rng: .ascii "calisma hatasi: dizi sinirlari disinda\n"
    .equ jx_e_rng_len, . - jx_e_rng
jx_e_stk: .ascii "calisma hatasi: deger yigini tasti\n"
    .equ jx_e_stk_len, . - jx_e_stk
    SECT_TEXT

FUNC(jit_err_range)
    ENTER(1)
    LEA_SYM(A0, jx_e_rng); MOVI(A1, jx_e_rng_len); CALL(print_str)
    LEA_SYM(A0, SYM(g_rterr)); LD32(A1W, A0); INC(A1); ST32_OFF(A0, 0, A1W)
    LEAVE_
    RET
ENDFUNC(jit_err_range)

FUNC(jit_err_stack)
    ENTER(1)
    LEA_SYM(A0, jx_e_stk); MOVI(A1, jx_e_stk_len); CALL(print_str)
    LEA_SYM(A0, SYM(g_rterr)); LD32(A1W, A0); INC(A1); ST32_OFF(A0, 0, A1W)
    LEAVE_
    RET
ENDFUNC(jit_err_stack)

/* ================== C / C++ ISLEVLERINI ADLA CAGIRMA ==================
 *
 * dlopen/dlsym YOK (statik + nostdlib, bare-metal'de kavram bile yok).
 * Bunun yerine STATIK BAGLAMA: kullanici C kodunu imajla derliyor,
 * src/tables/user_syms.inc icinde tanitiyor, biz adla buluyoruz.
 * Her hedefte calisir.
 */
#include "../tables/user_syms.inc"

    SECT_TEXT

/* csym_find(A0 = ad isaretcisi, A1 = uzunluk) -> RV = adres / 0 */
FUNC(csym_find)
    ENTER(4)
    SPILL(0, A0)
    SPILL(1, A1)
    LEA_SYM(A0, SYM(g_csyms))
    SPILL(2, A0)
cf_next:
    FILL(A0, 2)
    LD_OFF(A1, A0, WORD_SIZE)       /* uzunluk; 0 = nobetci */
    BZ(A1, cf_no)
    FILL(A2, 1)
    CMPR(A1, A2)
    BNE(cf_adv)
    /* uzunluklar esit: baytlari karsilastir */
    FILL(A0, 2); ADDI(A0, 2 * WORD_SIZE)
    FILL(A1, 0)
    FILL(A2, 1)
    CALL(mem_eq)
    BNZ(RV, cf_hit)
cf_adv:
    FILL(A0, 2); ADDI(A0, 64); SPILL(2, A0)
    B(cf_next)
cf_hit:
    FILL(A0, 2)
    LD(RV, A0)                      /* islev isaretcisi */
    LEAVE_
    RET
cf_no:
    MOVI(RV, 0)
    LEAVE_
    RET
ENDFUNC(csym_find)

/* cbul(ad) -> adres / bos */
FUNC(nat_cbul)
    ENTER(2)
    CMPI(A1, 1)
    BNE(ncb_nil)
    MOVI(A1, O_STR)
    CALL(obj_of)
    BZ(RV, ncb_nil)
    SPILL(0, RV)
    LD32_OFF(A1W, RV, OBJ_LEN)
    SPILL(1, A1)
    FILL(A0, 0); ADDI(A0, OBJ_DATA)
    FILL(A1, 1)
    CALL(csym_find)
    BZ(RV, ncb_nil)
    MOVR(A0, RV)
    CALL(ret_int)
    LEAVE_
    RET
ncb_nil:
    CALL(nat_ret_nil)
    LEAVE_
    RET
ENDFUNC(nat_cbul)

/* c(ad, a0..a5) -> adla bul ve cagir
 * cbul + cagir'in tek adimda hali: en cok kullanilan yol bu. */
FUNC(nat_c)
    ENTER(4)
    CMPI(A1, 1)
    BLO(nc_nil)
    SPILL(0, A0)
    SPILL(1, A1)
    MOVI(A1, O_STR)
    CALL(obj_of)
    BZ(RV, nc_nil)
    SPILL(2, RV)
    LD32_OFF(A1W, RV, OBJ_LEN)
    SPILL(3, A1)
    FILL(A0, 2); ADDI(A0, OBJ_DATA)
    FILL(A1, 3)
    CALL(csym_find)
    BZ(RV, nc_nil)
    SPILL(2, RV)                    /* adres */
    /* argumanlari topla: ad haric hepsi */
    MOVI(A0, 0)
    SPILL(3, A0)
nc_arg:
    FILL(A0, 3)
    FILL(A1, 1); DEC(A1)
    CMPR(A0, A1)
    BHS(nc_go)
    CMPI(A0, 6)
    BHS(nc_go)
    FILL(A0, 3); INC(A0); SHLI(A0, VAL_SHIFT)
    FILL(A1, 0); ADD(A0, A1)
    CALL(arg_int)
    BZ(RV, nc_nil)
    FILL(A0, 3); SHLI(A0, WORD_SHIFT)
    LEA_SYM(A2, SYM(g_ffi_args)); ADD(A0, A2)
    ST(A0, A1)
    FILL(A0, 3); INC(A0); SPILL(3, A0)
    B(nc_arg)
nc_go:
    FILL(A0, 2)
    LEA_SYM(A1, SYM(g_ffi_args))
    FILL(A2, 3)
    CALL(ffi_call)
    MOVR(A0, RV)
    CALL(ret_int)
    LEAVE_
    RET
nc_nil:
    CALL(nat_ret_nil)
    LEAVE_
    RET
ENDFUNC(nat_c)
