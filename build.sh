#!/usr/bin/env bash
# asmlang derleme betigi
#   ./build.sh                 yerel hedefi derle (Termux dahil otomatik algilanir)
#   ./build.sh termux-aarch64  tek hedef
#   ./build.sh all             denenebilir tum hedefler
#   ./build.sh liste           hedefleri listele
#
# TERMUX NOTU: shebang calismazsa "bash build.sh" ile calistirin.
#   pkg install clang binutils
set -u

SRC=src
OUT=build
# Yurutucu (player) kipi: lexer/parser/derleyici/gozetleme deligi YOK.
# Yalniz .bc yukleyici + dogrulayici + VM + calisma zamani.
if [ "${MODE_PLAYER:-0}" = "1" ]; then
SOURCES="$SRC/main.S $SRC/vm/codebuf.S $SRC/vm/vm.S $SRC/vm/natives.S $SRC/vm/natives2.S $SRC/vm/natives3.S $SRC/vm/osprim.S $SRC/vm/osdev.S $SRC/vm/klavye.S $SRC/vm/fare.S $SRC/vm/ffi.S
         $SRC/vm/bcfile.S $SRC/vm/jit.S $SRC/vm/jitasm.S $SRC/vm/jitlbl.S $SRC/vm/jitcomp.S $SRC/vm/jitx64.S $SRC/compiler/verify.S
         $SRC/rt/rt.S $SRC/rt/heap.S $SRC/rt/input.S $SRC/rt/args.S $SRC/rt/guard.S"
else
SOURCES="$SRC/main.S $SRC/lexer/lexer.S $SRC/parser/parser.S $SRC/parser/astdump.S
         $SRC/compiler/compiler.S $SRC/compiler/peephole.S $SRC/compiler/verify.S $SRC/compiler/cstats.S $SRC/vm/codebuf.S $SRC/vm/vm.S $SRC/vm/natives.S $SRC/vm/natives2.S $SRC/vm/natives3.S $SRC/vm/osprim.S $SRC/vm/osdev.S $SRC/vm/klavye.S $SRC/vm/fare.S $SRC/vm/ffi.S $SRC/vm/bcfile.S $SRC/vm/jit.S $SRC/vm/jitasm.S $SRC/vm/jitlbl.S $SRC/vm/jitcomp.S $SRC/vm/jitx64.S $SRC/vm/disasm.S
         $SRC/rt/rt.S $SRC/rt/heap.S $SRC/rt/input.S $SRC/rt/args.S $SRC/rt/guard.S"
fi
mkdir -p "$OUT"

is_termux() {
  [ -n "${TERMUX_VERSION:-}" ] && return 0
  case "${PREFIX:-}" in *com.termux*) return 0 ;; esac
  [ -d /data/data/com.termux ] && return 0
  return 1
}

# ad             os       ucluk(triple)
targets() {
  cat <<'EOF'
linux-x86_64    linux   x86_64-linux-gnu
linux-i386      linux   i386-linux-gnu
linux-aarch64   linux   aarch64-linux-gnu
linux-arm       linux   armv7-linux-gnueabihf
termux-aarch64  linux   aarch64-linux-android
termux-arm      linux   armv7a-linux-androideabi
termux-x86_64   linux   x86_64-linux-android
bare-x86_64     bare    x86_64-linux-gnu
bare-i386       bare    i386-linux-gnu
bare-aarch64    bare    aarch64-linux-gnu
bare-arm        bare    armv7-linux-gnueabihf
macos-x86_64    macos   x86_64-apple-macos11
macos-aarch64   macos   arm64-apple-macos11
windows-x86_64  windows x86_64-windows-gnu
windows-i386    windows i686-windows-gnu
windows-aarch64 windows aarch64-windows-gnu
EOF
}

os_ldflags() {
  case "$1" in
    bare)    echo "-Wl,-z,noexecstack -Wl,-e,_start -Wl,-T,$SRC/os/bare/image.ld -Wl,--defsym,LOAD_ADDR=${LOAD_ADDR:-0x100000} -Wl,--build-id=none" ;;
    linux)   echo "-Wl,-z,noexecstack -Wl,-e,_start" ;;
    macos)   echo "-Wl,-e,_main" ;;
    windows) echo "-lkernel32" ;;
  esac
}

# Baglama kiplerini oncelik sirasiyla dondurur; ilki tutmazsa digeri denenir.
link_modes() {
  local name="$1" os="$2"
  case "$os" in
    bare)    echo "-static -no-pie|" ; return ;;
    macos)   echo "|" ; return ;;
    windows) case "$name" in
               *-i386) echo "-Wl,-e,_mainCRTStartup|" ;;
               *)      echo "-Wl,-e,mainCRTStartup|" ;;
             esac ; return ;;
  esac
  # Linux/Android. Android PIE zorunlu kilabilir; kod yer degistirme kaydi
  # uretmedigi icin static-pie sorunsuz. ARM32 literal havuzunda mutlak
  # adres kullandigindan orada once no-pie denenir.
  case "$name" in
    termux-arm)  echo "-static -no-pie|-static-pie" ;;
    termux-*)    echo "-static-pie|-static -no-pie" ;;
    *)           echo "-static -no-pie|-static-pie" ;;
  esac
}

build_one() {
  local name="$1" os="$2" triple="$3"
  local cc="clang" pre="" ext=""
  [ "$os" = windows ] && ext=".exe"

  if command -v clang >/dev/null 2>&1; then
    # Termux'te yerel hedef icin ucluk zorlamayiz: clang zaten dogru
    # Android ABI'siyle yapilandirilmis gelir.
    if is_termux && [ "$name" = "$(native_target)" ]; then
      pre=""
    else
      pre="--target=$triple"
    fi
  else
    case "$name" in
      linux-x86_64|termux-x86_64|bare-x86_64) cc="gcc"; pre="-m64" ;;
      linux-i386|bare-i386)                   cc="gcc"; pre="-m32" ;;
      *) echo "ATLA  $name  (clang yok)"; return 2 ;;
    esac
  fi
  # -DBARE=1 HER IKI derleyici yolunda da gecmeli. Once yalnizca clang
  # dalindaydi; gcc ile derlenen bare-metal imajlar OS_BARE olmadan
  # kuruluyordu ve port G/C kodu hic uretilmiyordu. Bu ortamda clang
  # olmadigi icin BUTUN bare yapilari boyle derlenmis.
  if [ "$os" = bare ]; then
    pre="$pre -DBARE=1 -DLOAD_ADDR=${LOAD_ADDR:-0x100000}"
  fi
  if [ "${BC_EMBED:-0}" = "1" ]; then pre="$pre -DBC_EMBED=1"
  fi

  local modes; modes="$(link_modes "$name" "$os")"
  local first="${modes%%|*}" second="${modes#*|}"
  local base="$(os_ldflags "$os")"

  for mode in "$first" "$second"; do
    # EXTRA_CFLAGS: benchmark harness -DOPT_* / -DSRC_INC gecirmek icin
  # USER_SRC: kullanicinin C/C++ dosyalari. Ayni freestanding
  # bayraklariyla derlenir; bare-metal'de libc YOK.
  # USER_SYMS=1 ile user_syms.inc'teki tanitmalar etkinlesir.
  if $cc $pre -nostdlib -ffreestanding -I"$SRC" ${EXTRA_CFLAGS:-} \
         $SOURCES "$SRC/os/$os/os.S" ${USER_SRC:-} $base $mode \
         -o "${OUT_BIN:-$OUT/$name$ext}" 2> "$OUT/$name.log"; then
      echo "OK    $name  [${mode:-varsayilan}]"
      return 0
    fi
  done
  echo "FAIL  $name  -> $OUT/$name.log"
  return 1
}

native_target() {
  local m; m="$(uname -m)"
  local pfx="linux"; is_termux && pfx="termux"
  case "$m" in
    x86_64|amd64)   echo "$pfx-x86_64" ;;
    aarch64|arm64)  echo "${pfx}-aarch64"; ;;
    armv7l|armv8l|arm) echo "${pfx}-arm" ;;
    i?86)           echo "linux-i386" ;;
    *) echo "" ;;
  esac
}

case "${1:-native}" in
  kaynaklar)
    # Kaynak listesini TEK yerden ver. Testler bunu kullanir; listeyi
    # kopyalamak eskimeye yol aciyordu (static-pie testi bir kez bu
    # yuzden yanlis "kirildi" raporladi).
    echo $SOURCES ;;
  liste) targets | awk '{printf "  %-16s %s\n", $1, $3}' ;;
  all)   targets | while read -r n o t; do build_one "$n" "$o" "$t"; done ;;
  native)
    sel="$(native_target)"
    [ -z "$sel" ] && { echo "bilinmeyen mimari: $(uname -m)"; exit 1; }
    is_termux && echo "(Termux algilandi)"
    line="$(targets | awk -v s="$sel" '$1==s')"
    build_one $line && "$OUT/$sel"
    ;;
  *)
    line="$(targets | awk -v s="$1" '$1==s')"
    [ -z "$line" ] && { echo "bilinmeyen hedef: $1"; targets | awk '{print "  "$1}'; exit 1; }
    build_one $line
    ;;
esac
