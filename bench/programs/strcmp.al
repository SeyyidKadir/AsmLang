// Dizgi karsilastirma: == bayt bayt, O(n)
tanim a = "abcdefghijklmnopqrstuvwxyz0123456789"
tanim b = "abcdefghijklmnopqrstuvwxyz0123456789"
tanim n = 0
tanim i = 0
iken i < 300000 {
    eger a == b { n = n + 1 }
    i = i + 1
}
yazdir n
