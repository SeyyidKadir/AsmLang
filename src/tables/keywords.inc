/* keywords.inc - cift dilli anahtar kelime tablosu
 *
 * Kayit: 16 bayt  { u32 uzunluk; u32 token; char metin[8] }
 * Isaretci yok -> tablo 32 ve 64 bitte birebir ayni.
 * Sabit 8 baytlik metin alani en uzun anahtar kelimeyi karsilar
 * ("continue" = 8, "döndür" = 8 bayt UTF-8).
 *
 * Ayni token birden fazla yazimla eslesir:
 *   dogru Turkce   ("eğer")
 *   ASCII katlanmis ("eger")   -> Turkce klavye olmadan da yazilabilir
 *   Ingilizce      ("if")
 *
 * NOT: Turkce'de i/I katlamasi bozuk oldugu icin (ı-I ve i-İ) esleme
 * BUYUK/kucuk HARF DUYARLIDIR ve bayt bazinda birebirdir. Anahtar
 * kelimeler yalnizca kucuk harfle yazilir.
 */
#ifndef KEYWORDS_INC
#define KEYWORDS_INC

#define KW(l, t, s) .long l; .long t; .ascii s; .balign 16

    SECT_RODATA
    .p2align 4
    .globl SYM(kw_table)
SYM(kw_table):
    /* --- bildirim --- */
    KW(4, TOK_FN,       "fonk")
    KW(2, TOK_FN,       "fn")
    KW(5, TOK_LET,      "tanim")
    KW(6, TOK_LET,      "tan\304\261m")          /* tanım */
    KW(3, TOK_LET,      "let")
    KW(5, TOK_CONST,    "sabit")
    KW(5, TOK_CONST,    "const")

    /* --- denetim akisi --- */
    KW(4, TOK_IF,       "eger")
    KW(5, TOK_IF,       "e\304\237er")           /* eğer */
    KW(2, TOK_IF,       "if")
    KW(5, TOK_ELSE,     "yoksa")
    KW(4, TOK_ELSE,     "else")
    KW(4, TOK_WHILE,    "iken")
    KW(5, TOK_WHILE,    "while")
    KW(3, TOK_FOR,      "her")
    KW(3, TOK_FOR,      "for")
    KW(3, TOK_BREAK,    "kir")
    KW(4, TOK_BREAK,    "k\304\261r")            /* kır */
    KW(5, TOK_BREAK,    "break")
    KW(5, TOK_CONTINUE, "devam")
    KW(8, TOK_CONTINUE, "continue")
    KW(6, TOK_RETURN,   "dondur")
    KW(8, TOK_RETURN,   "d\303\266nd\303\274r")  /* döndür */
    KW(6, TOK_RETURN,   "return")

    /* --- degismezler --- */
    KW(5, TOK_TRUE,     "dogru")
    KW(6, TOK_TRUE,     "do\304\237ru")          /* doğru */
    KW(4, TOK_TRUE,     "true")
    KW(6, TOK_FALSE,    "yanlis")
    KW(8, TOK_FALSE,    "yanl\304\261\305\237")  /* yanlış */
    KW(5, TOK_FALSE,    "false")
    KW(3, TOK_NIL,      "bos")
    KW(4, TOK_NIL,      "bo\305\237")            /* boş */
    KW(3, TOK_NIL,      "nil")

    /* --- mantik --- */
    KW(2, TOK_AND,      "ve")
    KW(3, TOK_AND,      "and")
    KW(4, TOK_OR,       "veya")
    KW(2, TOK_OR,       "or")
    KW(5, TOK_NOT,      "degil")
    KW(6, TOK_NOT,      "de\304\237il")          /* değil */
    KW(3, TOK_NOT,      "not")

    /* --- cikti (parantezsiz deyim) --- */
    KW(6, TOK_PRINT,    "yazdir")
    KW(7, TOK_PRINT,    "yazd\304\261r")           /* yazdır */
    KW(5, TOK_PRINT,    "print")

    /* --- bitis nobetcisi --- */
    .long 0
    .long 0
    .balign 16

#endif
