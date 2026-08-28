// Cekirdek ornegi: ekran + ses + disk
tanim e = ekran()
eger e[0] == 0 {
    // yukleyici video kurmadi: metin ekranina yaz
    tanim msg = "asmlang cekirdek"
    her (tanim i = 0; i < uzunluk(msg); i = i + 1) {
        vga(i, 0, 65, 10)
    }
} yoksa {
    ekran_temizle(0)
    her (tanim x = 0; x < 200; x = x + 1) {
        piksel(x, 100, 16711680)
        piksel(100, x, 65280)
    }
}
ses(440)
ses_kapat()
tanim b = tampon(512)
yazdir disk_oku(0, 1, b)
