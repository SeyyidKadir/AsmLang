/* macOS OS katmani - x86_64, aarch64
 * BSD syscall'lari. x86_64'te 0x2000000 sinif maskesi kullanilir,
 * arm64'te maske YOKTUR: cikplak numara x16'ya konur, svc #0x80 atilir.
 * Giris noktasi _main (linker'a -e _main ile bildirilir).
 */
#include "../../abi.inc"

SECT_TEXT

/* ================= x86_64 ================= */
#if defined(ARCH_X86_64)

FUNC(os_write)
    movl $0x2000004, %eax       /* write */
    syscall
    ret

FUNC(os_read)
    movl $0x2000003, %eax       /* read */
    syscall
    ret

FUNC(os_open)
    movq %rsi, %rax
    testq %rax, %rax
    jz 1f
    movl $1537, %esi            /* O_WRONLY|O_CREAT|O_TRUNC (BSD degerleri) */
    movl $420, %edx
    jmp 2f
1:  xorl %esi, %esi
    xorl %edx, %edx
2:  movl $0x2000005, %eax       /* open */
    syscall
    jnc 3f
    movq $-1, %rax
3:  ret

FUNC(os_close)
    movl $0x2000006, %eax
    syscall
    ret

FUNC(os_seek)
    movl $0x20000C7, %eax       /* lseek */
    syscall
    jnc 1f
    movq $-1, %rax
1:  ret

FUNC(os_alloc_exec)
    movq %rdi, %rsi
    xorl %edi, %edi
    movl $7, %edx               /* RWX */
    movl $0x1002, %r10d
    movq $-1, %r8
    xorl %r9d, %r9d
    movl $0x20000C5, %eax
    syscall
    jnc 1f
    xorl %eax, %eax
1:  ret

FUNC(os_alloc)
    movq %rdi, %rsi             /* len */
    xorl %edi, %edi             /* addr */
    movl $3, %edx               /* PROT_READ|WRITE */
    movl $0x1002, %r10d         /* MAP_ANON|MAP_PRIVATE */
    movq $-1, %r8
    xorl %r9d, %r9d
    movl $0x20000C5, %eax       /* mmap */
    syscall
    jnc 1f                      /* CF set => hata */
    xorl %eax, %eax
1:  ret

FUNC(os_exit)
    movl $0x2000001, %eax       /* exit */
    syscall
    hlt

FUNC(main)
    xorl %ebp, %ebp
    movq (%rsp), %rax
    leaq 8(%rsp), %rdx
    leaq SYM(g_argc)(%rip), %rcx
    movl %eax, (%rcx)
    leaq SYM(g_argv)(%rip), %rcx
    movq %rdx, (%rcx)
    call SYM(lang_main)
    movq %rax, %rdi
    call SYM(os_exit)

/* ================= aarch64 ================= */
#elif defined(ARCH_AARCH64)

FUNC(os_write)
    mov x16, #4                 /* write */
    svc #0x80
    ret

FUNC(os_read)
    mov x16, #3                 /* read */
    svc #0x80
    ret

FUNC(os_open)
    mov x2, x1
    cbz x2, 1f
    mov x1, #1537
    mov x2, #420
    b 2f
1:  mov x1, xzr
    mov x2, xzr
2:  mov x16, #5                 /* open */
    svc #0x80
    b.cc 3f
    mov x0, #-1
3:  ret

FUNC(os_close)
    mov x16, #6
    svc #0x80
    ret

FUNC(os_seek)
    mov x16, #199               /* lseek */
    svc #0x80
    b.cc 1f
    mov x0, #-1
1:  ret

/* macOS arm64: MAP_JIT (0x0800) sart ve uygun entitlement ister.
 * Alinmazsa 0 doner, cagiran yorumlayiciya duser. */
FUNC(os_alloc_exec)
    mov x1, x0
    mov x0, xzr
    mov x2, #7
    mov x3, #0x1802             /* MAP_ANON|MAP_PRIVATE|MAP_JIT */
    mov x4, #-1
    mov x5, xzr
    mov x16, #197
    svc #0x80
    b.cc 1f
    mov x0, xzr
1:  ret

FUNC(os_alloc)
    mov x1, x0                  /* len */
    mov x0, xzr                 /* addr */
    mov x2, #3                  /* prot */
    mov x3, #0x1002             /* MAP_ANON|MAP_PRIVATE */
    mov x4, #-1
    mov x5, xzr
    mov x16, #197               /* mmap */
    svc #0x80
    b.cc 1f                     /* C set => hata */
    mov x0, xzr
1:  ret

FUNC(os_exit)
    mov x16, #1                 /* exit */
    svc #0x80
    brk #0

FUNC(main)
    mov x29, xzr
    ldr w0, [sp]
    add x1, sp, #8
    adrp x2, SYM(g_argc)@PAGE
    add x2, x2, SYM(g_argc)@PAGEOFF
    str w0, [x2]
    adrp x2, SYM(g_argv)@PAGE
    add x2, x2, SYM(g_argv)@PAGEOFF
    str x1, [x2]
    mov x30, xzr
    bl SYM(lang_main)
    bl SYM(os_exit)

#endif
