// Birikim deseni: x = x + y  (ACCG hedefi)
// Ayni zamanda TOS caching icin VEKIL OLCUM - ACCG yigin trafiginin
// TAMAMINI kaldirir, yani TOS'un saglayabilecegi en iyi durumun ustu.
tanim toplam = 0
tanim bir = 1
tanim i = 0
iken i < 20000000 {
    toplam = toplam + bir
    i = i + 1
}
yazdir toplam
