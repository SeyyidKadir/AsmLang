/* opcodes.inc - bytecode komut kumesi ve deger etiketleri */
#ifndef OPCODES_INC
#define OPCODES_INC

/* ---- Deger yerlesimi: 8 bayt slot ----
 *   +0  u32 etiket
 *   +4  u32 yuk
 * 32 ve 64 bitte ayni. Asama 3 tam sayi VM'i; kayan nokta ve 64-bit
 * NaN-boxing Asama 5'e birakildi.
 *
 * T_INT'in 0 olmasi bilincli: iki islenenin de tamsayi oldugunu
 * "t1 | t2" tek OR ile denetlemek icin. Ayrica sifirlanmis slot
 * dogal olarak tamsayi 0 oluyor.
 */
#define T_INT   0
#define T_NIL   1
#define T_BOOL  2
#define T_OBJ   3       /* yuk = nesne TUTAMAGI (isaretci degil!) */
#define T_FN    4       /* yuk = g_fns dizisindeki indeks */
#define T_NAT   5       /* yuk = govde fonksiyonu indeksi */

/* ---- Neden tutamak, isaretci degil ----
 * Yuk alani u32. 64-bitte isaretci sigmaz; slotu 16 bayta cikarmak
 * yerine nesneler g_objs tablosunda indekslenir. Iki kazanc:
 *   1. Deger yerlesimi 32 ve 64 bitte AYNI kalir (projenin baslangictan
 *      beri uyguladigi ilke: token, AST, atlama hedefi hepsi indeksli).
 *   2. Butun basvurular tek tablodan gectigi icin cop toplayici
 *      SIKISTIRMA yapabilir - nesneyi tasi, tablodaki tek girdiyi
 *      guncelle. Yigindaki/kureseldeki degerlere dokunmak gerekmez.
 * Bedeli: nesne erisiminde bir dolayli yukleme.
 */
#define O_STR   1
#define O_ARR   2
/* O_BUF: ham bayt tamponu. Dizgiden farki DEGISTIRILEBILIR olmasi ve
 * icinde tutamak bulunmamasi (GC taramaz). Ikili dosya G/C, dizgi
 * kodlamasi ve ileride MMIO icin ortak temel. */
#define O_BUF   3

/* Nesne basligi: 24 bayt, 8'e hizali
 *   +0 tur  +4 toplam boyut  +8 tutamak  +12 isaret  +16 uzunluk  +20 kapasite
 */
#define OBJ_KIND  0
#define OBJ_SIZE  4
#define OBJ_HND   8
#define OBJ_MARK  12
#define OBJ_LEN   16
#define OBJ_CAP   20
#define OBJ_DATA  24
#define HND_ORPHAN 0xFFFFFFFF

#define MAX_OBJS  4096

/* ---- Deger yuvasi ----
 * Yuk genisligi = MAKINE KELIMESI.
 *   x86_64 / aarch64 : 64-bit tamsayi, yuva 16 bayt
 *   i386   / arm32   : 32-bit tamsayi, yuva  8 bayt  (degisiklik yok)
 *
 * NEDEN boyle: 64-bit tamsayi 32-bit hedefte IKI register ister ve
 * butun VM'in register duzenini yeniden yazmak demektir. Oysa 64-bit
 * ihtiyaci (tasma payi, FFI isaretcisi) zaten 64-bit hedeflerde.
 * i386'da isaretci de tamsayi da 32 bit; orada kazanc yok, bedel var.
 *
 * BEDELI: .bc dosyasi artik kelime genisligine bagli. Basliga damga
 * konuyor ve uyusmazlik REDDEDILIYOR - sessizce yanlis calismasindansa
 * temiz hata. */
#define VAL_SIZE  (2 * WORD_SIZE)
#define VAL_TAG   0
#define VAL_PAY   WORD_SIZE
#if WORD_SIZE == 8
#  define VAL_SHIFT 4
#else
#  define VAL_SHIFT 3
#endif

/* ---- Komut kodlamasi: 4 bayt, hizali ----
 *   bit  0-7   islem kodu
 *   bit  8-15  kullanilmiyor
 *   bit 16-31  islenen (sabit indeksi / yuva / atlama hedefi)
 * Sabit genislik hizasizlik sorununu tumden kaldiriyor (ARM32'de onemli)
 * ve cozumleme tek yukleme + iki ALU islemine iniyor.
 */
#define INS_SIZE  4
#define OPD_SHIFT 16

#define OP_HALT       0
#define OP_CONST      1
#define OP_NIL        2
#define OP_TRUE       3
#define OP_FALSE      4
#define OP_POP        5
#define OP_GETLOCAL   6
#define OP_SETLOCAL   7
#define OP_GETGLOBAL  8
#define OP_SETGLOBAL  9
#define OP_DEFGLOBAL  10
#define OP_ADD        11
#define OP_SUB        12
#define OP_MUL        13
#define OP_DIV        14
#define OP_MOD        15
#define OP_NEG        16
#define OP_NOT        17
#define OP_EQ         18
#define OP_NE         19
#define OP_LT         20
#define OP_LE         21
#define OP_GT         22
#define OP_GE         23
#define OP_JMP        24
#define OP_JZ         25    /* yanlissa atla, degeri tuket   */
#define OP_JZP        26    /* yanlissa atla, degeri BIRAK   */
#define OP_JNZP       27    /* dogruysa atla, degeri BIRAK   */
#define OP_PRINT      28
#define OP_CALL       29
#define OP_RET        30
#define OP_ARRAY      31    /* islenen = eleman sayisi */
#define OP_INDEX      32
#define OP_SETIDX     33
/* --- gozetleme deligi (peephole) birlestirmeleri --- */
#define OP_SETGLOBAL_P 34   /* SETGLOBAL + POP */
#define OP_SETLOCAL_P  35   /* SETLOCAL  + POP */
#define OP_ADDK        36   /* CONST k + ADD   */
#define OP_SUBK        37   /* CONST k + SUB   */
#define OP_JEQ         38   /* NE + JZ  -> esitse atla */
#define OP_JNE         39   /* EQ + JZ */
#define OP_JLT         40   /* GE + JZ */
#define OP_JLE         41   /* GT + JZ */
#define OP_JGT         42   /* LE + JZ */
#define OP_JGE         43   /* LT + JZ */
/* --- superkomutlar: 16-bit islenen alani iki 8-bit alan tasiyor ---
 * Kuresel/yerel yuva sayisi 256'yi gecmedigi surece iki islenen sigar.
 * Sigmazsa gozetleme deligi birlestirmeyi atlar, dogruluk bozulmaz.
 */
#define OP_GETGLOBAL2 44   /* GETGLOBAL a + GETGLOBAL b   (a | b<<8) */
#define OP_GETLOCAL2  45   /* GETLOCAL  a + GETLOCAL  b   */
#define OP_ADD_SETG   46   /* ADD + SETGLOBAL_P n         */
#define OP_ADD_SETL   47   /* ADD + SETLOCAL_P  n         */
#define OP_ADDK_SETG  48   /* ADDK k + SETGLOBAL_P n      (k | n<<8) */
#define OP_INCGLOBAL  49   /* GETGLOBAL n + ADDK_SETG(k,n) (n | k<<8) */
#define OP_JNZ        50   /* dogruysa atla, degeri tuket (dongu geri kenari) */
#define OP_GETG_CONST 51   /* GETGLOBAL n + CONST k  (n | k<<8) */
#define OP_GETL_CONST 52   /* GETLOCAL  n + CONST k  */
#define OP_RETL       53   /* GETLOCAL n + RET */
#define OP_RETK       54   /* CONST k   + RET */
/* ACCG: gvals[a] += gvals[b]  - yigina HIC dokunmaz.
 * "x = x + y" birikimi cok yaygin. Ayni zamanda TOS caching icin
 * VEKIL OLCUM: TOS'un en iyi ihtimalle kazandiracagi seyin ust siniri,
 * cunku bu komut yigin trafiginin TAMAMINI kaldiriyor. */
#define OP_ACCG       55   /* GETGLOBAL2(a,b) + ADD_SETG(a) */
/* --- bit islemleri --- */
#define OP_BAND      56
#define OP_BOR       57
#define OP_BXOR      58
#define OP_SHL       59
#define OP_SHR       60
#define OP_BNOT      61

#define OP_COUNT   62

#define MAX_CONTS     64

#define MAX_CODE      8192
#define MAX_CONSTS    8192

#define MAX_LOCALS    64
#define MAX_GLOBALS   256
/* Cagri derinligi. 64 fazla dusuktu ve SINIR DENETIMI YOKTU:
 * 65. cerceve g_frames'in disina, dogrudan g_nframe uzerine yaziyordu.
 * Sonuc cokme degil SESSIZ YANLIS CEVAPTI (f(70) -> 16). En kotu tur.
 * Artik hem sinir buyuk hem denetim var. */
#define MAX_FRAMES    1024
/* Deger yigini boyu; op_call'da tasma denetimi icin de kullanilir. */
#define VM_STACK_BYTES 65536
#define VM_STACK_MARGIN 1024
/* Dosya okuma tamponu; natives.S ve rt/input.S ortak kullanir */
#define FILE_BUF_SIZE   65536
/* g_strbuf 4096 bayt; NUL ve hizalama payi birakilarak sinir. */
#define STRBUF_MAX      4000


#define MAX_LOOPS     16
#define MAX_BREAKS    64

#endif
