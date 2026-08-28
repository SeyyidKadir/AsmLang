#!/usr/bin/env bash
# qemu-kur.sh - yuklenen .deb paketlerini ac ve QEMU'yu kullanilabilir yap
#
# Kok dizine KURMAZ; /home/claude/qemu altina acar ve sarmalayici yazar.
# Boylece kapsayicinin geri kalanina dokunulmaz.
set -e
SRC="${1:-/mnt/user-data/uploads}"
PFX=/home/claude/qemu
TMP=/tmp/qemu-debs
rm -rf "$PFX" "$TMP"; mkdir -p "$PFX" "$TMP"

# Arsiv ya da tek tek .deb kabul edilir.
# Yukleme sirasinda uzanti degisebiliyor (.tar.gz -> _tar.gz),
# o yuzden ICERIGE bakiyoruz, ada degil.
for a in "$SRC"/*; do
  [ -f "$a" ] || continue
  case $(file -b "$a" 2>/dev/null) in
    *gzip*)  tar xzf "$a" -C "$TMP" 2>/dev/null || true ;;
    *bzip2*) tar xjf "$a" -C "$TMP" 2>/dev/null || true ;;
    *XZ*|*xz*) tar xJf "$a" -C "$TMP" 2>/dev/null || true ;;
    *Zip*)   unzip -q -o "$a" -d "$TMP" 2>/dev/null || true ;;
    *POSIX\ tar*) tar xf "$a" -C "$TMP" 2>/dev/null || true ;;
  esac
done
cp "$SRC"/*.deb "$TMP"/ 2>/dev/null || true

n=0
for d in $(find "$TMP" -name '*.deb' -type f); do
  dpkg-deb -x "$d" "$PFX"
  n=$((n+1))
done
[ "$n" = "0" ] && { echo "  $SRC icinde .deb ya da arsiv bulunamadi"; exit 1; }

BIN=$(find "$PFX" -name 'qemu-system-i386' -type f | head -1)
[ -z "$BIN" ] && { echo "  qemu-system-i386 cikmadi ($n paket acildi)"; exit 1; }

LIBS=$(find "$PFX" -name '*.so*' -printf '%h\n' | sort -u | tr '\n' ':')
mkdir -p "$PFX/bin"
for q in qemu-system-i386 qemu-system-x86_64; do
  B=$(find "$PFX" -name "$q" -type f | head -1)
  [ -z "$B" ] && continue
  # QEMU modulleri (accel-tcg, hw-*) derlenmis yoldan arar.
  # Kok dizine kurmadigimiz icin -L ile veri dizinini,
  # QEMU_MODULE_DIR ile de modul dizinini gostermek gerekiyor.
  # Modul dizini: ICINDE accel-tcg*.so olan dizin. Ad benzerligine
  # guvenmek yetmiyor - usr/lib/qemu bos cikabiliyor.
  MODS=$(dirname "$(find "$PFX" -name 'accel-tcg-*.so' | head -1)")
  # -L TEK dizin alir ama BIOS (seabios) ve ag onyukleyicileri (ipxe)
  # AYRI paketlerde geliyor. Hepsini tek veri dizininde topluyoruz.
  DATA="$PFX/share"
  mkdir -p "$DATA"
  for d in $(find "$PFX/usr/share" -maxdepth 1 -type d); do
    [ "$d" = "$PFX/usr/share" ] && continue
    cp -rns "$d"/* "$DATA"/ 2>/dev/null || true
  done
  cat > "$PFX/bin/$q" <<WRAP
#!/usr/bin/env bash
export LD_LIBRARY_PATH="$LIBS\$LD_LIBRARY_PATH"
export QEMU_MODULE_DIR="$MODS"
exec "$B" -L "$DATA" "\$@"
WRAP
  chmod +x "$PFX/bin/$q"
done

echo "  $n paket acildi"
echo "  PATH'e ekleyin: export PATH=$PFX/bin:\$PATH"
"$PFX/bin/qemu-system-i386" --version 2>&1 | head -1 | sed 's/^/  /'
