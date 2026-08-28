/* tokens.inc - token kimlikleri ve lexer karakter siniflari
 * Mimariden bagimsiz. gen_tables.py ile ayni degerleri kullanir.
 */
#ifndef TOKENS_INC
#define TOKENS_INC

/* ---- karakter siniflari (cc_table degerleri) ---- */
#define C_BAD    0
#define C_SPACE  1
#define C_DIGIT  2
#define C_ALPHA  3
#define C_QUOTE  4
#define C_SLASH  5
#define C_PUNCT  6
#define C_OP     7
#define C_COUNT  8

/* ---- token kimlikleri ---- */
#define TOK_EOF       0
#define TOK_ERROR     1
#define TOK_IDENT     2
#define TOK_NUMBER    3
#define TOK_STRING    4

/* anahtar kelimeler */
#define TOK_FN        10
#define TOK_LET       11
#define TOK_CONST     12
#define TOK_IF        13
#define TOK_ELSE      14
#define TOK_WHILE     15
#define TOK_FOR       16
#define TOK_BREAK     17
#define TOK_CONTINUE  18
#define TOK_RETURN    19
#define TOK_TRUE      20
#define TOK_FALSE     21
#define TOK_NIL       22
#define TOK_AND       23
#define TOK_OR        24
#define TOK_NOT       25
#define TOK_PRINT     26

/* noktalama */
#define TOK_LPAREN    30
#define TOK_RPAREN    31
#define TOK_LBRACE    32
#define TOK_RBRACE    33
#define TOK_LBRACK    34
#define TOK_RBRACK    35
#define TOK_COMMA     36
#define TOK_DOT       37
#define TOK_SEMI      38
#define TOK_COLON     39
#define TOK_PLUS      40
#define TOK_MINUS     41
#define TOK_STAR      42
#define TOK_SLASH     43
#define TOK_PERCENT   44

/* operatorler */
#define TOK_ASSIGN    50
#define TOK_EQ        51
#define TOK_NE        52
#define TOK_LT        53
#define TOK_LE        54
#define TOK_GT        55
#define TOK_GE        56
#define TOK_BANG      57

/* ---- Token kaydi: 16 bayt, tamami u32 ----
 *   +0  tur
 *   +4  satir
 *   +8  kaynaktaki bayt ofseti
 *   +12 bayt uzunlugu
 * Hepsi u32 oldugu icin 32 ve 64 bitte ayni yerlesim, bayt yazmasi gerekmez.
 */
/* Derleyici kaynak sinirlari. Denetimsizken tasma SESSIZ BELLEK
 * BOZULMASI uretiyordu (cerceve tasmasiyla ayni sinif). */
#define MAX_TOKENS    4096
/* Bilesik atama. 58+ BOS aralik: 46-50'ye koyup ASSIGN(50) ile
 * cakistirmistim. Token/dugum numaralari iki yerde tutuldugu icin
 * (tokens.inc ve gen_tables.py) her ekleme once BOSLUK KONTROLU
 * ister - bu projede ucuncu kez ayni tuzak. */
#define TOK_PLUSEQ    58
#define TOK_MINUSEQ   59
#define TOK_STAREQ    60
#define TOK_SLASHEQ   61
#define TOK_PCTEQ     62

/* Bit islemleri. 63-70 BOS aralik (kontrol edildi).
 * Donanim programlamada sart: maskeleme, bayrak kurma, kaydirma.
 * Bunlar olmadan BAR maskelemesi bolme/kalanla yapiliyordu ve
 * negatif degerde TERS calisiyordu (Asama 51). */
#define TOK_AMP       63    /* &  bit ve      */
#define TOK_PIPE      64    /* |  bit veya    */
#define TOK_CARET     65    /* ^  bit ozelveya*/
#define TOK_TILDE     66    /* ~  bit degil   */
#define TOK_SHL       67    /* << sola kaydir */
#define TOK_SHR       68    /* >> saga kaydir */

#define TOK_SIZE      16
#define TOK_OFF_TYPE  0
#define TOK_OFF_LINE  4
#define TOK_OFF_START 8
#define TOK_OFF_LEN   12

#endif
