#!/usr/bin/env bash
# tests/jit.sh - JIT'in yorumlayiciyla AYNI davrandigini dogrular
#
# Kural: her program icin JIT ve yorumlayici ciktisi BIREBIR ayni
# olmali. Farkli olmasi, hizlanmadan daha onemli bir hatadir.
set -u
cd "$(dirname "$0")/.."
fail=0
ok()  { echo "  GECTI $1"; }
bad() { echo "  KALDI $1"; fail=1; }

run_both() {  # $1 = ad, program stdin'den
  cat > /tmp/jt.al
  python3 bench/gen_embed.py /tmp/jt.al > src/bench_embed.inc
  EXTRA_CFLAGS="-DBENCH_SRC=1 -DOPT_JIT=1" OUT_BIN=build/jt-on  ./build.sh linux-x86_64 >/dev/null 2>&1
  EXTRA_CFLAGS="-DBENCH_SRC=1 -DOPT_JIT=0" OUT_BIN=build/jt-off ./build.sh linux-x86_64 >/dev/null 2>&1
  a=$(timeout 60 ./build/jt-on  < /dev/null 2>&1 | sed -n '/cikti/,/ozet/p' | grep -av -- '---')
  b=$(timeout 60 ./build/jt-off < /dev/null 2>&1 | sed -n '/cikti/,/ozet/p' | grep -av -- '---')
  if [ "$a" = "$b" ]; then ok "$1"; else bad "$1: JIT='$a' yorumlayici='$b'"; fi
}

run_both "tamsayi dongusu" <<'AL'
tanim t = 0
tanim b = 1
tanim i = 0
iken i < 1000 { t = t + b  i = i + 1 }
yazdir t
AL

run_both "birikim (ACCG)" <<'AL'
tanim t = 0
tanim u = 7
tanim i = 0
iken i < 500 { t = t + u  i = i + 1 }
yazdir t
AL

run_both "tasma: yan etki TEKRARLANMAMALI" <<'AL'
yazdir 111
yazdir 222
tanim a = 2000000000
tanim b = 2000000000
a = a + b
yazdir 999
AL

run_both "tur hatasi" <<'AL'
yazdir 111
tanim a = 0
tanim b = "x"
a = a + b
AL

run_both "fonksiyon cagrisi" <<'AL'
fonk f(x) { dondur x + 1 }
fonk g(a, b) { dondur a * b + f(a) }
yazdir f(41)
yazdir g(3, 4)
AL

run_both "ozyineleme (fib)" <<'AL'
fonk fib(n) { eger n < 2 { dondur n }  dondur fib(n - 1) + fib(n - 2) }
yazdir fib(1)
yazdir fib(10)
yazdir fib(20)
AL

run_both "ozyineleme (faktoryel)" <<'AL'
fonk f(n) { eger n <= 1 { dondur 1 }  dondur n * f(n - 1) }
yazdir f(1)
yazdir f(6)
yazdir f(12)
AL

run_both "derin ozyineleme" <<'AL'
fonk f(n) { eger n <= 0 { dondur 0 }  dondur 1 + f(n - 1) }
yazdir f(500)
yazdir f(900)
AL

run_both "cagri derinligi asimi" <<'AL'
yazdir 1
fonk f(n) { eger n <= 0 { dondur 0 }  dondur 1 + f(n - 1) }
yazdir f(5000)
AL

run_both "arite uyusmazligi" <<'AL'
yazdir 1
fonk f(a, b) { dondur a + b }
yazdir f(1)
AL

run_both "cagrilabilir degil" <<'AL'
yazdir 1
tanim x = 5
yazdir x(1)
AL

run_both "ic ice cagri + yerel" <<'AL'
fonk kare(x) { tanim y = x * x  dondur y }
fonk topla3(a, b, c) { dondur kare(a) + kare(b) + kare(c) }
yazdir topla3(2, 3, 4)
AL

run_both "desteklenmeyen: dizgi" <<'AL'
yazdir "a" + "b"
AL

run_both "desteklenmeyen: dizi" <<'AL'
tanim l = [1, 2, 3]
yazdir l[1]
AL

run_both "bos dongu" <<'AL'
tanim i = 0
iken i < 0 { i = i + 1 }
yazdir i
AL

run_both "ic ice dongu" <<'AL'
tanim t = 0
tanim bir = 1
tanim i = 0
iken i < 20 {
  tanim j = 0
  iken j < 20 { t = t + bir  j = j + 1 }
  i = i + 1
}
yazdir t
AL

run_both "aritmetik: + - *" <<'AL'
tanim a = 7
tanim b = 3
yazdir a + b
yazdir a - b
yazdir a * b
yazdir a + b * b - a
AL

run_both "sabitli aritmetik (ADDK/SUBK)" <<'AL'
tanim a = 10
yazdir a + 5
yazdir a - 5
yazdir 1 + 2 + 3 + 4
AL

run_both "karsilastirmalar (bool)" <<'AL'
tanim a = 3
tanim b = 9
yazdir a < b
yazdir a > b
yazdir a <= b
yazdir a >= b
yazdir dogru
yazdir yanlis
yazdir bos
AL

run_both "tum fused atlamalar" <<'AL'
tanim i = 0
iken i < 5 { yazdir i  i = i + 1 }
tanim j = 5
iken j > 0 { yazdir j  j = j - 1 }
tanim k = 0
iken k <= 3 { yazdir k  k = k + 1 }
AL

run_both "negatif ve sinir degerler" <<'AL'
tanim a = 0
tanim b = 1
yazdir a - b
yazdir 0 - 2147483647
tanim c = 2147483647
yazdir c
yazdir c - c
AL

run_both "carpim tasmasi" <<'AL'
yazdir 1
tanim a = 100000
tanim b = 100000
yazdir a * b
AL

run_both "kosullu (JZ/JNZ)" <<'AL'
tanim a = 5
eger dogru { yazdir 1 } yoksa { yazdir 2 }
eger yanlis { yazdir 3 } yoksa { yazdir 4 }
eger bos { yazdir 5 } yoksa { yazdir 6 }
eger a { yazdir 7 } yoksa { yazdir 8 }
tanim b = 0
eger b { yazdir 9 } yoksa { yazdir 10 }
AL

run_both "ve/veya kisa devre" <<'AL'
tanim a = 1
tanim b = 0
eger a < 2 ve b < 2 { yazdir 11 }
eger a > 9 veya b < 2 { yazdir 12 }
eger a > 9 ve b > 9 { yazdir 13 } yoksa { yazdir 14 }
AL

run_both "dongude kosullu cikis" <<'AL'
tanim i = 0
tanim t = 0
iken dogru {
  i = i + 1
  eger i > 5 { kir }
  t = t + i
}
yazdir t
yazdir i
AL

run_both "yerel degiskenler (blok kapsami)" <<'AL'
tanim g = 0
tanim i = 0
iken i < 6 {
  tanim y = i * 2
  tanim z = y + 1
  g = g + z
  i = i + 1
}
yazdir g
AL

run_both "esitlik (EQ/NE/JEQ/JNE)" <<'AL'
tanim a = 5
tanim b = 5
tanim c = 7
yazdir a == b
yazdir a == c
yazdir a != c
yazdir dogru == dogru
yazdir bos == bos
yazdir dogru == 1
eger a == b { yazdir 100 }
eger a != c { yazdir 200 }
AL

run_both "negatif ve degil" <<'AL'
tanim a = 42
yazdir -a
yazdir - -a
yazdir degil dogru
yazdir degil yanlis
yazdir degil bos
yazdir degil 0
AL

run_both "bit islemleri" <<'AL'
yazdir 12 & 10
yazdir 12 | 10
yazdir 12 ^ 10
yazdir ~5
yazdir ~0
yazdir 255 & ~15
tanim a = 0 - 1
yazdir a & 255
yazdir (a | 0) ^ a
AL

run_both "bolme ve kalan" <<'AL'
yazdir 17 / 5
yazdir 17 % 5
yazdir -17 / 5
yazdir -17 % 5
yazdir 100 / 10
AL

run_both "sifira bolme" <<'AL'
yazdir 1
tanim a = 10
tanim b = 0
yazdir a / b
AL

run_both "INT_MIN / -1" <<'AL'
yazdir 1
tanim a = 0 - 2147483647
tanim b = 0 - 1
yazdir a / b
AL

rm -f src/bench_embed.inc
./build.sh linux-x86_64 >/dev/null 2>&1
echo
[ $fail -eq 0 ] && echo "  TUM JIT TESTLERI GECTI" || echo "  JIT TEST HATASI"
exit $fail
