#!/usr/bin/env python3
"""tests/fuzz.py - asmlang derleyici + VM fuzzer'i

Amac: elle denetimin kacirdigi tasma/cokme yollarini bulmak.
Son iki denetimde bes tasma elle bulundu; bu yontem olceklenmiyor.

BASARISIZLIK olcutu (uydurma yok, hepsi gozlemlenebilir):
  - surec sinyalle olduyse           (rc >= 128)
  - zaman asimi                      (asilma)
  - "GUARD BOZULDU" ciktisi          (kanarya ihlali = bellek bozulmasi)
  - "dogrulama HATASI"               (bozuk bytecode uretildi)
  - cikis kodu 0/1 disinda

BASARILI sayilanlar: derleme hatasi, calisma hatasi, sinir asimi.
Bunlar dogru davranis - girdi bozuksa program temiz sikayet etmeli.

Determinist: --seed ile ayni sonuclar yeniden uretilir.
"""
import random, subprocess, sys, os, pathlib, argparse, hashlib

ROOT = pathlib.Path(__file__).resolve().parent.parent
os.chdir(ROOT)

KW = ["tanim", "sabit", "eger", "yoksa", "iken", "her", "kir", "devam",
      "dondur", "fonk", "yazdir", "dogru", "yanlis", "bos", "ve", "veya",
      "degil", "let", "if", "else", "while", "fn", "return", "print",
      "uzunluk", "ekle", "yazi", "sayi", "oku", "dosya", "yazf"]
PUNCT = ["(", ")", "{", "}", "[", "]", ",", ".", ";", ":", "+", "-", "*",
         "/", "%", "=", "==", "!=", "<", "<=", ">", ">=", "!"]
IDENT = ["a", "b", "c", "x", "y", "sayac", "deger", "ad", "liste",
         "\u00e7\u0131kt\u0131", "de\u011fer"]
NUM = ["0", "1", "2", "7", "42", "255", "256", "1000000000", "2147483647",
       "99999999999", "3.14", "0000", "-1"]
STR = ['"a"', '"merhaba"', '""', '"\\n"', '"\\\\"', '"' + "u" * 200 + '"',
       "'tek'", '"a\u00e7\u0131k"']

SEEDS = [
    'tanim a = 1\nyazdir a\n',
    'fonk f(x) { dondur x + 1 }\nyazdir f(2)\n',
    'tanim i = 0\niken i < 3 { yazdir i  i = i + 1 }\n',
    'tanim l = [1, 2, 3]\nl[1] = 9\nyazdir l\n',
    'eger dogru { yazdir "e" } yoksa { yazdir "h" }\n',
    'tanim s = "ab"\ns = s + s\nyazdir uzunluk(s)\n',
    'fonk f(n) { eger n <= 0 { dondur 0 }  dondur 1 + f(n - 1) }\nyazdir f(10)\n',
]


def tok_soup(rnd, n):
    pool = KW + PUNCT + IDENT + NUM + STR + ["\n", " "]
    return "".join(rnd.choice(pool) + rnd.choice([" ", "\n", ""]) for _ in range(n))


def mutate(rnd, src):
    b = bytearray(src.encode())
    if not b:
        return "yazdir 1\n"
    for _ in range(rnd.randint(1, 8)):
        op = rnd.randint(0, 4)
        i = rnd.randrange(len(b))
        if op == 0:                                   # bayt cevir
            b[i] = rnd.randrange(256)
        elif op == 1:                                 # sil
            del b[i:i + rnd.randint(1, 10)]
        elif op == 2:                                 # parca cogalt
            j = rnd.randrange(len(b)) if b else 0
            b[i:i] = b[j:j + rnd.randint(1, 40)]
        elif op == 3:                                 # sozcuk ekle
            b[i:i] = rnd.choice(KW + PUNCT).encode()
        else:                                         # derin ic ice
            d = rnd.randint(1, 60)
            b[i:i] = (b"(" * d) + b"1" + (b")" * d)
        if not b:
            b = bytearray(b"yazdir 1\n")
    return b.decode("utf-8", "replace")


def build(src, arch):
    pathlib.Path("/tmp/fuzz.al").write_bytes(src.encode("utf-8", "replace"))
    r = subprocess.run([sys.executable, "bench/gen_embed.py", "/tmp/fuzz.al"],
                       capture_output=True)
    if r.returncode != 0:
        return None
    pathlib.Path("src/bench_embed.inc").write_bytes(r.stdout)
    env = dict(os.environ)
    env["EXTRA_CFLAGS"] = "-DBENCH_SRC=1"
    env["OUT_BIN"] = "build/fuzzbin"
    b = subprocess.run(["./build.sh", "linux-" + arch], capture_output=True, env=env)
    return "build/fuzzbin" if os.path.exists("build/fuzzbin") else None


def verdict(src, arch):
    """-> (ok, sebep)"""
    binp = build(src, arch)
    if binp is None:
        return True, "derlenemedi (assembler; girdi hatasi degil)"
    try:
        r = subprocess.run([binp], capture_output=True, timeout=25,
                           stdin=subprocess.DEVNULL)
    except subprocess.TimeoutExpired:
        return False, "ZAMAN ASIMI"
    out = r.stdout.decode("utf-8", "replace") + r.stderr.decode("utf-8", "replace")
    if r.returncode < 0 or r.returncode >= 128:
        return False, "SINYAL/COKME rc=%d" % r.returncode
    if "GUARD BOZULDU" in out:
        return False, "KANARYA IHLALI: " + \
            [l for l in out.splitlines() if "GUARD" in l][0]
    if "dogrulama HATASI" in out:
        return False, "BOZUK BYTECODE: " + \
            [l for l in out.splitlines() if "dogrulama" in l][0]
    if r.returncode not in (0, 1):
        return False, "beklenmeyen cikis kodu %d" % r.returncode
    return True, "ok"


def minimize(src, arch, reason):
    """Basarisiz girdiyi satir satir kucult."""
    lines = src.split("\n")
    changed = True
    while changed and len(lines) > 1:
        changed = False
        for i in range(len(lines) - 1, -1, -1):
            trial = lines[:i] + lines[i + 1:]
            ok, _ = verdict("\n".join(trial), arch)
            if not ok:
                lines = trial
                changed = True
                break
    return "\n".join(lines)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--n", type=int, default=60)
    ap.add_argument("--seed", type=int, default=1)
    ap.add_argument("--arch", default="x86_64")
    a = ap.parse_args()
    rnd = random.Random(a.seed)
    fails = []
    print("fuzz: %d durum, seed=%d, arch=%s" % (a.n, a.seed, a.arch))
    for k in range(a.n):
        if k % 3 == 0:
            src = tok_soup(rnd, rnd.randint(5, 120))
        else:
            src = mutate(rnd, rnd.choice(SEEDS))
        ok, why = verdict(src, a.arch)
        if not ok:
            h = hashlib.sha1(src.encode("utf-8", "replace")).hexdigest()[:8]
            small = minimize(src, a.arch, why)
            path = "tests/fuzz-fail-%s.al" % h
            pathlib.Path(path).write_text(small)
            print("  BASARISIZ [%d] %s\n    kucultulmus -> %s" % (k, why, path))
            fails.append(why)
        elif k % 10 == 0:
            print("  ... %d/%d" % (k, a.n))
    for f in ("src/bench_embed.inc", "build/fuzzbin"):
        if os.path.exists(f):
            os.remove(f)
    subprocess.run(["./build.sh", "linux-x86_64"], capture_output=True)
    print("\n%d/%d basarisiz" % (len(fails), a.n))
    return 1 if fails else 0


sys.exit(main())
