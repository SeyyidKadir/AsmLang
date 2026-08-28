# Katkı

## Değişiklik yapmadan önce

```bash
./build.sh linux-x86_64 && tests/run.sh
```

## Değişiklikten sonra — hepsi geçmeli

```bash
tests/run.sh  tests/verify.sh  tests/limits.sh  tests/jit.sh
tests/bc.sh   tests/bare.sh    tests/lint.sh    tests/check_expand.sh
python3 tests/fuzz.py --n 15
tests/qemu.sh          # qemu varsa
```

## Bu projede tekrar eden hata sınıfları

Yeni kod yazarken bunlara dikkat edin; hepsi en az bir kez yaşandı.

**1. i386'da `RV == A0 == %eax`.** Bir çağrının dönüş değerini
kullanmadan `A0`'a yazarsanız kaybedersiniz. Yedi kez oldu.
`tests/lint.py` yakalıyor ama emin olmak için önce slota dökün.

**2. Yardımcı işlev çağıranın çerçeve slotunu göremez.** `FILL(A0, 3)`
*kendi* çerçevenizi okur. Değerleri argüman olarak geçirin.

**3. `ENTER(n)` kadar slot vardır.** `ENTER(6)` ile slot 6 kullanmak
çerçeve dışına yazar.

**4. Tablo adı uzunluğunu elle saymayın.** `NT(...)` ve `CSYM(...)`
kayıtlarında uzunluk yanlışsa ad **hiç çözülmez** ve sebebi belli
olmaz. Lint denetliyor.

**5. Yeni kaydı nöbetçiden ÖNCE ekleyin.** Tarama nöbetçide durur.

**6. Numara iki yerde tutuluyor.** `tokens.inc` / `ast.inc` ile
`tools/gen_tables.py` ayrışırsa her şey sessizce bozulur.

**7. `str.replace` çapası eşleşmezse sessizce hiçbir şey yapmaz.**
Her yamadan sonra `grep` ile doğrulayın.

**8. GC nesneleri taşır.** `str_new`/`arr_new` sonrası eski
işaretçiler geçersizdir; tutamaktan yeniden çözün.

## Yeni gövde fonksiyonu ekleme

1. `src/tables/natives.inc` — `NAT_*` indeksi + `NT(uzunluk, indeks, "ad")`
2. `src/vm/natives.S` — tabloya `.long SYM(nat_x) - SYM(nat_fns)`
3. Uygulama (`natives.S`, `natives2.S`, `natives3.S` ya da yeni dosya)
4. `NAT_COUNT`'u artırın
5. `python3 tests/lint.py` — uzunluk ve tablo boyutu denetlenir
6. `tests/verify.sh`'a test ekleyin

## Kural

Ölçülmeyen optimizasyon kabul edilmez. Bu projede iki "iyileştirme"
ölçülüp **geri alındı** (`VCOPY` %35 gerileme) ya da kazanç vermediği
için işaretlendi. `GELISTIRME.md` hepsini kaydediyor.

Ateşlediği kanıtlanmamış denetleyici de kabul edilmez: `lint.py` yedi
aşama boyunca hiçbir şey denetlemedi ve kimse fark etmedi.
