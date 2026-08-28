#!/usr/bin/env bash
# tests/limits.sh - kaynak sinirlarinin GUVENLI basarisiz oldugunu dogrular
#
# "Tampon sinirlari guvenli mi?" sorusuna iddia degil OLCUM ile cevap.
# Her durumda beklenen: sifir olmayan cikis kodu + acik hata iletisi,
# asla sessiz bozulma ya da cokme.
set -u
cd "$(dirname "$0")/.."
fail=0
gen() { python3 -c "$1" > /tmp/lim.al; }
chk() { # $1=ad $2=beklenen ileti parcasi
  python3 bench/gen_embed.py /tmp/lim.al > src/bench_embed.inc 2>/dev/null
  EXTRA_CFLAGS="-DBENCH_SRC=1" ./build.sh linux-x86_64 >/dev/null 2>&1
  out=$(timeout 30 ./build/linux-x86_64 < /dev/null 2>&1); rc=$?
  if [ $rc -ge 128 ] || [ $rc -eq 124 ]; then
    echo "  KALDI $1 -> cokme/askida (rc=$rc)"; fail=1; return; fi
  if [ $rc -ne 1 ]; then echo "  KALDI $1 -> beklenen cikis kodu 1, alinan $rc"; fail=1; return; fi
  if ! echo "$out" | grep -q "$2"; then
    echo "  KALDI $1 -> beklenen ileti yok: $2"; fail=1; return; fi
  echo "  GECTI $1 (rc=$rc)"
}

gen "print('yazdir uzunluk(\"' + 'a'*8000 + '\")')"
chk "uzun dizgi degismezi"  "yurutme iptal"

gen "
L=['tanim i=0','iken i<3 {','  i = i + 1']
for k in range(200): L.append('  eger i == %d { kir }' % k)
L += ['}','yazdir i']
print('\n'.join(L))"
chk "cok fazla kir"          "cok fazla kir"

gen "
L=['tanim c=0']
for k in range(40): L.append('iken c < 0 {')
L.append('c = c + 1')
for k in range(40): L.append('}')
print('\n'.join(L))"
chk "cok derin ic ice dongu" "dongu ic ice"

gen "
L=[]
for k in range(300): L.append('tanim v%d = %d' % (k,k))
print('\n'.join(L))"
chk "cok fazla kuresel"      "cok fazla kuresel"

gen "print('yazdir ' + '('*3000 + '1' + ')'*3000)"
chk "asiri ic ice parantez"  "yurutme iptal"

gen "
L=['tanim t = 0']
for i in range(2000): L.append('t = t + %d' % (i+1))
print('\n'.join(L))"
chk "token dizisi tasmasi"   "yurutme iptal"

gen "print('fonk f(n) { eger n <= 0 { dondur 0 } dondur 1 + f(n - 1) }\nyazdir f(5000)')"
chk "cagri derinligi"        "cagri derinligi asildi"

# Tasma siniri artik KELIME genisliginde: 64-bit hedefte 2^63,
# 32-bit hedefte 2^31. Test iki durumda da tasan bir ifade uretmeli.
gen "
import struct
half = (1 << 30)
print('tanim a = %d' % half)
print('tanim b = 0')
print('tanim i = 0')
print('iken i < 64 { b = a + a  a = b  i = i + 1 }')
print('yazdir a')"
chk "tamsayi tasmasi"        "tamsayi tasmasi"

rm -f src/bench_embed.inc
./build.sh linux-x86_64 >/dev/null 2>&1
./build.sh linux-i386 >/dev/null 2>&1
echo
[ $fail -eq 0 ] && echo "TUM SINIR TESTLERI GECTI" || echo "SINIR TESTI HATASI"
exit $fail
