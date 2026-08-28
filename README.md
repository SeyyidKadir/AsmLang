# asmlang

Assembly ile yazılmış, Türkçe anahtar kelimeli bir programlama dili.
Sözcük çözümleyici, ayrıştırıcı, derleyici, sanal makine, çöp
toplayıcı ve JIT — hepsi elle yazılmış assembly. **Standart kütüphane
yok, libc yok, çalışma zamanı yok.**

Barındırılan bir sistemde normal bir program gibi çalışır; bare-metal
derlendiğinde kendi önyükleyicisiyle **diskten açılan bir çekirdeğe**
dönüşür: ekran, klavye, fare, disk, ses.

```
tanim toplam = 0
her (tanim i = 1; i <= 100; i += 1) {
    toplam += i
}
yazdir toplam                       // 5050

fonk fib(n) {
    eger n < 2 { dondur n }
    dondur fib(n - 1) + fib(n - 2)
}
yazdir fib(20)                      // 6765
```

---

## Bu proje bir telefondan yazıldı

Baştan sona bir telefondan, Claude ile konuşarak. Ne IDE, ne hata
ayıklayıcı, ne ikinci ekran. Tek araç sohbet penceresi.

**Ölçüler:**

| | |
|---|---|
| kaynak | 20.593 satır assembly + tablolar |
| bytecode komutu | 62 |
| gövde fonksiyonu | 65 (128 ad, Türkçe + İngilizce) |
| hedef | 16 (4 mimari × 4 platform) |
| test paketi | 11 |
| geliştirme günlüğü | `GELISTIRME.md`, 5.745 satır |

---

## Hızlı başlangıç

```bash
./build.sh linux-x86_64          # ya da: ./build.sh   (hepsi)
echo 'yazdir "merhaba"' > selam.al
./build/linux-x86_64 selam.al
```

Testler:

```bash
tests/run.sh        # altin cikti
tests/verify.sh     # 59 davranis testi, iki mimaride
tests/jit.sh        # JIT == yorumlayici, 33 program
tests/limits.sh     # sinir durumlari
tests/bc.sh         # bytecode dosyasi
tests/bare.sh       # bare-metal imaj denetimleri
tests/qemu.sh       # GERCEK emulatorde 24 denetim (qemu varsa)
tests/lint.py       # kaynak denetimi (kendini de sinar)
tests/fuzz.py       # bozuk girdi
```

---

# Dil Referansı

## Değişkenler

```
tanim x = 5          // degistirilebilir  (tanım / let)
sabit y = 10         // degistirilemez    (const)
x = 7                // atama
x += 3   x -= 1   x *= 2   x /= 2   x %= 3
```

Kapsam bloklardır. **Kullanıcı tanımı gömülü adı gölgeler** —
`tanim buyuk = 5` yazarsanız `buyuk()` gövde fonksiyonu değil sizin
değişkeniniz kazanır.

## Türler

| tür | örnek | not |
|---|---|---|
| tamsayı | `42`, `-7` | 64-bit (x86_64/aarch64), 32-bit (i386/ARM) |
| dizgi | `"merhaba"` | değişmez, `+` ile birleşir |
| mantıksal | `dogru`, `yanlis` | |
| boş | `bos` | |
| dizi | `[1, 2, 3]` | değiştirilebilir, `[]` ile indekslenir |
| tampon | `tampon(64)` | ham bayt, GC taramaz |
| fonksiyon | `fonk f() {}` | |

**Taşma sessizce sarmaz, hata verir.** Bu bilinçli: yanlış sonuç
üretmektense durmak daha iyi.

```
yazdir 2147483647 + 1       // x86_64: 2147483648
                            // i386  : calisma hatasi: tamsayi tasmasi
```

## Operatörler

Öncelik sırası (gevşekten sıkıya):

```
=  +=  -=  *=  /=  %=        atama
veya                          mantiksal veya (kisa devre)
ve                            mantiksal ve  (kisa devre)
|                             bit veya
^                             bit ozelveya
&                             bit ve
==  !=                        esitlik
<  <=  >  >=                  karsilastirma
<<  >>                        kaydirma (>> ARITMETIK)
+  -                          toplama
*  /  %                       carpma
degil  !  -  ~                tekli
()  []                        cagri, indeks
```

```
yazdir 255 & ~15             // 240
yazdir (1 << 8) | (1 << 4)   // 272
yazdir 0 - 16 >> 2           // -4   (isaret korunur)
yazdir 1 << 100              // calisma hatasi: kaydirma sinir disinda
```

## Denetim akışı

```
eger x > 5 {
    yazdir "buyuk"
} yoksa {
    yazdir "kucuk"
}

iken i < 10 { i += 1 }

her (tanim i = 0; i < 5; i += 1) { yazdir i }
her (; kosul; ) { ... }
her (;;) { ... kir }

kir       // dongudan cik
devam     // sonraki tura gec  (her'de ADIMA gider, kosula degil)
```

## Fonksiyonlar

```
fonk topla(a, b) {
    dondur a + b
}
yazdir topla(20, 22)         // 42
```

Özyineleme çalışır. **Kapanış (closure) yoktur** — fonksiyon
dışarıdaki *yerel* değişkene erişemez; denerseniz derleme hatası
alırsınız (sessizce sıfır okumaz):

```
eger dogru {
    tanim G = 1024
    fonk f() { dondur G }    // derleyici hatasi: kapanis yok
}
```

Küresel değişkenlere erişilebilir.

## Anahtar kelimeler

Her birinin Türkçe (ASCII + tam), ve İngilizce karşılığı var:

```
fonk / fn            tanim / tanım / let      sabit / const
eger / eğer / if     yoksa / else             iken / while
her / for            kir / kır / break        devam / continue
dondur / döndür / return                      yazdir / yazdır / print
dogru / doğru / true                          yanlis / yanlış / false
bos / boş / nil      ve / and                 veya / or
degil / değil / not
```

---

# Gövde Fonksiyonları

Her fonksiyonun Türkçe ve İngilizce adı vardır; ikisi de aynı işi
yapar. Hatalı çağrı **`bos`** döner — sessizce yanlış sonuç vermez.

## Genel

| ad | işlev |
|---|---|
| `uzunluk(x)` / `len` | dizgi, dizi, tampon uzunluğu |
| `tur(x)` / `type` | `"tamsayi"` `"dizgi"` `"dizi"` `"tampon"` `"mantiksal"` `"bos"` `"fonksiyon"` |
| `yazdir x` | değer + satır sonu (anahtar kelime) |
| `yaz(x)` / `wr` | satır sonu **koymaz** |
| `oku()` / `read` / `input` | bir satır oku |

## Sayı ve dizgi

| ad | işlev | örnek |
|---|---|---|
| `yazi(n)` / `str` | tamsayı → dizgi | `yazi(42)` → `"42"` |
| `sayi(s)` / `num` | dizgi → tamsayı | `sayi("42")` → `42`, çözülemezse `bos` |
| `hex(n)` / `onaltilik` | 16 tabanı | `hex(255)` → `"ff"` |
| `bin(n)` / `ikilik` | 2 tabanı | `bin(10)` → `"1010"` |
| `taban(n, b)` / `tobase` | 2..36 arası | `taban(255,8)` → `"377"` |
| `tabandan(s, b)` / `frombase` | ters çevirim | `tabandan("ff",16)` → `255` |
| `parca(s, bas, uz)` / `substr` | alt dizgi | `parca("merhaba",2,3)` → `"rha"` |
| `bul(x, aranan)` / `find` | indeks ya da `-1` | dizgide **ve dizide** |
| `baslar(s, ön)` / `startswith` | | `baslar("merhaba","mer")` → `dogru` |
| `biter(s, son)` / `endswith` | | |
| `buyuk(s)` / `upper` | ASCII büyütme | |
| `kucuk(s)` / `lower` | | |

## Dizi

| ad | işlev |
|---|---|
| `ekle(d, x)` / `push` | sona ekle |
| `cikar(d)` / `pop` | sondan al ve döndür |
| `ters(d)` / `reverse` | yerinde ters çevir |
| `icerir(d, x)` / `has` | var mı |
| `sirala(d)` / `sort` | yerinde sırala (tamsayı) |
| `dilim(x, bas, uz)` / `slice` | dizi **ve dizgi** dilimi |
| `birlestir(d, ayr)` / `join` | `birlestir([1,2,3],",")` → `"1,2,3"` |
| `bol(s, ayr)` / `split` | `bol("a-b","-")` → `[a, b]`; ayraç boşsa karakterlere |

## Matematik

`mutlak/abs`, `en/min`, `buy/max`, `us/pow` (üs ≤ 64, taşmada `bos`)

## Tampon ve dosya

| ad | işlev |
|---|---|
| `tampon(n)` / `buffer` | n baytlık ham tampon |
| `tampona(s)` / `tobuf` | dizgi → tampon (kopya) |
| `metin(t)` / `tostr` | tampon → dizgi |
| `dosya(yol)` / `readfile` | metin oku |
| `yazf(yol, s)` / `write` | metin yaz |
| `ikili(yol)` / `readbin` | ikili oku → tampon |
| `yazikl(yol, t)` / `writebin` | ikili yaz |
| `kaydet(yol)` / `save` | derlenmiş bytecode'u `.bc` olarak yaz |
| `argsay()` / `argc`, `arg(i)` / `argv` | komut satırı |

Tamponda `t[i]` bayt okur/yazar.

## Konsol

`temizle()`, `imlec(satır, sütun)`, `renk(n)` — ANSI kaçış dizileri.
İşletim sistemine özel çağrı yok; bare-metal'de de çalışır.

---

# İşletim Sistemi / Donanım

**Bu bölümdeki işlevler yalnız bare-metal derlemede etkindir.**
Barındırılan bir sistemde (Linux/Windows/macOS) hepsi temiz `bos`
döner — çökmez. Sebebi: port G/Ç ayrıcalıklı bir işlemdir,
kullanıcı programı yapamaz.

| ad | işlev |
|---|---|
| `acilis()` / `boot` | `[multiboot_var_mi, bayraklar]` |
| `ekran()` / `screen` | `[adres, genişlik, yükseklik, satır_bayt, bpp]` |
| `piksel(x, y, renk)` | 24 ve 32 bpp |
| `ekran_temizle(renk)` | tüm tamponu doldur |
| `vga(x, y, karakter, renk)` | 80×25 metin (0xB8000) |
| `ses(hz)` / `ses_kapat()` | PC hoparlörü (PIT kanal 2) |
| `disk_oku(lba, n, tampon)` | ATA PIO, yoklamalı |
| `tus_var()`, `tus()`, `tuskod()` | PS/2 klavye |
| `fare_kur()`, `fare_var()`, `fare()` | PS/2 fare → `[x, y, düğmeler]` |
| `port_oku(p, gen)`, `port_yaz(p, d, gen)` | ham port G/Ç (1/2/4 bayt) |
| `bellek_oku(a, gen)`, `bellek_yaz(a, d, gen)` | MMIO (1/2/3/4/8 bayt) |
| `cpuid(yaprak)` | `[eax, ebx, ecx, edx]` |

**Bellek erişimi doğrulanmaz.** Verilen adres geçerli olmak zorunda.
Bilinçli: amaç tam da doğrulanamayan adreslere erişmek.

## Örnek: grafik kipi, tamamen bu dilde

`ornekler/grafik.al` — PCI taraması, BGA kayıtları, piksel yazımı.
Yeni gövde fonksiyonu kullanılmadan:

```
fonk pci_oku(veri, aygit, islev, ofset) {
    tanim adr = 1 << 31
    adr = adr | (veri << 16) | (aygit << 11) | (islev << 8) | ofset
    port_yaz(3320, adr, 4)          // 0xCF8
    dondur port_oku(3324, 4)        // 0xCFC
}
```

---

# C / C++ Çağırma

`dlopen` yok (ikili statik + nostdlib), bu yüzden **statik bağlama**.
Her hedefte çalışır, bare-metal dahil.

**1.** C kodunuzu yazın:

```c
long topla(long a, long b) { return a + b; }
```

C++ ise `extern "C"` ile sarın, yoksa ad bozulur.

**2.** `src/tables/user_syms.inc` içinde tanıtın (nöbetçiden **önce**):

```
CSYM(5, topla, "topla")
     ^  ^      ^
     |  |      asmlang'de gorunen ad
     |  C sembolu
     adin harf sayisi
```

**3.** Derleyin ve kullanın:

```bash
USER_SRC="kod.c" EXTRA_CFLAGS="-DUSER_SYMS=1" ./build.sh linux-x86_64
```

```
yazdir c("topla", 20, 22)     // 42
tanim adr = cbul("topla")     // adresi al
yazdir cagir(adr, 20, 22)     // ham cagri
yazdir cbul("yokboyle")       // bos - cokmez
```

**Sınırlar:** argümanlar ve dönüş tamsayı; en fazla 6 argüman
(x86_64), i386/ARM'de 4; imza doğrulanmaz.

## Ham makine kodu

```
tanim k = tampon(6)
k[0]=184 k[1]=42 k[2]=0 k[3]=0 k[4]=0 k[5]=195   // mov eax,42 ; ret
tanim adr = makinekod(k)                          // calistirilabilir bellege
yazdir cagir(adr)                                 // 42
```

---

# Bare-metal / Çekirdek

## Kendi önyükleyicimizle diskten açılış

```bash
python3 bench/gen_embed.py ornekler/onay.al > src/bench_embed.inc
EXTRA_CFLAGS="-DBENCH_SRC=1" ./build.sh bare-i386
python3 tools/disk-yap.py build/bare-i386 disk.img
qemu-system-i386 -drive file=disk.img,format=raw,if=ide -serial stdio -nic none
```

`src/os/bare/boot.S` — 512 baytlık MBR önyükleyici. Gerçek modda
başlar, **VBE'yi orada kurar** (korumalı moddan `int 0x10`
çağrılamaz), korumalı moda geçip çekirdeğe multiboot yapısıyla verir.
**GRUB gerekmez.**

## QEMU `-kernel` ile

```bash
qemu-system-i386 -kernel build/bare-i386 -serial stdio -nic none
```

Bu yol daha hızlı ama **çerçeve tamponu yoktur**: QEMU'nun multiboot
yükleyicisi VBE'yi desteklemez. Grafik için disk imajını kullanın.

## Örnekler

| dosya | ne yapar |
|---|---|
| `ornekler/onay.al` | 12 başlıklı donanım tanılama raporu |
| `ornekler/grafik.al` | BGA ile grafik kipi, PCI taraması |
| `ornekler/klavye.al` | PS/2 klavye |
| `ornekler/fare.al` | PS/2 fare |
| `ornekler/imlec.al` | fare imleci — grafik + girdi birlikte |
| `ornekler/cekirdek.al` | küçük çekirdek örneği |

---

# Derleme Hedefleri

```
linux-x86_64    linux-i386     linux-aarch64    linux-arm
termux-aarch64  termux-arm     termux-x86_64
bare-x86_64     bare-i386      bare-aarch64     bare-arm
macos-x86_64    macos-aarch64
windows-x86_64  windows-i386   windows-aarch64
```

```bash
./build.sh                 # hepsi
./build.sh linux-x86_64    # tek hedef
./build.sh liste           # hedefleri listele
```

## Derleme anahtarları

| anahtar | varsayılan | ne yapar |
|---|---|---|
| `OPT_JIT` | 0 | x86_64 JIT (53 opcode) |
| `OPT_OVFCHK` | 1 | taşmada hata |
| `OPT_TYPECHK` | 1 | tür denetimleri |
| `MODE_PLAYER` | 0 | yalnız yürütücü (%42 küçük) |
| `BC_EMBED` | 0 | bytecode ikiliye gömülü |
| `MB_VIDEO` | 0 | multiboot video isteği (GRUB için) |
| `BARE_SIM` | 0 | bare kod yolunu emülatörsüz koştur |
| `USER_SYMS` | 0 | C sembol tablosu |

---

# İç Yapı

```
kaynak -> sozcuk -> ayristirici -> derleyici -> bytecode -> VM
                                                    |
                                                    +-> JIT (x86_64)
```

- **Değer yuvası**: `{u32 etiket, i64 yük}`, yük genişliği = makine
  kelimesi
- **Çöp toplayıcı**: işaretle-süpür, tutamak tablosu üzerinden
  (nesneler taşınabilir)
- **JIT**: üç katman — komut kodlayıcı, etiket/yama, derleyici.
  Kodlayıcı ve etiket katmanı **kendilerini test eder**
- **Süperkomutlar**: `ACCG`, `ADDK_SETG`, `GETG_CONST` gibi 12 füzyon
- **Kanarya**: 20 tampon, 4 kontrol noktası

## `.bc` bytecode dosyası

```
kaydet("prog.bc")                    // derle ve kaydet
./build/player prog.bc               // yalniz yurut (derleyici yok)
python3 tools/append_bc.py player prog.bc tek_dosya
```

Başlıkta sürüm, opcode sayısı, gövde fonksiyonu sayısı **ve kelime
genişliği** damgası var. Uyuşmazlık sessizce yanlış çalışmak yerine
temiz hata verir.

---

# Bilinen Sınırlar

Dürüst liste. Bunlar hata değil, kapsam kararı — ama bilmelisiniz.

| | |
|---|---|
| kapanış (closure) | **yok** — derleme hatası verir, sessizce yanlış çalışmaz |
| kayan nokta | yok |
| `.` alan erişimi, nesne | yok |
| JIT | yalnız x86_64; dizgi/dizi/gövde fonksiyonu içeren program yorumlayıcıya düşer |
| JIT register tahsisi | yok — C referansına göre ~2,5× yavaş |
| `bare-x86_64` açılışı | **çalışmaz** — multiboot 32-bit modda başlatır, imaj ELF64 |
| çerçeve tamponu (`-kernel`) | yok — QEMU multiboot VBE'yi desteklemiyor; disk imajı kullanın |
| 64-bit FFI adresi | 32-bit hedefte adres tamsayıya sığmaz |
| aynı anda açık dosya | 1 |
| kesme (IDT), sayfalama | yok — klavye/fare/disk yoklamalı |
| Türkçe klavye düzeni | yok, US düzeni |

## Gerçekten çalıştırılan hedefler

| hedef | durum |
|---|---|
| `linux-x86_64`, `linux-i386` | ✅ tam test, her koşuda |
| `bare-i386` | ✅ **gerçek QEMU'da** açılıyor, 23 denetim |
| `bare-x86_64` | ⚠️ derleniyor, `BARE_SIM` ile koşuyor, **açılmıyor** |
| diğer 12 hedef | ⚠️ makro genişletme doğrulandı, **derlenmedi** |

Son satır önemli: bu ortamda cross derleyici yoktu. macOS, Windows ve
ARM hedefleri için `build.sh` yalnızca önişlemciden geçirilip makro
kazası olmadığı kontrol edildi. **Çalışma doğrulaması yapılmadı.**

---

# Testler

```
run.sh          altin cikti karsilastirma (3 hedef)
verify.sh       59 davranis testi, iki mimaride
limits.sh       9 sinir durumu (hepsi temiz hata vermeli)
jit.sh          33 program: JIT == yorumlayici
bc.sh           bytecode gidis-donus, bozuk dosya (360 deneme)
bare.sh         bare imaj: 0 syscall, 0 reloc, multiboot, UART
qemu.sh         GERCEK emulatorde 24 denetim
lint.py         kaynak denetimi — KENDINI DE SINAR
fuzz.py         determinist bozuk girdi
check_expand.sh 16 hedefte makro genisletme
```

`tests/qemu.sh` gerçekten açar, ekran görüntüsü alır, pikselleri
sayar, klavye ve fare olayı gönderir:

```
GECTI imaj aciliyor
GECTI multiboot yukleyici algilandi
GECTI gercek 16550 UART calisiyor
GECTI port G/C ring 0'da calisiyor
GECTI ATA PIO disk okundu
GECTI grafik: 640x480x32 mod kuruldu, 7 piksel dogrulandi
GECTI kendi onyukleyicimiz: diskten acildi (GRUB yok)
GECTI ekran goruntusu: 1024x768, cizgiler dogru, ekran dolu
GECTI klavye: PS/2 tarama kodu -> ASCII, shift dahil
GECTI fare: imlec rapor edilen konumda cizili, eskisi silinmis
```

QEMU yoksa bu paket **atlanır**, başarısız sayılmaz.
`tools/qemu-indir.sh` paketleri indirir.

---

# "Yapay zekâ kod yazamaz" diyenlere

Bu bölüm bir övünme değil. Tam tersi: **hata kaydı.**

Bu projede yapılan hataların sınıflandırılmış listesi:

| hata sınıfı | kaç kez |
|---|---|
| i386'da `RV == A0` çakışması | **7** |
| süperkomut/JIT'in bir dalı taşımaması | 3 |
| yardımcı işlevin çağıranın çerçeve slotunu okuması | 3 |
| token/düğüm numarası çakışması | 3 |
| elle makine kodunda ofset ya da ters koşul | 3 |
| tablo adı uzunluğunun yanlış sayılması | 8 |
| sessiz tampon taşması (sınır denetimi yok) | 8 tablo |
| paylaşılan tampon ezilmesi | 2 |
| kendi "optimizasyonunun" gerileme çıkması | 1 (%35) |
| hiç çalışmayan denetleyici | 1 (7 aşama boyunca ölü) |

Ve yorumlayıcıda **9 aşama saklı kalmış** iki bölme hatası — JIT ile
diferansiyel test olmasa hâlâ orada olurdu.

**Asıl mesele bu:** hataların hiçbiri gözle bulunmadı. Hepsini
şunlar buldu — altın çıktı karşılaştırması, denklik testi, kanarya,
fuzzer, lint, disassembler, ve en sonunda gerçek emülatör.

Bir örnek: bare-metal imajın **kendi yığını ve öbeği hiçbir LOAD
segmentinde değildi.** Bare-metal'de RAM orada durduğu için
"çalışıyor" görünüyordu, ama yükleyici o bölgeyi ayırmıyordu. Bu
hata ancak imaj **gerçekten çalıştırılınca** görüldü; hiçbir statik
denetim yakalayamazdı.

Bir başkası: `lint.py` yedi aşama boyunca **hiçbir şey denetlemiyordu**
(`\b` mawk'ta backspace). Sonra çalışır hâle geldi, sonra da
*eksik* olduğu ortaya çıktı — `CMPR(RV, A0)` desenini "güvenli"
sayıyordu ve yedinci `RV/A0` çakışmasını kaçırdı.

Yani: **soru "yapay zekâ kod yazabilir mi" değil.** Yazabildiği
zaten görünüyor — 20.000 satır assembly, on bir test paketi, gerçek
donanımda açılan bir çekirdek. Asıl soru şu:

> Kim yazarsa yazsın, kodun doğru olduğunu nereden biliyorsunuz?

Bu projenin cevabı: **ölçüyoruz.** Her optimizasyon ölçüldü —
bazıları reddedildi (`VCOPY` %35 gerileme, blok içi tür elemesi
kazanç yok). Her denetleyicinin ateşlediği kasıtlı bozmayla
kanıtlandı. Her "çalışıyor" iddiası ya testle ya emülatörle
desteklendi, desteklenemeyenler **açıkça "doğrulanmadı" diye
yazıldı.**

`GELISTIRME.md` 5.745 satır ve her aşamanın hatalarını da içeriyor.
Kimse "hiç hata yapmadım" demiyor. Söylenen şu: **hatalar bulundu,
kaydedildi, ve bir daha aynı sınıfa düşmemek için denetleyici
yazıldı.**

Elinizdeki metin bir telefondan yazıldı. Beğenmezseniz, ölçün.

---

# Lisans

Ne yaparsanız yapın.
