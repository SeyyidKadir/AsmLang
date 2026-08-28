// Dizgi birikimi: klasik O(n^2) tuzagi
// s = s + "x" her turda YENI nesne ayirir ve tamamini kopyalar
tanim s = ""
tanim i = 0
iken i < 8000 {
    s = s + "x"
    i = i + 1
}
yazdir uzunluk(s)
