/* bare/os.S - isletim sistemi OLMADAN HAL
 *
 * Ayni dilin ayni VM'i, cekirdek kipinde. Aşama 0'da kurdugumuz
 * L1 soyutlamasinin karsiligi: diger ~9700 satira dokunulmuyor.
 *
 * Saglanan:
 *   os_write  -> UART
 *   os_read   -> UART (yoklamali); girdi yoksa 0 doner (EOF)
 *   os_alloc  -> baglayici betiginden gelen bolgede itme (bump) ayirici
 *   os_exit   -> durdur
 *   os_open/os_close -> dosya sistemi YOK, -1 doner
 *
 * Giris: _start   yigin kur -> .bss sifirla -> lang_main -> os_exit
 *
 * .bss SIFIRLAMA KRITIK: barindirilan yapida bunu cekirdek yapiyordu.
 * Bare-metal'de yapilmazsa butun sayaclar ve tablolar cop degerle
 * baslar - sessiz ve tesbiti zor bir hata sinifi.
 */
#include "../../abi.inc"

/* UART adresleri. -D ile degistirilebilir.
 *   x86    : 16550 seri port, COM1 = 0x3F8 (port G/C)
 *   ARM    : PL011, QEMU "virt" makinesinde 0x09000000 (MMIO)
 */
/* ================== BARE_SIM ==================
 * Emulator olmadan bare kod yolunu GERCEKTEN calistirmak icin.
 *
 * Ayricalikli olmayan her sey aynen kalir:
 *   - .bss sifirlama
 *   - bare'in kendi itme ayiricisi (Linux mmap DEGIL)
 *   - mb_parse ve multiboot yapisi
 *   - sozcuk cozumleyici + ayristirici + derleyici + sanal makine
 *
 * Yalniz DONANIMA dokunan iki sey degistirilir:
 *   - UART -> write(1, ...) sistem cagrisi
 *   - port G/C -> sahte (in/out kullanici kipinde hata verir)
 *
 * Bu QEMU'nun YERINI TUTMAZ. Test etmedigi seyler:
 *   gercek acilis, gercek UART, gercek port G/C, gercek MMIO,
 *   gercek disk, korumali mod ayrintilari.
 * Test ettigi sey: bare HAL'in geri kalani ve dilin tamami.
 */
#ifndef BARE_SIM
#  define BARE_SIM 0
#endif

#ifndef UART_BASE
#  if defined(ARCH_X86_64) || defined(ARCH_I386)
#    define UART_BASE 0x3F8
#  else
#    define UART_BASE 0x09000000
#  endif
#endif

    .bss
    .p2align 3
    .globl SYM(g_bump)
SYM(g_bump):  .space 8        /* siradaki bos adres */

    SECT_TEXT

/* ---------------- UART tek bayt ---------------- */
#if defined(ARCH_X86_64) || defined(ARCH_I386)

/* uart_init() - 16550'yi 115200 8N1 kur.
 *
 * HIC YAPILMIYORDU. QEMU varsayilan olarak calisir durumda birakir,
 * bu yuzden fark edilmiyordu; gercek donanimda ya da farkli
 * yapilandirmada CIKTI HIC GELMEZ. Tanilama raporunun gorunmesi
 * tam da buna bagli.
 *
 *   +1 IER = 0      kesme yok
 *   +3 LCR = 0x80   DLAB ac (bolen erisimi)
 *   +0 DLL = 1      115200 (taban 115200 / 1)
 *   +1 DLM = 0
 *   +3 LCR = 0x03   8 bit, parite yok, 1 dur biti
 *   +2 FCR = 0xC7   FIFO ac, temizle, 14 bayt esik
 *   +4 MCR = 0x03   DTR + RTS
 */
FUNC(uart_init)
    ENTER(1)
#if BARE_SIM
    LEAVE_
    RET
#endif
    MOVI(A0, UART_BASE + 1); MOVI(A1, 0x00); MOVI(A2, 1); CALL(uart_raw_out)
    MOVI(A0, UART_BASE + 3); MOVI(A1, 0x80); MOVI(A2, 1); CALL(uart_raw_out)
    MOVI(A0, UART_BASE + 0); MOVI(A1, 0x01); MOVI(A2, 1); CALL(uart_raw_out)
    MOVI(A0, UART_BASE + 1); MOVI(A1, 0x00); MOVI(A2, 1); CALL(uart_raw_out)
    MOVI(A0, UART_BASE + 3); MOVI(A1, 0x03); MOVI(A2, 1); CALL(uart_raw_out)
    MOVI(A0, UART_BASE + 2); MOVI(A1, 0xC7); MOVI(A2, 1); CALL(uart_raw_out)
    MOVI(A0, UART_BASE + 4); MOVI(A1, 0x03); MOVI(A2, 1); CALL(uart_raw_out)
    LEAVE_
    RET
ENDFUNC(uart_init)

/* uart_raw_out(A0 = port, A1 = deger, A2 = genislik)
 * osprim.S'teki port_out ile ayni is ama BURADA da gerekiyor:
 * os.S once baglaniyor ve o dosyaya bagimli olmamali. */
FUNC(uart_raw_out)
#if defined(ARCH_X86_64)
    movl %edi, %edx
    movl %esi, %eax
    outb %al, %dx
    ret
#else
    pushl %ebx
    movl %eax, %ebx
    movl %edx, %eax
    movl %ebx, %edx
    outb %al, %dx
    popl %ebx
    ret
#endif
ENDFUNC(uart_raw_out)

/* uart_put(A0 = bayt) - LSR bit5 (THR bos) beklenir */
FUNC(uart_put)
    ENTER(1)
    SPILL(0, A0)
#if BARE_SIM
    /* Benzetim: bayti yigina koyup write(1, &b, 1) */
#  if defined(ARCH_X86_64)
    movq %rdi, %rax
    movb %al, -16(%rbp)
    leaq -16(%rbp), %rsi
    movl $1, %edi
    movl $1, %edx
    movl $1, %eax
    syscall
#  else
    /* %ebx CAGRILAN-KORUMALI ve i386'da VF = %ebx.
     * Ilk yazimda korumadan eziyordum: cerceve tabani cop oluyor,
     * ilk sayi basiminda cokuyordu. Gercek cagri yaparken kaydet. */
    pushl %ebx
    movl %eax, %ecx
    movb %cl, -16(%ebp)
    leal -16(%ebp), %ecx
    movl $1, %ebx
    movl $1, %edx
    movl $4, %eax
    int $0x80
    popl %ebx
#  endif
    LEAVE_
    RET
#endif
1:  movw $(UART_BASE + 5), %dx
    inb %dx, %al
    testb $0x20, %al
    jz 1b
    movw $UART_BASE, %dx
    FILL(A0, 0)
#if defined(ARCH_X86_64)
    movb %dil, %al
#else
    movb %al, %al
#endif
    outb %al, %dx
    LEAVE_
    RET
ENDFUNC(uart_put)

/* uart_get() -> RV = bayt, yoksa -1 */
FUNC(uart_get)
    ENTER(1)
    movw $(UART_BASE + 5), %dx
    inb %dx, %al
    testb $0x01, %al            /* veri hazir mi */
    jz 1f
    movw $UART_BASE, %dx
    xorl %eax, %eax
    inb %dx, %al
    LEAVE_
    RET
1:  MOVI(RV, -1)
    LEAVE_
    RET
ENDFUNC(uart_get)

#else   /* ARM / AArch64: PL011 MMIO */

FUNC(uart_put)
    ENTER(1)
    SPILL(0, A0)
    LEA_SYM(A1, uart_addr)
    LD(A1, A1)
1:  LD32_OFF(A2W, A1, 0x18)     /* UARTFR */
    ANDI(A2, 0x20)              /* TXFF: verici dolu */
    BNZ(A2, 1b)
    FILL(A0, 0)
    ST32_OFF(A1, 0, A0W)        /* UARTDR */
    LEAVE_
    RET
ENDFUNC(uart_put)

FUNC(uart_get)
    ENTER(1)
    LEA_SYM(A1, uart_addr)
    LD(A1, A1)
    LD32_OFF(A2W, A1, 0x18)     /* UARTFR */
    ANDI(A2, 0x10)              /* RXFE: alici bos */
    BNZ(A2, 1f)
    LD32_OFF(A0W, A1, 0)
    ANDI(A0, 255)
    MOVR(RV, A0)
    LEAVE_
    RET
1:  MOVI(RV, -1)
    LEAVE_
    RET
ENDFUNC(uart_get)

    SECT_RODATA
    .p2align 3
uart_addr:
    PTR UART_BASE
    SECT_TEXT

#endif

/* ---------------- HAL ---------------- */

/* os_write(A0 = fd, A1 = tampon, A2 = uzunluk) -> RV = uzunluk */
FUNC(os_write)
    ENTER(3)
    SPILL(0, A1)
    SPILL(1, A2)
    SPILL(2, A2)                /* dondurulecek uzunluk */
ow_loop:
    FILL(A0, 1)
    BZ(A0, ow_done)
    FILL(A0, 0)
    LDB(A0W, A0)
    CALL(uart_put)
    FILL(A0, 0); INC(A0); SPILL(0, A0)
    FILL(A0, 1); DEC(A0); SPILL(1, A0)
    B(ow_loop)
ow_done:
    FILL(RV, 2)
    LEAVE_
    RET
ENDFUNC(os_write)

/* os_read(A0 = fd, A1 = tampon, A2 = uzunluk) -> RV = okunan
 * Yoklamali ve BLOKLAMAZ: veri yoksa 0 doner (EOF gibi davranir).
 * Gercek bir cekirdekte burasi kesme surucusune baglanir. */
FUNC(os_read)
    ENTER(3)
    SPILL(0, A1)
    SPILL(1, A2)
    MOVI(A0, 0)
    SPILL(2, A0)
or_loop:
    FILL(A0, 1)
    BZ(A0, or_done)
    /* Once seri port, sonra KLAVYE: oku() bare-metal'de ikisinden
     * de girdi alsin. QEMU'da "-serial stdio" ile de gercek
     * klavyeyle de calisiyor. */
    CALL(uart_get)
    MOVR(A0, RV)
    CMPI(A0, 0)
    BGE(or_have)
    CALL(kbd_ascii)
    MOVR(A0, RV)
    BZ(A0, or_done)
or_have:
    SPILL(1, A0)                /* gecici: bayt (uzunluk asagida tazelenir) */
    FILL(A1, 0)
    FILL(A0, 1)
    STB(A1, A0B)
    FILL(A0, 0); INC(A0); SPILL(0, A0)
    FILL(A0, 2); INC(A0); SPILL(2, A0)
    MOVI(A0, 0)
    SPILL(1, A0)                /* tek bayt okuduk, dongu biter */
or_done:
    FILL(RV, 2)
    LEAVE_
    RET
ENDFUNC(os_read)

/* os_alloc(A0 = boyut) -> RV = isaretci, yer yoksa 0 */
FUNC(os_alloc)
    ENTER(2)
    ADDI(A0, 15)
    ANDI(A0, -16)
    SPILL(0, A0)
    LEA_SYM(A0, SYM(g_bump))
    LD(A1, A0)
    BNZ(A1, oa_have)
    LEA_SYM(A1, _heap_start)    /* ilk cagri: baglayiciden basla */
oa_have:
    SPILL(1, A1)
    FILL(A0, 0)
    ADD(A1, A0)
    LEA_SYM(A0, _heap_end)
    CMPR(A1, A0)
    BHI(oa_oom)
    LEA_SYM(A0, SYM(g_bump))
    ST(A0, A1)
    FILL(RV, 1)
    LEAVE_
    RET
oa_oom:
    MOVI(RV, 0)
    LEAVE_
    RET
ENDFUNC(os_alloc)

/* Bare-metal'de bellek zaten RWX (sayfalama yok): os_alloc ile ayni */
FUNC(os_alloc_exec)
    ENTER(1)
    CALL(os_alloc)
    LEAVE_
    RET
ENDFUNC(os_alloc_exec)

/* Dosya sistemi yok */
FUNC(os_open)
    MOVI(RV, -1)
    RET
ENDFUNC(os_open)

FUNC(os_close)
    MOVI(RV, 0)
    RET
ENDFUNC(os_close)

FUNC(os_seek)
    MOVI(RV, -1)
    RET
ENDFUNC(os_seek)

/* os_exit(A0 = kod) - donmez */
FUNC(os_exit)
#if BARE_SIM
    /* Benzetim: cli/hlt ayricalikli. Gercek cikis yapiyoruz ki
     * kabuk cikis kodunu gorebilsin. */
#  if defined(ARCH_X86_64)
    movl $60, %eax
    syscall
#  else
    movl %eax, %ebx
    movl $1, %eax
    int $0x80
#  endif
#endif
oe_halt:
#if defined(ARCH_X86_64) || defined(ARCH_I386)
    cli
    hlt
#elif defined(ARCH_AARCH64)
    wfi
#else
    wfi
#endif
    B(oe_halt)
ENDFUNC(os_exit)

/* ---------------- giris ---------------- */
    .globl _start
#if defined(ARCH_ARM)
    .type _start, %function
#endif
#if defined(ARCH_X86_64) || defined(ARCH_I386)
/* ================== MULTIBOOT 1 BASLIGI ==================
 * Bu baslik olmadan imaj ACILAMAZ: ne GRUB ne de
 * "qemu-system-x86_64 -kernel" yukleyebilir. Ilk 8 KB icinde ve
 * 4 bayta hizali olmali.
 *
 * bayrak 0 (0x01) : moduller/bolumler 4 KB hizali
 * bayrak 1 (0x02) : bellek haritasi istensin
 * bayrak 2 (0x04) : VIDEO MODU istensin -> yukleyici bize dogrusal
 *                   cerceve tamponu kurar (resim icin sart)
 */
    .section .multiboot, "a"
    .p2align 2
mb_hdr:
/* Bayrak 2 (0x04 = video modu) VARSAYILAN OLARAK KAPALI.
 *
 * QEMU'nun "-kernel" multiboot yukleyicisi VBE'yi DESTEKLEMIYOR:
 * bayragi gorunce "multiboot knows VBE. we don't" deyip acilisi
 * tamamen REDDEDIYOR. GRUB destekliyor.
 *
 * Bu yuzden varsayilan 0x03 (hizala + bellek haritasi) ve imaj
 * her iki yukleyicide de aciliyor. GRUB ile dogrusal cerceve
 * tamponu isteyecekseniz -DMB_VIDEO=1 ile derleyin; o zaman
 * QEMU ile acilmaz. */
#ifndef MB_VIDEO
#  define MB_VIDEO 0
#endif
#if MB_VIDEO
#  define MB_FLAGS 0x00000007
#else
#  define MB_FLAGS 0x00000003
#endif
    .long 0x1BADB002                    /* sihir */
    .long MB_FLAGS
    .long -(0x1BADB002 + MB_FLAGS)      /* toplam sifir olmali */
    /* a.out alanlari: header_addr, load_addr, load_end_addr,
     * bss_end_addr, entry_addr -> ELF'te kullanilmaz ama YER
     * KAPLAR. Ilk yazimda bes yerine dort saymistim ve video
     * alanlari kayiyordu (mod=768, genislik=cop). */
    .long 0                             /* header_addr    */
    .long 0                             /* load_addr      */
    .long 0                             /* load_end_addr  */
    .long 0                             /* bss_end_addr   */
    .long 0                             /* entry_addr     */
    .long 0                             /* mod: 0 = dogrusal grafik */
    .long 1024                          /* istenen genislik  */
    .long 768                           /* istenen yukseklik */
    .long 32                            /* istenen bit/piksel */
#endif

    SECT_TEXT
_start:
#if defined(ARCH_X86_64)
    /* Multiboot yukleyicisi: EAX = 0x2BADB002, EBX = bilgi yapisi.
     * SIHIR DENETLENMELI: yukleyici degilse EBX cop olur ve
     * mb_parse cop adresi okur. Denetimi hic yapmiyordum. */
    leaq _stack_top(%rip), %rsp
    /* Multiboot bilgisini .bss SIFIRLANDIKTAN SONRA yaz.
     * Once oncesinde yaziyordum ve sifirlama dongusu g_mbmagic'i
     * de kapsadigi icin siliyordu: "multiboot yukleyici YOK".
     * QEMU'da gercekten acinca gorulen ilk hata buydu. */
    pushq %rax
    pushq %rbx
    xorl %ebp, %ebp
#elif defined(ARCH_I386)
    movl $_stack_top, %esp
    pushl %eax
    pushl %ebx
    xorl %ebp, %ebp
#elif defined(ARCH_AARCH64)
    adrp x0, _stack_top
    add x0, x0, :lo12:_stack_top
    mov sp, x0
    mov x29, xzr
    mov x30, xzr
#else
    ldr sp, =_stack_top
    mov fp, #0
    mov lr, #0
#endif
    /* .bss sifirla: barindirilan yapida cekirdek yapiyordu */
    LEA_SYM(A0, __bss_start)
    LEA_SYM(A1, __bss_end)
bz_loop:
    CMPR(A0, A1)
    BHS(bz_done)
    MOVI(A2, 0)
    ST32_OFF(A0, 0, A2W)
    ADDI(A0, 4)
    B(bz_loop)
bz_done:
#if defined(ARCH_X86_64)
    popq %rbx
    popq %rax
    cmpl $0x2BADB002, %eax
    jne 7f
    leaq SYM(g_mbinfo)(%rip), %rax
    movq %rbx, (%rax)
    leaq SYM(g_mbmagic)(%rip), %rax
    movl $1, (%rax)
7:
#elif defined(ARCH_I386)
    popl %ebx
    popl %eax
    cmpl $0x2BADB002, %eax
    jne 7f
    movl %ebx, SYM(g_mbinfo)
    movl $1, SYM(g_mbmagic)
7:
#endif
#if defined(ARCH_X86_64) || defined(ARCH_I386)
    CALL(uart_init)                 /* seri port: rapor buradan cikiyor */
    CALL(mb_parse)                  /* cerceve tamponu bilgisini coz */
#endif
    CALL(lang_main)
    MOVR(A0, RV)
    CALL(os_exit)

#if defined(ARCH_X86_64) || defined(ARCH_I386)
    .bss
    .p2align 3
    .globl SYM(g_mbinfo)
SYM(g_mbinfo):  .space 8
    .globl SYM(g_mbmagic)
SYM(g_mbmagic): .space 8         /* 1 = multiboot yukleyicisi bulduk */
    .globl SYM(g_mbflags)
SYM(g_mbflags): .space 8
/* Cerceve tamponu: adres, genislik, yukseklik, satir bayti, bit/piksel.
 * Yukleyici video kurmadiysa hepsi 0 kalir ve piksel() bos doner. */
    .globl SYM(g_fb)
SYM(g_fb):      .space 8 * 5

    SECT_TEXT
/* mb_parse() - multiboot bilgi yapisindan cerceve tamponunu al.
 * Yapida ofset 0 = bayraklar; bit 12 (0x1000) set ise ofset 88'den
 * itibaren framebuffer_addr(8) pitch(4) width(4) height(4) bpp(1). */
FUNC(mb_parse)
    ENTER(2)
    LEA_SYM(A0, SYM(g_mbinfo))
    LD(A0, A0)
    BZ(A0, mbp_end)
    SPILL(0, A0)
    LD32(A1W, A0)                   /* bayraklar */
    LEA_SYM(A2, SYM(g_mbflags))
    ST(A2, A1)
    MOVR(A2, A1)
    ANDI(A2, 0x1000)
    BZ(A2, mbp_end)                 /* video bilgisi yok */
    LEA_SYM(A1, SYM(g_fb))
    FILL(A0, 0)
    LD_OFF(A2, A0, 88)              /* framebuffer_addr (64 bit) */
    ST(A1, A2)
    FILL(A0, 0); LD32_OFF(A2W, A0, 100); ST_OFF(A1, 8,  A2)   /* genislik */
    FILL(A0, 0); LD32_OFF(A2W, A0, 104); ST_OFF(A1, 16, A2)   /* yukseklik */
    FILL(A0, 0); LD32_OFF(A2W, A0, 96);  ST_OFF(A1, 24, A2)   /* pitch */
    FILL(A0, 0); LDB_OFF(A2W, A0, 108);  ST_OFF(A1, 32, A2)   /* bpp */
mbp_end:
    LEAVE_
    RET
ENDFUNC(mb_parse)
#endif
