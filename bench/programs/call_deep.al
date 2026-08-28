fonk f(n) { eger n <= 0 { dondur 0 } dondur 1 + f(n - 1) }
tanim i = 0
iken i < 4000 { f(500) i = i + 1 }
yazdir i
