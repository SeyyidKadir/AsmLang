// Determinist. NOT: eski surumu "toplam = toplam + i" idi ve 32-bit
// tasiyordu; sessizce 1642668640 uretiyordu. Tasma denetimi eklenince
// ortaya cikti. Komut karisimi ayni tutuldu (GETGLOBAL2 + ADD_SETG +
// INCGLOBAL + GETG_CONST + JLT = 5 dagitim/tur), tasma kaldirildi.
tanim toplam = 0
tanim bir = 1
tanim i = 0
iken i < 20000000 {
    toplam = bir + bir
    i = i + 1
}
yazdir toplam
