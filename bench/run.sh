#!/usr/bin/env bash
# asmlang benchmark harness
#
#   bench/run.sh                    tum program x varyant x mimari
#   bench/run.sh loop20m            tek program
#   bench/run.sh loop20m x86_64     tek program, tek mimari
#   REPS=20 bench/run.sh            tekrar sayisini degistir
#
# Kural: olculemeyen metrik UYDURULMAZ, "olculemedi" diye raporlanir.
set -u
cd "$(dirname "$0")/.."

REPS="${REPS:-12}"
PROGS="${1:-}"
ARCHS="${2:-}"
[ -z "$PROGS" ] && PROGS="$(ls bench/programs/*.al | xargs -n1 basename | sed 's/\.al$//' | tr '\n' ' ')"
[ -z "$ARCHS" ] && ARCHS="x86_64 i386"

# varyant -> derleyici bayraklari (birikimli)
variant_flags() {
  case "$1" in
    baseline) echo "-DOPT_ROTATE=0 -DOPT_PEEPHOLE=0 -DOPT_SUPER=0" ;;
    rotate)   echo "-DOPT_ROTATE=1 -DOPT_PEEPHOLE=0 -DOPT_SUPER=0" ;;
    peephole) echo "-DOPT_ROTATE=1 -DOPT_PEEPHOLE=1 -DOPT_SUPER=0" ;;
    full)     echo "-DOPT_ROTATE=1 -DOPT_PEEPHOLE=1 -DOPT_SUPER=1" ;;
  esac
}
VARIANTS="baseline rotate peephole full"

mkdir -p bench/out
HAVE_PERF=no
if command -v perf >/dev/null 2>&1; then
  if perf stat -e cycles true >/dev/null 2>&1; then HAVE_PERF=yes; fi
fi

echo "asmlang benchmark harness"
echo "  tekrar   : $REPS"
echo "  varyantlar: $VARIANTS"
echo "  mimariler : $ARCHS"
if [ "$HAVE_PERF" = yes ]; then
  echo "  perf      : var (cycles/instructions/branches/branch-misses/cache-misses)"
else
  echo "  perf      : YOK -> donanim sayaclari OLCULEMEDI (tahmin edilmiyor)"
fi
echo

for prog in $PROGS; do
  src="bench/programs/$prog.al"
  [ -f "$src" ] || { echo "yok: $src"; continue; }
  python3 bench/gen_embed.py "$src" > src/bench_embed.inc
  echo "=== $prog ==="

  for arch in $ARCHS; do
    for v in $VARIANTS; do
      bin="bench/out/${prog}-${arch}-${v}"
      flags="$(variant_flags "$v") -DBENCH_SRC=1"

      # 1) normal derleme: zamanlama icin
      EXTRA_CFLAGS="$flags" OUT_BIN="$bin" ./build.sh "linux-$arch" >/dev/null 2>&1
      if [ ! -x "$bin" ]; then
        echo "  $arch/$v: DERLENEMEDI (bkz. build/linux-$arch.log)"
        continue
      fi
      # 2) sayacli derleme: yurutulen bytecode komut sayisi icin
      EXTRA_CFLAGS="$flags -DOPT_COUNT=1" OUT_BIN="$bin.count" \
        ./build.sh "linux-$arch" >/dev/null 2>&1

      python3 bench/stats.py "$bin" "$REPS" "$arch" "$v" "$HAVE_PERF"
    done
  done
  echo
done

# demo yapisini geri getir
./build.sh linux-x86_64 >/dev/null 2>&1 || true
