#!/usr/bin/env bash
# qemu.sh - bare-metal imaji GERCEK emulatorde dogrula
#
# qemu-system-i386 gerekli. Yoksa test ATLANIR (basarisiz sayilmaz).
#   bash tools/qemu-kur.sh   ile kurulabilir
cd "$(dirname "$0")/.."
export PATH=/home/claude/qemu/bin:$PATH
ok()  { echo "  GECTI $*"; }
bad() { echo "  KALDI $*"; FAIL=1; }
FAIL=0

if ! command -v qemu-system-i386 >/dev/null 2>&1; then
  echo "  ATLANDI: qemu-system-i386 yok (tools/qemu-kur.sh)"
  exit 0
fi

python3 bench/gen_embed.py ornekler/onay.al > src/bench_embed.inc
EXTRA_CFLAGS="-DBENCH_SRC=1" ./build.sh bare-i386 >/dev/null 2>&1

# sahte disk: ilk sektorde taninabilir imza
python3 - <<'PY'
d = bytearray(65536)
d[0:4] = b'\xEB\x3C\x90\x41'
d[510:512] = b'\x55\xAA'
open('/tmp/asmlang-disk.img','wb').write(bytes(d))
PY

OUT=$(timeout 120 qemu-system-i386 -kernel build/bare-i386 \
        -serial stdio -display none -no-reboot -nic none \
        -drive file=/tmp/asmlang-disk.img,format=raw,if=ide 2>&1)

chk() {  # chk "aciklama" "beklenen desen"
  if echo "$OUT" | grep -qa "$2"; then ok "$1"; else bad "$1"; fi
}

chk "imaj aciliyor"                 "asmlang bare-metal onay"
chk "multiboot yukleyici algilandi" "multiboot yukleyici : VAR"
chk "gercek 16550 UART calisiyor"   "onay bitti"
chk "cpuid gercek deger donuyor"    "cpuid *: VAR"
chk "port G/C ring 0'da calisiyor"  "port G/C *: VAR"
chk "obek ayirma"                   "yigin ayirma *: TAMAM"
chk "cop toplama"                   "cop toplama *: TAMAM"
chk "ozyineleme"                    "fib(20) *: TAMAM"
chk "VGA metin ekranina yazildi"    "VGA metin ekrani *: YAZILDI"
chk "ATA PIO disk okundu"           "disk okuma *: OKUNDU  ilk iki bayt=eb 3c"
chk "PC hoparloru"                  "hoparloru *: CALDI"
chk "kanarya bozulmadi"             "guard   : 0"
chk "calisma hatasi yok"            "hata    : 0"

# 64-bit imaj multiboot ile ACILAMAZ: bunu da dogrula
./build.sh bare-x86_64 >/dev/null 2>&1
O64=$(timeout 30 qemu-system-x86_64 -kernel build/bare-x86_64 \
        -display none -no-reboot -nic none 2>&1 | head -2)
if echo "$O64" | grep -qa "give a 32bit one"; then
  ok "bare-x86_64 acilamiyor (belgelenen sinir dogrulandi)"
else
  bad "bare-x86_64 beklenmedik davranis: $O64"
fi

# ---- GRAFIK: BGA ile mod kur, EKRAN GORUNTUSU al, pikselleri dogrula ----
# Cizim tamamen asmlang'de yazildi (ornekler/grafik.al): PCI taramasi,
# BGA kayitlari, piksel yazimi. Yeni govde fonksiyonu kullanilmadi.
python3 bench/gen_embed.py ornekler/grafik.al > src/bench_embed.inc
EXTRA_CFLAGS="-DBENCH_SRC=1" ./build.sh bare-i386 >/dev/null 2>&1
rm -f /tmp/asmlang-fb.ppm /tmp/asmlang-mon
# DIKKAT: "-monitor stdio" ile misafir baslamiyor; monitor AYRI
# soket olmali. Bunu ancak deneyerek gorduk.
( qemu-system-i386 -kernel build/bare-i386 -vnc none -no-reboot -nic none \
    -serial file:/tmp/asmlang-fb.log \
    -monitor unix:/tmp/asmlang-mon,server,nowait & QPID=$!
  sleep 12
  python3 - <<'PY2' 2>/dev/null
import socket, time
s = socket.socket(socket.AF_UNIX)
s.connect("/tmp/asmlang-mon"); time.sleep(0.5)
s.sendall(b"screendump /tmp/asmlang-fb.ppm\n"); time.sleep(2)
s.sendall(b"quit\n"); time.sleep(0.5)
PY2
  wait $QPID 2>/dev/null ) >/dev/null 2>&1

if python3 - <<'PY3'
import sys
try:
    f = open("/tmp/asmlang-fb.ppm","rb")
    assert f.readline().strip() == b"P6"
    l = f.readline()
    while l.startswith(b"#"): l = f.readline()
    w, h = map(int, l.split()); f.readline(); d = f.read()
except Exception:
    sys.exit(1)
def px(x, y):
    i = (y*w + x)*3
    return tuple(d[i:i+3])
want = [((0,0),(255,0,0)), ((1,0),(0,255,0)), ((2,0),(0,0,255)),
        ((300,100),(255,0,0)), ((100,300),(0,255,0)),
        ((200,200),(255,255,255)), ((400,400),(34,65,154))]
if (w, h) != (640, 480): sys.exit(1)
for (x,y), e in want:
    if px(x,y) != e: sys.exit(1)
# butun ekran dolu olmali
if any(d[i:i+3] == b"\x00\x00\x00" for i in range(0, len(d), 3)): sys.exit(1)
sys.exit(0)
PY3
then ok "grafik: 640x480x32 mod kuruldu, 7 piksel dogrulandi, ekran dolu"
else bad "grafik: mod ya da piksel dogrulanamadi"
fi

# ---- KENDI ONYUKLEYICIMIZ: diskten acilis + VBE grafik ----
# GRUB YOK. Onyukleyici gercek modda VBE kuruyor (korumali moddan
# int 0x10 cagrilamaz), sonra korumali moda gecip cekirdege
# multiboot yapisiyla veriyor.
python3 bench/gen_embed.py ornekler/onay.al > src/bench_embed.inc
EXTRA_CFLAGS="-DBENCH_SRC=1" ./build.sh bare-i386 >/dev/null 2>&1
python3 tools/disk-yap.py build/bare-i386 /tmp/asmlang-boot.img >/dev/null 2>&1
rm -f /tmp/asmlang-boot.ppm /tmp/asmlang-boot.log /tmp/asmlang-bm
( qemu-system-i386 -drive file=/tmp/asmlang-boot.img,format=raw,if=ide \
    -vnc none -no-reboot -nic none -serial file:/tmp/asmlang-boot.log \
    -monitor unix:/tmp/asmlang-bm,server,nowait >/dev/null 2>&1 & ) 
sleep 14
python3 - <<'PY4' 2>/dev/null
import socket, time
s = socket.socket(socket.AF_UNIX); s.connect("/tmp/asmlang-bm"); time.sleep(0.5)
s.sendall(b"screendump /tmp/asmlang-boot.ppm\n"); time.sleep(2)
s.sendall(b"quit\n"); time.sleep(0.5)
PY4
sleep 1; pkill -f asmlang-boot.img 2>/dev/null

B=$(cat /tmp/asmlang-boot.log 2>/dev/null)
echo "$B" | grep -qa "onay bitti" \
  && ok "kendi onyukleyicimiz: diskten acildi (GRUB yok)" \
  || bad "kendi onyukleyicimiz: acilmadi"
echo "$B" | grep -qa "cerceve tamponu     : VAR" \
  && ok "onyukleyici VBE kipini kurdu (gercek modda)" \
  || bad "VBE kipi kurulmadi"
echo "$B" | grep -qa "grafik cizim       : CIZILDI" \
  && ok "cerceve tamponuna cizildi" \
  || bad "cizim yapilamadi"

if python3 - <<'PY5'
import sys
try:
    f = open("/tmp/asmlang-boot.ppm","rb"); f.readline()
    l = f.readline()
    while l.startswith(b"#"): l = f.readline()
    w, h = map(int, l.split()); f.readline(); d = f.read()
except Exception: sys.exit(1)
def px(x,y):
    i=(y*w+x)*3; return tuple(d[i:i+3])
if (w,h) != (1024,768): sys.exit(1)
if px(50,100) != (255,0,0): sys.exit(1)
if px(100,50) != (0,255,0): sys.exit(1)
if px(150,150) != (255,255,255): sys.exit(1)
if any(d[i:i+3] == b"\x00\x00\x00" for i in range(0, len(d), 3)): sys.exit(1)
sys.exit(0)
PY5
then ok "ekran goruntusu: 1024x768, cizgiler dogru, ekran dolu"
else bad "ekran goruntusu dogrulanamadi"
fi
rm -f /tmp/asmlang-boot.img /tmp/asmlang-boot.ppm /tmp/asmlang-boot.log /tmp/asmlang-bm

# ---- KLAVYE: PS/2, QEMU sendkey ile tus gonderiliyor ----
python3 bench/gen_embed.py ornekler/klavye.al > src/bench_embed.inc
EXTRA_CFLAGS="-DBENCH_SRC=1" ./build.sh bare-i386 >/dev/null 2>&1
python3 tools/disk-yap.py build/bare-i386 /tmp/asmlang-kbd.img >/dev/null 2>&1
rm -f /tmp/asmlang-kbd.log /tmp/asmlang-km
( qemu-system-i386 -drive file=/tmp/asmlang-kbd.img,format=raw,if=ide \
    -vnc none -no-reboot -nic none -serial file:/tmp/asmlang-kbd.log \
    -monitor unix:/tmp/asmlang-km,server,nowait >/dev/null 2>&1 & )
sleep 11
python3 - <<'PY6' 2>/dev/null
import socket, time
s = socket.socket(socket.AF_UNIX); s.connect("/tmp/asmlang-km"); time.sleep(0.5)
for k in ["a", "b", "1", "shift-a", "spc"]:
    s.sendall(("sendkey %s\n" % k).encode()); time.sleep(1.2)
time.sleep(2); s.sendall(b"quit\n"); time.sleep(0.5)
PY6
sleep 1; pkill -f asmlang-kbd.img 2>/dev/null
K=$(cat /tmp/asmlang-kbd.log 2>/dev/null | tr -d '\r')
# a=97 b=98 1=49 Shift+a=65 bosluk=32
if echo "$K" | grep -qa "tus 0 = 97" && echo "$K" | grep -qa "tus 3 = 65" \
   && echo "$K" | grep -qa "tus 4 = 32"; then
  ok "klavye: PS/2 tarama kodu -> ASCII, shift dahil"
else
  bad "klavye: $(echo "$K" | grep -a 'tus ' | tr '\n' ' ')"
fi
rm -f /tmp/asmlang-kbd.img /tmp/asmlang-kbd.log /tmp/asmlang-km

# ---- FARE: PS/2, QEMU mouse_move/mouse_button ile ----
# Imlec cerceve tamponuna ciziliyor: grafik + girdi birlikte.
python3 bench/gen_embed.py ornekler/imlec.al > src/bench_embed.inc
EXTRA_CFLAGS="-DBENCH_SRC=1" ./build.sh bare-i386 >/dev/null 2>&1
python3 tools/disk-yap.py build/bare-i386 /tmp/asmlang-ms.img >/dev/null 2>&1
rm -f /tmp/asmlang-ms.log /tmp/asmlang-msm /tmp/asmlang-ms.ppm
( qemu-system-i386 -drive file=/tmp/asmlang-ms.img,format=raw,if=ide \
    -vnc none -no-reboot -nic none -serial file:/tmp/asmlang-ms.log \
    -monitor unix:/tmp/asmlang-msm,server,nowait >/dev/null 2>&1 & )
sleep 13
python3 - <<'PY7' 2>/dev/null
import socket, time
s = socket.socket(socket.AF_UNIX); s.connect("/tmp/asmlang-msm"); time.sleep(0.5)
for c in ["mouse_move 200 150", "mouse_move 20 10", "mouse_button 1",
          "mouse_move 10 10", "mouse_button 0", "mouse_move 5 5",
          "mouse_move -20 0", "mouse_move 0 -20", "mouse_move 3 3"]:
    s.sendall((c + "\n").encode()); time.sleep(0.8)
time.sleep(2); s.sendall(b"screendump /tmp/asmlang-ms.ppm\n"); time.sleep(2)
s.sendall(b"quit\n"); time.sleep(0.5)
PY7
sleep 1; pkill -f asmlang-ms.img 2>/dev/null

M=$(cat /tmp/asmlang-ms.log 2>/dev/null)
echo "$M" | grep -qa "fare : dogru" \
  && ok "fare: PS/2 kurulumu (8042 ikinci kanal)" || bad "fare kurulamadi"
P=$(echo "$M" | grep -ao 'paket [0-9]*' | grep -o '[0-9]*')
[ "${P:-0}" -ge 5 ] && ok "fare: $P paket islendi (hareket + dugme)" \
  || bad "fare: yalniz ${P:-0} paket"

# imlec RAPOR EDILEN konumda mi: cizim ile veri tutarli olmali
if python3 - <<'PY8'
import sys, re, os
log = open("/tmp/asmlang-ms.log", errors="ignore").read()
m = re.search(r"konum (\d+),(\d+)", log)
if not m or not os.path.exists("/tmp/asmlang-ms.ppm"): sys.exit(1)
ex, ey = int(m.group(1)), int(m.group(2))
f = open("/tmp/asmlang-ms.ppm", "rb"); f.readline()
l = f.readline()
while l.startswith(b"#"): l = f.readline()
w, h = map(int, l.split()); f.readline(); d = f.read()
def px(x, y):
    i = (y*w + x)*3
    return d[i:i+3]
# imlecin sol ust kosesi rapor edilen konumda beyaz olmali
if px(ex, ey) != b"\xff\xff\xff": sys.exit(1)
# eski konumlar silinmis olmali: tam 19 beyaz piksel
n = sum(1 for i in range(0, len(d), 3) if d[i:i+3] == b"\xff\xff\xff")
if n != 19: sys.exit(1)
sys.exit(0)
PY8
then ok "fare: imlec rapor edilen konumda cizili, eskisi silinmis"
else bad "fare: imlec konumu dogrulanamadi"
fi
rm -f /tmp/asmlang-ms.img /tmp/asmlang-ms.log /tmp/asmlang-msm /tmp/asmlang-ms.ppm

rm -f src/bench_embed.inc /tmp/asmlang-disk.img /tmp/asmlang-fb.ppm /tmp/asmlang-mon /tmp/asmlang-fb.log
./build.sh linux-x86_64 >/dev/null 2>&1
[ "$FAIL" = "0" ] && echo "  TUM QEMU TESTLERI GECTI" || echo "  QEMU TEST HATASI"
exit $FAIL
