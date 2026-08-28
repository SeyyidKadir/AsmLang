#!/usr/bin/env python3
"""Mimariden bagimsiz lexer tablolarini uretir -> src/tables/charclass.inc

Uretilen tablolar:
  cc_table[256]   bayt -> karakter sinifi
  op1_table[256]  bayt -> tek karakterli token id
  op2_table[256]  bayt -> '=' ile birlesince olusan token id
"""
import os

C_BAD, C_SPACE, C_DIGIT, C_ALPHA, C_QUOTE, C_SLASH, C_PUNCT, C_OP = range(8)

T = {
    "ERROR": 1,
    "LPAREN": 30, "RPAREN": 31, "LBRACE": 32, "RBRACE": 33,
    "LBRACK": 34, "RBRACK": 35, "COMMA": 36, "DOT": 37,
    "SEMI": 38, "COLON": 39, "PLUS": 40, "MINUS": 41,
    "STAR": 42, "SLASH": 43, "PERCENT": 44,
    "ASSIGN": 50, "EQ": 51, "NE": 52, "LT": 53,
    "LE": 54, "GT": 55, "GE": 56, "BANG": 57,
    "AMP": 63, "PIPE": 64, "CARET": 65, "TILDE": 66,
    "SHL": 67, "SHR": 68,
    "PLUSEQ": 58, "MINUSEQ": 59, "STAREQ": 60,
    "SLASHEQ": 61, "PCTEQ": 62,
}

cc = [C_BAD] * 256
op1 = [T["ERROR"]] * 256
op2 = [T["ERROR"]] * 256

for c in "\t\n\v\f\r ":
    cc[ord(c)] = C_SPACE
for c in "0123456789":
    cc[ord(c)] = C_DIGIT
for c in "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ_":
    cc[ord(c)] = C_ALPHA
# UTF-8 devam baytlari: tum >=0x80 tanimlayici harfi sayilir.
# Boylece ı ğ ş ö ü ç ve diger tum Unicode harfler Unicode tablosu
# olmadan gecerli olur.
for b in range(0x80, 0x100):
    cc[b] = C_ALPHA
for c in "\"'":
    cc[ord(c)] = C_QUOTE
cc[ord("/")] = C_SLASH

punct = {
    "(": "LPAREN", ")": "RPAREN", "{": "LBRACE", "}": "RBRACE",
    "[": "LBRACK", "]": "RBRACK", ",": "COMMA", ".": "DOT",
    ";": "SEMI", ":": "COLON", "+": "PLUS", "-": "MINUS",
    "*": "STAR", "%": "PERCENT",
}
for c, name in punct.items():
    cc[ord(c)] = C_PUNCT
    op1[ord(c)] = T[name]
op1[ord("/")] = T["SLASH"]          # yorum degilse bolme
op2[ord("/")] = T["SLASHEQ"]        # "/=" 

ops = {"=": ("ASSIGN", "EQ"), "!": ("BANG", "NE"),
       "<": ("LT", "LE"), ">": ("GT", "GE"),
       "&": ("AMP", "AMP"), "|": ("PIPE", "PIPE"),
       "^": ("CARET", "CARET"), "~": ("TILDE", "TILDE"),
       "+": ("PLUS", "PLUSEQ"), "-": ("MINUS", "MINUSEQ"),
       "*": ("STAR", "STAREQ"), "%": ("PERCENT", "PCTEQ")}
for c, (single, double) in ops.items():
    cc[ord(c)] = C_OP
    op1[ord(c)] = T[single]
    op2[ord(c)] = T[double]


def emit(f, name, data):
    f.write("    .p2align 4\n")
    f.write("    .globl SYM(%s)\nSYM(%s):\n" % (name, name))
    for i in range(0, 256, 16):
        f.write("    .byte " + ",".join(str(v) for v in data[i:i + 16]) + "\n")
    f.write("\n")


out = os.path.join(os.path.dirname(__file__), "..", "src", "tables", "charclass.inc")
with open(out, "w") as f:
    f.write("/* OTOMATIK URETILDI - tools/gen_tables.py, elle duzenleme */\n")
    f.write("#ifndef CHARCLASS_INC\n#define CHARCLASS_INC\n\n")
    f.write("    SECT_RODATA\n\n")
    emit(f, "cc_table", cc)
    emit(f, "op1_table", op1)
    emit(f, "op2_table", op2)
    f.write("#endif\n")
print("yazildi:", os.path.normpath(out))

# ===================== Asama 2: parser tablolari =====================
N = {
    "NONE": 0, "NUMBER": 1, "STRING": 2, "IDENT": 3, "TRUE": 4, "FALSE": 5,
    "NIL": 6, "UNARY": 7, "BINARY": 8, "ASSIGN": 9, "CALL": 10, "LOGICAL": 11, "ARRAY": 12, "INDEX": 13,
    "BLOCK": 20, "LET": 21, "CONST": 22, "IF": 23, "WHILE": 24, "RETURN": 25,
    "BREAK": 26, "CONTINUE": 27, "PRINT": 28, "EXPRSTMT": 29, "FN": 30,
    "PARAM": 31, "PROGRAM": 32, "FOR": 33,
}
ND_A, ND_B, ND_C, NOFLD = 8, 12, 16, 255

# prec_table[token] = (sol baglama gucu, dugum turu, sag birlesme)
prec = [(0, 0, 0)] * 128   # token 68e kadar var
for tok, lbp, kind, rassoc in [
    (50, 1, N["ASSIGN"], 1),                       # =
    (58, 1, N["ASSIGN"], 1),                       # +=
    (59, 1, N["ASSIGN"], 1),                       # -=
    (60, 1, N["ASSIGN"], 1),                       # *=
    (61, 1, N["ASSIGN"], 1),                       # /=
    (62, 1, N["ASSIGN"], 1),                       # %=
    (24, 2, N["LOGICAL"], 0),                      # or / veya
    (23, 3, N["LOGICAL"], 0),                      # and / ve
    # --- bit islemleri: C sirasi  |  ^  &  ---
    (64, 4, N["BINARY"], 0),                                   # |
    (65, 5, N["BINARY"], 0),                                   # ^
    (63, 6, N["BINARY"], 0),                                   # &
    (51, 7, N["BINARY"], 0), (52, 7, N["BINARY"], 0),          # == !=
    (53, 8, N["BINARY"], 0), (54, 8, N["BINARY"], 0),          # <  <=
    (55, 8, N["BINARY"], 0), (56, 8, N["BINARY"], 0),          # >  >=
    (67, 9, N["BINARY"], 0), (68, 9, N["BINARY"], 0),          # << >>
    (40, 10, N["BINARY"], 0), (41, 10, N["BINARY"], 0),        # +  -
    (42, 11, N["BINARY"], 0), (43, 11, N["BINARY"], 0),
    (44, 11, N["BINARY"], 0),                                  # *  /  %
    (30, 13, N["CALL"], 0),                                    # (
    (34, 13, N["INDEX"], 0),                                   # [
]:
    prec[tok] = (lbp, kind, rassoc)

# kind_kids: hangi alanlar dugum indeksi (bit0=a bit1=b bit2=c)
# kind_tokfld: yazdirilacak token indeksi tutan alanin ofseti (yoksa 255)
kids = [0] * 64
tokfld = [NOFLD] * 64
for name, k, t in [
    ("NUMBER", 0, ND_A), ("STRING", 0, ND_A), ("IDENT", 0, ND_A),
    ("TRUE", 0, NOFLD), ("FALSE", 0, NOFLD), ("NIL", 0, NOFLD),
    ("UNARY", 1, ND_B), ("BINARY", 3, ND_C), ("LOGICAL", 3, ND_C),
    ("ASSIGN", 3, NOFLD), ("CALL", 3, NOFLD),
    ("ARRAY", 1, NOFLD), ("INDEX", 3, NOFLD),
    ("BLOCK", 1, NOFLD), ("LET", 2, ND_A), ("CONST", 2, ND_A),
    ("IF", 7, NOFLD), ("WHILE", 3, NOFLD), ("RETURN", 1, NOFLD),
    ("BREAK", 0, NOFLD), ("CONTINUE", 0, NOFLD), ("PRINT", 1, NOFLD),
    ("EXPRSTMT", 1, NOFLD), ("FN", 6, ND_A), ("PARAM", 0, ND_A), ("FOR", 7, NOFLD),
    ("PROGRAM", 1, NOFLD),
]:
    kids[N[name]] = k
    tokfld[N[name]] = t

names = ["?"] * 64
for name, v in N.items():
    names[v] = name


def emit_bytes(f, name, data, per=16):
    f.write("    .p2align 4\n    .globl SYM(%s)\nSYM(%s):\n" % (name, name))
    for i in range(0, len(data), per):
        f.write("    .byte " + ",".join(str(v) for v in data[i:i + per]) + "\n")
    f.write("\n")


out2 = os.path.join(os.path.dirname(__file__), "..", "src", "tables", "prec.inc")
with open(out2, "w") as f:
    f.write("/* OTOMATIK URETILDI - tools/gen_tables.py, elle duzenleme */\n")
    f.write("#ifndef PREC_INC\n#define PREC_INC\n\n    SECT_RODATA\n\n")
    flat = []
    for lbp, kind, rassoc in prec:
        flat += [lbp, kind, rassoc, 0]
    emit_bytes(f, "prec_table", flat)
    emit_bytes(f, "kind_kids", kids)
    emit_bytes(f, "kind_tokfld", tokfld)
    # kind_names: 16 baytlik kayit { u32 uzunluk; char[12] }
    f.write("    .p2align 4\n    .globl SYM(kind_names)\nSYM(kind_names):\n")
    for nm in names:
        nm = nm[:12]
        f.write('    .long %d; .ascii "%s"; .balign 16\n' % (len(nm), nm))
    f.write("\n#endif\n")
print("yazildi:", os.path.normpath(out2))

# ===================== Asama 3: islem kodu adlari =====================
OPS = ["HALT","CONST","NIL","TRUE","FALSE","POP","GETLOCAL","SETLOCAL",
       "GETGLOBAL","SETGLOBAL","DEFGLOBAL","ADD","SUB","MUL","DIV","MOD",
       "NEG","NOT","EQ","NE","LT","LE","GT","GE","JMP","JZ","JZP","JNZP",
       "PRINT","CALL","RET","ARRAY","INDEX","SETIDX",
       "SETGLOBAL_P","SETLOCAL_P","ADDK","SUBK",
       "JEQ","JNE","JLT","JLE","JGT","JGE",
       "GETGLOBAL2","GETLOCAL2","ADD_SETG","ADD_SETL","ADDK_SETG","INCGLOBAL",
       "JNZ","GETG_CONST","GETL_CONST","RETL","RETK","ACCG"]
out3 = os.path.join(os.path.dirname(__file__), "..", "src", "tables", "opnames.inc")
with open(out3, "w") as f:
    f.write("/* OTOMATIK URETILDI - tools/gen_tables.py */\n")
    f.write("#ifndef OPNAMES_INC\n#define OPNAMES_INC\n\n    SECT_RODATA\n")
    f.write("    .p2align 4\n    .globl SYM(op_names)\nSYM(op_names):\n")
    for nm in OPS:
        f.write('    .long %d; .ascii "%s"; .balign 16\n' % (len(nm), nm))
    # islenen bir atlama hedefi mi? (gozetleme deligi yeniden esleme icin)
    JUMPS = {"JMP","JZ","JZP","JNZP","JNZ","JEQ","JNE","JLT","JLE","JGT","JGE"}
    isj = [1 if nm in JUMPS else 0 for nm in OPS] + [0] * (64 - len(OPS))
    f.write("/* op_isjump -> opjump.inc */\n")

    for i in range(0, 64, 16):
        f.write("    .byte " + ",".join(str(v) for v in isj[i:i+16]) + "\n")
    f.write("\n#endif\n")
print("yazildi:", os.path.normpath(out3))

# ============ Asama 8: islenen anlam tablosu (dogrulama icin) ============
# Her islem kodunun islenen alani NE anlama geliyor? Dogrulama pass'i
# bunu bilmeden "target < code_count" gibi kontrolleri yapamaz.
OPK = {"NONE":0, "CODE":1, "CONST":2, "GLOBAL":3, "LOCAL":4, "COUNT":5,
       "GG":6, "LL":7, "GC":8, "LC":9, "CG":10}
OPKIND = {
  "CONST":"CONST", "ADDK":"CONST", "SUBK":"CONST",
  "RETL":"LOCAL", "RETK":"CONST",
  "GETLOCAL":"LOCAL", "SETLOCAL":"LOCAL", "SETLOCAL_P":"LOCAL", "ADD_SETL":"LOCAL",
  "GETGLOBAL":"GLOBAL", "SETGLOBAL":"GLOBAL", "DEFGLOBAL":"GLOBAL",
  "SETGLOBAL_P":"GLOBAL", "ADD_SETG":"GLOBAL",
  "JMP":"CODE", "JZ":"CODE", "JZP":"CODE", "JNZP":"CODE", "JNZ":"CODE",
  "JEQ":"CODE", "JNE":"CODE", "JLT":"CODE", "JLE":"CODE", "JGT":"CODE", "JGE":"CODE",
  "CALL":"COUNT", "ARRAY":"COUNT",
  "GETGLOBAL2":"GG", "GETLOCAL2":"LL", "ACCG":"GG",
  "GETG_CONST":"GC", "INCGLOBAL":"GC",     # dusuk=global, yuksek=sabit
  "GETL_CONST":"LC",                        # dusuk=yerel,  yuksek=sabit
  "ADDK_SETG":"CG",                         # dusuk=sabit,  yuksek=global
}
kinds = [OPK[OPKIND.get(nm, "NONE")] for nm in OPS] + [0] * (64 - len(OPS))
out4 = os.path.join(os.path.dirname(__file__), "..", "src", "tables", "opkind.inc")
with open(out4, "w") as f:
    f.write("/* OTOMATIK URETILDI - tools/gen_tables.py */\n")
    f.write("#ifndef OPKIND_INC\n#define OPKIND_INC\n\n")
    for k, v in sorted(OPK.items(), key=lambda x: x[1]):
        f.write("#define OPK_%-7s %d\n" % (k, v))
    f.write("\n    SECT_RODATA\n    .p2align 4\n")
    f.write("    .globl SYM(op_opkind)\nSYM(op_opkind):\n")
    for i in range(0, 64, 16):
        f.write("    .byte " + ",".join(str(v) for v in kinds[i:i+16]) + "\n")
    f.write("\n#endif\n")
print("yazildi:", os.path.normpath(out4))


# --- op_isjump ayri dosyada: hem derleyici hem YURUTUCU kullaniyor ---
out5 = os.path.join(os.path.dirname(__file__), "..", "src", "tables", "opjump.inc")
with open(out5, "w") as g2:
    g2.write("/* OTOMATIK URETILDI - tools/gen_tables.py */\n")
    g2.write("#ifndef OPJUMP_INC\n#define OPJUMP_INC\n\n    SECT_RODATA\n")
    g2.write("    .p2align 4\n    .globl SYM(op_isjump)\nSYM(op_isjump):\n")
    for i in range(0, 64, 16):
        g2.write("    .byte " + ",".join(
            ("1" if OPS[k] in JUMPS else "0") if k < len(OPS) else "0"
            for k in range(i, i + 16)) + "\n")
    g2.write("\n#endif\n")
print("yazildi:", os.path.normpath(out5))
