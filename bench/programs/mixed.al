// Genis JIT kapsamini olcen is yuku: yereller, bolme, esitlik, kosullu
tanim g = 0
tanim i = 0
iken i < 1500000 {
    tanim y = i % 7
    tanim z = y * 3 + 1
    eger z == 1 { g = g + 1 } yoksa { g = g + z }
    eger degil (y < 3) { g = g - 1 }
    i = i + 1
}
yazdir g
