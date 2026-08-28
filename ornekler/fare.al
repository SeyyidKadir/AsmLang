// fare.al - PS/2 fare denemesi
yazdir "== fare =="
yaz("kurulum : ")
yazdir fare_kur()
yazdir "hareket bekleniyor..."
tanim n = 0
her (tanim i = 0; i < 300000000; i = i + 1) {
    eger fare_var() {
        tanim f = fare()
        yaz("x=") yaz(yazi(f[0]))
        yaz(" y=") yaz(yazi(f[1]))
        yaz(" dugme=") yazdir yazi(f[2])
        n = n + 1
        eger n > 5 { kir }
    }
}
yaz("paket : ") yazdir yazi(n)
yazdir "== bitti =="
