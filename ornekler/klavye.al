// klavye.al - PS/2 klavye denemesi
yazdir "== klavye =="
yaz("tus_var ilk : ")
yazdir tus_var()
yazdir "tus bekleniyor (5 tus)..."
her (tanim i = 0; i < 5; i = i + 1) {
    tanim k = tus()
    yaz("tus ")
    yaz(yazi(i))
    yaz(" = ")
    yaz(yazi(k))
    yaz(" '")
    yaz(metin(tampona(yazi(k))))
    yazdir "'"
}
yazdir "== bitti =="
