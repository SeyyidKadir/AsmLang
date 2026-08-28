// imlec.al - fare imleci: grafik + fare birlikte
//
// DIKKAT: fonksiyonlar disaridaki YEREL degiskene erisemez
// (kapanis yok). Bu yuzden ekran bilgileri KURESEL tutuluyor.

tanim e  = ekran()
tanim FB = 0
tanim G  = 0
tanim Y  = 0
tanim P  = 0
tanim B  = 0

fonk nokta(x, y, renk) {
    eger x < 0 { dondur bos }
    eger y < 0 { dondur bos }
    eger x >= G { dondur bos }
    eger y >= Y { dondur bos }
    dondur bellek_yaz(FB + y * P + x * B, renk, B)
}

fonk imlec(x, y, renk) {
    her (tanim i = 0; i < 10; i = i + 1) {
        nokta(x + i, y, renk)
        nokta(x, y + i, renk)
    }
}

eger e == bos {
    yazdir "cerceve tamponu yok"
} yoksa {
    FB = e[0]
    G  = e[1]
    Y  = e[2]
    P  = e[3]
    B  = e[4] >> 3
    yaz("ekran ") yaz(yazi(G)) yaz("x") yaz(yazi(Y)) yaz(" bpp ") yazdir yazi(e[4])

    ekran_temizle(2105376)
    yaz("fare : ") yazdir fare_kur()

    tanim ex = G / 2
    tanim ey = Y / 2
    tanim ox = ex
    tanim oy = ey
    imlec(ex, ey, 16777215)

    tanim n = 0
    her (tanim i = 0; i < 300000000; i = i + 1) {
        eger fare_var() {
            tanim f = fare()
            ex = (G / 2) + f[0]
            ey = (Y / 2) + f[1]
            eger ex < 0 { ex = 0 }
            eger ey < 0 { ey = 0 }
            eger ex > G - 12 { ex = G - 12 }
            eger ey > Y - 12 { ey = Y - 12 }
            imlec(ox, oy, 2105376)
            tanim renk = 16777215
            eger (f[2] & 1) == 1 { renk = 16711680 }
            imlec(ex, ey, renk)
            ox = ex
            oy = ey
            n = n + 1
            eger n > 8 { kir }
        }
    }
    yaz("paket ") yazdir yazi(n)
    yaz("konum ") yaz(yazi(ex)) yaz(",") yazdir yazi(ey)
}
yazdir "== bitti =="
