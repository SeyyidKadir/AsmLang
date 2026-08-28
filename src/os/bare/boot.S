/* boot.S - asmlang onyukleyicisi
 *
 * GRUB'a GEREK BIRAKMAZ. Diskin ilk sektorunde durur, BIOS
 * tarafindan 0x7C00'e yuklenip 16-bit GERCEK MODDA calistirilir.
 *
 * ================== NEDEN KENDI ONYUKLEYICIMIZ ==================
 *
 * Cerceve tamponu icin iki secenek vardi:
 *   1) GRUB'un multiboot video istegi - grub-mkrescue gerekiyor
 *   2) Korumali moddan VBE cagirmak - MUMKUN DEGIL, int 0x10
 *      gercek mod hizmeti
 *
 * Onyukleyici gercek modda basladigi icin VBE'yi ORADA kuruyoruz,
 * sonra korumali moda gecip cekirdege multiboot yapisiyla veriyoruz.
 * QEMU'nun "-kernel" yolu VBE'yi desteklemiyordu; bu onu da asiyor.
 *
 * ================== ADIMLAR ==================
 *
 *   1. Yigin kur, disk numarasini sakla
 *   2. Cekirdegi diskten dusuk bellege oku (int 0x13 AH=0x42)
 *   3. VBE kipini kur (int 0x10 AX=0x4F02), bilgileri al
 *   4. A20 hattini ac
 *   5. GDT yukle, korumali moda gec
 *   6. Cekirdegi 1 MB'a kopyala
 *   7. EAX=0x2BADB002, EBX=&multiboot_bilgi ile atla
 *
 * ================== DISK DUZENI ==================
 *
 *   sektor 0      : bu onyukleyici (512 bayt)
 *   sektor 1..N   : cekirdek ikilisi (ham, ELF degil)
 *
 * ELF cozumlemek 512 bayta sigmaz; cekirdek HAM IKILI olarak
 * yaziliyor (tools/disk-yap.py objcopy ile uretiyor).
 */

/* Multiboot yapisi ve VBE tamponu SEKTORUN DISINDA: 512 bayta
 * sigmiyorlar. Bos dusuk bellekte SABIT adresler kullaniyoruz.
 * Tanimlar EN BASTA olmali: cpp sirali calisir, asagida
 * tanimlanan makro yukarida gorulmez. */
#define MB_SEG        0x07E0
#define VB_SEG        0x07F0
#define mb_info       0x7E00
#define mb_flags      (mb_info + 0)
#define mb_fb_addr    (mb_info + 88)
#define mb_fb_pitch   (mb_info + 96)
#define mb_fb_width   (mb_info + 100)
#define mb_fb_height  (mb_info + 104)
#define mb_fb_bpp     (mb_info + 108)
#define mb_fb_type    (mb_info + 109)
#define vbe_info      0x7F00
#define vbe_pitch     (vbe_info + 16)
#define vbe_width     (vbe_info + 18)
#define vbe_height    (vbe_info + 20)
#define vbe_bpp       (vbe_info + 25)
#define vbe_phys      (vbe_info + 40)

    .code16
    .text
    .globl _boot
_boot:
    /* BIOS bizi 0x0000:0x7C00'e yukler. Bagi 0 tabanli tutup
     * DS/ES/SS'i 0x07C0 yapiyoruz: boylece butun ofsetler kucuk
     * kalir ve 16-bit yer degistirmeye sigar. 0x7C00 tabanli
     * baglamak "relocation truncated to fit" veriyordu. */
    /* GERCEK MODDA 16-bit uzak atlama olmali. "ljmpl" 0x66 onekiyle
     * 32-bit ofset uretiyor ve islemci resetleniyordu (QEMU hic
     * cikti vermeden cikiyordu). */
    ljmp    $0x07C0, $(1f - _boot)
1:  cli
    /* Gercek modda da DOGRUDAN seri porta isaret: BIOS teletype
     * VGA'ya gidiyor ve otomatik doğrulamada gorunmuyor. */
    movb    $0x31, %al
    call    ser16
    movw    $0x07C0, %ax
    movw    %ax, %ds
    movw    %ax, %es
    xorw    %ax, %ax
    movw    %ax, %ss
    movw    $0x7C00, %sp
    sti

    /* BIOS disk numarasini DL'de birakir */
    movb    %dl, disk_no


    /* multiboot yapisini sifirla. ES'i gecici olarak 0 yapiyoruz
     * ki $mb_info mutlak adres olarak calissin. */
    pushw   %es
    xorw    %ax, %ax
    movw    %ax, %es
    movw    $mb_info, %di
    movw    $120, %cx
    cld
    rep stosb
    popw    %es

/* ---- 2. Cekirdegi oku: LBA 1'den itibaren KERNEL_SECTORS sektor ----
 * int 0x13 AH=0x42 (genisletilmis okuma) DAP yapisi ister.
 * Bir seferde en fazla 127 sektor guvenli; parca parca okuyoruz.
 * Hedef: 0x10000 (64 KB), segment adim adim ilerliyor. */
    movw    $0, sec_done
load_loop:
    movw    sec_done, %ax
    cmpw    $KERNEL_SECTORS, %ax
    jae     load_done

    /* bu turda kac sektor: en fazla 64 (32 KB) */
    movw    $KERNEL_SECTORS, %bx
    subw    %ax, %bx
    cmpw    $64, %bx
    jbe     1f
    movw    $64, %bx
1:  movw    %bx, dap_count

    /* LBA = 1 + sec_done */
    movw    %ax, %cx
    incw    %cx
    movw    %cx, dap_lba

    /* hedef segment: 0x1000 + (sec_done * 512 / 16) = 0x1000 + sec_done*32 */
    movw    %ax, %dx
    shlw    $5, %dx
    addw    $0x1000, %dx
    movw    %dx, dap_seg
    movw    $0, dap_off

    movw    $dap, %si
    movb    disk_no, %dl
    movb    $0x42, %ah
    int     $0x13
    jc      disk_err

    movw    sec_done, %ax
    addw    dap_count, %ax
    movw    %ax, sec_done
    jmp     load_loop
load_done:
    movb    $0x32, %al
    call    ser16


/* ---- 3. VBE kipi kur ----
 * Once mod bilgisini al (AX=0x4F01), dogrusal tampon adresini
 * ogren, sonra kipi ac (AX=0x4F02, bit 14 = dogrusal tampon).
 * Basarisiz olursa metin kipinde devam ediyoruz - cekirdek
 * cerceve tamponu YOK diye bildirecek. */
    pushw   %es
    xorw    %ax, %ax
    movw    %ax, %es
    movw    $VBE_MODE, %cx
    movw    $vbe_info, %di
    movw    $0x4F01, %ax
    int     $0x10
    popw    %es
    cmpw    $0x004F, %ax
    jne     no_video

    movw    $VBE_MODE, %bx
    orw     $0x4000, %bx            /* dogrusal cerceve tamponu */
    movw    $0x4F02, %ax
    int     $0x10
    cmpw    $0x004F, %ax
    jne     no_video

    /* mb_/vbe_ MUTLAK adresler: ES = 0 yapip oradan erisiyoruz */
    xorw    %ax, %ax
    movw    %ax, %es

    /* multiboot yapisina yaz: bayrak bit 12 (0x1000) */
    movl    $0x1000, %es:mb_flags
    movw    %es:vbe_pitch, %ax
    movzwl  %ax, %eax
    movl    %eax, %es:mb_fb_pitch
    movw    %es:vbe_width, %ax
    movzwl  %ax, %eax
    movl    %eax, %es:mb_fb_width
    movw    %es:vbe_height, %ax
    movzwl  %ax, %eax
    movl    %eax, %es:mb_fb_height
    movb    %es:vbe_bpp, %al
    movb    %al, %es:mb_fb_bpp
    movl    %es:vbe_phys, %eax
    movl    %eax, %es:mb_fb_addr
    movl    $0, %es:mb_fb_addr+4
    movb    $1, mb_fb_type          /* dogrudan renk */
    jmp     video_done
no_video:
    movl    $0x0, %es:mb_flags
video_done:
    movb    $0x33, %al
    call    ser16

/* ---- 4. A20 ---- */
    inb     $0x92, %al
    orb     $2, %al
    outb    %al, $0x92

/* ---- 5. Korumali mod ----
 * GDT tabani MUTLAK adres olmali. Kod 0 tabanli baglandigi ve
 * DS=0x07C0 oldugu icin "gdt" sembolu 0x7C00 eklenmeden yaziliyordu;
 * islemci cop bir GDT okuyup resetleniyordu (isaretler "123"te
 * duruyordu). Calisma aninda duzeltiyoruz. */
    cli
    xorl    %eax, %eax
    movw    $gdt, %ax
    addl    $0x7C00, %eax
    movl    %eax, gdt_base
    lgdt    gdt_desc
    movl    %cr0, %eax
    orl     $1, %eax
    movl    %eax, %cr0
    ljmpl   $0x08, $(pm_start + 0x7C00)

disk_err:
    movb    $0x45, %al              /* 'E' */
    call    ser16
1:  hlt
    jmp     1b

/* ser16(AL = bayt) - DOGRUDAN seri porta. BIOS teletype VGA'ya
 * gidiyor ve otomatik dogrulamada gorunmuyor; tanilama icin UART
 * sart. Tek yordam: uc ayri yerde tekrarlayinca sektor tasti. */
ser16:
    pushw   %dx
    movw    $0x3F8, %dx
    outb    %al, %dx
    popw    %dx
    ret


/* ================== 32-BIT KORUMALI MOD ================== */
    .code32
pm_start:
    /* Korumali modda BIOS yok; tanilama icin DOGRUDAN seri porta
     * yaziyoruz. UART'i cekirdek kuruyor ama QEMU varsayilani
     * calisir durumda, tek karakter icin yeterli. */
    movw    $0x10, %ax
    movw    %ax, %ds
    movw    %ax, %es
    movw    %ax, %fs
    movw    %ax, %gs
    movw    %ax, %ss
    movl    $0x90000, %esp

    /* 6. Cekirdegi 0x10000'den 0x100000'e kopyala */
    movw    $0x3F8, %dx
    movb    $0x50, %al
    outb    %al, %dx

    movl    $0x10000, %esi
    movl    $0x100000, %edi
    movl    $(KERNEL_SECTORS * 512 / 4), %ecx
    cld
    rep movsl

    /* 7. Multiboot sozlesmesi ile cekirdege atla */
    movw    $0x3F8, %dx
    movb    $0x4B, %al
    outb    %al, %dx

    movl    $0x2BADB002, %eax
    movl    $mb_info, %ebx
    /* Cekirdegin GIRIS NOKTASI 0x100000 DEGIL: baglayici _start'i
     * ortalara koyuyor. Adres ELF basligindan okunup buraya
     * gomuluyor (tools/disk-yap.py). Once 0x100000'e atliyordum ve
     * kod ortasina dusuyordu - hic cikti gelmiyordu. */
    ljmpl   $0x08, $KERNEL_ENTRY

/* ================== VERI ================== */
    .align 4
/* Disk Adres Paketi (int 0x13 AH=0x42) */
dap:
    .byte   16                      /* yapi boyutu */
    .byte   0
dap_count:
    .word   0
dap_off:
    .word   0
dap_seg:
    .word   0
dap_lba:
    .quad   0

sec_done:   .word 0
disk_no:    .byte 0


    .align 8
gdt:
    .quad   0                       /* bos */
    /* kod: taban 0, sinir 4G, 32-bit, calistirilabilir */
    .word   0xFFFF, 0x0000
    .byte   0x00, 0x9A, 0xCF, 0x00
    /* veri: taban 0, sinir 4G, 32-bit, yazilabilir */
    .word   0xFFFF, 0x0000
    .byte   0x00, 0x92, 0xCF, 0x00
gdt_end:
gdt_desc:
    .word   gdt_end - gdt - 1
gdt_base:
    .long   0                       /* calisma aninda doldurulur */

/* Multiboot yapisi ve VBE tamponu SEKTORUN DISINDA: 512 bayta
 * sigmiyorlar. Bos dusuk bellekte sabit adresler kullaniyoruz.
 * 0x7E00 onyukleyicinin hemen ardi, cekirdek 0x10000'e gidiyor. */
    .org 510
    .word 0xAA55
