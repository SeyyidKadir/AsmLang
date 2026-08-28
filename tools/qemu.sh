#!/usr/bin/env bash
# qemu.sh - bare-metal imaji emulatorde calistir ve seri ciktiyi goster
#
#   tools/qemu.sh [program.al]
#
# Program verilmezse ornekler/onay.al kullanilir (tanilama raporu).
set -e
cd "$(dirname "$0")/.."

PROG="${1:-ornekler/onay.al}"
TARGET="${TARGET:-bare-i386}"

echo "== derleniyor: $PROG -> $TARGET =="
python3 bench/gen_embed.py "$PROG" > src/bench_embed.inc
EXTRA_CFLAGS="-DBENCH_SRC=1" ./build.sh "$TARGET"

case "$TARGET" in
  bare-i386)   QEMU=qemu-system-i386 ;;
  bare-x86_64) QEMU=qemu-system-x86_64
               echo "!! UYARI: multiboot cekirdegi 32-BIT korumali modda"
               echo "!! baslatir. bare-x86_64 ELF64'tur ve DOGRUDAN ACILAMAZ."
               echo "!! Uzun mod gecis kodu yazilmadi. bare-i386 kullanin." ;;
  *) echo "bu hedef emulatorde denenmiyor: $TARGET"; exit 1 ;;
esac

if ! command -v "$QEMU" >/dev/null 2>&1; then
  echo "$QEMU bulunamadi. Kurulum:"
  echo "  Debian/Ubuntu : sudo apt install qemu-system-x86"
  echo "  Fedora        : sudo dnf install qemu-system-x86"
  echo "  macOS         : brew install qemu"
  exit 1
fi

echo
echo "== calisiyor (cikmak icin Ctrl-A sonra X) =="
echo
# -serial stdio : UART ciktisi terminale
# -display none : pencere acma (grafik testi icin kaldirin)
# -nic none : ag karti ROM'u (efi-e1000.rom) ayri pakette gelmiyor
exec "$QEMU" -kernel "build/$TARGET" -serial stdio -display none \
     -no-reboot -nic none
