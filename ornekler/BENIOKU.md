# Bare-metal örnekler

## Çekirdek imajı derleme ve çalıştırma

```bash
python3 bench/gen_embed.py ornekler/cekirdek.al > src/bench_embed.inc
EXTRA_CFLAGS="-DBENCH_SRC=1" ./build.sh bare-x86_64
qemu-system-x86_64 -kernel build/bare-x86_64 -serial stdio
```

İmaj **multiboot 1** başlığı taşır, yani `qemu -kernel` ve GRUB
doğrudan yükler. Başlıkta 1024×768×32 doğrusal çerçeve tamponu
isteniyor; yükleyici veremezse `ekran()` sıfır döner ve program
metin ekranına (VGA 0xB8000) düşer.

## Kullanılabilir donanım arayüzü

| işlev | ne yapar |
|---|---|
| `ekran()` | `[adres, genişlik, yükseklik, satır_bayt, bpp]` |
| `piksel(x, y, renk)` | 32 bpp tek piksel |
| `ekran_temizle(renk)` | tüm tamponu doldur |
| `vga(x, y, karakter, renk)` | 80×25 metin ekranı |
| `ses(frekans)` / `ses_kapat()` | PC hoparlörü (PIT kanal 2) |
| `disk_oku(lba, sektör, tampon)` | ATA PIO okuma |
| `port_oku/yaz(port, ..., genişlik)` | ham port G/Ç |
| `bellek_oku/yaz(adres, ..., genişlik)` | MMIO |
| `cpuid(yaprak)` | `[eax, ebx, ecx, edx]` |
| `makinekod(tampon)` / `cagir(adres, ...)` | ham makine kodu |

**Bunlar yalnız bare-metal derlemede etkindir.** Barındırılan bir
sistemde (Linux/Windows/macOS) hepsi temiz `boş` döner — çökmez.
Sebebi: port G/Ç ayrıcalıklı bir işlemdir, kullanıcı programı
yapamaz.

## Bootloader yazmak

Gereken parçalar hazır:

1. **Açılabilir imaj** — multiboot başlığı var
2. **Disk okuma** — `disk_oku(lba, n, tampon)`
3. **Koda atlama** — `makinekod(tampon)` + `cagir(adres)`

Yani `disk_oku` ile ikinci aşamayı belleğe alıp `cagir` ile ona
atlayan bir yükleyici bu dilde yazılabilir.

## DOĞRULANMADI

Bu ortamda `qemu-system-*` yok. İmaj derleniyor ve **statik olarak**
doğrulanıyor (multiboot başlığı geçerli, 0 syscall, 0 yer değiştirme,
gerçek `in`/`out` komutları üretilmiş) ama **hiç çalıştırılmadı**.
Gerçek donanım/emülatör doğrulaması sende.

---

# C / C++ İşlevlerini Çağırma

Ağır işi C'de yazıp asmlang'den çağırabilirsiniz. `dlopen` yok
(ikili statik + nostdlib, bare-metal'de kavram bile yok), bu yüzden
**statik bağlama** kullanılıyor — her hedefte çalışır.

## Üç adım

**1. C kodunuzu yazın** (`ornekler/c_ornek.c`):

```c
long topla(long a, long b) { return a + b; }
```

C++ ise `extern "C"` ile sarın, yoksa ad bozulur:

```cpp
extern "C" long topla(long a, long b) { return a + b; }
```

**2. `src/tables/user_syms.inc` içinde tanıtın:**

```
CSYM(5, topla, "topla")
     ^  ^      ^
     |  |      asmlang'de görünen ad
     |  C sembolü
     adın harf sayısı
```

Nöbetçiden **önce** ekleyin; sonrasına eklenen kayıt hiç görülmez.
`tests/lint.py` uzunluğu denetliyor.

**3. Derleyin ve kullanın:**

```bash
USER_SRC="ornekler/c_ornek.c" \
  EXTRA_CFLAGS="-DUSER_SYMS=1" ./build.sh linux-x86_64
```

```
yazdir c("topla", 20, 22)      // 42
tanim adr = cbul("kare")       // adresi al
yazdir cagir(adr, 9)           // ham cagri
yazdir cbul("yokboyle")        // bos (cokmez)
```

## Sınırlar

- Argümanlar ve dönüş **tamsayı**. Kayan nokta, yapı geçirme/döndürme yok.
- En fazla 6 argüman (x86_64 SysV); i386/ARM'de 4.
- Bare-metal'de C kodunuz **freestanding** olmalı: libc yok.
- İmza doğrulanmaz — yanlış imzalı çağrı çökme demektir.
- C kodu bağlanmazsa `cbul` ve `c` temiz `boş` döner, çökmez.

---

# QEMU'da Doğrulama

```bash
tools/qemu.sh                      # tanılama raporu
tools/qemu.sh ornekler/cekirdek.al # kendi programınız
```

`ornekler/onay.al` **dilin kendisinde yazılmış** bir doğrulama
raporudur. Seri porta 12 başlık basar. Raporun görünüyor olması
zaten sözcük çözümleyici + ayrıştırıcı + derleyici + sanal makine +
UART yolunun tamamının çalıştığının kanıtıdır.

Beklenen çıktı:

```
================================
  asmlang bare-metal onay
================================
1. multiboot yukleyici : VAR
   bayraklar           : ...
2. cerceve tamponu     : VAR 1024x768x32   (ya da YOK)
3. cpuid               : VAR  en buyuk yaprak=...  imza=756e6547
4. port G/C            : VAR  port 0x61 = ...
5. yigin ayirma        : TAMAM (4096 bayt)
6. cop toplama         : TAMAM (200 birlestirme)
7. tamsayi genisligi   : 32 bit          (bare-i386)
8. ozyineleme fib(20)  : TAMAM
9. VGA metin ekrani    : YAZILDI
10. grafik cizim       : CIZILDI  (ya da ATLANDI)
11. ATA PIO disk okuma : YOK ya da disk bagli degil
12. PC hoparloru       : CALDI
================================
```

Grafiği görmek için `-display none` bayrağını `tools/qemu.sh`'ten
kaldırın. Disk denemek için:

```bash
qemu-system-i386 -kernel build/bare-i386 -serial stdio \
  -drive file=disk.img,format=raw,if=ide
```

## bare-x86_64 AÇILAMAZ

Multiboot 1 çekirdeği **32-bit korumalı modda** başlatır.
`bare-x86_64` ELF64'tür ve doğrudan giremez — uzun mod geçiş kodu
(GDT, sayfa tabloları, `CR4.PAE`, `EFER.LME`, `CR0.PG`) yazılmadı.

**Açılabilir hedef: `bare-i386`.**

---

# QEMU'yu Bu Ortama Getirmek

Kapsayıcıda ağ kapalı (`apt` 403 veriyor). Paketleri siz indirip
yüklerseniz emülatör doğrulaması yapılabilir.

## 1. İndirin (Termux ya da herhangi bir yer)

```sh
sh tools/qemu-indir.sh
```

**bash, python, zip gerekmez** — yalnız `curl` ya da `wget`.
Termux'ta yoksa: `pkg install curl`

Paketler amd64 Linux için; Termux'ta yalnızca *indiriliyorlar*,
çalıştırılmıyorlar. Android'de olmanız sorun değil.

Sonunda **qemu-debs.tar.gz** oluşur (~16 MB). Tek dosya —
21 dosyayı tek tek yüklemenize gerek yok. Yarım kalırsa betiği
tekrar çalıştırın, inenler atlanır.

`qemu-debs/` klasörüne 21 `.deb` iner. Liste betiğin içinde gömülü ve **bu kapsayıcının kendi paket
verisinden** üretildi — sürümler birebir uyumlu.

Paket listesi betiğin **içinde gömülü** — başka dosya gerekmez.

## 2. Yükleyin

**qemu-debs.tar.gz** dosyasını sohbete yükleyin.

## 3. Kurulum (bu tarafta)

```bash
bash tools/qemu-kur.sh
export PATH=/home/claude/qemu/bin:$PATH
```

Kök dizine kurmaz; `/home/claude/qemu` altına açar ve sarmalayıcı
yazar. Kapsayıcının geri kalanına dokunulmaz.

## 4. Doğrulama

```bash
tools/qemu.sh                       # 12 başlıklı tanılama raporu
tools/qemu.sh ornekler/cekirdek.al  # grafik/ses örneği
```

## Ortam bilgisi

```
mimari : amd64
glibc  : 2.39
dağıtım: Ubuntu 24.04 (noble)
qemu   : 8.2.2+ds-0ubuntu1.16
```

Farklı bir dağıtımdan paket almayın — `glibc` uyumsuzluğu olur.

---

# Kendi Önyükleyicimiz (GRUB'a gerek yok)

```bash
python3 bench/gen_embed.py ornekler/onay.al > src/bench_embed.inc
EXTRA_CFLAGS="-DBENCH_SRC=1" ./build.sh bare-i386
python3 tools/disk-yap.py build/bare-i386 disk.img
qemu-system-i386 -drive file=disk.img,format=raw,if=ide \
                 -serial stdio -nic none
```

## Neden kendi önyükleyicimiz

Doğrusal çerçeve tamponu için iki yol vardı:

| yol | sorun |
|---|---|
| QEMU `-kernel` multiboot | VBE'yi **desteklemiyor** (`multiboot knows VBE. we don't`) |
| korumalı moddan VBE | **mümkün değil** — `int 0x10` gerçek mod hizmeti |
| GRUB | `grub-mkrescue` + `xorriso` gerekiyor, bu ortamda yok |

Önyükleyici **gerçek modda** başladığı için VBE'yi orada kuruyor,
sonra korumalı moda geçip çekirdeğe multiboot yapısıyla veriyor.

## Disk düzeni

```
sektor 0      onyukleyici (512 bayt, MBR imzali)
sektor 1..N   cekirdek HAM IKILI (ELF degil)
```

ELF çözümleyici 512 bayta sığmaz. `tools/disk-yap.py` çekirdeği
`objcopy` ile düz ikiliye çeviriyor, **giriş noktasını ELF
başlığından okuyup** önyükleyiciye gömüyor.

## Adımlar

1. Yığın kur, disk numarasını sakla
2. Çekirdeği diskten oku (`int 0x13 AH=0x42`, 32 KB'lık parçalar)
3. VBE kipini kur (`int 0x10 AX=0x4F02`), bilgileri multiboot yapısına yaz
4. A20 hattını aç
5. GDT yükle, korumalı moda geç
6. Çekirdeği 1 MB'a kopyala
7. `EAX=0x2BADB002`, `EBX=&multiboot_bilgi` ile atla

Tanılama: her adımda seri porta bir karakter (`1 2 3 P K`). Takılırsa
nerede durduğu görülür.
