/* lexer.S - tablo guduml√ºlexer, mimariden bagimsiz
 *
 * Ana dongu tek bir hesaplanmis dallanmadir:
 *     sinif = cc_table[bayt];  goto cc_jump[sinif]
 * Butun karar mantigi veride; burada yalnizca tablolari yuruten motor var.
 *
 * Neden lexer tarafsiz makrolarla yazildi da elle dort kez degil:
 * lexer kaynak boyutunda BIR KEZ calisir. Asil sicak dongu VM dagitimi
 * (NEXT) olacak ve o, mimari basina elle yazilacak. Optimizasyon emegini
 * milyarlarca kez donen donguye saklıyoruz.
 *
 * Registerlar:  VP = imlec, VS = kaynak sonu, VF = token yazma imleci
 */
#include "../abi.inc"
#include "../tables/tokens.inc"

/* ---- lexer durumu ---- */
    .bss
    .p2align 3
    .globl SYM(g_line)
SYM(g_line):  .space 4
    .globl SYM(g_nerr)
SYM(g_nerr):  .space 4
    .globl SYM(g_toks_end)
SYM(g_toks_end): .space 8
    .globl SYM(g_toks_full)
SYM(g_toks_full): .space 4

#include "../tables/charclass.inc"
#include "../tables/keywords.inc"

/* ---- sinif -> islem dagitim tablosu ---- */
/* ---- sinif -> islem dagitim tablosu ----
 * Mutlak adres DEGIL, lx_base'e gore 32-bit ofset tutulur.
 * Iki kazanc:
 *   1. Tabloda hic yer degistirme (relocation) kaydi olmaz -> PIE ve
 *      static-pie bagliyor sorunsuz calisir. Android/Termux PIE zorunlu
 *      kilabildigi icin bu sart.
 *   2. Tablo 64-bitte de 32 bit kalir -> onbellek dostu.
 * Ayni teknik Asama 2'de bytecode optable icin de kullanilacak.
 */
    SECT_RODATA
    .p2align 4
    .globl SYM(cc_jump)
SYM(cc_jump):
    .long lx_bad   - lx_base    /* C_BAD   */
    .long lx_space - lx_base    /* C_SPACE */
    .long lx_digit - lx_base    /* C_DIGIT */
    .long lx_alpha - lx_base    /* C_ALPHA */
    .long lx_quote - lx_base    /* C_QUOTE */
    .long lx_slash - lx_base    /* C_SLASH */
    .long lx_punct - lx_base    /* C_PUNCT */
    .long lx_op_entry - lx_base /* C_OP    */

    SECT_TEXT
/* Butun ofsetler pozitif olsun diye taban en basta. */
lx_base:

/* =====================================================================
 * emit_tok(A0 = token turu, A1 = sozcuk baslangic isaretcisi)
 * Bitis olarak VP'yi kullanir (dahili yardimci; VP her zaman canli).
 * VF'yi 16 bayt ilerletir.
 * ===================================================================== */
FUNC(emit_tok)
    ENTER(2)
    SPILL(0, A0)                    /* token turu - denetim A0'i ezecek */
    SPILL(1, A1)
    /* token dizisi doldu mu: tasarsa VF komsu bellege yazardi */
    LEA_SYM(A0, SYM(g_toks_end))
    LD(A0, A0)
    CMPR(VF, A0)
    BHS(et_full)
    FILL(A0, 0)
    ST32_OFF(VF, TOK_OFF_TYPE, A0W)

    LEA_SYM(A1, SYM(g_line))
    LD32(A0W, A1)
    ST32_OFF(VF, TOK_OFF_LINE, A0W)

    FILL(A0, 1)                     /* baslangic isaretcisi */
    LEA_SYM(A1, SYM(g_src))
    LD(A1, A1)
    SUB(A0, A1)                     /* -> kaynak ofseti */
    ST32_OFF(VF, TOK_OFF_START, A0W)

    MOVR(A0, VP)
    FILL(A1, 1)
    SUB(A0, A1)                     /* -> uzunluk */
    ST32_OFF(VF, TOK_OFF_LEN, A0W)

    ADDI(VF, TOK_SIZE)
    LEAVE_
    RET
/* Token dizisi doldu. Sadece durmak YETMEZ: parser TOK_EOF nobetcisini
 * arayarak ilerliyor, nobetci yazilmazsa dizinin disina tasiyor (bu
 * gercek bir segfault uretti). Son yuvaya EOF yazip kaynagi bitiriyoruz. */
et_full:
    LEA_SYM(A0, SYM(g_toks_full))
    LD32(A1W, A0)
    BNZ(A1, et_done)
    MOVI(A1, 1)
    ST32_OFF(A0, 0, A1W)
    LEA_SYM(A0, SYM(g_nerr))
    LD32(A1W, A0)
    INC(A1)
    ST32_OFF(A0, 0, A1W)
    MOVI(A0, TOK_EOF)
    ST32_OFF(VF, TOK_OFF_TYPE, A0W)
    MOVI(A0, 0)
    ST32_OFF(VF, TOK_OFF_LINE, A0W)
    ST32_OFF(VF, TOK_OFF_START, A0W)
    ST32_OFF(VF, TOK_OFF_LEN, A0W)
    ADDI(VF, TOK_SIZE)
    MOVR(VP, VS)                    /* kaynagi bitir */
et_done:
    LEAVE_
    RET
ENDFUNC(emit_tok)

/* =====================================================================
 * kw_lookup(A0 = isaretci, A1 = uzunluk) -> RV = token turu
 * Bulunamazsa TOK_IDENT doner.
 * TODO: dogrusal tarama. 40 girdi icin kabul edilebilir; Asama 2'de
 *       ilk bayt + uzunluga gore mukemmel hash'e cevrilecek.
 * ===================================================================== */
FUNC(kw_lookup)
    ENTER(4)
    SPILL(0, A0)                    /* isaretci   */
    SPILL(1, A1)                    /* uzunluk    */
    CMPI(A1, 8)
    BHI(kw_no)                      /* 8 bayttan uzun -> tanimlayici */

    LEA_SYM(A0, SYM(kw_table))
    SPILL(2, A0)

kw_next:
    FILL(A0, 2)
    LD32(A1W, A0)                   /* girdi uzunlugu */
    BZ(A1, kw_no)                   /* 0 = nobetci */
    FILL(A2, 1)
    CMPR(A1, A2)
    BNE(kw_adv)                     /* uzunluk tutmuyor */

    MOVI(A0, 0)
    SPILL(3, A0)                    /* i = 0 */
kw_cmp:
    FILL(A0, 3)
    FILL(A1, 1)
    CMPR(A0, A1)
    BHS(kw_hit)                     /* i >= uzunluk -> tam eslesme */
    FILL(A1, 0)
    LDB_IDX(A2W, A1, A0)            /* tanimlayici[i] */
    FILL(A1, 2)
    ADDI(A1, 8)                     /* girdi metni */
    LDB_IDX(A1W, A1, A0)            /* anahtar[i] */
    CMPR(A1, A2)
    BNE(kw_adv)
    FILL(A0, 3)
    INC(A0)
    SPILL(3, A0)
    B(kw_cmp)

kw_hit:
    FILL(A0, 2)
    LD32_OFF(RVW, A0, 4)
    LEAVE_
    RET

kw_adv:
    FILL(A0, 2)
    ADDI(A0, 16)
    SPILL(2, A0)
    B(kw_next)

kw_no:
    MOVI(RV, TOK_IDENT)
    LEAVE_
    RET
ENDFUNC(kw_lookup)

/* =====================================================================
 * lex_all(A0 = kaynak, A1 = uzunluk, A2 = token dizisi) -> RV = adet
 * Cerceve slotlari: 0=kaynak 1=uzunluk 2=cikti 3,4=islem gecici
 *                   5,6,7=cagiranin VP/VS/VF'i
 * ===================================================================== */
FUNC(lex_all)
    ENTER(8)
    SAVE3(5)
    SPILL(0, A0)
    SPILL(1, A1)
    SPILL(2, A2)

    LEA_SYM(A1, SYM(g_src))         /* g_src = kaynak */
    FILL(A0, 0)
    ST(A1, A0)
    LEA_SYM(A1, SYM(g_line))        /* g_line = 1 */
    MOVI(A0, 1)
    ST32_OFF(A1, 0, A0W)
    LEA_SYM(A1, SYM(g_nerr))        /* g_nerr = 0 */
    MOVI(A0, 0)
    ST32_OFF(A1, 0, A0W)

    FILL(VP, 0)                     /* imlec  = kaynak */
    FILL(VS, 0)
    FILL(A0, 1)
    ADD(VS, A0)                     /* son    = kaynak + uzunluk */
    FILL(VF, 2)                     /* cikti  = token dizisi */
    FILL(A0, 2)
    ADDI(A0, (MAX_TOKENS - 1) * TOK_SIZE)
    LEA_SYM(A1, SYM(g_toks_end))
    ST(A1, A0)
    MOVI(A0, 0)
    LEA_SYM(A1, SYM(g_toks_full))
    ST32_OFF(A1, 0, A0W)

/* --- ana dongu: sinifi bul, dagit --- */
lx_main:
    CMPR(VP, VS)
    BHS(lx_eof)
    LDB(A0W, VP)
    LEA_SYM(A1, SYM(cc_table))
    LDB_IDX(A0W, A1, A0)            /* A0 = karakter sinifi */
    LEA_SYM(TMP, SYM(cc_jump))
    LD32_IDX(TMPW, TMP, A0)         /* ofset (sifir genisletilir) */
    LEA_SYM(A1, lx_base)
    ADD(TMP, A1)
    JMPR(TMP)

/* --- bosluk: satir sayacini guncelle --- */
lx_space:
    LDB(A0W, VP)
    INC(VP)
    CMPI(A0, 10)                    /* '\n' */
    BNE(lx_main)
    LEA_SYM(A1, SYM(g_line))
    LD32(A0W, A1)
    INC(A0)
    ST32_OFF(A1, 0, A0W)
    B(lx_main)

/* --- '/' : yorum mu bolme mi --- */
lx_slash:
    MOVR(A0, VP)
    INC(A0)
    CMPR(A0, VS)
    BHS(lx_punct)
    LDB(A1W, A0)
    CMPI(A1, 47)                    /* '/' */
    BEQ(lx_comment)
    /* "/=" : '/' yorum tespiti icin ayri ele alindigindan genel
     * iki-karakterli operator yoluna (op2_table) girmiyor. Burada
     * elle bakilmali - yoksa "a /= 6" ayristirici hatasi verir. */
    CMPI(A1, 61)                    /* '=' */
    BNE(lx_punct)
    MOVR(A1, VP)
    ADDI(VP, 2)
    MOVI(A0, TOK_SLASHEQ)
    CALL(emit_tok)
    B(lx_main)
lx_comment:
    CMPR(VP, VS)
    BHS(lx_main)
    LDB(A0W, VP)
    CMPI(A0, 10)
    BEQ(lx_main)                    /* '\n' bosluk isleyicisine birakilir */
    INC(VP)
    B(lx_comment)

/* "<<" ve ">>": genel iki-karakterli operator yolu yalniz "X="
 * biciminde olanlari biliyor (op2_table). Ayni karakterin iki kez
 * gelmesi ayri ele alinmali. */
lx_shift:
    MOVR(A0, VP)
    INC(A0)
    CMPR(A0, VS)
    BHS(lx_op)
    LDB(A1W, A0)
    LDB(A2W, VP)
    CMPR(A1, A2)
    BNE(lx_op)
    /* iki ayni karakter: << ya da >> */
    MOVR(A1, VP)
    ADDI(VP, 2)
    CMPI(A2, 60)                    /* '<' */
    BNE(lx_shr)
    MOVI(A0, TOK_SHL)
    CALL(emit_tok)
    B(lx_main)
lx_shr:
    MOVI(A0, TOK_SHR)
    CALL(emit_tok)
    B(lx_main)

/* --- tek karakterli noktalama --- */
lx_punct:
    LDB(A0W, VP)
    LEA_SYM(A1, SYM(op1_table))
    LDB_IDX(A0W, A1, A0)
    MOVR(A1, VP)
    INC(VP)
    CALL(emit_tok)
    B(lx_main)

/* --- = ! < > : ardindan '=' gelebilir --- */
lx_op_entry:
    LDB(A0W, VP)
    CMPI(A0, 60)                    /* '<' */
    BEQ(lx_shift)
    CMPI(A0, 62)                    /* '>' */
    BEQ(lx_shift)
lx_op:
    LDB(A0W, VP)
    SPILL(3, A0)                    /* operator bayti */
    MOVR(A1, VP)
    SPILL(4, A1)                    /* baslangic */
    INC(VP)
    CMPR(VP, VS)
    BHS(lx_op1)
    LDB(A1W, VP)
    CMPI(A1, 61)                    /* '=' */
    BNE(lx_op1)
    INC(VP)
    FILL(A0, 3)
    LEA_SYM(A1, SYM(op2_table))
    LDB_IDX(A0W, A1, A0)
    B(lx_op_emit)
lx_op1:
    FILL(A0, 3)
    LEA_SYM(A1, SYM(op1_table))
    LDB_IDX(A0W, A1, A0)
lx_op_emit:
    FILL(A1, 4)
    CALL(emit_tok)
    B(lx_main)

/* --- sayi: rakamlar + en fazla bir ondalik nokta --- */
lx_digit:
    MOVR(A1, VP)
    SPILL(4, A1)                    /* baslangic */
    MOVI(A0, 0)
    SPILL(3, A0)                    /* nokta gorulду mu */
lx_num_loop:
    CMPR(VP, VS)
    BHS(lx_num_end)
    LDB(A0W, VP)
    CMPI(A0, 46)                    /* '.' */
    BNE(lx_num_digit)
    FILL(A1, 3)
    BNZ(A1, lx_num_end)             /* ikinci nokta -> sayi biter */
    MOVI(A1, 1)
    SPILL(3, A1)
    INC(VP)
    B(lx_num_loop)
lx_num_digit:
    LEA_SYM(A1, SYM(cc_table))
    LDB_IDX(A0W, A1, A0)
    CMPI(A0, C_DIGIT)
    BNE(lx_num_end)
    INC(VP)
    B(lx_num_loop)
lx_num_end:
    MOVI(A0, TOK_NUMBER)
    FILL(A1, 4)
    CALL(emit_tok)
    B(lx_main)

/* --- tanimlayici / anahtar kelime ---
 * cc_table'da 0x80-0xFF tamami C_ALPHA oldugu icin butun UTF-8 harfleri
 * (ı ğ ş ö ü ç dahil) Unicode tablosu olmadan tanimlayicida gecerli.
 */
lx_alpha:
    MOVR(A1, VP)
    SPILL(4, A1)
lx_id_loop:
    CMPR(VP, VS)
    BHS(lx_id_end)
    LDB(A0W, VP)
    LEA_SYM(A1, SYM(cc_table))
    LDB_IDX(A0W, A1, A0)
    CMPI(A0, C_ALPHA)
    BEQ(lx_id_next)
    CMPI(A0, C_DIGIT)
    BNE(lx_id_end)
lx_id_next:
    INC(VP)
    B(lx_id_loop)
lx_id_end:
    FILL(A0, 4)
    MOVR(A1, VP)
    SUB(A1, A0)                     /* uzunluk */
    CALL(kw_lookup)
    MOVR(A0, RV)
    FILL(A1, 4)
    CALL(emit_tok)
    B(lx_main)

/* --- dizgi: acan tirnak kapatani belirler --- */
lx_quote:
    LDB(A0W, VP)
    SPILL(3, A0)                    /* tirnak karakteri */
    MOVR(A1, VP)
    SPILL(4, A1)
    INC(VP)
lx_str_loop:
    CMPR(VP, VS)
    BHS(lx_str_err)
    LDB(A0W, VP)
    CMPI(A0, 92)                    /* '\' kacis */
    BNE(lx_str_chk)
    INC(VP)
    CMPR(VP, VS)
    BHS(lx_str_err)
    INC(VP)
    B(lx_str_loop)
lx_str_chk:
    FILL(A1, 3)
    CMPR(A0, A1)
    BEQ(lx_str_done)
    CMPI(A0, 10)                    /* kapanmadan satir sonu -> hata */
    BEQ(lx_str_err)
    INC(VP)
    B(lx_str_loop)
lx_str_done:
    INC(VP)
    MOVI(A0, TOK_STRING)
    FILL(A1, 4)
    CALL(emit_tok)
    B(lx_main)
lx_str_err:
    MOVI(A0, TOK_ERROR)
    FILL(A1, 4)
    CALL(emit_tok)
    B(lx_err_count)

/* --- taninmayan bayt --- */
lx_bad:
    MOVR(A1, VP)
    SPILL(4, A1)
    INC(VP)
    MOVI(A0, TOK_ERROR)
    FILL(A1, 4)
    CALL(emit_tok)
lx_err_count:
    LEA_SYM(A1, SYM(g_nerr))
    LD32(A0W, A1)
    INC(A0)
    ST32_OFF(A1, 0, A0W)
    B(lx_main)

/* --- kaynak bitti --- */
lx_eof:
    MOVI(A0, TOK_EOF)
    MOVR(A1, VP)
    CALL(emit_tok)
    MOVR(A0, VF)
    FILL(A1, 2)
    SUB(A0, A1)
    SHRI(A0, 4)                     /* / TOK_SIZE */
    MOVR(RV, A0)
    REST3(5)
    LEAVE_
    RET
ENDFUNC(lex_all)
