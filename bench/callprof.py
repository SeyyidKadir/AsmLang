#!/usr/bin/env python3
"""bench/callprof.py - CALL/RET maliyeti profili

Yontem: her cagri varyanti, cagrisiz AYNI dongu ile karsilastirilir.
Fark tamamen cagriya aittir; dongu maliyeti sadelestirilir.

  cagri basina sure    = (t_variant - t_none) / cagri_sayisi
  cagri basina dagitim = (d_variant - d_none) / cagri_sayisi

Cagri basina bellek erisimi analitik olarak op_call/op_ret kaynagindan
sayilir (asagidaki sabitler); olcum degil, kod okumasidir - oyle
etiketlenir.
"""
import subprocess, sys, os, statistics, re, pathlib

REPS = int(os.environ.get("REPS", "9"))
ARCHS = sys.argv[1:] or ["x86_64", "i386"]
ROOT = pathlib.Path(__file__).resolve().parent.parent
os.chdir(ROOT)

# (program, dongu turu, tur basina cagri sayisi)
CASES = [
    ("call_none", 2_000_000, 0, "cagri yok (taban)"),
    ("call_0",    2_000_000, 1, "0 argumanli cagri"),
    ("call_1",    2_000_000, 1, "1 argumanli cagri"),
    ("call_3",    2_000_000, 1, "3 argumanli cagri"),
    ("call_loc",  2_000_000, 1, "1 arg + 2 yerel"),
    ("call_deep", 4_000,     501, "derin ozyineleme (500)"),
]

def build(prog, arch, extra=""):
    subprocess.run([sys.executable, "bench/gen_embed.py",
                    f"bench/programs/{prog}.al"],
                   stdout=open("src/bench_embed.inc", "w"), check=True)
    env = dict(os.environ)
    env["EXTRA_CFLAGS"] = "-DBENCH_SRC=1 " + extra
    env["OUT_BIN"] = f"build/cp-{prog}-{arch}"
    r = subprocess.run(["./build.sh", f"linux-{arch}"], capture_output=True, env=env)
    return env["OUT_BIN"] if os.path.exists(env["OUT_BIN"]) else None

def timeit(binp):
    import time
    for _ in range(2):
        subprocess.run([binp], capture_output=True)
    ts = []
    for _ in range(REPS):
        t0 = time.perf_counter_ns()
        subprocess.run([binp], capture_output=True)
        ts.append((time.perf_counter_ns() - t0) / 1e6)
    return statistics.median(ts), statistics.pstdev(ts)

def dispatch(prog, arch):
    b = build(prog, arch, "-DOPT_COUNT=1")
    if not b:
        return None
    r = subprocess.run([b], capture_output=True, text=True)
    m = re.search(r"dagitim\s*:\s*(\d+)", r.stdout)
    return int(m.group(1)) if m else None

for arch in ARCHS:
    print(f"=== {arch} ===")
    base_t = base_d = None
    print(f"  {'durum':24s} {'medyan':>10s} {'std':>7s} "
          f"{'dagitim':>13s} {'ns/cagri':>10s} {'dagitim/cagri':>14s}")
    for prog, iters, per, label in CASES:
        b = build(prog, arch)
        if not b:
            print(f"  {label:24s}  DERLENEMEDI")
            continue
        med, sd = timeit(b)
        d = dispatch(prog, arch)
        calls = iters * per
        if per == 0:
            base_t, base_d = med, d
            ns = dpc = "-"
        else:
            ns = f"{(med - base_t) * 1e6 / calls:10.1f}" if base_t else "-"
            dpc = f"{(d - base_d) / calls:14.2f}" if (d and base_d) else "-"
        ds = f"{d:,}" if d else "olculemedi"
        print(f"  {label:24s} {med:8.2f}ms {sd:7.2f} {ds:>13s} {ns:>10s} {dpc:>14s}")
    print()

print("cagri basina bellek erisimi (op_call/op_ret KAYNAK SAYIMI, olcum degil):")
print("  op_call FN yolu : 2 tasma denetimi + 3 yukleme (etiket, fn idx, arite)")
print("                    + 4 yukleme/saklama (cerceve: retpc, eski VF)")
print("                    + 2 yukleme (kod tabani, giris) = ~11 erisim")
print("  op_ret          : 2 yukleme (sonuc) + 3 yukleme/saklama (cerceve coz)")
print("                    + 2 saklama (sonucu it) + 1 yukleme (kod tabani)")
print("                    = ~8 erisim")
print("  arguman tasima  : yok - argumanlar zaten yigindaki yerinde kaliyor,")
print("                    VF dogrudan oraya kuruluyor (kopyalama sifir)")
