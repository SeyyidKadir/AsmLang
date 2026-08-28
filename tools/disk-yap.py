#!/usr/bin/env python3
"""disk-yap.py - onyukleyici + cekirdekten acilabilir disk imaji uret.

    python3 tools/disk-yap.py build/bare-i386 disk.img

Duzen:
    sektor 0      onyukleyici (512 bayt, MBR imzali)
    sektor 1..N   cekirdek HAM IKILI olarak (ELF degil)

Cekirdek neden ham: 512 baytlik onyukleyiciye ELF cozumleyici
sigmaz. objcopy ile duz ikiliye ceviriyoruz; cekirdek zaten
0x100000'e yuklenecek sekilde baglaniyor.
"""
import subprocess, sys, os, tempfile

if len(sys.argv) != 3:
    sys.exit(__doc__)
kernel, out = sys.argv[1], sys.argv[2]
root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

# 1) cekirdegi ham ikiliye cevir
raw = tempfile.mktemp(suffix=".bin")
subprocess.run(["objcopy", "-O", "binary", kernel, raw], check=True)
ksize = os.path.getsize(raw)
ksect = (ksize + 511) // 512
print(f"  cekirdek : {ksize} bayt -> {ksect} sektor")

# 1b) giris noktasini ELF basligindan al
hdr = subprocess.run(["readelf", "-h", kernel], capture_output=True, text=True).stdout
entry = int(hdr.split("Entry point address:")[1].split()[0], 16)
print(f"  giris    : 0x{entry:x}")

# 2) onyukleyiciyi cekirdek boyutunu ve girisi bilerek derle
boot_o = tempfile.mktemp(suffix=".o")
boot_bin = tempfile.mktemp(suffix=".bin")
subprocess.run(["gcc", "-m32", "-c", "-nostdlib", "-ffreestanding",
                f"-DKERNEL_SECTORS={ksect}", "-DVBE_MODE=0x4118",
                f"-DKERNEL_ENTRY=0x{entry:x}",
                os.path.join(root, "src/os/bare/boot.S"), "-o", boot_o],
               check=True)
# -Ttext 0: kod 0x07C0 segmentinde 0 ofsetten basliyor. 0x7C00
# tabanli baglamak 16-bit yer degistirmeye sigmiyor.
subprocess.run(["ld", "-m", "elf_i386", "-Ttext", "0", "-e", "_boot",
                "--oformat", "binary", "-o", boot_bin, boot_o], check=True)
bsize = os.path.getsize(boot_bin)
if bsize != 512:
    sys.exit(f"  HATA: onyukleyici {bsize} bayt, 512 olmali")
sig = open(boot_bin, "rb").read()[510:512]
if sig != b"\x55\xAA":
    sys.exit("  HATA: MBR imzasi yok")
print(f"  onyukleyici: 512 bayt, imza tamam")

# 3) imaji birlestir
with open(out, "wb") as f:
    f.write(open(boot_bin, "rb").read())
    f.write(open(raw, "rb").read())
    # QEMU IDE icin en az 1 MB'a tamamla
    pad = 1024 * 1024 - f.tell()
    if pad > 0:
        f.write(b"\0" * pad)
print(f"  imaj     : {out} ({os.path.getsize(out)} bayt)")
os.unlink(raw); os.unlink(boot_o); os.unlink(boot_bin)
