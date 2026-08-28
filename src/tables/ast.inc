/* ast.inc - AST dugum turleri ve yerlesimi
 *
 * Dugumlere ISARETCIYLE degil INDEKSLE erisilir. Butun alanlar u32
 * oldugu icin AST yapisi 32 ve 64 bitte birebir ayni; parser kodunda
 * hicbir yerde isaretci boyutu gecmez.
 *
 * Dugum 0 "null" nobetcisidir, hicbir zaman kullanilmaz.
 */
#ifndef AST_INC
#define AST_INC

/* ---- dugum yerlesimi: 32 bayt, adres = taban + (indeks << 5) ----
 * 32 bayt secildi cunku carpma yerine tek kaydirma yetiyor.
 */
#define MAX_NODES   8192
/* Ayristirici ozyineleme derinligi. Sinirsizken 3000 ic ice parantez
 * makine yigininini tasiriyordu. */
#define MAX_PARSE_DEPTH 200
#define NODE_SHIFT  5
#define NODE_SIZE   32
#define ND_KIND     0
#define ND_LINE     4
#define ND_A        8
#define ND_B        12
#define ND_C        16
#define ND_NEXT     20

/* ---- ifadeler ---- */
#define N_NONE      0
#define N_NUMBER    1   /* a = token indeksi */
#define N_STRING    2   /* a = token indeksi */
#define N_IDENT     3   /* a = token indeksi */
#define N_TRUE      4
#define N_FALSE     5
#define N_NIL       6
#define N_UNARY     7   /* a = islenen,  b = operator token indeksi */
#define N_BINARY    8   /* a = sol, b = sag, c = operator token indeksi */
#define N_ASSIGN    9   /* a = hedef, b = deger */
#define N_CALL      10  /* a = cagrilan, b = ilk arguman (next ile zincir) */
#define N_LOGICAL   11  /* a = sol, b = sag, c = operator (kisa devre) */
#define N_ARRAY     12  /* a = ilk eleman (next ile zincir) */
#define N_INDEX     13  /* a = nesne, b = indeks */

/* ---- deyimler ---- */
#define N_BLOCK     20  /* a = ilk deyim */
#define N_LET       21  /* a = ad token indeksi, b = ilk deger */
#define N_CONST     22
#define N_IF        23  /* a = kosul, b = govde, c = yoksa dali */
#define N_WHILE     24  /* a = kosul, b = govde */
#define N_RETURN    25  /* a = ifade */
#define N_BREAK     26
#define N_CONTINUE  27
#define N_PRINT     28  /* a = ifade */
#define N_EXPRSTMT  29  /* a = ifade */
#define N_FN        30  /* a = ad token, b = ilk parametre, c = govde */
#define N_PARAM     31  /* a = ad token indeksi */
#define N_PROGRAM   32  /* a = ilk deyim */
/* her (baslangic; kosul; adim): A = kosul, B = govde, C = adim.
 * DIKKAT: bu numara gen_tables.py'deki N sozlugu ile AYNI olmali.
 * Ilk denememde 27 yazip N_CONTINUE ile cakistirdim, sonra
 * N_PROGRAM'i kaydirip uretilen tablolarla ayristirdim: iki kez
 * butun derleyiciyi bozdum. Iki yerde tutulan bir numara, tek
 * yerde tutulmali - ama en azindan ayni olmali. */
#define N_FOR       33  /* a = ilk deyim */

/* Onek (unary) baglama gucu: prec_table'daki en yuksek ikili
 * operatorden (9 = cagri) dusuk, carpmadan (7) yuksek olmali. */
#define BP_UNARY    8

#endif
