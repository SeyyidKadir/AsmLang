#!/bin/sh
# qemu-indir.sh - QEMU paketlerini indirip TEK ARSIVDE paketler.
#
#   sh qemu-indir.sh
#
# Sonunda qemu-debs.tar.gz olusur; onu sohbete yukleyin.
#
# Termux dahil her yerde calisir: bash/python/zip GEREKMEZ,
# yalniz curl ya da wget (Termux'ta yoksa: pkg install curl).
# Paketler amd64 Linux icin; burada sadece INDIRILIYORLAR,
# calistirilmiyorlar - Android'de olmaniz sorun degil.
# Yarim kalirsa betigi tekrar calistirin, inenler atlanir.
# Toplam ~16 MB, 21 paket.

set -e
DIR=qemu-debs
mkdir -p "$DIR"

if command -v curl >/dev/null 2>&1; then
  GET='curl -fsSL --retry 3 -o'
elif command -v wget >/dev/null 2>&1; then
  GET='wget -q -O'
else
  echo "curl ya da wget gerekli.  Termux: pkg install curl"
  exit 1
fi

n=0; hata=0
for u in \
  http://archive.ubuntu.com/ubuntu/pool/main/libb/libbpf/libbpf1_1.3.0-2build2_amd64.deb \
  http://archive.ubuntu.com/ubuntu/pool/main/libn/libnl3/libnl-3-200_3.7.0-0.3build1.1_amd64.deb \
  http://archive.ubuntu.com/ubuntu/pool/main/libn/libnl3/libnl-route-3-200_3.7.0-0.3build1.1_amd64.deb \
  http://archive.ubuntu.com/ubuntu/pool/main/r/rdma-core/libibverbs1_50.0-2ubuntu0.2_amd64.deb \
  http://archive.ubuntu.com/ubuntu/pool/main/a/acl/acl_2.3.2-1build1.1_amd64.deb \
  http://archive.ubuntu.com/ubuntu/pool/main/i/ipxe/ipxe-qemu_1.21.1%2bgit-20220113.fbbdc3926-0ubuntu2_all.deb \
  http://archive.ubuntu.com/ubuntu/pool/main/liba/libaio/libaio1t64_0.3.113-6build1.1_amd64.deb \
  http://archive.ubuntu.com/ubuntu/pool/main/b/brltty/libbrlapi0.8_6.6-4ubuntu5_amd64.deb \
  http://archive.ubuntu.com/ubuntu/pool/main/libc/libcacard/libcacard0_2.8.0-3build4_amd64.deb \
  http://archive.ubuntu.com/ubuntu/pool/main/n/ndctl/libdaxctl1_77-2ubuntu2_amd64.deb \
  http://archive.ubuntu.com/ubuntu/pool/main/n/ndctl/libndctl6_77-2ubuntu2_amd64.deb \
  http://archive.ubuntu.com/ubuntu/pool/main/p/pmdk/libpmem1_1.13.1-1.1ubuntu2_amd64.deb \
  http://archive.ubuntu.com/ubuntu/pool/main/r/rdma-core/librdmacm1t64_50.0-2ubuntu0.2_amd64.deb \
  http://archive.ubuntu.com/ubuntu/pool/main/libs/libslirp/libslirp0_4.7.0-1ubuntu3_amd64.deb \
  http://archive.ubuntu.com/ubuntu/pool/main/libu/liburing/liburing2_2.5-1build1_amd64.deb \
  http://archive.ubuntu.com/ubuntu/pool/main/u/usbredir/libusbredirparser1t64_0.13.0-2.1build1_amd64.deb \
  http://archive.ubuntu.com/ubuntu/pool/main/q/qemu/qemu-system-common_8.2.2%2bds-0ubuntu1.16_amd64.deb \
  http://archive.ubuntu.com/ubuntu/pool/main/q/qemu/qemu-system-data_8.2.2%2bds-0ubuntu1.16_all.deb \
  http://archive.ubuntu.com/ubuntu/pool/main/d/device-tree-compiler/libfdt1_1.7.0-2build1_amd64.deb \
  http://archive.ubuntu.com/ubuntu/pool/main/s/seabios/seabios_1.16.3-2_all.deb \
  http://archive.ubuntu.com/ubuntu/pool/main/q/qemu/qemu-system-x86_8.2.2%2bds-0ubuntu1.16_amd64.deb \
  ; do
  [ "$u" = ";" ] && continue
  f=`echo "$u" | sed 's|.*/||; s|%2b|+|g; s|%2B|+|g'`
  if [ -s "$DIR/$f" ]; then
    echo "  var     $f"
    continue
  fi
  echo "  iniyor  $f"
  if $GET "$DIR/$f" "$u"; then
    n=`expr $n + 1`
  else
    echo "  HATA    $f"
    hata=`expr $hata + 1`
  fi
done

echo
if [ "$hata" != "0" ]; then
  echo "  $hata paket inemedi. Betigi tekrar calistirin."
  exit 1
fi

tar czf qemu-debs.tar.gz "$DIR"
echo "  $n paket indi"
echo "  paketlendi -> qemu-debs.tar.gz (`du -h qemu-debs.tar.gz | cut -f1`)"
echo
echo "  Simdi qemu-debs.tar.gz dosyasini sohbete yukleyin."
