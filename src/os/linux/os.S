/* Linux OS katmani - x86_64, i386, aarch64, arm
 * Saglanan HAL:
 *   os_write(A0=fd, A1=buf, A2=len) -> RV
 *   os_alloc(A0=size)               -> RV (basarisizsa 0)
 *   os_exit(A0=code)                -> donmez
 * Giris noktasi: _start -> lang_main -> os_exit
 */
#include "../../abi.inc"

SECT_TEXT

/* ================= x86_64 ================= */
#if defined(ARCH_X86_64)

FUNC(os_write)
    movl $1, %eax               /* sys_write; rdi,rsi,rdx zaten yerinde */
    syscall
    ret

FUNC(os_read)
    xorl %eax, %eax             /* sys_read */
    syscall
    ret

/* os_open(A0=yol, A1=kip) -> RV = fd, hata -1   (kip: 0=oku 1=yaz)
 * openat kullaniliyor: aarch64'te "open" syscall'i YOK, yalniz openat var.
 * Tek yol dort mimaride de calisiyor. */
FUNC(os_open)
    movq %rsi, %rax             /* kip */
    movq %rdi, %rsi             /* yol */
    movq $-100, %rdi            /* AT_FDCWD */
    testq %rax, %rax
    jz 1f
    movl $577, %edx             /* O_WRONLY|O_CREAT|O_TRUNC */
    movl $420, %r10d            /* 0644 */
    jmp 2f
1:  xorl %edx, %edx             /* O_RDONLY */
    xorl %r10d, %r10d
2:  movl $257, %eax             /* sys_openat */
    syscall
    ret

FUNC(os_close)
    movl $3, %eax               /* sys_close */
    syscall
    ret

/* os_seek(A0 = fd, A1 = ofset, A2 = kip) -> RV = yeni konum, hata -1
 * kip: 0 = bastan, 1 = simdiki, 2 = sondan */
FUNC(os_seek)
    movl $8, %eax               /* sys_lseek */
    syscall
    ret

/* os_alloc_exec(A0 = boyut) -> RV = RWX bellek, hata 0
 * JIT icin. W^X uygulayan sistemlerde RWX reddedilebilir; o zaman 0
 * doner ve cagiran yorumlayiciya duser. Sessizce basarisiz OLMAZ. */
FUNC(os_alloc_exec)
    movq %rdi, %rsi
    xorl %edi, %edi
    movl $7, %edx               /* PROT_READ|WRITE|EXEC */
    /* MAP_32BIT ARTIK GEREKSIZ: tamsayi 64 bite cikinca adres
     * deger yuvasina sigiyor. Asama 37'de bu bir kirpma cozumuydu;
     * Asama 38 kok sebebi ortadan kaldirdi. */
    movl $0x22, %r10d
    movq $-1, %r8
    xorl %r9d, %r9d
    movl $9, %eax
    syscall
    cmpq $-4095, %rax
    jb 1f
    xorl %eax, %eax
1:  ret

FUNC(os_alloc)
    movq %rdi, %rsi             /* len   */
    xorl %edi, %edi             /* addr = NULL */
    movl $3, %edx               /* PROT_READ|PROT_WRITE */
    movl $0x22, %r10d           /* MAP_PRIVATE|MAP_ANONYMOUS */
    movq $-1, %r8               /* fd */
    xorl %r9d, %r9d             /* offset */
    movl $9, %eax               /* sys_mmap */
    syscall
    cmpq $-4095, %rax           /* -4095..-1 => hata */
    jb 1f
    xorl %eax, %eax
1:  ret

FUNC(os_exit)
    movl $231, %eax             /* sys_exit_group */
    syscall
    hlt

    .globl _start
_start:
    xorl %ebp, %ebp
    movq (%rsp), %rax                   /* argc */
    leaq 8(%rsp), %rdx                  /* argv */
    leaq SYM(g_argc)(%rip), %rcx
    movl %eax, (%rcx)
    leaq SYM(g_argv)(%rip), %rcx
    movq %rdx, (%rcx)
    call SYM(lang_main)
    movq %rax, %rdi
    call SYM(os_exit)

/* ================= i386 ================= */
#elif defined(ARCH_I386)

FUNC(os_write)                  /* A0=eax fd, A1=edx buf, A2=ecx len */
    pushl %ebx
    movl %eax, %ebx
    xchgl %ecx, %edx            /* ecx=buf, edx=len */
    movl $4, %eax               /* sys_write */
    int $0x80
    popl %ebx
    ret

FUNC(os_read)                   /* A0=eax fd, A1=edx buf, A2=ecx len */
    pushl %ebx
    movl %eax, %ebx
    xchgl %ecx, %edx
    movl $3, %eax               /* sys_read */
    int $0x80
    popl %ebx
    ret

FUNC(os_open)                   /* A0=eax yol, A1=edx kip */
    pushl %ebx
    pushl %esi
    movl %eax, %ecx
    movl $-100, %ebx
    testl %edx, %edx
    jz 1f
    movl $577, %edx
    movl $420, %esi
    jmp 2f
1:  xorl %edx, %edx
    xorl %esi, %esi
2:  movl $295, %eax             /* sys_openat */
    int $0x80
    popl %esi
    popl %ebx
    ret

FUNC(os_close)
    pushl %ebx
    movl %eax, %ebx
    movl $6, %eax               /* sys_close */
    int $0x80
    popl %ebx
    ret

/* os_seek(A0=eax fd, A1=edx ofset, A2=ecx kip) -> RV = yeni konum, -1
 * i386'da lseek yok; _llseek(140) 64-bit ofset ve AYRI sonuc tamponu
 * kullaniyor:
 *   ebx=fd  ecx=ofset_yuksek  edx=ofset_dusuk  esi=sonuc*  edi=kip
 */
FUNC(os_seek)
    pushl %ebx
    pushl %esi
    pushl %edi
    pushl %ecx                  /* kip sakla (ecx ezilecek) */
    subl $8, %esp               /* loff_t sonuc */
    movl %eax, %ebx             /* fd */
    movl %edx, %eax
    sarl $31, %eax              /* isaret genisletme -> yuksek 32 bit */
    movl %eax, %ecx
    movl %esp, %esi             /* sonuc tamponu */
    movl 8(%esp), %edi          /* kip */
    movl $140, %eax             /* sys__llseek */
    int $0x80
    testl %eax, %eax
    js 1f
    movl (%esp), %eax           /* sonucun dusuk 32 biti */
    jmp 2f
1:  movl $-1, %eax
2:  addl $8, %esp
    popl %ecx
    popl %edi
    popl %esi
    popl %ebx
    ret

FUNC(os_alloc_exec)             /* A0=eax boyut */
    pushl %ebx
    pushl %esi
    pushl %edi
    pushl %ebp
    movl %eax, %ecx
    xorl %ebx, %ebx
    movl $7, %edx               /* RWX */
    movl $0x22, %esi
    movl $-1, %edi
    xorl %ebp, %ebp
    movl $192, %eax
    int $0x80
    cmpl $-4095, %eax
    jb 1f
    xorl %eax, %eax
1:  popl %ebp
    popl %edi
    popl %esi
    popl %ebx
    ret

FUNC(os_alloc)                  /* A0=eax size */
    pushl %ebx
    pushl %esi
    pushl %edi
    pushl %ebp
    movl %eax, %ecx             /* len */
    xorl %ebx, %ebx             /* addr */
    movl $3, %edx               /* prot */
    movl $0x22, %esi            /* flags */
    movl $-1, %edi              /* fd */
    xorl %ebp, %ebp             /* pgoff */
    movl $192, %eax             /* sys_mmap2 */
    int $0x80
    cmpl $-4095, %eax
    jb 1f
    xorl %eax, %eax
1:  popl %ebp
    popl %edi
    popl %esi
    popl %ebx
    ret

FUNC(os_exit)
    movl %eax, %ebx
    movl $252, %eax             /* sys_exit_group */
    int $0x80
    hlt

    .globl _start
_start:
    xorl %ebp, %ebp
    movl (%esp), %eax
    movl %eax, SYM(g_argc)
    leal 4(%esp), %eax
    movl %eax, SYM(g_argv)
    call SYM(lang_main)
    call SYM(os_exit)           /* A0=eax = donus degeri */

/* ================= aarch64 ================= */
#elif defined(ARCH_AARCH64)

FUNC(os_write)
    mov x8, #64                 /* __NR_write */
    svc #0
    ret

FUNC(os_read)
    mov x8, #63                 /* __NR_read */
    svc #0
    ret

FUNC(os_open)
    mov x2, x1                  /* kip */
    mov x1, x0                  /* yol */
    mov x0, #-100               /* AT_FDCWD */
    cbz x2, 1f
    mov x2, #577
    mov x3, #420
    b 2f
1:  mov x2, xzr
    mov x3, xzr
2:  mov x8, #56                 /* __NR_openat */
    svc #0
    ret

FUNC(os_close)
    mov x8, #57                 /* __NR_close */
    svc #0
    ret

FUNC(os_seek)
    mov x8, #62                 /* __NR_lseek */
    svc #0
    ret

FUNC(os_alloc_exec)
    mov x1, x0
    mov x0, xzr
    mov x2, #7                  /* RWX */
    mov x3, #0x22
    mov x4, #-1
    mov x5, xzr
    mov x8, #222
    svc #0
    cmn x0, #4095
    b.lo 1f
    mov x0, xzr
1:  ret

FUNC(os_alloc)
    mov x1, x0                  /* len */
    mov x0, xzr                 /* addr */
    mov x2, #3                  /* prot */
    mov x3, #0x22               /* flags */
    mov x4, #-1                 /* fd */
    mov x5, xzr                 /* offset */
    mov x8, #222                /* __NR_mmap */
    svc #0
    cmn x0, #4095               /* x0 > -4096 ise hata */
    b.lo 1f
    mov x0, xzr
1:  ret

FUNC(os_exit)
    mov x8, #94                 /* __NR_exit_group */
    svc #0
    brk #0

    .globl _start
_start:
    mov x29, xzr
    ldr w0, [sp]
    add x1, sp, #8
    adrp x2, SYM(g_argc)
    add x2, x2, :lo12:SYM(g_argc)
    str w0, [x2]
    adrp x2, SYM(g_argv)
    add x2, x2, :lo12:SYM(g_argv)
    str x1, [x2]
    mov x30, xzr
    bl SYM(lang_main)
    bl SYM(os_exit)

/* ================= arm32 ================= */
#elif defined(ARCH_ARM)

FUNC(os_write)
    push {r7, lr}
    mov r7, #4                  /* __NR_write */
    svc #0
    pop {r7, pc}
ENDFUNC(os_write)

FUNC(os_read)
    push {r7, lr}
    mov r7, #3                  /* __NR_read */
    svc #0
    pop {r7, pc}
ENDFUNC(os_read)

FUNC(os_open)
    push {r7, lr}
    mov r2, r1
    mov r1, r0
    mvn r0, #99                 /* AT_FDCWD = -100 */
    cmp r2, #0
    beq 1f
    ldr r2, =577
    ldr r3, =420
    b 2f
1:  mov r2, #0
    mov r3, #0
2:  ldr r7, =322                /* __NR_openat */
    svc #0
    pop {r7, pc}
ENDFUNC(os_open)

FUNC(os_close)
    push {r7, lr}
    mov r7, #6                  /* __NR_close */
    svc #0
    pop {r7, pc}
ENDFUNC(os_close)

FUNC(os_seek)
    push {r7, lr}
    mov r7, #19                 /* __NR_lseek */
    svc #0
    pop {r7, pc}
ENDFUNC(os_seek)

FUNC(os_alloc_exec)
    push {r4, r5, r7, lr}
    mov r1, r0
    mov r0, #0
    mov r2, #7                  /* RWX */
    mov r3, #0x22
    mvn r4, #0
    mov r5, #0
    ldr r7, =192
    svc #0
    cmn r0, #4096
    bhi 1f
    mov r0, #0
1:  pop {r4, r5, r7, pc}
ENDFUNC(os_alloc_exec)

FUNC(os_alloc)
    push {r4, r5, r7, lr}
    mov r1, r0                  /* len */
    mov r0, #0                  /* addr */
    mov r2, #3                  /* prot */
    mov r3, #0x22               /* flags */
    mvn r4, #0                  /* fd = -1 */
    mov r5, #0                  /* pgoff */
    ldr r7, =192                /* __NR_mmap2 */
    svc #0
    cmn r0, #4096
    bhi 1f
    mov r0, #0
1:  pop {r4, r5, r7, pc}
ENDFUNC(os_alloc)

FUNC(os_exit)
    ldr r7, =248                /* __NR_exit_group */
    svc #0
    udf #0
ENDFUNC(os_exit)

    .globl _start
    .type _start, %function
_start:
    mov fp, #0
    ldr r0, [sp]
    add r1, sp, #4
    ldr r2, =SYM(g_argc)
    str r0, [r2]
    ldr r2, =SYM(g_argv)
    str r1, [r2]
    mov lr, #0
    bl SYM(lang_main)
    bl SYM(os_exit)

#endif
