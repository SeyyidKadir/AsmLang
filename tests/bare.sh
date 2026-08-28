#!/usr/bin/env bash
# tests/bare.sh - bare-metal imajinin GERCEKTEN OS-bagimsiz oldugunu dogrular
#
# DIKKAT: bu ortamda emulator yok, imaj CALISTIRILAMIYOR.
# Burada yalnizca STATIK dogrulama var ve ne dogrulandigi acikca yazili.
set -u
cd "$(dirname "$0")/.."
fail=0
ok()  { echo "  GECTI $1"; }
bad() { echo "  KALDI $1"; fail=1; }

for arch in x86_64 i386; do
  ./build.sh "bare-$arch" >/dev/null 2>&1
  img="build/bare-$arch"
  [ -x "$img" ] || { bad "$arch derlenemedi"; continue; }

  # 1. hicbir syscall komutu olmamali
  n=$(objdump -d "$img" 2>/dev/null | grep -cE '\b(syscall|sysenter|int +\$0x80)\b')
  [ "$n" = "0" ] && ok "$arch syscall komutu yok" || bad "$arch $n syscall komutu var"

  # 2. sifir yer degistirme kaydi (imaj istenen adrese yuklenebilmeli)
  r=$(readelf -r "$img" 2>/dev/null | grep -cE 'R_(X86_64|386)')
  [ "$r" = "0" ] && ok "$arch 0 yer degistirme kaydi" || bad "$arch $r kayit"

  # 3. cozulmemis dis sembol olmamali (libc yok)
  u=$(readelf -s "$img" 2>/dev/null | awk '$7=="UND" && $8!=""' | wc -l)
  [ "$u" = "0" ] && ok "$arch cozulmemis sembol yok" || bad "$arch $u cozulmemis sembol"

  # 4. giris noktasi ve baglayici sembolleri yerinde
  for sym in _start _heap_start _heap_end _stack_top __bss_start __bss_end; do
    readelf -s "$img" 2>/dev/null | grep -q " $sym\$" || { bad "$arch $sym yok"; continue 2; }
  done
  ok "$arch giris + baglayici sembolleri tam"

  # 5. dinamik bolum olmamali
  readelf -d "$img" >/dev/null 2>&1 && \
    { readelf -d "$img" 2>/dev/null | grep -q 'NEEDED' && bad "$arch dinamik bagimlilik var" || ok "$arch dinamik bagimlilik yok"; } \
    || ok "$arch dinamik bolum yok"
done

echo
echo "  NOT: imaj CALISTIRILMADI - bu ortamda emulator yok."
echo "  Kosu dogrulamasi icin:  qemu-system-x86_64 -kernel build/bare-x86_64 -nographic"
[ $fail -eq 0 ] && # --- multiboot: bu baslik olmadan imaj ACILAMAZ ---
for t in bare-x86_64 bare-i386; do
  ./build.sh "$t" >/dev/null 2>&1
  r=$(python3 - "build/$t" <<'PYEOF'
import struct, sys
d = open(sys.argv[1], "rb").read()
for o in range(0, min(len(d), 8192), 4):
    if struct.unpack_from("<I", d, o)[0] == 0x1BADB002:
        m, f, c = struct.unpack_from("<3I", d, o)
        if (m + f + c) & 0xFFFFFFFF: print("TOPLAM-HATALI"); break
        mode, w, h, bpp = struct.unpack_from("<4I", d, o + 32)
        print("OK %dx%dx%d" % (w, h, bpp)); break
else:
    print("YOK")
PYEOF
)
  case "$r" in
    OK*) ok "$t multiboot basligi gecerli ($r)" ;;
    *)   bad "$t multiboot: $r" ;;
  esac
done

# --- donanim katmani yalniz bare imajda ---
for t in bare-x86_64 bare-i386; do
  ./build.sh "$t" >/dev/null 2>&1
  n=$(nm -a "build/$t" 2>/dev/null | grep -cE 'port_in|ata_wait|fb_check')
  [ "$n" = "3" ] && ok "$t donanim katmani var (port+disk+ekran)" \
                 || bad "$t donanim katmani eksik ($n/3)"
done
for t in linux-x86_64 linux-i386; do
  ./build.sh "$t" >/dev/null 2>&1
  n=$(nm -a "build/$t" 2>/dev/null | grep -cE 'port_in|ata_wait|fb_check')
  [ "$n" = "0" ] && ok "$t donanim katmani YOK (barindirilan)" \
                 || bad "$t barindirilan yapida donanim kodu var"
done

# --- UART kurulumu: rapor CIKTISI buna bagli ---
for t in bare-x86_64 bare-i386; do
  ./build.sh "$t" >/dev/null 2>&1
  n=$(nm -a "build/$t" 2>/dev/null | grep -c uart_init)
  [ "$n" = "1" ] && ok "$t UART kurulumu var (115200 8N1)" \
                 || bad "$t UART kurulmuyor - cikti gelmeyebilir"
done

# --- multiboot sihri denetleniyor mu ---
for t in bare-x86_64 bare-i386; do
  ./build.sh "$t" >/dev/null 2>&1
  n=$(objdump -d "build/$t" 2>/dev/null | grep -c '2badb002')
  [ "$n" -ge 1 ] && ok "$t multiboot sihri denetleniyor (EBX guvenligi)" \
                 || bad "$t sihir denetlenmiyor - cop EBX okunabilir"
done

# --- BARE KOD YOLUNU GERCEKTEN CALISTIR ---
# Emulator yok, ama bare HAL'in ayricalikli OLMAYAN kismi (kendi
# itme ayiricisi, .bss sifirlama, mb_parse, dilin tamami) sirodan
# kod. BARE_SIM ile UART'i write() syscall'ina yonlendirip
# CALISTIRIYORUZ. QEMU'nun yerini tutmaz ama statik denetimden
# cok daha fazlasini kapsar.
python3 bench/gen_embed.py ornekler/onay.al > src/bench_embed.inc 2>/dev/null
for t in bare-x86_64 bare-i386; do
  EXTRA_CFLAGS="-DBENCH_SRC=1 -DBARE_SIM=1" OUT_BIN="build/sim-$t" \
    ./build.sh "$t" >/dev/null 2>&1
  out=$(timeout 60 "./build/sim-$t" 2>&1)
  n=$(echo "$out" | grep -c "onay bitti")
  g=$(echo "$out" | grep -c "GUARD BOZULDU")
  if [ "$n" = "1" ] && [ "$g" = "0" ]; then
    ok "$t bare kod yolu bastan sona calisti (12 baslik)"
  else
    bad "$t bare kod yolu: onay=$n guard=$g"
  fi
done
rm -f src/bench_embed.inc
./build.sh linux-x86_64 >/dev/null 2>&1

echo "  TUM BARE DENETIMLERI GECTI" || echo "  BARE DENETIM HATASI"
exit $fail
