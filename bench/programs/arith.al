// Genisleyen JIT kapsamini olcen is yuku: ADD/SUB/MUL, ADDK, karsilastirma
tanim a = 0
tanim i = 0
iken i < 3000000 {
    a = a + 3
    a = a - 1
    a = a * 1
    eger a > 1000000 { a = 0 }
    i = i + 1
}
yazdir a
