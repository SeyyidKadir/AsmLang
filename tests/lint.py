#!/usr/bin/env python3
"""tests/lint.py - i386'da RV == A0 cakismasini yakalayan statik denetim

Bu tuzaga ALTI kez dusuldu (Asama 4, 11, 13, 15, 20, 27).
x86_64'te RV=%rax ve A0=%rdi AYRI; i386'da IKISI DE %eax. Hata yalniz
i386'da ortaya cikiyor, x86_64 testleri temiz gorunuyor.

NOT: ilk surum awk ile yazilmisti ve `\\b` kullaniyordu. mawk'ta `\\b`
kelime siniri DEGIL backspace karakteri; kural hicbir zaman eslesmedi
ve denetleyici her zaman "temiz" dedi. Kendi kendini test etmeyen bir
denetleyicinin degeri yok - bu yuzden lint artik kendi testini de
icinde tasiyor (--selftest).

Desen: CALL(...) -> RV baska yere ALINMADAN A0'a yazma -> RV kullanimi
"""
import re, sys, pathlib

RV   = re.compile(r'(?<![A-Za-z_])RVW?(?![A-Za-z_])')
CALL = re.compile(r'^\s*CALL\(')
A0W  = re.compile(r'^\s*(FILL|MOVI|LEA_SYM|MOVR|LD32|LD)\(\s*A0[,)]')
# "RV hala canli" sayilan denetimler. AMA A0 EZILDIYSE canli DEGIL:
# CMPR(RV, A0) i386'da eax'i eax ile karsilastirir, hep esit cikar.
# Once bu deseni "guvenli" sayip atliyordum ve klavye surucusundeki
# gercek hatayi kacirdim (yedinci RV/A0 cakismasi).
TEST = re.compile(r'^\s*(BZ|BNZ|CMPI)\(\s*RVW?[,)]')
SAVE = re.compile(r'^\s*(MOVR|SPILL)\([^)]*(?<![A-Za-z_])RVW?(?![A-Za-z_])')
BOUND= re.compile(r'^(FUNC|ENDFUNC)\(')

def scan(path, text):
    hits, pending, clob, cl, ll = [], False, False, 0, 0
    for i, line in enumerate(text.split("\n"), 1):
        if BOUND.match(line): pending = clob = False; continue
        if CALL.match(line):  pending, clob, ll = True, False, i; continue
        if TEST.match(line) and not (pending and clob): continue
        if SAVE.match(line):  pending = clob = False; continue
        if pending and A0W.match(line): clob, cl = True, i; continue
        # DIKKAT: bazi makrolarda ILK arguman da KAYNAK'tir.
        # CMPR(RV, A0) karsilastirma yapar, RV'ye YAZMAZ. Kural
        # bunu "RV yazildi, guvenli" sanip klavye surucusundeki
        # gercek hatayi KACIRDI (yedinci RV/A0 cakismasi).
        # ST(A0, RV) gibi saklama makrolarinda ilk arguman adres.
        if FIRST_IS_SRC.match(line):
            m2 = re.match(r'^\s*[A-Z_0-9]+\((.*)\)\s*$', line)
            if m2 and any(RV.search(a) for a in m2.group(1).split(",")):
                if pending and clob:
                    hits.append((path, i, ll, cl, line.strip()))
                pending = clob = False
                continue
        # RV ILK argumansa YAZILIYOR demektir (guvenli): FILL(RV,2),
        # MOVI(RV,1), LD32(RVW,A0)... Tehlikeli olan RV'nin SONRAKI
        # argumanda, yani KAYNAK olarak gecmesi: ST(A0, RV).
        m = re.match(r'^\s*[A-Z_0-9]+\((.*)\)\s*$', line)
        args = m.group(1).split(",") if m else []
        rv_src = any(RV.search(a) for a in args[1:])
        rv_dst = bool(args) and bool(RV.search(args[0]))
        if rv_src:
            if pending and clob:
                hits.append((path, i, ll, cl, line.strip()))
            pending = clob = False
        elif rv_dst:
            pending = clob = False
    return hits

# Ilk argumani KAYNAK olan makrolar: karsilastirma, dallanma,
# saklama. Bunlarda RV'nin ilk argumanda gecmesi "yazildi" demek
# DEGIL, "okundu" demektir.
FIRST_IS_SRC = re.compile(r'^\s*(CMPR|CMPI|CMPS|BZ|BNZ|ST|STB|STH|ST32|ST32_OFF|ST_OFF|B[A-Z]{2,3})\(')

SELF_BAD = """FUNC(x)
    CALL(os_alloc_exec)
    BZ(RV, ji_no)
    LEA_SYM(A0, SYM(g_jit_base))
    ST(A0, RV)
ENDFUNC(x)
"""
SELF_BAD2 = """FUNC(x)
    CALL(kbd_ham)
    MOVI(A0, -1)
    CMPR(RV, A0)
ENDFUNC(x)
"""

SELF_OK = """FUNC(x)
    CALL(os_alloc_exec)
    BZ(RV, ji_no)
    MOVR(A1, RV)
    LEA_SYM(A0, SYM(g_jit_base))
    ST(A0, A1)
ENDFUNC(x)
"""

if "--selftest" in sys.argv:
    bad  = len(scan("<test>", SELF_BAD))
    bad2 = len(scan("<test>", SELF_BAD2))
    ok   = len(scan("<test>", SELF_OK))
    print("  selftest: yazma-cakismasi %s, KARSILASTIRMA-cakismasi %s, temiz ornek %s" %
          ("YAKALANDI" if bad else "KACIRILDI",
           "YAKALANDI" if bad2 else "KACIRILDI",
           "temiz" if not ok else "YANLIS ALARM"))
    sys.exit(0 if (bad == 1 and bad2 == 1 and ok == 0) else 1)

root = pathlib.Path(__file__).resolve().parent.parent

# --- govde fonksiyonu tablosu tutarliligi ---
# NT(uzunluk, indeks, "ad") kaydinda uzunluk adin harf sayisiyla AYNI
# olmali. Yanlis olursa ad HIC cozulmez ve "cagrilabilir degil" hatasi
# alinir; sebebi hic belli olmaz. Bir defada YEDI tanesini yanlis
# saydim - elle sayilan her sey bu sinifa girer.
tbl = []
_ni = root / "src" / "tables" / "natives.inc"
if _ni.exists():
    for i, line in enumerate(_ni.read_text().split("\n"), 1):
        m = re.search(r'NT\((\d+),\s*(NAT_[A-Z_]+),\s*"([^"]+)"\)', line)
        if m and int(m.group(1)) != len(m.group(3)):
            tbl.append("  NT UZUNLUK %s:%d  %s yazilmis, \"%s\" %d harf"
                       % (_ni.name, i, m.group(1), m.group(3), len(m.group(3))))
# CSYM(uzunluk, sembol, "ad") ayni sinif: yanlis uzunluk sessizce
# "bulunamadi" demek. cpu_adi'yi 8 yazmistim, 7 harf.
_us = root / "src" / "tables" / "user_syms.inc"
if _us.exists():
    for i, line in enumerate(_us.read_text().split("\n"), 1):
        m = re.search(r'CSYM\((\d+),\s*\w+,\s*"([^"]+)"\)', line)
        if m and int(m.group(1)) != len(m.group(2)):
            tbl.append("  CSYM UZUNLUK %s:%d  %s yazilmis, \"%s\" %d harf"
                       % (_us.name, i, m.group(1), m.group(2), len(m.group(2))))

if _ni.exists():
    # NAT_COUNT ile tablo girdisi sayisi ayni mi
    m = re.search(r'#define NAT_COUNT\s+(\d+)', _ni.read_text())
    _ns = root / "src" / "vm" / "natives.S"
    if m and _ns.exists():
        want = int(m.group(1))
        # nat_bad NOBETCI: tablo disina atlamayi yakalamak icin var,
        # sayilan govde fonksiyonlarina dahil degil.
        _all = re.findall(r'\.long SYM\(nat_(\w+)\)\s*-\s*SYM\(nat_fns\)', _ns.read_text())
        got = len([x for x in _all if x != "bad"])
        if got != want:
            tbl.append("  NAT_COUNT=%d ama natives.S'te %d girdi var" % (want, got))

hits = []
for f in sorted(root.glob("src/**/*.S")):
    hits += scan(str(f.relative_to(root)), f.read_text())
for p, i, ll, cl, src in hits:
    print("  SUPHELI %s:%d  CALL@%d -> A0 yazildi@%d -> %s" % (p, i, ll, cl, src))
for t in tbl:
    print(t)
if not hits and not tbl:
    print("  lint temiz: RV/A0 cakismasi ve tablo tutarsizligi yok")
elif hits:
    print("  LINT UYARISI: %d yer (elle dogrula)" % len(hits))
sys.exit(1 if (hits or tbl) else 0)
