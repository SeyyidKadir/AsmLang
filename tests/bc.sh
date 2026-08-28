#!/usr/bin/env bash
# tests/bc.sh - .bc gidis-donusu ve YUKLEYICI GUVENLIGI
#
# Yurutucu (player) icin .bc GUVENILMEYEN girdidir. Bu test bozuk
# dosyalarin COKME degil TEMIZ RED urettigini dogrular.
set -u
cd "$(dirname "$0")/.."
fail=0
ok()  { echo "  GECTI $1"; }
bad() { echo "  KALDI $1"; fail=1; }

cat > /tmp/bctest.al <<'AL'
fonk topla(a, b) { dondur a + b }
fonk fakt(n) { eger n <= 1 { dondur 1 }  dondur n * fakt(n - 1) }
tanim ad = "dunya"
yazdir "merhaba, " + ad + "!"
yazdir topla(20, 22)
yazdir fakt(6)
tanim l = [1, 2, 3]
ekle(l, 42)
yazdir l
kaydet(arg(1))
AL
python3 bench/gen_embed.py /tmp/bctest.al > src/bench_embed.inc

for arch in x86_64 i386; do
  rm -f "/tmp/bc-$arch.bc"
  EXTRA_CFLAGS="-DBENCH_SRC=1" OUT_BIN="build/bc-comp-$arch" ./build.sh "linux-$arch" >/dev/null 2>&1
  MODE_PLAYER=1 EXTRA_CFLAGS="-DMODE_PLAYER=1" OUT_BIN="build/bc-play-$arch" ./build.sh "linux-$arch" >/dev/null 2>&1
  # yol ARGUMANDAN geliyor (sabit yol degil)
  c=$(timeout 30 "./build/bc-comp-$arch" "/tmp/bc-$arch.bc" < /dev/null 2>&1 | sed -n '/cikti/,/ozet/p' | grep -av -- '---' | tr -d '\n ')
  p=$(timeout 30 "./build/bc-play-$arch" "/tmp/bc-$arch.bc" < /dev/null 2>&1 | sed -n '/cikti/,/ozet/p' | grep -av -- '---' | tr -d '\n ')
  [ -s "/tmp/bc-$arch.bc" ] || { bad "$arch .bc uretilmedi"; continue; }
  if [ "$c" = "$p" ] && [ -n "$c" ]; then ok "$arch derleyici == yurutucu ciktisi"
  else bad "$arch cikti farkli: '$c' vs '$p'"; fi
  cs=$(stat -c%s "build/bc-comp-$arch"); ps=$(stat -c%s "build/bc-play-$arch")
  [ "$ps" -lt "$cs" ] && ok "$arch yurutucu daha kucuk ($ps < $cs)" || bad "$arch yurutucu kucuk degil"
done

# Kelime genisligi damgasi: 64-bit uretilen .bc 32-bit yurutucude
# CALISMAMALI, temiz REDDEDILMELI. (Tamsayi 64 bite cikinca .bc
# artik kelime genisligine bagli; sessizce yanlis calismasindansa
# acik hata.)
cp /tmp/bc-x86_64.bc /tmp/bc_good.bc
out=$(timeout 30 ./build/bc-play-i386 /tmp/bc_good.bc < /dev/null 2>&1)
if echo "$out" | grep -q "kelime genisligi uyusmuyor"; then
  ok "capraz genislik temiz reddedildi"
else bad "capraz genislik reddedilmedi: $(echo "$out"|head -1)"; fi

echo "  --- komut satiri argumanlari ---"
cat > /tmp/argtest.al <<'AL'
yazdir argsay()
yazdir arg(1)
yazdir arg(2)
yazdir arg(99)
AL
python3 bench/gen_embed.py /tmp/argtest.al > src/bench_embed.inc
for arch in x86_64 i386; do
  EXTRA_CFLAGS="-DBENCH_SRC=1" OUT_BIN="build/bc-arg-$arch" ./build.sh "linux-$arch" >/dev/null 2>&1
  got=$(timeout 20 "./build/bc-arg-$arch" bir iki < /dev/null 2>&1 | sed -n '/cikti/,/ozet/p' | grep -av -- '---' | tr -d '\n ')
  if [ "$got" = "3biriki bos" ] || [ "$got" = "3birikibos" ]; then ok "$arch argsay/arg"
  else bad "$arch argsay/arg -> '$got'"; fi
done
python3 bench/gen_embed.py /tmp/bctest.al > src/bench_embed.inc

echo "  --- gomulu bytecode (BC_EMBED) ---"
# .bc ikiliye gomulu: dosya sistemi gerekmeden calismali
cp /tmp/bc-x86_64.bc src/embed.bc
BC_EMBED=1 MODE_PLAYER=1 EXTRA_CFLAGS="-DMODE_PLAYER=1 -DBC_EMBED=1" \
  OUT_BIN=build/bc-emb ./build.sh linux-x86_64 >/dev/null 2>&1
rm -f /tmp/asmlang.bc
e=$(timeout 30 ./build/bc-emb < /dev/null 2>&1 | sed -n '/cikti/,/ozet/p' | grep -av -- '---' | tr -d '\n ')
ref=$(timeout 30 ./build/bc-play-x86_64 </dev/null 2>&1 >/dev/null; echo)
p=$(timeout 30 ./build/bc-play-x86_64 /tmp/bc-x86_64.bc < /dev/null 2>&1 | sed -n '/cikti/,/ozet/p' | grep -av -- '---' | tr -d '\n ')
if [ "$e" = "$p" ] && [ -n "$e" ]; then ok "gomulu == dosyadan (dosya silinmisken bile)"
else bad "gomulu cikti farkli: '$e' vs '$p'"; fi

# bare-metal + gomulu = cekirdek imaji
BC_EMBED=1 MODE_PLAYER=1 EXTRA_CFLAGS="-DMODE_PLAYER=1 -DBC_EMBED=1" \
  OUT_BIN=build/bc-kernel ./build.sh bare-x86_64 >/dev/null 2>&1
if [ -x build/bc-kernel ]; then
  sc=$(objdump -d build/bc-kernel 2>/dev/null | grep -cE '\b(syscall|sysenter|int +\$0x80)\b')
  rl=$(readelf -r build/bc-kernel 2>/dev/null | grep -c R_X86_64)
  if [ "$sc" = "0" ] && [ "$rl" = "0" ]; then
    ok "bare+gomulu cekirdek imaji: 0 syscall, 0 reloc ($(stat -c%s build/bc-kernel) bayt)"
  else bad "cekirdek imaji: $sc syscall, $rl reloc"; fi
else bad "bare+gomulu derlenemedi"; fi
rm -f src/embed.bc

echo "  --- kip B: .bc yurutucunun SONUNA ekli (tek dosya) ---"
for arch in x86_64 i386; do
  python3 tools/append_bc.py "build/bc-play-$arch" "/tmp/bc-$arch.bc" "/tmp/one-$arch" >/dev/null 2>&1
  # ARGUMANSIZ calismali: kendi yolunu argv[0]'dan bulup kendini okuyor
  got=$(timeout 30 "/tmp/one-$arch" < /dev/null 2>&1 | sed -n '/cikti/,/ozet/p' | grep -av -- '---' | tr -d '\n ')
  ref=$(timeout 30 "./build/bc-play-$arch" "/tmp/bc-$arch.bc" < /dev/null 2>&1 | sed -n '/cikti/,/ozet/p' | grep -av -- '---' | tr -d '\n ')
  if [ "$got" = "$ref" ] && [ -n "$got" ]; then ok "$arch tek dosya (kendi sonundan okuyor)"
  else bad "$arch tek dosya -> '$got' vs '$ref'"; fi
  # fuye BOZULURSA temiz davranmali
  python3 - "$arch" <<'PYX'
import sys, pathlib
p = pathlib.Path("/tmp/one-%s" % sys.argv[1])
d = bytearray(p.read_bytes()); d[-1] ^= 0xFF
pathlib.Path("/tmp/onebad-%s" % sys.argv[1]).write_bytes(bytes(d))
PYX
  chmod +x "/tmp/onebad-$arch"
  out=$(timeout 30 "/tmp/onebad-$arch" < /dev/null 2>&1); rc=$?
  if [ $rc -lt 128 ] && [ $rc -ne 124 ]; then ok "$arch bozuk fuye: cokme yok (rc=$rc)"
  else bad "$arch bozuk fuye rc=$rc"; fi
  rm -f "/tmp/one-$arch" "/tmp/onebad-$arch"
done

echo "  --- yukleyici guvenligi: bozuk .bc ---"
python3 - <<'PY'
import subprocess, random, sys
good = open('/tmp/bc_good.bc','rb').read()
crash = to = caught = ran = 0
for seed in (7, 99, 2024):
    random.seed(seed)
    for _ in range(120):
        d = bytearray(good)
        for _ in range(random.randint(1, 10)):
            d[random.randrange(len(d))] = random.randrange(256)
        open('/tmp/asmlang.bc','wb').write(d)
        try:
            r = subprocess.run(['./build/bc-play-x86_64','/tmp/asmlang.bc'], capture_output=True,
                               timeout=25, stdin=subprocess.DEVNULL)
        except subprocess.TimeoutExpired:
            to += 1; continue
        out = (r.stdout + r.stderr).decode('utf-8', 'replace')
        if r.returncode < 0 or r.returncode >= 128 or 'GUARD BOZULDU' in out:
            crash += 1
        elif r.returncode == 1: caught += 1
        else: ran += 1
print(f"  360 bozuk .bc -> {crash} cokme, {to} zaman asimi, {caught} reddedildi, {ran} calisti")
open('/tmp/asmlang.bc','wb').write(good)
sys.exit(1 if (crash or to) else 0)
PY
[ $? -eq 0 ] && ok "bozuk .bc cokme uretmiyor" || bad "bozuk .bc cokme/asilma uretti"

rm -f src/bench_embed.inc
./build.sh linux-x86_64 >/dev/null 2>&1
./build.sh linux-i386 >/dev/null 2>&1
echo
[ $fail -eq 0 ] && echo "  TUM BC TESTLERI GECTI" || echo "  BC TEST HATASI"
exit $fail
