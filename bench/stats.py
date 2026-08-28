#!/usr/bin/env python3
"""Bir ikiliyi N kez calistirir, dagilim istatistigi ve sayaclari raporlar.

  stats.py <ikili> <tekrar> <mimari> <varyant> <perf_var_mi>

Ilkeler:
  - Wall-clock icin en dusuk DEGIL medyan raporlanir; min/max/ortalama/std da
    verilir ki gurultu goruilsun. (En dusuk tek basina yaniltiyor: bu projede
    bir kez "%20 yavasladi" sonucu tamamen gurultu cikti.)
  - Yurutulen bytecode komut sayisi VM'in kendi sayacindan alinir; bu
    disassembly'den TAHMIN degil, olcumdur.
  - perf yoksa donanim sayaclari "olculemedi" yazilir, uydurulmaz.
"""
import subprocess, sys, time, statistics, re, os, shutil, resource

binpath, reps, arch, variant, have_perf = sys.argv[1], int(sys.argv[2]), sys.argv[3], sys.argv[4], sys.argv[5]

# --- dogruluk: cikti tutarli mi? ---
outs = set()
def run_once():
    """CPU zamani olcer, duvar saati DEGIL.

    Paylasimli konteynerde duvar saati gurultusu %3-5'e ciktigi olculdu
    (ayni ikili iki kez olculunce %3.3 fark). CPU zamani planlayici
    gurultusunden bagimsiz oldugu icin cok daha kararli."""
    b = resource.getrusage(resource.RUSAGE_CHILDREN)
    r = subprocess.run([binpath], capture_output=True, stdin=subprocess.DEVNULL)
    a = resource.getrusage(resource.RUSAGE_CHILDREN)
    cpu = (a.ru_utime - b.ru_utime) + (a.ru_stime - b.ru_stime)
    outs.add(r.stdout)
    return cpu * 1000.0, r.returncode

# isinma (sayfa hatalari, dosya onbellegi)
for _ in range(2):
    run_once()

times, rcs = [], set()
for _ in range(reps):
    ms, rc = run_once()
    times.append(ms); rcs.add(rc)

med = statistics.median(times)
mn, mx = min(times), max(times)
avg = statistics.fmean(times)
sd = statistics.pstdev(times) if len(times) > 1 else 0.0

status = "OK" if rcs == {0} and len(outs) == 1 else "TUTARSIZ"

# --- yurutulen bytecode komutu (VM sayaci) ---
disp = "olculemedi"
cbin = binpath + ".count"
if os.path.exists(cbin):
    r = subprocess.run([cbin], capture_output=True, text=True)
    m = re.search(r"dagitim\s*:\s*(\d+)", r.stdout)
    if m:
        disp = m.group(1)

print(f"  {arch:6s} {variant:9s} cpu-medyan {med:8.2f} ms  "
      f"min {mn:8.2f}  max {mx:8.2f}  ort {avg:8.2f}  std {sd:6.2f}  "
      f"dagitim {disp:>12s}  [{status}]")

# --- donanim sayaclari ---
if have_perf == "yes":
    ev = "cycles,instructions,branches,branch-misses,cache-misses"
    r = subprocess.run(["perf", "stat", "-x,", "-e", ev, binpath],
                       capture_output=True, text=True)
    vals = {}
    for line in r.stderr.splitlines():
        parts = line.split(",")
        if len(parts) >= 3:
            v, _, name = parts[0], parts[1], parts[2]
            vals[name] = v
    if vals:
        def g(k):
            v = vals.get(k, "")
            return v if v and v[0].isdigit() else "olculemedi"
        ins, cyc = g("instructions"), g("cycles")
        ipc = ""
        try:
            ipc = f"  IPC {int(ins)/int(cyc):.2f}"
        except Exception:
            pass
        print(f"         cycles {cyc:>14s}  instructions {ins:>14s}"
              f"  branches {g('branches'):>12s}"
              f"  br-miss {g('branch-misses'):>10s}"
              f"  cache-miss {g('cache-misses'):>10s}{ipc}")
    else:
        print("         donanim sayaclari: OLCULEMEDI (perf cikti vermedi)")
else:
    print("         donanim sayaclari: OLCULEMEDI (perf yok / izin yok)")
