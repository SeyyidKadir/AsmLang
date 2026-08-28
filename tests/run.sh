#!/usr/bin/env bash
# Derlenebilen hedefleri altin ciktiyla karsilastirir.
cd "$(dirname "$0")/.."
fail=0
for t in linux-x86_64 linux-i386 linux-aarch64 linux-arm termux-aarch64 termux-arm termux-x86_64; do
  ./build.sh "$t" >/dev/null 2>&1 || { echo "ATLA $t (derlenemedi)"; continue; }
  bin="build/$t"
  case "$t" in
    *-aarch64) run="qemu-aarch64-static" ;;
    *-arm)         run="qemu-arm-static" ;;
    *)             run="" ;;
  esac
  if [ -n "$run" ] && ! command -v "$run" >/dev/null; then echo "ATLA $t ($run yok)"; continue; fi
  if $run "$bin" < /dev/null 2>/dev/null | diff -q - tests/golden/run.expected >/dev/null; then
    echo "GECTI $t"
  else
    echo "KALDI $t"; $run "$bin" < /dev/null 2>&1 | diff - tests/golden/run.expected | head -5; fail=1
  fi
done
./tests/check_expand.sh
exit $fail
