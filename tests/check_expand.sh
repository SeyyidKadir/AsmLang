#!/usr/bin/env bash
# Capraz derleyici olmadan makro genisletmesini denetler.
# Stringify kazasi (#param) ve tanimsiz makro kalintilarini yakalar.
set -u
cd "$(dirname "$0")/.."
fail=0
check() {
  local name=$1 arch=$2 os=$3 osdir=$4
  out=$(gcc -E -x assembler-with-cpp -U__x86_64__ -U__linux__ -U__unix__ \
        -D$arch -D$os -Isrc src/main.S src/os/$osdir/os.S 2>&1)
  if [ $? -ne 0 ]; then echo "FAIL $name (cpp hatasi)"; fail=1; return; fi
  # .ascii veri satirlarini disla: icindeki "addk" gibi metinler
  # komut sanilip yanlis alarm veriyordu (gercek bir yanlis pozitif)
  if echo "$out" | grep -v '\.ascii' | grep -qE '^[[:space:]]*(mov|add|sub|ldr|str)[^\n]*"'; then
    echo "FAIL $name: stringify kazasi"; echo "$out" | grep -E '(mov|add|sub)[^\n]*"' | head -3; fail=1; return
  fi
  if echo "$out" | grep -vE '^#' | grep -qE '\b(MOVI|LEA_SYM|CALL|ENTER|LEAVE_|SPILL|FILL|BZ|RET|FUNC)\b'; then
    echo "FAIL $name: genisletilmemis makro"; fail=1; return
  fi
  echo "OK   $name"
}
check linux-x86_64   __x86_64__ __linux__  linux
check linux-i386     __i386__   __linux__  linux
check linux-aarch64  __aarch64__ __linux__ linux
check linux-arm      __arm__    __linux__  linux
check macos-x86_64   __x86_64__ __APPLE__  macos
check macos-aarch64  __aarch64__ __APPLE__ macos
check windows-x86_64 __x86_64__ _WIN32     windows
check windows-i386   __i386__   _WIN32     windows
check windows-aarch64 __aarch64__ _WIN32   windows
# bare-metal: OS makrosu yok, -DBARE=1 ile secilir
bcheck() {
  local name=$1 arch=$2
  out=$(gcc -E -x assembler-with-cpp -U__x86_64__ -U__linux__ -U__unix__ \
        -D$arch -DBARE=1 -DLOAD_ADDR=0x100000 -Isrc \
        src/main.S src/os/bare/os.S 2>&1)
  if [ $? -ne 0 ]; then echo "FAIL $name (cpp hatasi)"; fail=1; return; fi
  if echo "$out" | grep -v '\.ascii' | grep -qE '^[[:space:]]*(mov|add|sub|ldr|str)[^\n]*"'; then
    echo "FAIL $name: stringify kazasi"; fail=1; return; fi
  echo "OK   $name"
}
bcheck bare-x86_64  __x86_64__
bcheck bare-i386    __i386__
bcheck bare-aarch64 __aarch64__
bcheck bare-arm     __arm__
exit $fail
