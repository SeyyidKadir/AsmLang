/* user_syms.inc - C / C++ islevlerini asmlang'e tanitma
 *
 * ================== NEDEN ==================
 *
 * FFI'de ham cagri (cagir(adres, ...)) vardi ama ADRESI BULMANIN
 * yolu yoktu. dlopen/dlsym bizde YOK: ikili statik + nostdlib, ve
 * bare-metal'de yukleyici kavrami zaten yok.
 *
 * Cozum: STATIK BAGLAMA. C kodunuzu imajla birlikte derliyorsunuz,
 * burada tanitiyorsunuz, asmlang adla buluyor. Bu her hedefte
 * calisir - bare-metal dahil.
 *
 * ================== KULLANIM ==================
 *
 * 1) C dosyanizi yazin (ornekler/c_ornek.c):
 *
 *      int topla(int a, int b) { return a + b; }
 *
 *    C++ ise: extern "C" { ... }  ile sarin, yoksa ad bozulur.
 *
 * 2) Asagida tanitin:
 *
 *      CSYM(5, topla, "topla")
 *          ^  ^      ^
 *          |  |      asmlang'de gorunen ad
 *          |  C sembolu
 *          adin harf sayisi
 *
 * 3) Derleyin:
 *
 *      USER_SRC="ornekler/c_ornek.c" ./build.sh linux-x86_64
 *
 * 4) Kullanin:
 *
 *      yazdir c("topla", 20, 22)      // -> 42
 *      tanim adr = cbul("topla")      // adresi al
 *      yazdir cagir(adr, 20, 22)      // ham cagri
 *
 * ================== SINIRLAR ==================
 *
 * - Argumanlar ve donus degeri TAMSAYI. Kayan nokta, yapi geciren
 *   ya da donduren islevler desteklenmiyor.
 * - En fazla 6 arguman (SysV x86_64); i386/ARM'de 4.
 * - Bare-metal'de C kodunuz FREESTANDING olmali: libc yok,
 *   printf/malloc yok.
 * - Ad HIC dogrulanmaz: yanlis imzali bir islevi cagirmak cokme
 *   demektir. cagir() ile ayni risk sinifinda.
 */
#ifndef USER_SYMS_INC
#define USER_SYMS_INC

/* Kayit 64 bayt: islev isaretcisi + uzunluk + ad.
 * (48 denedim: .balign iki kuvveti ister, assembler reddetti.)
 * natives.inc'teki NT ile ayni ilke; oradaki hatalari tekrarlamamak
 * icin tests/lint.py CSYM uzunluklarini da denetliyor. */
#define CSYM(l, f, s) \
    .p2align 6;       \
    PTR f;            \
    PTR l;            \
    .ascii s;         \
    .balign 64

    SECT_RODATA
    /* Tablonun BASLANGICI da 64'e hizali olmali; yoksa ilk kaydin
     * uzunlugu 48 cikiyor ve tarama ikinci kaydi kaciriyor.
     * (Olculdu: 0x4141d0 -> 0x414200 = 48 bayt.) */
    .p2align 6
    .globl SYM(g_csyms)
SYM(g_csyms):

/* ---- BURAYA KENDI ISLEVLERINIZI EKLEYIN ---- */
#if defined(USER_SYMS) && USER_SYMS
    CSYM(5, topla, "topla")
    CSYM(4, kare, "kare")
    CSYM(7, cpu_adi, "cpu_adi")
#endif
/* ---- BURAYA KADAR ---- */

    /* Nobetci: tarama burada durur. YENI KAYITLARI BUNDAN ONCE
     * EKLEYIN - sonrasina eklenen kayit HIC gorulmez. Bu hatayi
     * govde fonksiyonu tablosunda bir kez yaptim. */
    PTR 0
    PTR 0
    .balign 64

    SECT_TEXT

#endif /* USER_SYMS_INC */
