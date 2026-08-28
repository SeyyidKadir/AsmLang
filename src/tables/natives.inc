/* natives.inc - govde (native) fonksiyon ad tablosu
 * Kayit: 16 bayt { u32 uzunluk; u32 indeks; char metin[8] }
 * Anahtar kelime tablosuyla ayni sekil; ayni cift dil ilkesi gecerli.
 */
#ifndef NATIVES_INC
#define NATIVES_INC

#define NAT_LEN   0
#define NAT_PUSH  1
#define NAT_STR   2
#define NAT_READ  3
#define NAT_NUM   4
#define NAT_RDF   5
#define NAT_WRF   6
#define NAT_BUF   7
#define NAT_RDB   8
#define NAT_WRB   9
#define NAT_TOS   10
#define NAT_SAVE  11
#define NAT_ARGC  12
#define NAT_ARG   13
#define NAT_TOBUF 14
/* --- yeni: matematik, dizi, dizgi --- */
#define NAT_ABS   15
#define NAT_MIN   16
#define NAT_MAX   17
#define NAT_POW   18
#define NAT_TYPE  19
#define NAT_WR    20
#define NAT_POP   21
#define NAT_REV   22
#define NAT_HAS   23
#define NAT_SUB   24
#define NAT_FIND  25
#define NAT_UPPER 26
#define NAT_LOWER 27
#define NAT_STARTS 28
#define NAT_ENDS  29
#define NAT_CURS  30
#define NAT_CLS   31
#define NAT_COLOR 32
#define NAT_FFI   33
#define NAT_ADDR  34
#define NAT_MKC   35
/* --- taban donusumu ve dizi/dizgi --- */
#define NAT_TOBASE 36
#define NAT_FRBASE 37
#define NAT_JOIN   38
#define NAT_SPLIT  39
#define NAT_SLICE  40
#define NAT_SORT   41
#define NAT_HEX    42
#define NAT_BIN    43
/* --- isletim sistemi primitifleri --- */
#define NAT_MRD    44
#define NAT_MWR    45
#define NAT_PRD    46
#define NAT_PWR    47
#define NAT_CPUID  48
/* --- ekran, ses, disk --- */
#define NAT_SCREEN 49
#define NAT_PIXEL  50
#define NAT_CLSFB  51
#define NAT_VGA    52
#define NAT_BEEP   53
#define NAT_BEEPOFF 54
#define NAT_DISKRD 55
#define NAT_CBUL   56
#define NAT_C      57
#define NAT_BOOT   58
#define NAT_KEYHIT 59
#define NAT_SCAN   60
#define NAT_KEY    61
#define NAT_MSINIT 62
#define NAT_MSHIT  63
#define NAT_MOUSE  64
#define NAT_COUNT  65

/* Kayit 32 bayt: 4 (uzunluk) + 4 (indeks) + 24 (ad).
 * ONCE 16 baytti, yani ada yalnizca 8 bayt kaliyordu ve
 * "makinekod" (9) / "startswith" (10) gibi adlar SONRAKI KAYDI
 * eziyordu - tablo sessizce bozuluyordu. */
#define NT(l, i, s) .long l; .long i; .ascii s; .balign 32

#ifndef NAT_COUNT_ONLY

    SECT_RODATA
    .p2align 4
    .globl SYM(nat_table)
SYM(nat_table):
    NT(7, NAT_LEN,  "uzunluk")
    NT(3, NAT_LEN,  "len")
    NT(4, NAT_PUSH, "ekle")
    NT(4, NAT_PUSH, "push")
    NT(4, NAT_STR,  "yazi")
    NT(3, NAT_STR,  "str")
    /* --- girdi --- */
    NT(3, NAT_READ, "oku")
    NT(4, NAT_READ, "read")
    NT(5, NAT_READ, "input")
    NT(4, NAT_NUM,  "sayi")
    NT(3, NAT_NUM,  "num")
    /* --- dosya --- */
    NT(5, NAT_RDF,  "dosya")
    NT(8, NAT_RDF,  "readfile")
    NT(4, NAT_WRF,  "yazf")
    NT(5, NAT_WRF,  "write")
    /* --- bayt tamponu --- */
    NT(6, NAT_BUF,  "tampon")
    NT(6, NAT_BUF,  "buffer")
    NT(5, NAT_RDB,  "ikili")
    NT(7, NAT_RDB,  "readbin")
    NT(6, NAT_WRB,  "yazikl")
    NT(8, NAT_WRB,  "writebin")
    NT(5, NAT_TOS,  "metin")
    NT(5, NAT_TOS,  "tostr")
    /* --- bytecode dosyasi --- */
    NT(6, NAT_SAVE, "kaydet")
    NT(4, NAT_SAVE, "save")
    /* --- komut satiri --- */
    NT(6, NAT_ARGC, "argsay")
    NT(4, NAT_ARGC, "argc")
    NT(3, NAT_ARG,  "arg")
    NT(4, NAT_ARG,  "argv")
    NT(7, NAT_TOBUF, "tampona")
    NT(5, NAT_TOBUF, "tobuf")
    /* --- matematik --- */
    NT(6, NAT_ABS,   "mutlak")
    NT(3, NAT_ABS,   "abs")
    NT(2, NAT_MIN,   "en")
    NT(3, NAT_MIN,   "min")
    NT(3, NAT_MAX,   "buy")
    NT(3, NAT_MAX,   "max")
    NT(2, NAT_POW,   "us")
    NT(3, NAT_POW,   "pow")
    /* --- tur ve cikti --- */
    NT(3, NAT_TYPE,  "tur")
    NT(4, NAT_TYPE,  "type")
    NT(3, NAT_WR,    "yaz")
    NT(2, NAT_WR,    "wr")
    /* --- dizi --- */
    NT(5, NAT_POP,   "cikar")
    NT(3, NAT_POP,   "pop")
    NT(4, NAT_REV,   "ters")
    NT(7, NAT_REV,   "reverse")
    NT(6, NAT_HAS,   "icerir")
    NT(3, NAT_HAS,   "has")
    /* --- dizgi --- */
    NT(5, NAT_SUB,   "parca")
    NT(6, NAT_SUB,   "substr")
    NT(3, NAT_FIND,  "bul")
    NT(4, NAT_FIND,  "find")
    NT(5, NAT_UPPER, "buyuk")
    NT(5, NAT_UPPER, "upper")
    NT(5, NAT_LOWER, "kucuk")
    NT(5, NAT_LOWER, "lower")
    NT(6, NAT_STARTS, "baslar")
    NT(10, NAT_STARTS, "startswith")
    NT(5, NAT_ENDS,  "biter")
    NT(8, NAT_ENDS,  "endswith")
    /* --- konsol --- */
    NT(5, NAT_CURS,  "imlec")
    NT(6, NAT_CURS,  "cursor")
    NT(7, NAT_CLS,   "temizle")
    NT(5, NAT_CLS,   "clear")
    NT(4, NAT_COLOR, "renk")
    NT(5, NAT_COLOR, "color")
    /* --- FFI: ham cagri (yukleyici GEREKTIRMEZ) --- */
    NT(5, NAT_FFI,   "cagir")
    NT(4, NAT_FFI,   "call")
    NT(5, NAT_ADDR,  "adres")
    NT(4, NAT_ADDR,  "addr")
    /* makinekod(tampon) -> calistirilabilir bellege kopyalar, adres doner */
    NT(9, NAT_MKC,   "makinekod")
    NT(8, NAT_MKC,   "machcode")
    /* --- taban donusumu --- */
    NT(5, NAT_TOBASE, "taban")
    NT(6, NAT_TOBASE, "tobase")
    NT(9, NAT_HEX,    "onaltilik")
    NT(3, NAT_HEX,    "hex")
    NT(6, NAT_BIN,    "ikilik")
    NT(3, NAT_BIN,    "bin")
    NT(8, NAT_FRBASE, "tabandan")
    NT(8, NAT_FRBASE, "frombase")
    /* --- dizi / dizgi --- */
    NT(9, NAT_JOIN,  "birlestir")
    NT(4, NAT_JOIN,  "join")
    NT(3, NAT_SPLIT, "bol")
    NT(5, NAT_SPLIT, "split")
    NT(5, NAT_SLICE, "dilim")
    NT(5, NAT_SLICE, "slice")
    NT(6, NAT_SORT,  "sirala")
    NT(4, NAT_SORT,  "sort")
    /* --- OS primitifleri --- */
    NT(10, NAT_MRD, "bellek_oku")
    NT(5, NAT_MRD, "memrd")
    NT(10, NAT_MWR, "bellek_yaz")
    NT(5, NAT_MWR, "memwr")
    NT(8, NAT_PRD, "port_oku")
    NT(3, NAT_PRD, "inp")
    NT(8, NAT_PWR, "port_yaz")
    NT(4,  NAT_PWR,   "outp")
    NT(5,  NAT_CPUID, "cpuid")
    /* --- ekran / ses / disk (bare-metal) --- */
    NT(5,  NAT_SCREEN,  "ekran")
    NT(6,  NAT_SCREEN,  "screen")
    NT(6,  NAT_PIXEL,   "piksel")
    NT(5,  NAT_PIXEL,   "pixel")
    NT(13, NAT_CLSFB,   "ekran_temizle")
    NT(7,  NAT_CLSFB,   "clearfb")
    NT(3,  NAT_VGA,     "vga")
    NT(3,  NAT_BEEP,    "ses")
    NT(4,  NAT_BEEP,    "beep")
    NT(9,  NAT_BEEPOFF, "ses_kapat")
    NT(7,  NAT_BEEPOFF, "beepoff")
    NT(8,  NAT_DISKRD,  "disk_oku")
    NT(6,  NAT_DISKRD,  "diskrd")
    /* --- C / C++ islevleri --- */
    NT(4,  NAT_CBUL, "cbul")
    NT(7,  NAT_CBUL, "csymbol")
    NT(1,  NAT_C,    "c")
    NT(6,  NAT_BOOT, "acilis")
    NT(4,  NAT_BOOT, "boot")
    /* --- klavye --- */
    NT(7, NAT_KEYHIT, "tus_var")
    NT(6, NAT_KEYHIT, "keyhit")
    NT(6, NAT_SCAN,   "tuskod")
    NT(8, NAT_SCAN,   "scancode")
    NT(3, NAT_KEY,    "tus")
    NT(3, NAT_KEY,    "key")
    /* --- fare --- */
    NT(8, NAT_MSINIT, "fare_kur")
    NT(10, NAT_MSINIT, "mouse_init")
    NT(8, NAT_MSHIT,  "fare_var")
    NT(8, NAT_MSHIT,  "mousehit")
    NT(4, NAT_MOUSE,  "fare")
    NT(5, NAT_MOUSE,  "mouse")
    .long 0
    .long 0
    .balign 32
#endif

#endif
