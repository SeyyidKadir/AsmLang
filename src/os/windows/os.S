/* Windows OS katmani - x86_64, i386, aarch64
 * Windows'ta kararli bir syscall arayuzu YOKTUR (ntdll numaralari surumle
 * degisir). Bu yuzden kernel32 import tablosu uzerinden cagri yapilir.
 * "fd" burada g_handles tablosunda bir indekstir: 1=stdout, 2=stderr.
 * Giris noktasi: mainCRTStartup
 */
#include "../../abi.inc"

    .bss
    .p2align 3
    .globl SYM(g_handles)
SYM(g_handles):
    .space 8 * 8                /* [0] stdin [1] stdout [2] stderr [3] acik dosya
                                 * NOT: ayni anda TEK dosya. dosya_oku/dosya_yaz
                                 * ac-oku-kapat bicimde calistigi icin yeterli. */

SECT_TEXT

/* ================= x86_64 (MS x64 ABI: rcx,rdx,r8,r9 + 32B shadow) ===== */
#if defined(ARCH_X86_64)

FUNC(os_write)
    pushq %rbp
    movq %rsp, %rbp
    subq $64, %rsp                      /* shadow(32) + 5.arg + yerel */
    movq %rdx, %r8                      /* nNumberOfBytesToWrite */
    leaq SYM(g_handles)(%rip), %rax
    movq (%rax,%rdi,8), %rcx            /* hFile */
    movq %rsi, %rdx                     /* lpBuffer */
    leaq -8(%rbp), %r9                  /* lpNumberOfBytesWritten */
    movq $0, 32(%rsp)                   /* lpOverlapped = NULL */
    call WriteFile
    movq -8(%rbp), %rax
    movq %rbp, %rsp
    popq %rbp
    ret

FUNC(os_read)
    pushq %rbp
    movq %rsp, %rbp
    subq $64, %rsp
    movq %rdx, %r8                      /* nNumberOfBytesToRead */
    leaq SYM(g_handles)(%rip), %rax
    movq (%rax,%rdi,8), %rcx            /* hFile */
    movq %rsi, %rdx                     /* lpBuffer */
    leaq -8(%rbp), %r9                  /* lpNumberOfBytesRead */
    movq $0, 32(%rsp)                   /* lpOverlapped */
    call ReadFile
    testl %eax, %eax
    jz 1f
    movq -8(%rbp), %rax
    jmp 2f
1:  movq $-1, %rax
2:  movq %rbp, %rsp
    popq %rbp
    ret

FUNC(os_open)
    pushq %rbp
    movq %rsp, %rbp
    subq $80, %rsp
    movq %rdi, %rcx                     /* lpFileName */
    testq %rsi, %rsi
    jz 1f
    movl $0x40000000, %edx              /* GENERIC_WRITE */
    movl $2, %eax                       /* CREATE_ALWAYS */
    jmp 2f
1:  movl $0x80000000, %edx              /* GENERIC_READ */
    movl $3, %eax                       /* OPEN_EXISTING */
2:  movl $1, %r8d                       /* FILE_SHARE_READ */
    xorl %r9d, %r9d                     /* lpSecurityAttributes */
    movq %rax, 32(%rsp)                 /* dwCreationDisposition */
    movq $128, 40(%rsp)                 /* FILE_ATTRIBUTE_NORMAL */
    movq $0, 48(%rsp)                   /* hTemplateFile */
    call CreateFileA
    cmpq $-1, %rax
    je 3f
    leaq SYM(g_handles)(%rip), %rcx
    movq %rax, 24(%rcx)                 /* yuva 3 */
    movq $3, %rax
    jmp 4f
3:  movq $-1, %rax
4:  movq %rbp, %rsp
    popq %rbp
    ret

/* SetFilePointerEx(hFile, liDistanceToMove, lpNewFilePointer, dwMoveMethod)
 *                  rcx        rdx                r8                r9 */
FUNC(os_seek)
    pushq %rbp
    movq %rsp, %rbp
    subq $64, %rsp
    movq %rdx, %r9                      /* kip ONCE: rdx ezilecek */
    leaq SYM(g_handles)(%rip), %rax
    movq (%rax,%rdi,8), %rcx            /* hFile */
    movq %rsi, %rdx                     /* mesafe */
    leaq -8(%rbp), %r8                  /* yeni konum */
    call SetFilePointerEx
    testl %eax, %eax
    jz 1f
    movq -8(%rbp), %rax
    jmp 2f
1:  movq $-1, %rax
2:  movq %rbp, %rsp
    popq %rbp
    ret

FUNC(os_close)
    subq $40, %rsp
    leaq SYM(g_handles)(%rip), %rax
    movq (%rax,%rdi,8), %rcx
    call CloseHandle
    addq $40, %rsp
    ret

FUNC(os_alloc_exec)
    pushq %rbp
    movq %rsp, %rbp
    subq $32, %rsp
    movq %rdi, %rdx
    xorl %ecx, %ecx
    movl $0x3000, %r8d
    movl $0x40, %r9d            /* PAGE_EXECUTE_READWRITE */
    call VirtualAlloc
    movq %rbp, %rsp
    popq %rbp
    ret

FUNC(os_alloc)
    pushq %rbp
    movq %rsp, %rbp
    subq $32, %rsp
    movq %rdi, %rdx                     /* dwSize */
    xorl %ecx, %ecx                     /* lpAddress = NULL */
    movl $0x3000, %r8d                  /* MEM_COMMIT|MEM_RESERVE */
    movl $0x04, %r9d                    /* PAGE_READWRITE */
    call VirtualAlloc
    movq %rbp, %rsp
    popq %rbp
    ret

FUNC(os_exit)
    subq $40, %rsp
    movq %rdi, %rcx
    call ExitProcess
    hlt

FUNC(mainCRTStartup)
    subq $40, %rsp
    movl $-11, %ecx                     /* STD_OUTPUT_HANDLE */
    call GetStdHandle
    leaq SYM(g_handles)(%rip), %rcx
    movq %rax, 8(%rcx)
    movl $-12, %ecx                     /* STD_ERROR_HANDLE */
    call GetStdHandle
    leaq SYM(g_handles)(%rip), %rcx
    movq %rax, 16(%rcx)
    movl $-10, %ecx                     /* STD_INPUT_HANDLE */
    call GetStdHandle
    leaq SYM(g_handles)(%rip), %rcx
    movq %rax, 0(%rcx)
    call GetCommandLineA
    movq %rax, %rdi
    call SYM(win_args)
    xorl %ebp, %ebp
    call SYM(lang_main)
    movq %rax, %rdi
    call SYM(os_exit)

/* ================= i386 (stdcall, @N susleme, callee temizler) ========= */
#elif defined(ARCH_I386)

FUNC(os_write)                          /* eax=fd, edx=buf, ecx=len */
    pushl %ebp
    movl %esp, %ebp
    subl $24, %esp
    movl SYM(g_handles)(,%eax,4), %eax
    movl %eax, -24(%ebp)                /* hFile */
    movl %edx, -20(%ebp)                /* lpBuffer */
    movl %ecx, -16(%ebp)                /* nNumberOfBytesToWrite */
    leal -4(%ebp), %eax
    movl %eax, -12(%ebp)                /* lpNumberOfBytesWritten */
    movl $0, -8(%ebp)                   /* lpOverlapped */
    leal -24(%ebp), %esp
    call _WriteFile@20
    movl -4(%ebp), %eax
    movl %ebp, %esp
    popl %ebp
    ret

FUNC(os_read)                           /* eax=fd, edx=buf, ecx=len */
    pushl %ebp
    movl %esp, %ebp
    subl $24, %esp
    movl SYM(g_handles)(,%eax,4), %eax
    movl %eax, -24(%ebp)                /* hFile */
    movl %edx, -20(%ebp)                /* lpBuffer */
    movl %ecx, -16(%ebp)                /* nBytes */
    leal -4(%ebp), %eax
    movl %eax, -12(%ebp)                /* lpNumberOfBytesRead */
    movl $0, -8(%ebp)                   /* lpOverlapped */
    leal -24(%ebp), %esp
    call _ReadFile@20
    testl %eax, %eax
    jz 1f
    movl -4(%ebp), %eax
    jmp 2f
1:  movl $-1, %eax
2:  movl %ebp, %esp
    popl %ebp
    ret

FUNC(os_open)                           /* eax=yol, edx=kip */
    pushl %ebp
    movl %esp, %ebp
    testl %edx, %edx
    jz 1f
    movl $0x40000000, %ecx
    pushl $0
    pushl $128
    pushl $2
    jmp 2f
1:  movl $0x80000000, %ecx
    pushl $0
    pushl $128
    pushl $3
2:  pushl $0
    pushl $1
    pushl %ecx
    pushl %eax
    call _CreateFileA@28
    cmpl $-1, %eax
    je 3f
    movl %eax, SYM(g_handles)+12
    movl $3, %eax
    jmp 4f
3:  movl $-1, %eax
4:  movl %ebp, %esp
    popl %ebp
    ret

FUNC(os_seek)                           /* eax=fd, edx=ofset, ecx=kip */
    pushl %ebp
    movl %esp, %ebp
    pushl %ecx
    pushl $0
    pushl %edx
    pushl SYM(g_handles)(,%eax,4)
    call _SetFilePointer@16
    movl %ebp, %esp
    popl %ebp
    ret

FUNC(os_close)
    pushl SYM(g_handles)(,%eax,4)
    call _CloseHandle@4
    ret

FUNC(os_alloc_exec)                     /* eax=boyut */
    pushl %ebp
    movl %esp, %ebp
    pushl $0x40                         /* PAGE_EXECUTE_READWRITE */
    pushl $0x3000
    pushl %eax
    pushl $0
    call _VirtualAlloc@16
    movl %ebp, %esp
    popl %ebp
    ret

FUNC(os_alloc)                          /* eax=size */
    pushl %ebp
    movl %esp, %ebp
    pushl $0x04                         /* flProtect  */
    pushl $0x3000                       /* flAllocationType */
    pushl %eax                          /* dwSize */
    pushl $0                            /* lpAddress */
    call _VirtualAlloc@16
    movl %ebp, %esp
    popl %ebp
    ret

FUNC(os_exit)
    pushl %eax
    call _ExitProcess@4
    hlt

FUNC(mainCRTStartup)
    pushl $-11
    call _GetStdHandle@4
    movl %eax, SYM(g_handles)+4
    pushl $-12
    call _GetStdHandle@4
    movl %eax, SYM(g_handles)+8
    pushl $-10
    call _GetStdHandle@4
    movl %eax, SYM(g_handles)+0
    call _GetCommandLineA@0
    call SYM(win_args)
    xorl %ebp, %ebp
    call SYM(lang_main)
    call SYM(os_exit)

/* ================= aarch64 (x0-x7, shadow space yok) ================== */
#elif defined(ARCH_AARCH64)

FUNC(os_write)
    PROLOGUE
    sub sp, sp, #32
    mov x8, x2                          /* len */
    LEA_SYM(x9, SYM(g_handles))
    ldr x9, [x9, x0, lsl #3]            /* hFile */
    mov x3, sp                          /* lpNumberOfBytesWritten */
    mov x2, x8                          /* nBytes */
    mov x0, x9
    mov x4, xzr                         /* lpOverlapped */
    bl WriteFile
    ldr x0, [sp]
    add sp, sp, #32
    EPILOGUE
    ret

FUNC(os_read)
    PROLOGUE
    sub sp, sp, #32
    mov x8, x2
    LEA_SYM(x9, SYM(g_handles))
    ldr x9, [x9, x0, lsl #3]
    mov x3, sp                          /* lpNumberOfBytesRead */
    mov x2, x8
    mov x0, x9
    mov x4, xzr
    bl ReadFile
    cbz w0, 1f
    ldr x0, [sp]
    b 2f
1:  mov x0, #-1
2:  add sp, sp, #32
    EPILOGUE
    ret

FUNC(os_open)
    PROLOGUE
    mov x7, x1                          /* kip */
    mov x2, #1                          /* FILE_SHARE_READ */
    mov x3, xzr                         /* security */
    cbz x7, 1f
    mov w1, #0x4000
    lsl w1, w1, #16                     /* GENERIC_WRITE */
    mov x4, #2                          /* CREATE_ALWAYS */
    b 2f
1:  mov w1, #0x8000
    lsl w1, w1, #16                     /* GENERIC_READ */
    mov x4, #3                          /* OPEN_EXISTING */
2:  mov x5, #128
    mov x6, xzr
    bl CreateFileA
    cmn x0, #1
    b.eq 3f
    LEA_SYM(x9, SYM(g_handles))
    str x0, [x9, #24]
    mov x0, #3
    b 4f
3:  mov x0, #-1
4:  EPILOGUE
    ret

FUNC(os_seek)                           /* x0=fd, x1=ofset, x2=kip */
    PROLOGUE
    sub sp, sp, #32
    mov x3, x2                          /* dwMoveMethod */
    mov x9, x1                          /* mesafe */
    LEA_SYM(x10, SYM(g_handles))
    ldr x0, [x10, x0, lsl #3]
    mov x1, x9
    mov x2, sp
    bl SetFilePointerEx
    cbz w0, 1f
    ldr x0, [sp]
    b 2f
1:  mov x0, #-1
2:  add sp, sp, #32
    EPILOGUE
    ret

FUNC(os_close)
    PROLOGUE
    LEA_SYM(x9, SYM(g_handles))
    ldr x0, [x9, x0, lsl #3]
    bl CloseHandle
    EPILOGUE
    ret

FUNC(os_alloc_exec)
    PROLOGUE
    mov x1, x0
    mov x0, xzr
    mov w2, #0x3000
    mov w3, #0x40
    bl VirtualAlloc
    EPILOGUE
    ret

FUNC(os_alloc)
    PROLOGUE
    mov x1, x0                          /* dwSize */
    mov x0, xzr                         /* lpAddress */
    mov w2, #0x3000
    mov w3, #4
    bl VirtualAlloc
    EPILOGUE
    ret

FUNC(os_exit)
    PROLOGUE
    bl ExitProcess
    brk #0

FUNC(mainCRTStartup)
    PROLOGUE
    mov w0, #-11
    bl GetStdHandle
    LEA_SYM(x9, SYM(g_handles))
    str x0, [x9, #8]
    mov w0, #-12
    bl GetStdHandle
    LEA_SYM(x9, SYM(g_handles))
    str x0, [x9, #16]
    mov w0, #-10
    bl GetStdHandle
    LEA_SYM(x9, SYM(g_handles))
    str x0, [x9]
    bl GetCommandLineA
    bl SYM(win_args)
    bl SYM(lang_main)
    bl SYM(os_exit)

#endif
