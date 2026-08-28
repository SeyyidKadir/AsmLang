// grafik.al - dogrusal cerceve tamponu, YUKLEYICI OLMADAN
//
// QEMU'nun standart VGA'si (ve gercek Bochs/QXL) "Bochs Graphics
// Adapter" arayuzunu destekler: mod kurulumu 0x1CE/0x1CF
// portlarindan yapilir, 16-bit BIOS cagrisina GEREK YOKTUR.
//
// Bu onemli: multiboot cekirdegi 32-bit korumali modda baslar ve
// oradan "int 0x10" cagrilamaz. GRUB'un video istegi ya da gercek
// mod donusu gerekirdi. BGA ikisini de atlatiyor.
//
// TAMAMEN BU DILDE YAZILDI - yeni govde fonksiyonu eklenmedi.
// Kullanilanlar: port_oku, port_yaz, bellek_yaz, bellek_oku.
//
//   tools/qemu.sh ornekler/grafik.al

// Bit islemleri geldikten sonra: kaydirma ve maske ile tek satir.
// Onceki surum bolme/kalanla yapiyordu ve negatif degerde isaret
// duzeltmesi gerekiyordu.
fonk uhex(v) {
    dondur hex((v >> 16) & 65535) + hex(v & 65535)
}

// ---- PCI yapilandirma alani (portlar 0xCF8 / 0xCFC) ----
// Etkinlestirme biti artik kaydirma ile: 1 << 31.
fonk pci_oku(veri, aygit, islev, ofset) {
    tanim adr = 1 << 31
    adr = adr | (veri << 16)
    adr = adr | (aygit << 11)
    adr = adr | (islev << 8)
    adr = adr | ofset
    port_yaz(3320, adr, 4)
    dondur port_oku(3324, 4)
}

// VGA aygitini bul: sinif kodu 0x0300 (ofset 0x08'in ust yarisi)
fonk vga_bul() {
    her (tanim d = 0; d < 32; d = d + 1) {
        tanim kimlik = pci_oku(0, d, 0, 0)
        // 0xFFFFFFFF 32 bit isaretli olarak -1 gorunur
        eger kimlik != 0 - 1 {
            tanim sinif = (pci_oku(0, d, 0, 8) >> 16) & 65535
            eger sinif == 768 {
                dondur d
            }
        }
    }
    dondur 0 - 1
}

// ---- BGA kayitlari ----
fonk bga_yaz(indeks, deger) {
    port_yaz(462, indeks, 2)
    port_yaz(463, deger, 2)
}

fonk bga_oku(indeks) {
    port_yaz(462, indeks, 2)
    dondur port_oku(463, 2)
}

yazdir "== asmlang grafik: BGA uzerinden mod kurulumu =="

// 1. BGA var mi: surum kaydi 0xB0C0..0xB0C5 arasi olmali
tanim surum = bga_oku(0)
yaz("BGA surumu     : ")
yazdir hex(surum)
eger surum < 45248 {
    yazdir "BGA yok - bu ekran karti desteklemiyor"
} yoksa {

// 2. VGA aygitini PCI'da bul, cerceve tamponu adresini al (BAR0)
tanim d = vga_bul()
yaz("PCI VGA aygiti : ")
eger d < 0 {
    yazdir "bulunamadi"
} yoksa {
    yazdir yazi(d)
    tanim bar = pci_oku(0, d, 0, 16)
    // BAR0'in alt 4 biti bayrak; maskeyle temizlenir.
    // Bit islemleri gelmeden once bunu bolme/kalanla yapiyorduk
    // ve negatif degerde TERS calisiyordu (Asama 51).
    tanim fb = bar & ~15
    yaz("cerceve tamponu: ")
    yazdir uhex(fb)

    // 3. Modu kur: 640x480x32, dogrusal cerceve tamponu
    tanim G = 640
    tanim Y = 480
    bga_yaz(4, 0)          // once KAPAT (mod degistirmeden sart)
    bga_yaz(1, G)          // genislik
    bga_yaz(2, Y)          // yukseklik
    bga_yaz(3, 32)         // bit/piksel
    bga_yaz(4, 65)         // 0x41 = etkin | dogrusal tampon

    yaz("kurulan mod    : ")
    yaz(yazi(bga_oku(1)))
    yaz("x")
    yaz(yazi(bga_oku(2)))
    yaz("x")
    yazdir yazi(bga_oku(3))

    // 4. Ciz: mavi zemin, kirmizi/yesil/beyaz cizgiler
    her (tanim y = 0; y < Y; y = y + 1) {
        tanim satir = fb + y * G * 4
        her (tanim x = 0; x < G; x = x + 1) {
            bellek_yaz(satir + x * 4, 2245018, 4)
        }
    }
    // yatay kirmizi
    her (tanim x = 0; x < G; x = x + 1) {
        bellek_yaz(fb + 100 * G * 4 + x * 4, 16711680, 4)
    }
    // dikey yesil
    her (tanim y = 0; y < Y; y = y + 1) {
        bellek_yaz(fb + y * G * 4 + 100 * 4, 65280, 4)
    }
    // capraz beyaz
    her (tanim i = 0; i < 400; i = i + 1) {
        bellek_yaz(fb + i * G * 4 + i * 4, 16777215, 4)
    }
    // dogrulama icin bilinen desen: sol ust kose
    bellek_yaz(fb, 16711680, 4)
    bellek_yaz(fb + 4, 65280, 4)
    bellek_yaz(fb + 8, 255, 4)

    yazdir "cizim tamam    : mavi zemin + kirmizi/yesil/beyaz"
    yaz("sol ust 3 piksel: ")
    yaz(hex(bellek_oku(fb, 4)))
    yaz(" ")
    yaz(hex(bellek_oku(fb + 4, 4)))
    yaz(" ")
    yazdir hex(bellek_oku(fb + 8, 4))
}
}

yazdir "== grafik bitti =="
