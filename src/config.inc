/* config.inc - mimari ve isletim sistemi tespiti
 * Bu dosya derleyicinin onceden tanimli makrolarindan hedefi cikarir.
 * Kaynakta hicbir yerde __x86_64__ gibi ham makrolar kullanilmaz;
 * sadece ARCH_* / OS_* kullanilir.
 */
#ifndef CONFIG_INC
#define CONFIG_INC

/* ---- Mimari ---- */
#if defined(__x86_64__) || defined(_M_X64)
#  define ARCH_X86_64  1
#  define WORD_SIZE    8
#elif defined(__i386__) || defined(_M_IX86)
#  define ARCH_I386    1
#  define WORD_SIZE    4
#elif defined(__aarch64__) || defined(_M_ARM64)
#  define ARCH_AARCH64 1
#  define WORD_SIZE    8
#elif defined(__arm__) || defined(_M_ARM)
#  define ARCH_ARM     1
#  define WORD_SIZE    4
#else
#  error "Desteklenmeyen mimari"
#endif

/* ---- Isletim sistemi ----
 * BARE: hicbir isletim sistemi yok. Cekirdek/gomulu imaj icin.
 * Derleyicinin onceden tanimli bir makrosu olmadigi icin -DBARE=1
 * ile secilir ve digerlerinden ONCE bakilir. */
#if defined(BARE) && BARE
#  define OS_BARE      1
#elif defined(__linux__)
#  define OS_LINUX     1
#elif defined(__APPLE__)
#  define OS_MACOS     1
#elif defined(_WIN32) || defined(__MINGW32__) || defined(__CYGWIN__)
#  define OS_WINDOWS   1
#else
#  error "Desteklenmeyen isletim sistemi"
#endif

/* ---- Gecersiz kombinasyonlar ---- */
#if defined(OS_MACOS) && (defined(ARCH_I386) || defined(ARCH_ARM))
#  error "macOS artik 32-bit desteklemiyor"
#endif
#if defined(OS_WINDOWS) && defined(ARCH_ARM)
#  error "Windows 32-bit ARM desteklenmiyor"
#endif

/* ---- Sembol on eki ----
 * Mach-O ve Windows/i386 sembolleri alt cizgi ile onekler.
 * SYM() her global sembol tanimi ve referansinda kullanilir.
 */
#if defined(OS_MACOS) || (defined(OS_WINDOWS) && defined(ARCH_I386))
#  define SYM(n) _##n
#else
#  define SYM(n) n
#endif

/* VM yigin slotu her hedefte 8 bayt. 64-bit'te NaN-boxing,
 * 32-bit'te 4 bayt tag + 4 bayt payload. */
#define SLOT_SIZE 8

/* ---- Optimizasyon anahtarlari ----
 * Hepsi varsayilan olarak ACIK. Benchmark harness bunlari -D ile
 * kapatarak ayni kaynaktan farkli varyantlar uretir.
 *   OPT_ROTATE    dongu rotasyonu (kosulu dibe al)
 *   OPT_PEEPHOLE  gozetleme deligi (dar kurallar)
 *   OPT_SUPER     superkomutlar (acgozlu asama 1)
 *   OPT_INTERN    sabit havuzu ic ice gecirme (dedup)
 *   OPT_COUNT     VM dagitim sayaci (olcum icin; kendisi yavaslatir)
 */
#ifndef OPT_ROTATE
#  define OPT_ROTATE   1
#endif
#ifndef OPT_PEEPHOLE
#  define OPT_PEEPHOLE 1
#endif
#ifndef OPT_SUPER
#  define OPT_SUPER    1
#endif
/* OPT_OVFCHK: tamsayi tasmasinda sessizce sarmak yerine hata ver */
#ifndef OPT_OVFCHK
#  define OPT_OVFCHK  1
#endif
/* OPT_TYPECHK=0: aritmetikteki BUTUN tur denetimlerini kaldirir.
 * GUVENSIZ - dizgi birlestirmeyi ve tur hatalarini bozar.
 * Tek amaci: tur ozellesmesinin (ADD_II) kazanc TAVANINI olcmek.
 * Cikarim motoru yazmadan once tavani bilmek istiyoruz. */
/* OPT_CFI=0: yonlendirme savunmalarini kapatir (SET_PC sinir denetimi,
 * obj_ptr tutamak denetimi). GUVENSIZ - yalniz maliyet olcumu icin.
 * optable/nat_fns doldurmasi bundan BAGIMSIZ: sifir maliyetli, hep acik. */
/* OPT_BASEREG: kuresel/sabit havuzu tabanlarini registerda tut.
 *
 * OLCULDU: 60M turluk kosuda, CPU zamaniyla, 20 tekrar ->
 *   registerli 466,78 ms   LEA ile 468,88 ms   (min 458,65 / 458,43)
 * Fark %0,45, olcum gurultusunun (%1-2) ALTINDA. Kazanc yok.
 *
 * VARSAYILAN KAPALI: mekanizma duruyor ama VC ve VK registerlarini
 * serbest birakiyor. TOS caching bu iki registeri istiyor ve beklenen
 * kazanci daha buyuk; olculemeyen bir iyilestirme icin kit kaynagi
 * harcamak yanlis takas olurdu. */
#ifndef OPT_BASEREG
#  define OPT_BASEREG 0
#endif
#ifndef OPT_CFI
#  define OPT_CFI 1
#endif
#ifndef OPT_TYPECHK
#  define OPT_TYPECHK 1
#endif
#ifndef OPT_INTERN
#  define OPT_INTERN   1
#endif
#ifndef OPT_COUNT
#  define OPT_COUNT    0
#endif

/* ---- Kanarya (canary) ----
 * Her sabit tampona GUARD_PAD bayt fazla ayrilir ve sonuna sihirli
 * deger yazilir. Tasmayi ONLEMEZ; sessiz bellek bozulmasini GURULTULU
 * hataya cevirir. Fuzzer'in bozulmayi gorebilmesi icin sart:
 * kanarya olmadan tasma komsu degiskeni ezip sessizce devam ediyor,
 * fuzzer "gecti" diyor. */
#define GUARD_PAD    16
#define GUARD_MAGIC  0x7E57C0DE
#if WORD_SIZE == 8
#  define WORD_SHIFT 3
#else
#  define WORD_SHIFT 2
#endif

/* Deger yuvasi kopyalama: etiket (32 bit) + yuk (KELIME genisliginde).
 * Yuva 16 bayta cikinca eski 8-baytlik kopyalama yuku kaybediyordu:
 * butun sabitler 0 goruluyordu. Tek yerde tanimli olsun ki bir daha
 * genislik degisirse burasi yetsin. */
/* Etiket 32 bit ama gecici registerin "W" turevini makro icinde
 * uretemiyoruz (t##W calismiyor: t zaten %rsi gibi tam ad).
 * Etiketi de kelime genisliginde tasiyoruz - etiket 0..5 arasi,
 * ust bitler zaten sifir ve dolgu alanina yaziyoruz. */
#define VCOPY(d,s,t)  LD_OFF(t, s, VAL_TAG); ST_OFF(d, VAL_TAG, t); \
                      LD_OFF(t, s, VAL_PAY); ST_OFF(d, VAL_PAY, t)

/* 10'un kuvvetleri tablosunun girdi sayisi. Tamsayi genisligine
 * bagli: 64-bit'te 20 basamak, 32-bit'te 10. Hem print_u32 hem
 * i32_to_str kullaniyor -> ORTAK basikta. */
#if WORD_SIZE == 8
#  define POW10_N 20
#else
#  define POW10_N 10
#endif

#endif /* CONFIG_INC */
