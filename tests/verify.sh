#!/usr/bin/env bash
# tests/verify.sh - optimizer sonrasi otomatik regression testleri
#
#   1. Normal derlemede dogrulama 0 hata vermeli (tum varyantlarda)
#   2. Kasitli bozulan metadata YAKALANMALI ve yurutme iptal edilmeli
#      (hic ateslenmeyen bir denetleyici test edilmemis demektir)
#   3. VCOPY varyantlari AYNI ciktiyi uretmeli
#      (bu deney "daha az bellek islemi = daha hizli" varsayimini
#       curuten olcumun kaynagi; korunmasi istendi)
set -u
cd "$(dirname "$0")/.."
fail=0
ok()   { echo "  GECTI $1"; }
bad()  { echo "  KALDI $1"; fail=1; }

echo "=== 1. dogrulama tum varyantlarda temiz mi ==="
for v in "-DOPT_ROTATE=0 -DOPT_PEEPHOLE=0 -DOPT_SUPER=0" \
         "-DOPT_ROTATE=1 -DOPT_PEEPHOLE=0 -DOPT_SUPER=0" \
         "-DOPT_ROTATE=1 -DOPT_PEEPHOLE=1 -DOPT_SUPER=0" \
         "-DOPT_ROTATE=1 -DOPT_PEEPHOLE=1 -DOPT_SUPER=1"; do
  for arch in x86_64 i386; do
    EXTRA_CFLAGS="$v" ./build.sh "linux-$arch" >/dev/null 2>&1
    n=$(timeout 30 "./build/linux-$arch" < /dev/null 2>&1 | sed -n 's/^dogrula *: *//p')
    if [ "$n" = "0" ]; then ok "$arch [$v]"; else bad "$arch [$v] -> dogrula=$n"; fi
  done
done

echo "=== 2. kasitli bozma yakalaniyor mu ==="
for arch in x86_64 i386; do
  EXTRA_CFLAGS="-DTEST_CORRUPT=1" ./build.sh "linux-$arch" >/dev/null 2>&1
  out=$(timeout 30 "./build/linux-$arch" < /dev/null 2>&1)
  rc=$?
  # rc=1 BEKLENIYOR: dogrulama hatasi artik cikis koduna yansiyor
  if echo "$out" | grep -q "fonksiyon girisi kod disinda" \
     && echo "$out" | grep -q "yurutme iptal" && [ $rc -eq 1 ]; then
    ok "$arch bozuk metadata yakalandi, cokme yok"
  else
    bad "$arch bozuk metadata YAKALANMADI (rc=$rc)"
  fi
done

echo "=== 3. VCOPY varyantlari ayni ciktiyi uretiyor mu ==="
EXTRA_CFLAGS="-DOPT_VCOPY64=0" OUT_BIN=build/vc0 ./build.sh linux-x86_64 >/dev/null 2>&1
EXTRA_CFLAGS="-DOPT_VCOPY64=1" OUT_BIN=build/vc1 ./build.sh linux-x86_64 >/dev/null 2>&1
if [ -x build/vc0 ] && [ -x build/vc1 ]; then
  if timeout 30 ./build/vc0 < /dev/null 2>&1 | diff -q - <(timeout 30 ./build/vc1 < /dev/null 2>&1) >/dev/null; then
    ok "VCOPY 2x4bayt == VCOPY movq (davranis)"
  else
    bad "VCOPY varyantlari FARKLI cikti uretiyor"
  fi
else
  bad "VCOPY varyantlari derlenemedi"
fi

echo "=== 4. superkomutlar dizgi anlamini bozmuyor mu ==="
# ADD_SETG "s = s + s" icin op_add'in yerini aliyor; ilk surumu
# yalniz tamsayi destekliyordu ve dizgi birlestirmeyi bozuyordu.
cat > /tmp/strcat.al <<'AL'
tanim s = "ab"
s = s + s
yazdir s
fonk f() { tanim l = "p"  l = l + "q"  dondur l }
yazdir f()
AL
python3 bench/gen_embed.py /tmp/strcat.al > src/bench_embed.inc
for arch in x86_64 i386; do
  EXTRA_CFLAGS="-DBENCH_SRC=1" ./build.sh "linux-$arch" >/dev/null 2>&1
  got=$(timeout 20 "./build/linux-$arch" < /dev/null 2>&1 | sed -n '/cikti/,/ozet/p' | grep -v -- '---' | tr -d '\n ')
  if [ "$got" = "ababpq" ]; then ok "$arch dizgi birlestirme (s = s + s)"
  else bad "$arch dizgi birlestirme -> '$got'"; fi
done
# ACCG de op_add'in yerini aliyor: uc dalinin da tasindigini dogrula
cat > /tmp/accg.al <<'AL'
tanim s = "ab"
tanim u = "cd"
s = s + u
yazdir s
tanim t = 0
tanim b = 3
tanim i = 0
iken i < 4 { t = t + b  i = i + 1 }
yazdir t
AL
python3 bench/gen_embed.py /tmp/accg.al > src/bench_embed.inc
for arch in x86_64 i386; do
  EXTRA_CFLAGS="-DBENCH_SRC=1" ./build.sh "linux-$arch" >/dev/null 2>&1
  got=$(timeout 20 "./build/linux-$arch" < /dev/null 2>&1 | sed -n '/cikti/,/ozet/p' | grep -v -- '---' | tr -d '\n ')
  if [ "$got" = "abcd12" ]; then ok "$arch ACCG (dizgi + tamsayi)"
  else bad "$arch ACCG -> '$got'"; fi
done
rm -f src/bench_embed.inc
rm -f src/bench_embed.inc

echo "=== 4b. bayt tamponu (O_BUF) ==="
cat > /tmp/buftest.al <<'AL'
tanim b = tampon(4)
b[0] = 72
b[1] = 105
yazdir uzunluk(b)
yazdir b[0]
yazdir b[1]
tanim c = tampon(4)
c[0] = 72
c[1] = 105
yazdir b == c
yazikl("/tmp/_bt.dat", b)
tanim d = ikili("/tmp/_bt.dat")
yazdir uzunluk(d)
yazdir b == d
AL
python3 bench/gen_embed.py /tmp/buftest.al > src/bench_embed.inc
for arch in x86_64 i386; do
  EXTRA_CFLAGS="-DBENCH_SRC=1" ./build.sh "linux-$arch" >/dev/null 2>&1
  got=$(timeout 20 "./build/linux-$arch" < /dev/null 2>&1 | sed -n '/cikti/,/ozet/p' | grep -av -- '---' | tr -d '\n ')
  if [ "$got" = "472105dogru4dogru" ]; then ok "$arch O_BUF (indeks + esitlik + ikili dosya)"
  else bad "$arch O_BUF -> '$got'"; fi
done
rm -f src/bench_embed.inc /tmp/_bt.dat

echo "=== 4a. her (for) dongusu ==="
cat > /tmp/fortest.al <<'AL'
her (tanim i = 0; i < 3; i = i + 1) { yazdir i }
tanim t = 0
her (tanim j = 1; j <= 5; j += 1) { t += j }
yazdir t
her (tanim k = 0; k < 6; k = k + 1) {
  eger k == 2 { devam }
  eger k == 4 { kir }
  yazdir k
}
tanim m = 0
her (;;) { m = m + 1  eger m > 2 { kir } }
yazdir m
AL
python3 bench/gen_embed.py /tmp/fortest.al > src/bench_embed.inc
for arch in x86_64 i386; do
  EXTRA_CFLAGS="-DBENCH_SRC=1" ./build.sh "linux-$arch" >/dev/null 2>&1
  got=$(timeout 20 "./build/linux-$arch" < /dev/null 2>&1 | sed -n '/cikti/,/ozet/p' | grep -av -- '---' | tr -d '\n ')
  if [ "$got" = "012150133" ]; then ok "$arch her(for): devam adima gidiyor"
  else bad "$arch her(for) -> '$got'"; fi
done

echo "=== 4a2. bilesik atama ve yeni govde fonksiyonlari ==="
cat > /tmp/nattest.al <<'AL'
tanim a = 10
a += 5  a -= 3  a *= 4  a /= 6  a %= 5
yazdir a
yazdir mutlak(0 - 42)
yazdir en(3, 9)
yazdir buy(3, 9)
yazdir us(2, 10)
yazdir tur("ab")
yazdir cikar([1, 2, 3])
yazdir ters([1, 2, 3])
yazdir icerir([1, 2], 2)
yazdir parca("merhaba dunya", 8, 5)
yazdir bul("merhaba dunya", "dunya")
yazdir buyuk("aBc")
yazdir kucuk("AbC")
AL
python3 bench/gen_embed.py /tmp/nattest.al > src/bench_embed.inc
for arch in x86_64 i386; do
  EXTRA_CFLAGS="-DBENCH_SRC=1" ./build.sh "linux-$arch" >/dev/null 2>&1
  got=$(timeout 20 "./build/linux-$arch" < /dev/null 2>&1 | sed -n '/cikti/,/ozet/p' | grep -av -- '---' | tr -d '\n ')
  exp='342391024dizgi3[3,2,1]dogrudunya8ABCabc'
  if [ "$got" = "$exp" ]; then ok "$arch bilesik atama + 13 govde fonksiyonu"
  else bad "$arch -> '$got'"; fi
done
rm -f src/bench_embed.inc
./build.sh linux-x86_64 >/dev/null 2>&1

echo "=== 4a8. bit islemleri ==="
cat > /tmp/bittest.al <<'AL'
yazdir 12 & 10
yazdir 12 | 10
yazdir 12 ^ 10
yazdir ~0
yazdir ~5
yazdir 1 << 4
yazdir 256 >> 4
yazdir 0 - 16 >> 2
yazdir 255 & ~15
yazdir (1 << 8) | (1 << 4) | 1
yazdir (3 & 1) == 1
yazdir 1 << 100
AL
python3 bench/gen_embed.py /tmp/bittest.al > src/bench_embed.inc
exp='8146-1-61616-4240273dogrucalismahatasi:kaydirmasayisisinirdisinda'
for arch in x86_64 i386; do
  EXTRA_CFLAGS="-DBENCH_SRC=1" ./build.sh "linux-$arch" >/dev/null 2>&1
  got=$(timeout 20 "./build/linux-$arch" < /dev/null 2>&1 | sed -n '/cikti/,/ozet/p' | grep -av -- '---' | tr -d '\n ')
  if [ "$got" = "$exp" ]; then ok "$arch bit islemleri (& | ^ ~ << >>) + oncelik + sinir"
  else bad "$arch bit islemleri -> '$got'"; fi
done
rm -f src/bench_embed.inc
./build.sh linux-x86_64 >/dev/null 2>&1

echo "=== 4a7. C / C++ islevlerini adla cagirma ==="
cat > /tmp/ctest.al <<'AL'
yazdir cbul("topla") != bos
yazdir c("topla", 20, 22)
yazdir c("kare", 7)
tanim adr = cbul("kare")
yazdir cagir(adr, 9)
yazdir hex(c("cpu_adi"))
yazdir cbul("yokboyle")
yazdir c("yokboyle", 1)
AL
python3 bench/gen_embed.py /tmp/ctest.al > src/bench_embed.inc
for arch in x86_64 i386; do
  USER_SRC="ornekler/c_ornek.c" \
    EXTRA_CFLAGS="-DBENCH_SRC=1 -DUSER_SYMS=1" ./build.sh "linux-$arch" >/dev/null 2>&1
  got=$(timeout 20 "./build/linux-$arch" < /dev/null 2>&1 | sed -n '/cikti/,/ozet/p' | grep -av -- '---' | tr -d '\n ')
  # cpu_adi uretici imzasi: makineye gore degisir, varligini denetliyoruz
  case "$got" in
    dogru4249*81*bosbos) ok "$arch C islevi adla cagriliyor (statik baglama)" ;;
    *) bad "$arch C cagrisi -> '$got'" ;;
  esac
done
# C kodu BAGLANMAZSA temiz bos donmeli, cokmemeli
python3 bench/gen_embed.py /tmp/ctest.al > src/bench_embed.inc
EXTRA_CFLAGS="-DBENCH_SRC=1" ./build.sh linux-x86_64 >/dev/null 2>&1
got=$(timeout 20 ./build/linux-x86_64 < /dev/null 2>&1 | sed -n '/cikti/,/ozet/p' | grep -av -- '---' | tr -d '\n ')
[ "$got" = "yanlisbosbosbosbosbosbos" ] && ok "C kodu yokken temiz bos (cokme yok)" \
  || bad "C kodu yokken -> '$got'"
rm -f src/bench_embed.inc
./build.sh linux-x86_64 >/dev/null 2>&1

echo "=== 4a6. isletim sistemi primitifleri ==="
cat > /tmp/ostest.al <<'AL'
tanim c = cpuid(0)
yazdir uzunluk(c)
yazdir c[0] > 0
tanim t = tampon(16)
tanim a = adres(t)
yazdir bellek_yaz(a, 4660, 2)
yazdir bellek_oku(a, 2)
yazdir bellek_yaz(a, 305419896, 4)
yazdir hex(bellek_oku(a, 4))
yazdir bellek_oku(a, 1)
yazdir bellek_oku(a, 3)    // 24 bit: cerceve tamponu icin
yazdir bellek_oku(a, 7)    // gecersiz genislik -> bos
yazdir port_oku(96, 1)
AL
python3 bench/gen_embed.py /tmp/ostest.al > src/bench_embed.inc
exp='4dogrudogru4660dogru123456781203430008bosbos'
for arch in x86_64 i386; do
  EXTRA_CFLAGS="-DBENCH_SRC=1" ./build.sh "linux-$arch" >/dev/null 2>&1
  got=$(timeout 20 "./build/linux-$arch" < /dev/null 2>&1 | sed -n '/cikti/,/ozet/p' | grep -av -- '---' | tr -d '\n ')
  if [ "$got" = "$exp" ]; then ok "$arch cpuid + MMIO + port kapali (barindirilan)"
  else bad "$arch OS primitifleri -> '$got'"; fi
done
rm -f src/bench_embed.inc
./build.sh linux-x86_64 >/dev/null 2>&1

# Port G/C AYRICALIKLI: yalniz bare-metal imajda uretilmeli.
for t in bare-x86_64 bare-i386; do
  ./build.sh "$t" >/dev/null 2>&1
  n=$(nm -a "build/$t" 2>/dev/null | grep -c "port_in")
  if [ "$n" -ge 1 ]; then ok "$t port G/C var (ayricalikli, dogru yer)"
  else bad "$t port G/C uretilmemis"; fi
done
for t in linux-x86_64 linux-i386; do
  ./build.sh "$t" >/dev/null 2>&1
  n=$(nm -a "build/$t" 2>/dev/null | grep -c "port_in")
  if [ "$n" = "0" ]; then ok "$t port G/C YOK (barindirilan sistemde yapilamaz)"
  else bad "$t barindirilan yapida port G/C var"; fi
done

echo "=== 4a5. taban donusumu ve dizi/dizgi ==="
cat > /tmp/convtest.al <<'AL'
yazdir hex(255)
yazdir bin(10)
yazdir taban(255, 8)
yazdir hex(0 - 255)
yazdir hex(0)
yazdir tabandan("ff", 16)
yazdir tabandan("1010", 2)
yazdir tabandan("-ff", 16)
yazdir tabandan("xyz", 16)
yazdir birlestir(["a","b","c"], "-")
yazdir birlestir([1,2,3], ",")
yazdir bol("a-b-c", "-")
yazdir bol("abc", "")
yazdir dilim([1,2,3,4,5], 1, 3)
yazdir dilim("merhaba", 2, 3)
yazdir sirala([3,1,2])
yazdir yazi(42)
yazdir sayi("42")
AL
python3 bench/gen_embed.py /tmp/convtest.al > src/bench_embed.inc
exp='ff1010377-ff025510-255bosa-b-c1,2,3[a,b,c][a,b,c][2,3,4]rha[1,2,3]4242'
for arch in x86_64 i386; do
  EXTRA_CFLAGS="-DBENCH_SRC=1" ./build.sh "linux-$arch" >/dev/null 2>&1
  got=$(timeout 20 "./build/linux-$arch" < /dev/null 2>&1 | sed -n '/cikti/,/ozet/p' | grep -av -- '---' | tr -d '\n ')
  if [ "$got" = "$exp" ]; then ok "$arch taban donusumu + dizi/dizgi (18 durum)"
  else bad "$arch -> '$got'"; fi
done
rm -f src/bench_embed.inc
./build.sh linux-x86_64 >/dev/null 2>&1

echo "=== 4a4. golgeleme + 64-bit sinir denetimi ==="
cat > /tmp/shtest.al <<'AL'
tanim buyuk = 5
yazdir buyuk
yazdir buyuk + 1
tanim en = 7
yazdir en
yazdir kucuk("AB")
AL
python3 bench/gen_embed.py /tmp/shtest.al > src/bench_embed.inc
for arch in x86_64 i386; do
  EXTRA_CFLAGS="-DBENCH_SRC=1" ./build.sh "linux-$arch" >/dev/null 2>&1
  got=$(timeout 20 "./build/linux-$arch" < /dev/null 2>&1 | sed -n '/cikti/,/ozet/p' | grep -av -- '---' | tr -d '\n ')
  if [ "$got" = "567ab" ]; then ok "$arch kullanici tanimi gomulu adi golgeliyor"
  else bad "$arch golgeleme -> '$got'"; fi
done

# 64-bit degerler indeks/boyut bekleyen yerlere verilince COKMEMELI
cat > /tmp/bigtest.al <<'AL'
tanim n = 4611686018427387903
tanim l = [1, 2, 3]
tanim b = tampon(8)
yazdir tampon(n) == bos
yazdir parca("merhaba", n, 3) == bos
yazdir us(2, n) == bos
yazdir arg(n) == bos
AL
python3 bench/gen_embed.py /tmp/bigtest.al > src/bench_embed.inc
for arch in x86_64 i386; do
  EXTRA_CFLAGS="-DBENCH_SRC=1" ./build.sh "linux-$arch" >/dev/null 2>&1
  out=$(timeout 20 "./build/linux-$arch" < /dev/null 2>&1); rc=$?
  if [ $rc -lt 128 ] && ! echo "$out" | grep -q "GUARD BOZULDU"; then
    ok "$arch buyuk deger indeks/boyut yerlerinde cokme yok (rc=$rc)"
  else bad "$arch buyuk deger -> rc=$rc"; fi
done
rm -f src/bench_embed.inc
./build.sh linux-x86_64 >/dev/null 2>&1

echo "=== 4a3. dizgi sorgulari + FFI ham cagri ==="
cat > /tmp/sxtest.al <<'AL'
yazdir bul("merhaba dunya", "dunya")
yazdir bul([10, 20, 30], 20)
yazdir bul([10, 20, 30], 99)
yazdir baslar("merhaba", "mer")
yazdir biter("merhaba", "aba")
yazdir baslar("ab", "abcd")
AL
python3 bench/gen_embed.py /tmp/sxtest.al > src/bench_embed.inc
for arch in x86_64 i386; do
  EXTRA_CFLAGS="-DBENCH_SRC=1" ./build.sh "linux-$arch" >/dev/null 2>&1
  got=$(timeout 20 "./build/linux-$arch" < /dev/null 2>&1 | sed -n '/cikti/,/ozet/p' | grep -av -- '---' | tr -d '\n ')
  if [ "$got" = "81-1dogrudogruyanlis" ]; then ok "$arch bul/baslar/biter"
  else bad "$arch -> '$got'"; fi
done

# FFI: dilin ICINDEN makine kodu uretip cagirmak.
# "mov eax, 42 ; ret" iki mimaride de ayni kodlama.
cat > /tmp/ffitest.al <<'AL'
tanim k = tampon(6)
k[0] = 184  k[1] = 42  k[2] = 0  k[3] = 0  k[4] = 0  k[5] = 195
tanim adr = makinekod(k)
eger adr == bos { yazdir "WX" } yoksa { yazdir cagir(adr) }
AL
python3 bench/gen_embed.py /tmp/ffitest.al > src/bench_embed.inc
for arch in x86_64 i386; do
  EXTRA_CFLAGS="-DBENCH_SRC=1" ./build.sh "linux-$arch" >/dev/null 2>&1
  got=$(timeout 20 "./build/linux-$arch" < /dev/null 2>&1 | sed -n '/cikti/,/ozet/p' | grep -av -- '---' | tr -d '\n ')
  if [ "$got" = "42" ]; then ok "$arch FFI: uretilen makine kodu cagrildi"
  elif [ "$got" = "WX" ]; then ok "$arch FFI: W^X engeli temiz raporlandi"
  else bad "$arch FFI -> '$got'"; fi
done
rm -f src/bench_embed.inc
./build.sh linux-x86_64 >/dev/null 2>&1

echo "=== 4b2. dizgi <-> tampon donusumu + NX yigin ==="
cat > /tmp/tbtest.al <<'AL'
tanim s = "Merhaba"
tanim b = tampona(s)
yazdir uzunluk(b)
yazdir metin(b) == s
b[0] = 109
yazdir metin(b)
yazdir s
AL
python3 bench/gen_embed.py /tmp/tbtest.al > src/bench_embed.inc
for arch in x86_64 i386; do
  EXTRA_CFLAGS="-DBENCH_SRC=1" ./build.sh "linux-$arch" >/dev/null 2>&1
  got=$(timeout 20 "./build/linux-$arch" < /dev/null 2>&1 | sed -n '/cikti/,/ozet/p' | grep -av -- '---' | tr -d '\n ')
  # tampon KOPYA olmali: b degisince s degismemeli
  if [ "$got" = "7dogrumerhabaMerhaba" ]; then ok "$arch tampona() kopya semantigi"
  else bad "$arch tampona() -> '$got'"; fi
done
rm -f src/bench_embed.inc
./build.sh linux-x86_64 >/dev/null 2>&1
for arch in x86_64 i386; do
  ./build.sh "linux-$arch" >/dev/null 2>&1
  gs=$(readelf -lW "build/linux-$arch" 2>/dev/null | grep GNU_STACK)
  if echo "$gs" | grep -q 'RW '; then ok "$arch calistirilamaz yigin (NX)"
  elif [ -z "$gs" ]; then bad "$arch GNU_STACK basligi YOK (yigin calistirilabilir sayilir)"
  else bad "$arch yigin izinleri: $gs"; fi
done

echo "=== 4b3. komut satiri ayristiricisi (Windows mantigi) ==="
# Windows'ta calistiramiyoruz; ayristirici mantigini burada dogruluyoruz.
for arch in x86_64 i386; do
  EXTRA_CFLAGS="-DTEST_CMDLINE=1" ./build.sh "linux-$arch" >/dev/null 2>&1
  got=$(timeout 20 "./build/linux-$arch" < /dev/null 2>&1 | sed -n '/cmdline argc=/,/^== asmlang/p' | grep -a '^\[\|argc=' | tr -d '\n')
  exp='cmdline argc=6[prog.exe][bir][iki uc][dort][][bes]'
  if [ "$got" = "$exp" ]; then ok "$arch cmdline ayristirici (tirnak, bos, coklu bosluk)"
  else bad "$arch cmdline -> '$got'"; fi
done
./build.sh linux-x86_64 >/dev/null 2>&1

echo "=== 4c0. JIT kodlayici ve etiket katmani oz testi ==="
# Katman 1 (kodlayici) ve Katman 2 (etiketler) kendilerini sinar.
# Bozulurlarsa DERLEME degil ILK KOSU yakalar.
for arch in x86_64; do
  EXTRA_CFLAGS="-DTEST_JITASM=1" ./build.sh "linux-$arch" >/dev/null 2>&1
  out=$(timeout 20 "./build/linux-$arch" < /dev/null 2>&1)
  a=$(echo "$out" | grep -ac "jitasm oz test: GECTI")
  b=$(echo "$out" | grep -ac "jitlbl oz test: GECTI")
  if [ "$a" = "1" ] && [ "$b" = "1" ]; then ok "$arch jitasm + jitlbl oz testi"
  else bad "$arch oz test: $(echo "$out"|grep -a 'oz test'|tr '\n' ' ')"; fi
done
./build.sh linux-x86_64 >/dev/null 2>&1

echo "=== 4c. JIT mekanizmasi (calisma zamani kod uretimi) ==="
# Calistirilabilir bellek ayir, makine kodu yaz, CAGIR.
# W^X engeli varsa temiz sekilde raporlanmali, cokmemeli.
for arch in x86_64 i386; do
  EXTRA_CFLAGS="-DTEST_JIT=1" ./build.sh "linux-$arch" >/dev/null 2>&1
  out=$(timeout 20 "./build/linux-$arch" < /dev/null 2>&1); rc=$?
  if echo "$out" | grep -q "uretilen kod dondurdu -> 1234"; then
    ok "$arch uretilen kod calisti (1234)"
  elif echo "$out" | grep -q "calistirilabilir bellek alinamadi"; then
    ok "$arch W^X engeli temiz raporlandi"
  else bad "$arch JIT mekanizmasi (rc=$rc)"; fi
done

echo "=== 5. yonlendirme (control-flow hijack) savunmalari ==="
# Saldirganin tasma ile elde edecegi seyi taklit eder: bozuk bytecode.
# Beklenen: her durumda TEMIZ hata, asla cokme ve asla kontrol devri.
for h in 1 2 3; do
  case $h in
   1) w="gecersiz islem kodu";;  2) w="atlama hedefi kod disinda";;
   3) w="tur uyusmazligi";; esac
  for arch in x86_64 i386; do
    EXTRA_CFLAGS="-DTEST_HIJACK=$h" ./build.sh "linux-$arch" >/dev/null 2>&1
    out=$(timeout 30 "./build/linux-$arch" < /dev/null 2>&1); rc=$?
    if [ $rc -eq 1 ] && echo "$out" | grep -q "$w" \
       && ! echo "$out" | grep -qE 'Segmentation|Bus error'; then
      ok "$arch hijack-$h engellendi ($w)"
    else bad "$arch hijack-$h -> rc=$rc"; fi
  done
done

echo "=== 6. sifir yer degistirme kaydi (static-pie / ASLR / cekirdek imaji) ==="
# Asama 2'den beri korunan degismez. Kanarya tablosu bir kez .rodata'ya
# mutlak adres koyup bunu kirmisti; artik test altinda.
SRCS="$(./build.sh kaynaklar) src/os/linux/os.S"
if gcc -m64 -nostdlib -ffreestanding -Isrc $SRCS -static-pie -Wl,-e,_start \
     -o build/pietest 2>/tmp/pie.err; then
  n=$(readelf -r build/pietest 2>/dev/null | grep -c R_X86_64)
  if [ "$n" = "0" ]; then
    if timeout 30 ./build/pietest < /dev/null >/dev/null 2>&1; then
      ok "static-pie: 0 reloc ve calisiyor"
    else bad "static-pie baglandi ama calismiyor"; fi
  else bad "static-pie: $n yer degistirme kaydi (0 olmali)"; fi
else
  bad "static-pie baglanamadi: $(head -1 /tmp/pie.err)"
fi
rm -f build/pietest

./build.sh linux-x86_64 >/dev/null 2>&1
./build.sh linux-i386 >/dev/null 2>&1
echo
[ $fail -eq 0 ] && echo "TUM REGRESSION TESTLERI GECTI" || echo "REGRESSION HATASI"
exit $fail
