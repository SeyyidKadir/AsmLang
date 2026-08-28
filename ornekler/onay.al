// onay.al - bare-metal dogrulama raporu
//
// Bu program CEKIRDEK ICINDE calisir ve seri porta rapor basar.
// Kendisinin calisiyor olmasi zaten sozcuk cozumleyici + ayristirici
// + derleyici + sanal makine + UART yolunun tamaminin calistiginin
// kanitidir.
//
// Calistirma:
//   python3 bench/gen_embed.py ornekler/onay.al > src/bench_embed.inc
//   EXTRA_CFLAGS="-DBENCH_SRC=1" ./build.sh bare-i386
//   qemu-system-i386 -kernel build/bare-i386 -serial stdio -display none

yazdir "================================"
yazdir "  asmlang bare-metal onay"
yazdir "================================"

// ---- 1. Yukleyici ----
tanim b = acilis()
yaz("1. multiboot yukleyici : ")
eger b == bos {
    yazdir "SORGULANMADI (bare degil)"
} yoksa {
    eger b[0] == 1 {
        yazdir "VAR"
        yaz("   bayraklar           : ")
        yazdir hex(b[1])
    } yoksa {
        yazdir "YOK - EBX guvenilmez, video/bellek bilgisi okunmadi"
    }
}

// ---- 2. Ekran ----
tanim e = ekran()
yaz("2. cerceve tamponu     : ")
eger e == bos {
    yazdir "SORGULANMADI"
} yoksa {
    eger e[0] == 0 {
        yazdir "YOK (yukleyici video kurmadi) -> metin ekrani kullanilacak"
    } yoksa {
        yaz("VAR ")
        yaz(yazi(e[1]))  yaz("x")  yaz(yazi(e[2]))  yaz("x")  yazdir yazi(e[4])
        yaz("   taban adresi        : ")
        yazdir hex(e[0])
    }
}

// ---- 3. CPU ----
tanim c = cpuid(0)
yaz("3. cpuid               : ")
eger c == bos {
    yazdir "YOK"
} yoksa {
    yaz("VAR  en buyuk yaprak=")
    yaz(yazi(c[0]))
    yaz("  imza=")
    yazdir hex(c[1])
}

// ---- 4. Port G/C ----
yaz("4. port G/C            : ")
tanim p = port_oku(97, 1)
eger p == bos {
    yazdir "YOK (barindirilan yapi)"
} yoksa {
    yaz("VAR  port 0x61 = ")
    yazdir hex(p)
}

// ---- 5. Bellek ----
yaz("5. yigin ayirma        : ")
tanim t = tampon(4096)
eger t == bos {
    yazdir "BASARISIZ"
} yoksa {
    yazdir "TAMAM (4096 bayt)"
}

yaz("6. cop toplama         : ")
tanim s = ""
her (tanim i = 0; i < 200; i = i + 1) { s = s + "x" }
eger uzunluk(s) == 200 {
    yazdir "TAMAM (200 birlestirme)"
} yoksa {
    yazdir "BASARISIZ"
}

// ---- 7. Aritmetik ----
yaz("7. tamsayi genisligi   : ")
// Tasma HATA firlatiyor (sarmiyor), o yuzden tasmadan olcelim:
// 2^30 kac kere ikiye katlanabiliyor -> genislik.
tanim v = 1073741824
tanim n = 30
eger us(2, 40) == bos {
    yazdir "32 bit"
} yoksa {
    yazdir "64 bit"
}

// ---- 8. Dil ----
fonk fib(n) { eger n < 2 { dondur n }  dondur fib(n - 1) + fib(n - 2) }
yaz("8. ozyineleme fib(20)  : ")
tanim f = fib(20)
eger f == 6765 {
    yazdir "TAMAM"
} yoksa {
    yaz("BASARISIZ -> ")
    yazdir yazi(f)
}

// ---- 9. Metin ekrani ----
yaz("9. VGA metin ekrani    : ")
tanim v = vga(0, 0, 65, 10)
eger v == bos {
    yazdir "YOK"
} yoksa {
    yazdir "YAZILDI (ekranin sol ustunde yesil 'A' gorunmeli)"
}

// ---- 10. Grafik ----
yaz("10. grafik cizim       : ")
eger e == bos {
    yazdir "ATLANDI"
} yoksa {
    eger e[0] == 0 {
        yazdir "ATLANDI (cerceve tamponu yok)"
    } yoksa {
        tanim t = ekran_temizle(1122867)
        eger t == bos {
            yazdir "BASARISIZ (bu bit derinligi desteklenmiyor)"
        } yoksa {
            her (tanim x = 0; x < 256; x = x + 1) {
                piksel(x, 100, 16711680)
                piksel(100, x, 65280)
                piksel(x, x, 16777215)
            }
            yazdir "CIZILDI (mavi zemin, kirmizi/yesil/beyaz cizgiler)"
        }
    }
}

// ---- 11. Disk ----
yaz("11. ATA PIO disk okuma : ")
tanim sek = tampon(512)
tanim r = disk_oku(0, 1, sek)
eger r == bos {
    yazdir "YOK ya da disk bagli degil"
} yoksa {
    yaz("OKUNDU  ilk iki bayt=")
    yaz(hex(sek[0]))
    yaz(" ")
    yazdir hex(sek[1])
}

// ---- 12. Ses ----
yaz("12. PC hoparloru       : ")
tanim ses1 = ses(880)
eger ses1 == bos {
    yazdir "YOK"
} yoksa {
    her (tanim i = 0; i < 200000; i = i + 1) { }
    ses_kapat()
    yazdir "CALDI (880 Hz, kisa)"
}

yazdir "================================"
yazdir "  onay bitti"
yazdir "================================"
