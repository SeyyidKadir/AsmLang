# asmlang — Aşama 0: Platform iskeleti

Assembly ile yazılmış, Türkçe/İngilizce anahtar kelimeli bir bytecode
yorumlayıcısı. Bu aşamada **yorumlayıcı yok** — sadece 9 hedefte derlenip
çalışan platform katmanı var.

## Neden önce bu?

Projedeki en büyük bilinmeyenler Windows PE import katmanı, macOS syscall
sınıflandırması ve i386'nın register kıtlığı. Bunları 5.000 satır lexer
yazdıktan sonra keşfetmek istemiyoruz.

## Hedef matrisi

| | x86_64 | i386 | aarch64 | arm32 |
|---|---|---|---|---|
| Linux | ✅ test edildi | ✅ test edildi | ⬜ yazıldı | ⬜ yazıldı |
| macOS | ⬜ yazıldı | — | ⬜ yazıldı | — |
| Windows | ⬜ yazıldı | ⬜ yazıldı | ⬜ yazıldı | — |

- ✅ = derlendi ve çalıştırıldı
- ⬜ = kod yazıldı + makro genişletmesi doğrulandı, **assembler'dan geçirilmedi**
- — = platform mevcut değil (macOS 32-bit'i bıraktı, Windows RT öldü)

Geliştirme konteynerinde clang, cross-binutils ve qemu yoktu; ⬜ hedeflerin
gerçek doğrulaması senin makinende yapılmalı.

## Kurulum ve derleme

```bash
./build.sh                  # yerel hedef, derle + çalıştır
./build.sh linux-aarch64    # tek hedef
./build.sh all              # hepsini dene
./tests/check_expand.sh     # 9 hedefte makro denetimi (cross toolchain gerekmez)
```

Tam matris için gereken:

```bash
apt install clang lld qemu-user-static gcc-mingw-w64
# macOS hedefleri yalnızca macOS'ta (SDK + codesign gerekir)
```

## Mimari

```
src/
  config.inc          hedef tespiti, SYM() sembol ön eki
  abi.inc             doğru arch katmanını seçer, bölüm makroları
  arch/<isa>/abi.inc  sanal registerlar + makro seti
  os/<os>/os.S        HAL gerçeklemesi + giriş noktası
  main.S              mimariye tarafsız — 9 hedefte aynı dosya
```

### HAL sözleşmesi

```
os_write(A0=fd, A1=buf, A2=len) -> RV   yazılan bayt
os_alloc(A0=size)               -> RV   işaretçi, hata 0
os_exit(A0=code)                        dönmez
```

Linux ham syscall, macOS BSD syscall, Windows kernel32 import kullanır.
Hata normalizasyonu OS katmanında yapılır: `os_alloc` her yerde başarısızlıkta
0 döner, çağıran taraf platform farkı görmez.

### İç çağrı kuralı

İç kod **platform ABI'sine uymaz**. Sadece `os_*` trampolinleri uyar.
Kural mimari başına sabittir, OS'e göre değişmez:

| | A0 | A1 | A2 | A3 | RV |
|---|---|---|---|---|---|
| x86_64 | rdi | rsi | rdx | rcx | rax |
| i386 | eax | edx | ecx | yığın | eax |
| aarch64 | x0 | x1 | x2 | x3 | x0 |
| arm32 | r0 | r1 | r2 | r3 | r0 |

### Sanal registerlar

| Sanal | x86_64 | i386 | aarch64 | arm32 |
|---|---|---|---|---|
| VP bytecode ptr | rbx | esi | x19 | r4 |
| VS yığın tepesi | r12 | edi | x20 | r5 |
| VF çerçeve | r13 | ebx | x21 | r6 |
| VC sabit havuzu | r14 | **bellek** | x22 | r8 |
| VA scratch | r15 | eax | x23 | r10 |
| VB scratch | r10 | edx | x24 | r11 |

Kaçınılanlar: arm32'de r7 (syscall no) ve r9 (platform), aarch64'te x18 (TEB).

**i386 kısıtı:** yedek callee-saved register yok. Çağrılar arası değer taşımak
zorunlu olarak çerçeve slotu gerektiriyor. Bunu `SPILL(i,r)` / `FILL(r,i)`
makroları gizliyor — tarafsız kod dokuz hedefte de aynı kalıyor, x86_64'te
registera düşüyor, i386'da belleğe.

## Yol boyunca bulunan hatalar

**cpp stringify kazası.** `#define MOVI(r,i) mov r, #i` — macro gövdesinde
`#i` stringify operatörüdür ve `mov x0, "FD_STDOUT"` üretir. ARM ve AArch64'te
immediate öneki `#` olduğu için tüm ARM hedeflerini sessizce bozuyordu; x86
`$i` kullandığı için etkilenmemişti. Düzeltme: `#(i)` — `#` ardından `(`
geldiğinde stringify tetiklenmez. `tests/check_expand.sh` bu sınıfı yakalar.

## Sonraki adım (Aşama 1)

Dilin sözdizimi ve anahtar kelime tablosu. Tablolar `src/tables/` altında
mimariden bağımsız `.inc` dosyaları olacak; lexer/parser motorları o tabloları
yürütecek. Türkçe tarafında dikkat: `ı/İ` katlama sorunu nedeniyle anahtar
kelimeler **büyük/küçük harf duyarlı** ve byte-exact eşleşecek.

---

# Aşama 1: Sözdizimi + Lexer

## Dil kararı

Yapı sembollerle (`{}`, `()`, `,`), **anlam** çift dilli anahtar kelimelerle.
Böylece parser tek, tablo çift olur — `{` çevirmeye gerek yok.

```
tanim sayac = 10
sabit esik = 3.14

eğer sayac > 5 ve sayac != 42 {
    yazdır "büyük değer"
} yoksa {
    yazdir 'küçük'
}

fn topla(a, b) { return a + b }
iken sayac > 0 { sayac = sayac - 1 }
```

## Anahtar kelimeler — üç yazım, tek token

| Token | Türkçe | ASCII katlanmış | English |
|---|---|---|---|
| FN | `fonk` | — | `fn` |
| LET | `tanım` | `tanim` | `let` |
| CONST | `sabit` | — | `const` |
| IF | `eğer` | `eger` | `if` |
| ELSE | `yoksa` | — | `else` |
| WHILE | `iken` | — | `while` |
| FOR | `her` | — | `for` |
| BREAK | `kır` | `kir` | `break` |
| CONTINUE | `devam` | — | `continue` |
| RETURN | `döndür` | `dondur` | `return` |
| TRUE | `doğru` | `dogru` | `true` |
| FALSE | `yanlış` | `yanlis` | `false` |
| NIL | `boş` | `bos` | `nil` |
| AND | `ve` | — | `and` |
| OR | `veya` | — | `or` |
| NOT | `değil` | `degil` | `not` |
| PRINT | `yazdır` | `yazdir` | `print` |

ASCII katlanmış biçim, Türkçe klavyesi olmayanlar için. Üç yazım da aynı
token'a çözülür — mekanizma zaten çift dil için kurulduğu için bedava.

**Büyük/küçük harf duyarlı.** Türkçe'de `ı/I` ve `i/İ` katlaması bozuk
olduğundan (`strcasecmp` yanlış sonuç verir) eşleme bayt bazında birebir.
Anahtar kelimeler yalnızca küçük harf.

## Türkçe karakterler nasıl çözüldü

Unicode tablosu **yok**. `cc_table`'da `0x80–0xFF` aralığının tamamı
`C_ALPHA` işaretli — yani her UTF-8 devam baytı tanımlayıcı harfi sayılıyor.
`sayaç`, `değer`, `öğrenci` bedava çalışıyor; hiçbir kod yolu UTF-8 çözmüyor,
lexer bayt üzerinde kalıyor.

## Lexer mimarisi

Ana döngü tek bir hesaplanmış dallanma:

```
sinif = cc_table[bayt];  goto cc_jump[sinif]
```

Karar mantığının tamamı veride (`src/tables/`, dokuz hedefte birebir aynı
baytlar). Assembly yalnızca tabloları yürüten motor.

**Neden lexer tarafsız makrolarla yazıldı, elle dört kez değil:** lexer
kaynak boyutunda bir kez çalışır. Asıl sıcak döngü VM dağıtımı olacak ve o
mimari başına elle yazılacak. Optimizasyon emeğini milyarlarca kez dönen
döngüye saklıyoruz.

### Token kaydı — 16 bayt, tamamı u32

```
+0 tür   +4 satır   +8 kaynak ofseti   +12 uzunluk
```

Alan yok ki bayt yazması gereksin, işaretçi yok ki 32/64-bit ayrışsın.
Anahtar kelime tablosu da aynı mantıkta: `{u32 len, u32 tok, char[8]}` —
işaretçi içermediği için tablo dokuz hedefte birebir aynı.

`print_u32` bölme komutu kullanmaz (ARMv7'nin bir kısmında `udiv` yok);
onluk kuvvetlerinden tekrarlı çıkarma yapar.

## Sonuç

```
$ ./build/linux-x86_64
4 13 'eğer'      4 55 '>'       4 52 '!='
5 26 'yazdır'   5 4 '"büyük değer"'
11 19 'döndür'   11 20 'doğru'
token adedi: 54    lexer hatasi: 0
```

x86_64 ve i386 çıktıları **birebir aynı** — `tests/run.sh` bunu altın
çıktıyla doğruluyor.

## Bilinen eksikler

- `kw_lookup` doğrusal tarama (40 girdi). Aşama 2'de ilk bayt + uzunluğa
  göre mükemmel hash'e çevrilecek.
- Sayı sözcüğü ayrılıyor ama değere çevrilmiyor (parser'ın işi).
- Dizgi kaçışları sözcük içinde bırakılıyor, çözülmüyor.

## Sonraki adım (Aşama 2)

Pratt parser + AST arena. Öncelik tablosu `src/tables/prec.inc`'e girecek,
motor yine tabloyu yürütecek. Ardından bytecode derleyici ve `NEXT` dağıtım
döngüsü — o dördü elle yazılacak.


---

# Termux / Android desteği

```bash
pkg install clang binutils
bash build.sh          # Termux otomatik algılanır
```

`build.sh` `$TERMUX_VERSION`, `$PREFIX` ve `/data/data/com.termux` üzerinden
Termux'ü tanır ve yerel derlemede `--target` zorlamaz — Termux'ün clang'ı
zaten doğru Android ABI'siyle yapılandırılmış gelir.

Shebang çalışmazsa `bash build.sh` kullanın (Termux'te `/usr/bin/env` yok;
`termux-exec` genelde bunu düzeltir ama garanti değil).

## Android için ne değişti: konumdan bağımsızlık

Android PIE zorunlu kılabildiği için ikili dosyanın yer değiştirme kaydı
(relocation) üretmemesi gerekiyordu. Sorun `cc_jump` tablosundaydı: mutlak
adres tutuyordu, yani her giriş bir `R_*_RELATIVE` kaydı doğuruyordu.

Çözüm — tablo artık **32-bit ofset** tutuyor:

```
SYM(cc_jump):
    .long lx_bad   - lx_base
    .long lx_space - lx_base
    ...
```

İki etiket de `.text` içinde olduğu için assembler farkı derleme anında
çözüyor; geriye tek bir kayıt kalmıyor. Doğrulandı:

```
$ readelf -r build/linux-x86_64   →  0 kayıt
$ gcc ... -static-pie             →  çalışıyor
```

Yan kazanç: tablo 64-bitte de 32 bit kalıyor, önbellek dostu. Aynı teknik
Aşama 2'de bytecode `optable` için de kullanılacak — zaten ASLR altında
mutlak adres gömmek istemiyorduk.

**Bağlama kipleri.** `build.sh` her hedefte iki kip dener:

| Hedef | Önce | Sonra |
|---|---|---|
| `termux-aarch64`, `termux-x86_64` | `-static-pie` | `-static -no-pie` |
| `termux-arm` | `-static -no-pie` | `-static-pie` |
| diğer Linux | `-static -no-pie` | `-static-pie` |

ARM32'de sıra ters, çünkü `LEA_SYM` orada `ldr r, =sym` (literal havuzunda
**mutlak** adres) kullanıyor — PC-göreli değil, yani PIE'de kayıt üretir.
AArch64 (`adrp`/`add`) ve x86_64 (`leaq ...(%rip)`) tamamen PC-göreli, orada
sorun yok. Termux'te baskın mimari aarch64 olduğu için pratikte etkilenmiyor.

## Termux hedefleri

| Hedef | Üçlük |
|---|---|
| `termux-aarch64` | `aarch64-linux-android` |
| `termux-arm` | `armv7a-linux-androideabi` |
| `termux-x86_64` | `x86_64-linux-android` |

Syscall katmanı Linux'unkiyle aynı — Bionic'i atlayıp doğrudan çekirdeğe
gittiğimiz için Android ile GNU/Linux arasında fark yok.

---

# Aşama 2: Pratt Parser + AST

## Sonuç

```
tanim sayac = 10
sabit esik = 2 + 3 * 4
eğer sayac > 5 ve sayac != 42 { yazdır "büyük değer" }
yoksa eğer sayac == 0 { yazdir 'sifir' }
yoksa { print "küçük" }
fonk topla(a, b) { dondur a + b }
iken sayac > 0 { sayac = sayac - 1 }
yazdir topla(1, 2 * 3)
```

```
PROGRAM
  CONST esik
    BINARY +
      NUMBER 2
      BINARY *          ← * , + 'dan sıkı bağladı
        NUMBER 3
        NUMBER 4
  IF
    LOGICAL ve          ← ve , karşılaştırmalardan gevşek
      BINARY >
      BINARY !=
    BLOCK ...
    IF                  ← "yoksa eğer" iç içe IF oldu
  FN topla
    PARAM a
    PARAM b
    BLOCK ...
  PRINT
    CALL
      IDENT topla
      NUMBER 1
      BINARY *
```

token: 74   düğüm: 59   hata: 0 — x86_64 ve i386 çıktıları **birebir aynı**.

## Öncelik tablosu

| Bağlama gücü | Operatörler | Birleşme |
|---|---|---|
| 1 | `=` | sağ |
| 2 | `veya` `or` | sol |
| 3 | `ve` `and` | sol |
| 4 | `==` `!=` | sol |
| 5 | `<` `<=` `>` `>=` | sol |
| 6 | `+` `-` | sol |
| 7 | `*` `/` `%` | sol |
| 8 | tekli `-` `değil` `!` | önek |
| 9 | `(` çağrı | sol |

Tamamı `prec_table`'da: `{lbp, düğüm türü, sağ birleşme}` × 4 bayt. Yeni
operatör eklemek `gen_tables.py`'de tek satır — parser koduna dokunulmuyor.
Sağ birleşme tek bir çıkarmayla düşüyor: `parse_expr(lbp - rassoc)`.

## AST neden indeks tabanlı

Düğümler işaretçiyle değil **u32 indeksle** bağlanıyor. Sonuç: AST yerleşimi
32 ve 64 bitte birebir aynı, parser kodunda hiçbir yerde işaretçi boyutu
geçmiyor. Aynı gerekçe token kaydında ve anahtar kelime tablosunda da vardı —
tutarlı bir ilke haline geldi.

Düğüm 32 bayt (24 yeterdi) çünkü adresleme `taban + (indeks << 5)` — tek
kaydırma, çarpma yok. 8 bayt israf, dört mimaride de bedava adresleme.

```
+0 kind  +4 line  +8 a  +12 b  +16 c  +20 next
```

`next` alanı kardeş zinciri: deyim listeleri, argümanlar ve parametreler
ayrı bir dizi yapısına gerek kalmadan aynı mekanizmayı kullanıyor.

## Parser VP/VS/VF kullanmıyor

Bilinçli karar. Parser özyinelemeli; sanal register kullansaydı her çağrıda
kurtarma/geri yükleme gerekirdi ve i386'da (yedek callee-saved register yok)
bu ciddi bir karmaşa olurdu. Bunun yerine tüm durum küresel değişkenlerde ve
çerçeve slotlarında. Biraz yavaş — ama parser da lexer gibi bir kez çalışıyor.

## Sonsuz döngü güvencesi

`parse_stmts` her turda `g_tpos`'u kaydediyor; `parse_stmt` hiç token
tüketmeden dönerse zorla bir token ilerletiyor. Bozuk girdiyle doğrulandı:

```
tanim = 5 / eğer ) { / yazdir 1 + / fonk (a { } / @#$ / tanim y = 1 = 2 = 3
→ 13 hata, ilk 5'i basıldı, temiz çıkış (kod 13), askıda kalma yok
```

`1 = 2 = 3` sağ birleşmeli çözüldü — anlamsal olarak geçersiz ama
*sözdizimsel* olarak doğru. Atama hedefi denetimi anlamsal geçişin işi.

## AST yazıcısı da tablo güdümlü

`dump_node` hangi alanın çocuk düğüm hangisinin token indeksi olduğunu
bilmiyor; `kind_kids` (bit maskesi) ve `kind_tokfld` tablolarından okuyor.
Yeni düğüm türü eklemek yine `gen_tables.py`'de tek satır.

## Bilinen eksikler

- Hata sonrası AST anlamsız (panic-mode senkronizasyonu yok — `;` veya `}`
  görene kadar atlama eklenecek).
- Ad alanı boş kalan düğümlerde yazıcı token 0'ı basıyor; yalnızca hata
  yollarında görünen kozmetik sorun.
- Sayı sözcüğü hâlâ değere çevrilmiyor.

## Sonraki adım (Aşama 3)

Bytecode derleyici + `NEXT` dağıtım döngüsü. Burada strateji değişiyor:
dağıtım döngüsü **mimari başına elle** yazılacak. `optable` de `cc_jump`
gibi offset tabanlı olacak — ASLR altında mutlak adres gömmemek için.

---

# Aşama 3: Bytecode Derleyici + VM

Dil artık **çalışıyor**.

```
sabit esik = 2 + 3 * 4
yazdir esik                          → 14
yazdir 17 / 5                        → 3
yazdir 17 % 5                        → 2
yazdir -esik                         → -14
eğer esik > 10 ve sayac != 0 { yazdır "buyuk" } yoksa { yazdır "kucuk" }
iken sayac > 0 { yazdir sayac  sayac = sayac - 1 }   → 3 2 1
fonk topla(a, b) { döndür a + b }
yazdir topla(20, 42)                 → 42
fonk faktoryel(n) {
    eğer n <= 1 { döndür 1 }
    döndür n * faktoryel(n - 1)
}
yazdir faktoryel(5)                  → 120     ← özyineleme
yazdir doğru ve yanlış               → yanlis  ← kısa devre
{ tanim ic = 7  yazdir ic * 2 }      → 14      ← blok-yerel
```

x86_64 ve i386 çıktıları birebir aynı. 121 token → 98 düğüm → 99 komut.

## Komut kodlaması: 4 bayt, hizalı

```
bit  0-7   işlem kodu
bit  8-15  boş
bit 16-31  işlenen (sabit indeksi / yuva / atlama hedefi)
```

Sabit genişlik seçildi çünkü **hizasızlık sorununu tümden kaldırıyor** —
ARM32'de bayt yönelimli kodlamada `u32` işlenen okumak hizasız erişim
demekti. Bedeli: bytecode bayt yönelimli bir kodlamadan daha büyük.
Kazancı: çözümleme tek yükleme + iki ALU işlemi, dört mimaride de aynı.

## Dağıtım çekirdeği — mimari başına elle

Projenin başından beri "sıcak %10" dediğim yer burası. `NEXT` her mimaride
ayrı yazıldı ve **her işleyicinin sonuna kopyalanıyor** — merkezi döngü yok,
çünkü dallanma tahmincisi için asıl kazanç orada.

```
x86_64                              aarch64
  movl (VP), %r11d                    ldr w24, [VP], #4
  addq $4, VP                         and w24, w24, #0xff
  movzbl %r11b, %r11d                 adrp/add x25, optable
  leaq optable(%rip), %r10            ldrsw x24, [x25, x24, lsl #2]
  movslq (%r10,%r11,4), %r11          add x25, x25, x24
  addq %r11, %r10                     br x25
  jmp *%r10

arm32                               i386
  ldr r11, [VP], #4                   movl (VP), %eax
  and r11, r11, #255                  addl $4, VP
  ldr r12, =optable                   movzbl %al, %eax
  ldr r11, [r12, r11, lsl #2]         movl $optable, %ecx
  add pc, r12, r11   ← pc'ye add      movl (%ecx,%eax,4), %eax
                       dallanmadır    addl %ecx, %eax
                                      jmp *%eax
```

`optable` **`.text` içinde** ve ofsetleri kendi tabanına göre. Böylece
`isleyici - optable` derleme anında katlanıyor:

```
$ readelf -r  (static-pie yapıda)  →  0 yer değiştirme kaydı
```

Aşama 2'de `cc_jump` için kurduğumuz teknik. ASLR altında bytecode'a mutlak
adres gömmemenin karşılığı bu.

## Kayıt haritası (VM)

| | rol |
|---|---|
| VP | program sayacı |
| VS | değer yığını tepesi |
| VF | çerçeve tabanı (yerel 0'ın adresi) |

`VC` (sabit havuzu) kullanılmadı — i386'da register kalmadığı için tabanı
her `CONST`'ta bellekten okuyoruz. Dört mimaride tek kod yolu; kaybı bir
yükleme.

## Değer temsili

8 baytlık slot: `{u32 etiket, u32 yük}`. 32 ve 64 bitte aynı.

`T_INT = 0` **bilinçli**: iki işlenenin de tamsayı olduğunu tek OR ile
denetliyoruz:

```
NEED_INT2:  t1 = tag[-16];  t2 = tag[-8];  t1 |= t2;  if (t1) → tür hatası
```

Ayrıca sıfırlanmış slot doğal olarak tamsayı 0 oluyor.

## Yol boyunca bulunan iki hata

**1. 64-bit'te işaret genişletme.** `LD32_OFF` sıfır genişletiyordu, yani
`-3` yükü (`0xFFFFFFFD`) x86_64'te 4294967293 oluyordu. `yazdir -esik`
yanlış sonuç veriyordu. Çözüm: `LD32S_OFF` — `movslq` / `ldursw` / `movl` /
`ldr`, tek komutta işaretli yükleme. Etiketler ve indeksler için sıfır
genişleten sürüm kaldı.

**2. i386'da `VA == VF`.** VM işleyicilerinde `VA`'yı geçici olarak
kullanmıştım; i386'da `VA` ve `VF` aynı register (`%ebx`), yani çerçeve
tabanı eziliyordu. Çözüm: işleyiciler `run`'ın çerçeve slotlarını kullanıyor
(slot 4-7). Yine i386 kısıtı yol gösterdi.

## Bölme komutu kullanılmıyor

`udivmod` kaydır-çıkar uzun bölme yapıyor — 32 tur, sabit maliyet. Gerekçe:
ARMv7'nin bir kısmında `udiv` yok ve x86'da `div`'in `edx:eax` kısıtı makro
katmanını kirletiyor. `print_u32` de aynı sebeple onluk kuvvetlerinden
tekrarlı çıkarma yapıyor.

## Çalışma hataları — hepsi test edildi

| Girdi | Çıktı |
|---|---|
| `yazdir 1 + "x"` | tür uyuşmazlığı |
| `yazdir 7 / 0` | sıfıra bölme |
| `fonk f(a){...} f(1,2)` | argüman sayısı uymuyor |
| `yazdir bos()` | çağrılabilir değil |

## Bilinen eksikler

- **Tamsayı VM.** Kayan nokta yok; `3.14` tamsayı kısmına kırpılıyor.
  64-bit'te NaN-boxing, 32-bit'te ayrı temsil Aşama 5'e bırakıldı.
- Kapanış (closure) yok, fonksiyonlar üst seviyede.
- Dizgi birleştirme, dizi, sözlük yok.
- Aritmetikte tür denetimi her işlemde yapılıyor; tür-özelleşmiş işlem
  kodları (`ADD_II`) sonraki hız adımı.
- İşlenen registerda tutulmuyor, `GETOPD` her seferinde `(VP-4)`'ten
  okuyor. i386 dışında boş register var; mimari başına iyileştirilebilir.

## Sonraki adım (Aşama 4)

Kapanışlar + üst değerler (upvalue), dizgi/dizi türleri ve bir GC. Ardından
Aşama 5'te kayan nokta ve NaN-boxing.

---

# Aşama 4: Dizgi, Dizi ve Çöp Toplayıcı

```
tanim ad = "dunya"
yazdir "merhaba, " + ad + "!"       → merhaba, dunya!
yazdir uzunluk(ad)                  → 5
yazdir "a" + "b" == "ab"            → dogru      ← içerik karşılaştırması
tanim liste = [1, 2, 3]
liste[1] = 99
ekle(liste, 42)  ekle(liste, "son")
yazdir liste                        → [1, 99, 3, 42, son]
yazdir [[1,2],[3,4]][1][0]          → 3          ← iç içe dizi
yazdir "sayi: " + yazi(6 * 7)       → sayi: 42
```

GC stresi: 3000 geçici dizgi → **2 GC turu**, ardından `ad` ve `liste` sağlam.
x86_64 / i386 çıktıları birebir aynı.

## Nesnelere işaretçiyle değil TUTAMAKLA erişiliyor

Yük alanı `u32`. 64-bitte işaretçi sığmaz. Slotu 16 bayta çıkarmak yerine
nesneler `g_objs` tablosunda indekslendi. İki kazanç:

1. **Değer yerleşimi 32 ve 64 bitte aynı kalıyor** — projenin baştan beri
   uyguladığı ilke (token, AST, atlama hedefi hepsi indeksli).
2. **Çöp toplayıcı SIKIŞTIRMA yapabiliyor.** Bütün başvurular tek tablodan
   geçtiği için nesneyi taşımak = tabloda tek girdiyi güncellemek. Yığındaki,
   küresellerdeki, sabitlerdeki değerlere hiç dokunulmuyor.

Bedeli: nesne erişiminde bir dolaylı yükleme.

```
Nesne başlığı (24 bayt):
+0 tür  +4 boyut  +8 tutamak  +12 işaret  +16 uzunluk  +20 kapasite
```

`OBJ_HND` alanı sıkıştırmanın anahtarı: yığını doğrusal dolaşırken her
nesne kendi tutamağını söylüyor, tabloya geri yazmak tek satır.

`ekle()` diziyi büyütürken yeni nesne ayırıp **tutamağı ona yönlendiriyor**,
eskisini `HND_ORPHAN` işaretliyor. Tutamak değişmediği için diziye yapılmış
bütün başvurular geçerli kalıyor — yerinde büyümüş gibi.

## Yol boyunca bulunan üç hata

**1. Tutamak 0 hem geçerli hem "hata".** İlk dizgi tutamak 0 alıyordu,
`BZ(RV, ...)` bunu OOM sanıp veriyi kopyalamadan dönüyordu — 5 null bayt.
AST'de düğüm 0'ı nöbetçi yaptığımız gibi burada da tutamak 0 rezerve edildi.

**2. Negatif ofsetli atlama tablosu.** `nat_fns` fonksiyonlardan *sonra*
geliyordu, yani `nat_len - nat_fns` negatif. Sıfır genişleten indeksli
yükleme bunu devasa pozitife çevirip çöp adres üretti. `optable`'da tablo
zaten başta olduğu için orada görülmemişti.

**3. `RV == A0` (i386) — üç yerde.**

```
CALL(obj_ptr)
LD32_OFF(A0W, RV, OBJ_KIND)   ; x86_64: %edi ← (%rax)   RV sağlam
                              ; i386:   %eax ← (%eax)   RV YOK OLDU
LD32_OFF(A0W, RV, OBJ_LEN)    ; i386: çöp adresten okuma → segfault
```

Aynı hata `mem_copy`'de de vardı: `movl %eax, (%eax)`. x86_64'te ikisi ayrı
register olduğu için hiç görünmüyordu.

**Kural (artık disiplin):** `obj_ptr` sonucu birden fazla alan okunacaksa
önce çerçeve slotuna dökülür. i386 bu projede dördüncü kez yol gösterdi.

## Taban ölçüm

```
iken i < 5000000 { toplam = toplam + i  i = i + 1 }
→ 15 bytecode komutu/tur × 5.000.000 = 75.000.000 komut

linux-x86_64 :  98 ms  →  765 milyon komut/s
linux-i386   :  98 ms  →  765 milyon komut/s

ikili boyutu : 45 KB (x86_64) / 36 KB (i386), statik, libc yok
```

Bu, optimize edeceğimiz sayı. Şu an masada duran kazançlar:

| Fırsat | Beklenen etki |
|---|---|
| İşleneni registerda tut (`GETOPD` her seferinde `(VP-4)`'ten okuyor) | orta |
| Tür-özelleşmiş komutlar (`ADD_II` — tür denetimini derleyiciye kaydır) | yüksek |
| Süperkomut (`GETLOCAL+GETLOCAL+ADD` tek komut) | yüksek |
| Küresel yerine yerel yuva (döngü değişkenleri) | yüksek |
| Doğrudan iplikleme (bytecode'a handler adresi göm) | düşük, PIE'yi bozar |

## OS geliştirme için not (ileriye dönük)

Temel buna hazır kuruldu:

- **Zaten freestanding.** libc yok, ham syscall. Bare-metal'e geçmek
  `src/os/bare/os.S` eklemek demek — `os_write` UART'a, `os_alloc` sabit
  bir bölgeye. Diğer 4800 satıra dokunulmaz.
- **Sıfır yer değiştirme kaydı.** `readelf -r` → 0. Çekirdek imajı istediği
  adrese yüklenebilir.
- **Dinamik ayırma dışarıdan veriliyor.** `heap_init(taban, boyut)` — çekirdek
  kendi fiziksel bellek haritasından besler.
- **GC çekirdekte sorun.** Sıkıştırma duraklaması kesme gecikmesini bozar.
  Çözüm: çekirdek kipinde GC'yi kapatıp yalnız arena kullanmak, ya da
  artımlı/nesil tabanlı GC. Tutamak dolaylılığı ikisini de kolaylaştırıyor.
- **Eksik:** kesme işleyicileri, volatile MMIO erişimi, `kesme`/`kritik`
  gibi dil ilkelleri, ve satır içi assembly kaçışı.

## Bilinen eksikler

- Tamsayı VM (kayan nokta yok).
- Kapanış (closure) yok.
- Sözlük/harita yok.
- Dizgiler ic içe geçirilmiyor (interning) — `==` içerik karşılaştırıyor,
  O(n). Hash + interning ile O(1) yapılabilir.

---

# Aşama 5: Hız Turu

Hedef: "bir işlem için kırk takla" durumunu kesmek. Döngü gövdesi
derleyiciden **15 komut** çıkıyordu:

```
toplam = toplam + i   GETGLOBAL GETGLOBAL ADD SETGLOBAL POP
i = i + 1             GETGLOBAL CONST ADD SETGLOBAL POP
i < 5000000           GETGLOBAL CONST LT JZ ... JMP
```

## 1. Gözetleme deliği (peephole) birleştirmesi — en büyük kazanç

Bytecode VM'inde en pahalı şey **dağıtımdır** (dolaylı dallanma, dal
tahmincisi için zor). İş yapmayan komutu silmek en ucuz kazanç.

| Örüntü | Birleşik | Kazanç |
|---|---|---|
| `SETGLOBAL n; POP` | `SETGLOBAL_P n` | 1 dağıtım |
| `SETLOCAL n; POP` | `SETLOCAL_P n` | 1 |
| `CONST k; ADD` | `ADDK k` | 1 |
| `CONST k; SUB` | `SUBK k` | 1 |
| `LT; JZ t` | `JGE t` | 1 |
| `LE/GT/GE/EQ/NE; JZ` | `JGT/JLE/JLT/JNE/JEQ` | 1 |

**15 → 11 komut/tur.**

Üç geçiş: (0) atlama hedeflerini işaretle, (1) çiftleri yerinde birleştir ve
eski→yeni indeks haritası kur, (2) atlama işlenenlerini yeniden eşle.

Kritik kural: **ikinci komut bir atlama hedefiyse birleştirilmez** — yoksa
dışarıdan gelen atlama birleşik komutun ortasına düşer. Bu yüzden geçiş 0 var.

`CONST k; ADD` birleşmesi sabitin tamsayı olmasını şart koşuyor; yoksa dizgi
birleştirme (`"a" + "b"`) bozulurdu.

## 2. Değer taşımada tek erişim

Her `GETGLOBAL` şunu yapıyordu: etiketi yükle, yükü yükle, etiketi sakla,
yükü sakla — **bir değer için 4 bellek işlemi**. Slot zaten 8 bayt ve hizalı:

```
x86_64 / aarch64:  movq (s), t ; movq t, (d)      → 2 işlem
i386   / arm32  :  iki çift (32-bit register)     → 4 işlem
```

Mimari başına ayrışan `VCOPY` makrosu. 64-bit hedeflerde bellek trafiği
yarıya indi, 32-bit'te bir şey kaybedilmedi.

## 3. İşlenen artık registerda

`GETOPD` her seferinde `(VP-4)`'ten okuyordu. `NEXT` komutu zaten yüklüyor —
`INS` registerinde tutuluyor artık:

```
aarch64/arm : lsr dW, INS, #16        (1 komut, bellek erişimi yok)
x86_64      : movl INSW, dW; shr $16  (2 komut, bellek erişimi yok)
i386        : boş register yok → eski yol korundu
```

## Sonuç

```
20.000.000 tur          önce      sonra
x86_64                 470 ms    396 ms    %16 hızlı
i386                   383 ms    321 ms    %16 hızlı
```

Davranış birebir aynı (`tests/golden` geçti), x86_64 ↔ i386 paritesi korundu.

## Ölçüm hakkında dürüst not

İlk ölçümde x86_64 "%20 yavaşladı" göründü. 5.000.000 turluk koşu paylaşımlı
konteynerde çok kısaydı; 20.000.000 tura çıkınca fark **ölçüm gürültüsü**
çıktı (400 vs 402 ms). Değişiklikleri tek tek ayırıp yeniden ölçmeden sonuç
yazmadım. Kısa mikro-ölçüm yanıltır.

Ayrıca dikkat: **dağıtım/saniye düştü** (638M → 556M) ama program hızlandı.
Doğru metrik dağıtım sayısı değil, işi bitirme süresi — birleşik komutlar
daha fazla iş yapıyor, sayıları az ama tek tek pahalı.

## Sırada ne var (etki sırasına göre)

| # | İş | Beklenen |
|---|---|---|
| 1 | Üst seviye `tanim` → yerel yuva (küresel arama yerine `VF+n`) | orta |
| 2 | Tür-özelleşme: derleyici tamsayı olduğunu biliyorsa `ADD_II` | yüksek |
| 3 | Yığın tepesini registerda tut (top-of-stack caching) | yüksek, karmaşık |
| 4 | `GETGLOBAL x; GETGLOBAL y; ADD` → tek süperkomut | orta |
| 5 | Dizgi iç içe geçirme (interning): `==` O(n) → O(1) | orta |

2 ve 3 birlikte yapılırsa döngü gövdesi 11'den ~6 komuta iner.

## RAM maliyeti (senin isteğin üzerine ölçüldü)

```
ikili           45 KB (x86_64) / 36 KB (i386), statik, libc yok
komut           4 bayt/komut, hizalı
değer slotu     8 bayt (etiket + yük)
nesne başlığı   24 bayt
derleyici tablosu  g_map 32 KB + g_tgt 8 KB  (yalnız derleme anında)
```

Derleyici tabloları çekirdek kipinde israf — `MAX_CODE` düşürülebilir ya da
arenadan ayrılabilir. Not edildi.

---

# Aşama 6: Süperkomutlar — döngü gövdesi 15 → 7

## Fikir: 16-bit işlenen alanına iki 8-bit işlenen

Küresel ve yerel yuva sayısı 256'yı geçmediği sürece iki işlenen tek alana
sığıyor. Sığmazsa gözetleme deliği birleştirmeyi atlıyor — doğruluk hiç
riske girmiyor.

| Örüntü | Süperkomut |
|---|---|
| `GETGLOBAL a; GETGLOBAL b` | `GETGLOBAL2 (a \| b<<8)` |
| `GETLOCAL a; GETLOCAL b` | `GETLOCAL2` |
| `ADD; SETGLOBAL_P n` | `ADD_SETG n` |
| `ADD; SETLOCAL_P n` | `ADD_SETL n` |
| `ADDK k; SETGLOBAL_P n` | `ADDK_SETG (k \| n<<8)` |
| `GETGLOBAL n; ADDK_SETG(k,n)` | `INCGLOBAL (n \| k<<8)` |

Sonuncusu özel: `i = i + 1` **yığına hiç dokunmadan** tek komutta oluyor.
Küresel değeri oku, sabiti ekle, geri yaz. İt-çek yok.

## Sabit noktaya kadar döndürme

Bir turda oluşan birleşik komut, bir sonraki turda tekrar birleşebiliyor.
Peephole artık değişiklik kalmayana kadar dönüyor (en fazla 8 tur):

```
tur 0:  GETGLOBAL i, CONST 1, ADD, SETGLOBAL i, POP
tur 1:  GETGLOBAL i, ADDK 1, SETGLOBAL_P i
tur 2:  GETGLOBAL i, ADDK_SETG(1, i)
tur 3:  INCGLOBAL(i, 1)                    ← 5 komut → 1
```

## Üretilen bytecode

```
iken i < 20000000 { toplam = toplam + i  i = i + 1 }

 4  GETGLOBAL   1          ← döngü başı
 5  CONST       2
 6  JGE        11          ← LT + JZ birleşik
 7  GETGLOBAL2  256        ← toplam(0) ve i(1) tek komutta
 8  ADD_SETG    0          ← ADD + SETGLOBAL + POP
 9  INCGLOBAL   769        ← i += 1, yığına dokunmadan
10  JMP         4
```

**7 komut/tur** (başlangıçta 15).

## Ölçüm

```
20.000.000 tur       peephole yok      tam       kazanç
x86_64                  467 ms        251 ms      %46
i386                    386 ms        233 ms      %40
```

Davranış birebir aynı (`tests/golden` geçiyor), x86_64 ↔ i386 paritesi korundu.

## Neden bu kadar işe yaradı

Bytecode VM'inde asıl maliyet **dolaylı dallanma** — dal tahmincisi her
dağıtımda zorlanıyor. 15 dağıtımı 7'ye indirmek, tahmincinin işini yarıya
indirmek demek. Buna karşılık her süperkomut daha fazla iş yapıyor ama
düz kod olarak, tahmin edilebilir şekilde.

İkinci etken: `INCGLOBAL` değer yığınına hiç dokunmuyor. Öncesinde `i = i + 1`
bir it, bir sabit it, topla, geri yaz, çek yapıyordu — dört bellek trafiği
turu. Şimdi bir oku, bir yaz.

## Bilinen sınır

Süperkomutlar 256'dan fazla küresel/yerel olduğunda devreye girmiyor.
Bunun çözümü işlenen alanını büyütmek değil (komut 4 baytta kalmalı),
sık kullanılan yuvaları düşük indekslere toplamak — bir "yuva sıklığı"
geçişi. Sonraya not edildi.

## Sırada

| # | İş | Beklenen |
|---|---|---|
| 1 | Yığın tepesini registerda tut (TOS caching) | yüksek, i386'da register yok |
| 2 | Tür-özelleşme (`ADD_II`) — statik tür çıkarımı gerekir | yüksek |
| 3 | `GETGLOBAL n; CONST k; JGE t` → 3'lü karşılaştırma | orta |
| 4 | Dizgi iç içe geçirme | orta |
| 5 | Bare-metal katmanı (`src/os/bare/os.S`) | OS hedefi için |

1 numara i386'da boş register olmadığı için mimari ayrışması gerektiriyor —
projenin şimdiye kadarki "tek kod yolu" ilkesini ilk kez bozacak. Yapılırsa
bilinçli yapılmalı.

---

# Aşama 7: Süperkomut + Döngü Rotasyonu — 15 → 5

## Sonuç

```
20.000.000 tur       ham        tam        kazanç
x86_64             368 ms     206 ms      %44
i386               275 ms     134 ms      %51
komut/tur             15          5
```

Üretilen döngü:

```
iken i < 20000000 { toplam = toplam + i  i = i + 1 }

 4  JMP         8        ← bir kerelik, koşula giriş
 5  GETGLOBAL2  256      ← toplam ve i tek komutta
 6  ADD_SETG    0        ← ADD + SETGLOBAL + POP
 7  INCGLOBAL   513      ← i += 1, yığına hiç dokunmadan
 8  GETG_CONST  769      ← i ve sabiti tek komutta
 9  JLT         5        ← karşılaştır ve geri dallan
```

**5 komut/tur.** Başlangıçtaki 15'in üçte biri.

## 1. Döngü rotasyonu

Düz derleme her turda fazladan bir `JMP` yürütür:

```
başla: koşul ; JZ çıkış ; gövde ; JMP başla        ← tur başına 2 dallanma
JMP koşul ; gövde: gövde ; koşul: koşul ; JNZ gövde ← tur başına 1
```

Girişte bir kerelik `JMP` maliyeti, **her turda** bir dağıtım kazancı.

Bunun için `OP_JNZ` eklendi ve `devam` (continue) mekanizması değişti:
rotasyonlu düzende koşul gövdeden *sonra* geldiği için hedef derleme
anında bilinmiyor — `break` gibi `devam` da yama listesine girdi.

## 2. İki 8-bit işlenen tek 16-bit alanda

| Örüntü | Süperkomut |
|---|---|
| `GETGLOBAL a; GETGLOBAL b` | `GETGLOBAL2` |
| `GETLOCAL a; GETLOCAL b` | `GETLOCAL2` |
| `GETGLOBAL n; CONST k` | `GETG_CONST` |
| `GETLOCAL n; CONST k` | `GETL_CONST` |
| `ADD; SETGLOBAL_P n` | `ADD_SETG` |
| `ADDK k; SETGLOBAL_P n` | `ADDK_SETG` |
| `GETGLOBAL n; ADDK_SETG(k,n)` | `INCGLOBAL` |

Yuva sayısı 256'yı geçerse birleştirme atlanır — doğruluk riske girmez,
yalnız hız kaybedilir. Komut hâlâ **4 bayt**; RAM maliyeti değişmedi.

## 3. Kural önceliği — ölçerek bulundu

İlk denemede `GETG_CONST` her turdan itibaren açıktı ve ölçüm
**251 → 289 ms kötüleşti**. Sebep: açgözlü kural `GETGLOBAL i; CONST 1`
çiftini hemen yutuyor, böylece

```
CONST+ADD → ADDK → ADDK_SETG → INCGLOBAL
```

zinciri hiç oluşamıyordu. `i = i + 1` tek komut yerine iki komut kalıyordu.

Çözüm: **iki aşamalı gözetleme deliği.** Aşama 0'da yalnızca dar kurallar
sabit noktaya kadar döner; `INCGLOBAL` oluştuktan sonra Aşama 1 açgözlü
kuralları açar. Bu, "önce en çok iş yapan birleşmeyi bul" ilkesinin
mekanik hali.

## Yol boyunca bulunan iki hata

**1. Bayat fonksiyon giriş noktaları — sinsi olanı.**

Gözetleme deliği atlama işlenenlerini yeniden eşliyordu ama
`g_fns[i].entry` derleyicinin yazdığı **eski** indekste kalıyordu.
Birleşme fonksiyon gövdesinden *önce* oluştuğunda `CALL` çöp adrese
sıçrıyor, program çöküyordu.

```
GETG_CONST kapalı:  JMP 44 ... gövde 39'da    g_fns.entry = 39 ✓
GETG_CONST açık:    JMP 39 ... gövde 34'te    g_fns.entry = 39 ✗
```

Küçük testlerde görünmüyordu çünkü orada birleşme hep gövdeden *sonra*
oluyordu. Delta-debug ile 29 satırlık programdan 9 satıra indirilerek
bulundu.

**Ders: kod indeksi tutan HER yer yeniden eşlenmeli.** Peephole'a bir
"geçiş 3" eklendi. Kapanış/metot tabloları gelirse onlar da eklenmeli.

**2. Döngü rotasyonu `devam`'ı bozdu.** `patch_conts` hedefi hiç
hesaplamıyor, ayarlanmamış bir çerçeve slotundan çöp okuyordu — sonsuz
döngü. `patch_breaks` `here()` kullanabiliyordu ama devam hedefi
geçmişte kaldığı için dışarıdan verilmek zorunda.

## Ölçüm disiplini

Bu turda üç kez ölçüm beklentiyle çelişti ve üçünde de **ölçüm haklı çıktı**:

1. "%20 yavaşladı" → 5M tur çok kısaydı, gürültüydü (20M'de fark yok).
2. "5 komut ama daha yavaş" → gerçekti, kural önceliği sorunu.
3. "INCGLOBAL neden yok" → test betiğimin bıraktığı `B(fz_no)` yamaları
   kuralı kapalı tutuyordu.

Üçüncüsü kendi hatamdı: hata ayıklama yamalarını dosyada bırakmıştım.
Disassembler olmasa hiçbiri görülemezdi — **kendi çıktısını okuyabilen
bir derleyici yazmak yatırıma değer.**

## Durum

```
ikili        52 KB (x86_64) / 43 KB (i386), statik, libc yok
static-pie   0 yer değiştirme kaydı
9 hedef      makro genişletmesi doğrulandı
2 hedef      derlendi + çalıştırıldı, çıktılar birebir aynı
```

## Sırada

| # | İş | Beklenen |
|---|---|---|
| 1 | Yığın tepesini registerda tut | yüksek; i386'da `ebp`'yi serbest bırakmak gerekir |
| 2 | Tür-özelleşme (`ADD_II`) — statik tür çıkarımı | yüksek |
| 3 | Kapanışlar + üst değerler | dil zenginliği |
| 4 | Bare-metal katmanı (`src/os/bare/os.S`) | OS hedefi |

1 numara için not: i386'da boş register **var** — `run`'ın çerçeve
slotlarını `.bss`'e taşırsak `ebp` serbest kalır. Yani "i386'da register
yok" gerekçesi yanlıştı; feda etmemiz gereken bir şey yok.

---

# Aşama 8: Benchmark Harness — ve kendi hatamı bulması

## Neden harness

README'deki sayılar tek seferlik kabuk komutlarıyla üretiliyordu:
bağımsız doğrulanamaz, dağılım görülemez, iddia ile ölçüm ayrışmaz.
Artık her sayı tek komutla yeniden üretilebiliyor:

```bash
bench/run.sh                    # tüm program × varyant × mimari
bench/run.sh loop20m x86_64     # tek kombinasyon
REPS=20 bench/run.sh            # tekrar sayısı
```

Varyantlar aynı kaynaktan, derleme-zamanı anahtarlarıyla üretiliyor:

| varyant | bayraklar |
|---|---|
| `baseline` | `-DOPT_ROTATE=0 -DOPT_PEEPHOLE=0 -DOPT_SUPER=0` |
| `rotate` | `+ döngü rotasyonu` |
| `peephole` | `+ dar gözetleme deliği kuralları` |
| `full` | `+ süperkomutlar` |

Raporlanan: **medyan**, min, max, ortalama, standart sapma — en düşük tek
başına değil. Bu projede bir kez "%20 yavaşladı" sonucu tamamen gürültü
çıkmıştı; dağılımı göstermek bunu baştan engelliyor.

## Dağıtım sayacı: iddia değil, ölçüm

`-DOPT_COUNT=1` ile VM her dağıtımda bir sayaç artırıyor. Böylece
"15 → 5 komut/tur" iddiası disassembly'den **tahmin** edilmiyor,
çalıştırılarak ölçülüyor:

```
baseline  300.000.011  = 15,0 / tur
rotate    280.000.012  = 14,0 / tur
peephole  200.000.011  = 10,0 / tur
full      100.000.010  =  5,0 / tur
```

Sayaç kendi başına yavaşlatır; zamanlama ayrı (sayaçsız) ikiliden alınır.

## Ölçüm Aşama 5'teki hatamı buldu

Aşama 5'te "değer taşımada tek erişim" diye 64-bit hedeflerde slot
kopyalamayı tek `movq`'ya indirmiştim. Gerekçem: bellek işlemi sayısı
4'ten 2'ye düşüyor. **Ölçüm tersini söyledi:**

```
x86_64  VCOPY = movq   (8 bayt)     208 ms
x86_64  VCOPY = movl   (2 × 4 bayt) 134 ms      ← %35 daha hızlı
i386    (zaten hep 2 × 4 bayt)      139 ms
```

Sebep: slot 8 bayt yazılıp hemen ardından `+4` ofsetinden 4 bayt
okunuyor (`ADD_SETG`, `JLT`, `INDEX` ...). Store-to-load forwarding
cezalanıyor. **Daha az bellek işlemi ≠ daha hızlı.**

Bu aynı zamanda "i386 neden x86_64'ten hızlı?" sorusunun cevabı:
i386 hızlı değildi, **x86_64 benim tarafımdan yavaşlatılmıştı.**
Düzeltmeden sonra ikisi aynı hizaya geldi.

AArch64'te aynı sorun olabilir — `OPT_VCOPY64=0` anahtarı orada da var
ama bu ortamda **ölçülemedi**, tahminle değiştirilmedi.

## Düzeltilmiş sonuçlar (medyan, 10 tekrar)

**loop20m** — 20.000.000 tur, tamsayı aritmetiği

| varyant | x86_64 | i386 | dağıtım |
|---|---|---|---|
| baseline | 282,0 ms | 287,4 ms | 300 M |
| rotate | 277,0 ms | 277,2 ms | 280 M |
| peephole | 228,1 ms | 219,3 ms | 200 M |
| **full** | **132,6 ms** | **138,0 ms** | **100 M** |
| kazanç | **%53** | **%52** | **%67 daha az dağıtım** |

**fib(27)** — çağrı ağırlıklı, ~700 K çağrı

| varyant | x86_64 | i386 | dağıtım |
|---|---|---|---|
| baseline | 9,64 ms | 10,00 ms | 6.991.834 |
| **full** | **9,08 ms** | **9,24 ms** | **5.084.971** |
| kazanç | %6 | %8 | %27 daha az dağıtım |

**empty** — yalnız başlangıç (lex + parse + derle): **0,22 ms**.
Yani loop20m ölçümünde derleme maliyeti %0,2'nin altında.

Dikkat çeken: fib'de dağıtım %27 azalıyor ama süre yalnız %6 azalıyor.
Çağrı ağırlıklı iş yükünde darboğaz dağıtım değil, çerçeve kurma/çözme.
Süperkomutlar oraya dokunmuyor — beklenen ve doğru davranış.

## Donanım sayaçları: ÖLÇÜLEMEDİ

Bu ortamda `perf` yok. Harness bunu **açıkça raporluyor**, tahmin
üretmiyor:

```
perf : YOK -> donanım sayaçları OLCULEMEDI (tahmin edilmiyor)
```

`perf` bulunan bir makinede aynı komut cycles / instructions / branches /
branch-misses / cache-misses ve IPC raporlar. Özellikle 15 → 5 geçişinin
dolaylı dallanma tahminine etkisini görmek için gerekli.

## i386 x86_64'te nasıl çalışıyor

Ayrı emülatör gerekmiyor: 64-bit Linux çekirdeği 32-bit ELF'i doğrudan
çalıştırır ve ikilimiz statik + libc'siz olduğu için `ia32-libs` gibi bir
bağımlılık yok. Harness her iki mimariyi de yerel olarak ölçüyor.

---

# Aşama 9: Bytecode Metadata Consistency Pass

## Rapor

```
optimizasyon    : metadata consistency pass (doğruluk, hız değil)
iş yükü         : demo + tüm benchmark programları, 4 varyant × 2 mimari
baseline        : optimizer sonrası hiçbir doğrulama yok
optimize        : her derlemede otomatik doğrulama + hata varsa yürütme iptal
delta (süre)    : ~0,04 ms derleme başına — ölçüm gürültü sınırında
VM dispatch     : değişmedi (çalışma anını etkilemiyor)
bytecode delta  : değişmedi
donanım sayaçları: ÖLÇÜLEMEDİ (perf yok)
doğruluk        : 8 varyant × mimari kombinasyonunda 0 hata;
                  kasıtlı bozma her ikisinde de yakalandı
```

## Neden gerekliydi

Gözetleme deliği kodu sıkıştırınca atlama işlenenleri yeniden eşleniyordu
ama **fonksiyon giriş noktaları** derleyicinin yazdığı eski indekste
kalıyordu. `CALL` çöp adrese sıçrıyor, program çöküyordu. Küçük testlerde
görünmüyordu çünkü orada birleşme hep gövdeden *sonra* oluyordu.

Artık kod indeksi ya da tablo indeksi tutan her alan denetleniyor.

## Ne denetleniyor

Denetim **tablo güdümlü**: `op_opkind[]` her işlem kodunun işlenen alanının
ne anlama geldiğini söylüyor (`gen_tables.py` üretiyor).

| işlenen türü | denetim |
|---|---|
| `OPK_CODE` | atlama hedefi < komut sayısı |
| `OPK_CONST` | sabit indeksi < havuz boyu |
| `OPK_GLOBAL` | küresel yuva < tanımlı küresel sayısı |
| `OPK_LOCAL` | yerel yuva < MAX_LOCALS |
| `OPK_GG/LL/GC/LC/CG` | paketli iki işlenen, ikisi de ayrı denetlenir |
| fonksiyon tablosu | `g_fns[i].entry` < komut sayısı |

Ayrıca her komutun işlem kodu `OP_COUNT`'tan küçük mü kontrol ediliyor.

`break`/`devam`/`yoksa` hedefleri ayrı alan değil — atlama işleneni
olarak zaten kapsanıyor. Kapanış girişi, istisna işleyicisi ve switch
tablosu **henüz yok**; geldiklerinde `verify_meta`'ya birer döngü
eklenmeli, yeri yorumla işaretlendi.

## Instruction boundary denetimi neden yok

Sabit 4-baytlık komut kodlaması sayesinde indeksler **komut numarası**,
bayt ofseti değil. "Hedef komut ortasına düşmüş" hatası kodlama
seçimiyle baştan imkânsız. Değişken uzunluklu kodlamaya geçilirse bu
denetim eklenmeli.

## Hata bulunca ne oluyor

Yürütme **iptal ediliyor**. Kanıtlanmış bozuk bytecode'u çalıştırmak
çöküş üretir; temiz tanı daha değerli:

```
dogrulama HATASI: fonksiyon girisi kod disinda @ fonksiyon 0
bytecode dogrulamasi basarisiz - yurutme iptal
```

Öncesinde aynı durum `Bus error` veriyordu.

## Denetleyicinin kendisi test edildi

**Hiç ateşlenmeyen bir denetleyici, test edilmemiş denetleyicidir.**
`-DTEST_CORRUPT=1` derlemesi `g_fns[0].entry`'yi bilerek bozuyor;
regression test bunun yakalandığını ve çökme olmadığını doğruluyor.

## Regression testleri

```bash
tests/verify.sh
```

1. Dört varyant × iki mimarinin hepsinde doğrulama 0 hata veriyor mu
2. Kasıtlı bozma yakalanıyor ve yürütme iptal ediliyor mu
3. **VCOPY varyantları aynı çıktıyı üretiyor mu** — bu deney
   "daha az bellek işlemi = daha hızlı" varsayımını çürüten ölçümün
   kaynağı; korunması istendi, artık davranış eşdeğerliği test altında

## Maliyet

Doğrulama derleme anında O(komut sayısı) çalışıyor. Boş programda
ölçülen fark 0,23 ms → 0,19 ms; standart sapma 0,10 olduğu için bu
**gürültü sınırında**, anlamlı bir maliyet ölçülemedi.
`-DOPT_VERIFY=0` ile kapatılabilir ama varsayılan açık.

---

# Aşama 10: CALL/RET Profili — ve bir sessiz doğruluk hatası

## Önce: çağrı derinliği taşması (sessiz yanlış cevap)

Derin özyineleme mikrobenchmark'ını yazmadan önce sınırlara baktım.
`MAX_FRAMES = 64` idi ve **sınır denetimi yoktu**. `g_nframe`,
`g_frames`'in hemen ardında duruyor; 65. çerçeve doğrudan sayacın
üzerine yazıyordu.

Sonuç çökme değildi — **sessizce yanlış cevaptı**:

```
fonk f(n) { eğer n <= 0 { döndür 0 }  döndür 1 + f(n - 1) }

beklenen: f(10)=10  f(60)=60  f(63)=63  f(64)=64  f(70)=70  f(200)=200
alınan  :       10        60        63        10        16         38
```

x86_64 ve i386'da birebir aynı (deterministik bozulma). Çöken bir program
hata verir; yanlış cevap veren program vermez. Bu yüzden bu sınıf daha
tehlikeli.

**Düzeltme:** `op_call` içinde çerçeve itmeden önce iki denetim —
çağrı derinliği ve değer yığını taşması. `MAX_FRAMES` 64 → 1024
(8 KB, önemsiz). Artık:

```
f(1000) -> 1000
f(5000) -> calisma hatasi: cagri derinligi asildi
```

Denetimlerin maliyeti `op_call` başına iki karşılaştırma; profil
tablosunda ölçülebilir bir fark yaratmadı.

## Profil: darboğaz çerçeve kurma DEĞİL

```
x86_64                 medyan    dağıtım/çağrı   ns/çağrı
çağrı yok (taban)      9,87 ms         -            -
0 argümanlı           23,80 ms       5,00          7,0
1 argümanlı           24,96 ms       5,00          7,5
3 argümanlı           27,77 ms       7,00          9,0
1 arg + 2 yerel       37,03 ms       9,00         13,6
derin özyineleme      29,59 ms       6,01          9,8
```

Kritik hesap:

```
taban döngü : 9,87 ms / 6.000.008 dağıtım = 1,65 ns/dağıtım
çağrı yolu  : 13,93 ms / 10.000.003 ek dağıtım = 1,39 ns/dağıtım
```

**CALL/RET dağıtım başına daha ucuz.** Çerçeve kurma/çözme darboğaz
değil. Maliyet, bir çağrının en az **5 dağıtım** gerektirmesi:

```
GETGLOBAL f ; CALL 0 ; POP ; CONST 0 ; RET
```

Argüman taşıma maliyeti de **sıfır**: argümanlar zaten yığındaki yerinde
kalıyor, `VF` doğrudan oraya kuruluyor, kopyalama yok.

Bu, "çağrı ağırlıklı iş yükünde darboğaz dağıtım dışında" varsayımını
**desteklemiyor**. Aksine doğru hamle dağıtım azaltmak.

## RETL / RETK — ölçümün önerdiği hamle

| örüntü | süperkomut |
|---|---|
| `GETLOCAL n; RET` | `RETL n` |
| `CONST k; RET` | `RETK k` |

Dar kurallar (Aşama 0), açgözlü değil. `op_ret` ortak bir kuyruğa
çevrildi; üç giriş noktası da sonucun adresini hesaplayıp aynı çerçeve
çözme koduna dalıyor.

## Rapor

```
optimizasyon    : RETL / RETK (dönüş yolu süperkomutları)
iş yükü         : bench/programs/call_*.al + fib(27)
donanım sayaçları: ÖLÇÜLEMEDİ (perf yok)
doğruluk        : tests/run.sh + tests/verify.sh geçti (8 varyant × 2 mimari,
                  doğrulama 0 hata, kasıtlı bozma yakalandı)
```

| durum | önce | sonra | delta | dağıtım/çağrı | ns/çağrı |
|---|---|---|---|---|---|
| 0 argümanlı | 23,80 ms | 21,37 ms | **−10,2%** | 5,00 → 4,00 | 7,0 → 5,8 (−17%) |
| 1 argümanlı | 24,96 | 22,71 | −9,0% | 5,00 → 4,00 | 7,5 → 6,4 (−15%) |
| 3 argümanlı | 27,77 | 26,63 | −4,1% | 7,00 → 6,00 | 9,0 → 8,4 (−7%) |
| 1 arg + 2 yerel | 37,03 | 33,70 | −9,0% | 9,00 → 8,00 | 13,6 → 11,9 (−12%) |
| derin özyineleme | 29,59 | 28,83 | −2,6% | 6,01 → 6,01 | 9,8 → 9,5 (−3%) |
| **fib(27)** | **9,08** | **8,62** | **−5,1%** | dağıtım −6,3% | |

Derin özyinelemede dağıtım değişmedi (`döndür 1 + f(n-1)` → `ADD; RET`,
kural yok) ama %2,6 hızlandı — bu gürültü sınırında, anlamlı sayılmamalı.

Kabul kriteri sağlandı: her çağrı biçiminde ölçülebilir kazanç var,
regression yok.

## Bir sonraki adım için not

`ADD; RET` → `RET_ADD` gibi ek füzyonlar mümkün ama komut çoğaltmanın
sınırı var. Ölçüm önerisi: önce **`CALL; POP`** birleştirmesi — deyim
seviyesindeki her çağrıda bir dağıtım daha. Tek engel, sonucun atılacağı
bilgisinin çerçevede taşınması gerekmesi (`op_call` iterken, `op_ret`
dönerken). Yapılabilir ama çerçeve biçimini değiştiriyor; ayrı ölçülmeli.

## Yeni mikrobenchmark'lar

```
bench/programs/call_none.al   çağrısız taban döngü
bench/programs/call_0.al      0 argümanlı çağrı
bench/programs/call_1.al      1 argümanlı çağrı
bench/programs/call_3.al      3 argümanlı çağrı
bench/programs/call_loc.al    1 argüman + 2 yerel
bench/programs/call_deep.al   derinlik 500 özyineleme

python3 bench/callprof.py            # çağrı başına maliyet tablosu
```

---

# Aşama 11: Constant Interning — ve üç sessiz taşma hatası

## Rapor

```
optimizasyon    : sabit havuzu iç içe geçirme (interning / dedup)
iş yükü         : bench/programs/manyconst.al (300 tekrarlı literal + 2M turluk sıcak döngü)
donanım sayaçları: ÖLÇÜLEMEDİ (perf yok)
doğruluk        : tests/run.sh + tests/verify.sh geçti
```

| metrik | interning YOK | interning VAR | delta |
|---|---|---|---|
| sabit havuzu | 305 | **8** | −97% |
| bytecode | 407 komut | **312** | −23% |
| VM dağıtımı | 18.000.401 | **8.000.310** | −56% |
| süre x86_64 | 23,10 ms | **13,77 ms** | **−40%** |
| süre i386 | 22,12 ms | **15,80 ms** | **−29%** |

Sıcak döngü **9 → 4 dağıtım/tur**.

## Hipotez doğrulandı

Aşama 8'de "süperkomut kapsamını kısan şey değişken yuvası değil,
**sabit havuzu indeksi**" demiştim. Ölçüm doğruladı: 300 sabitin ardından
gelen sıcak döngünün literalleri 256'yı aşıyor ve `INCGLOBAL` /
`GETG_CONST` füzyonları ateşlenemiyor. Interning havuzu 8'e indirince
indeksler tekrar düşük aralığa giriyor ve füzyon çalışıyor.

**Ama demo programında kapsam hiç değişmedi** (süperkomut 15, getgc 9,
addk 2 — ikisinde de aynı). Çünkü orada indeksler zaten 256'nın
altındaydı. Yani interning küçük programlarda yalnız havuzu küçültüyor,
hızı değiştirmiyor. Bunu ayrıca ölçmeden "hızlandırdı" demek yanlış olurdu.

## Maliyet: O(n²) tarama

| durum | interning YOK | interning VAR | delta |
|---|---|---|---|
| demo (14 tekrarlı sabit) | 0,64 ms | 0,65 ms | gürültü içinde |
| 700 **benzersiz** sabit (en kötü) | 0,77 ms | 1,17 ms | +0,40 ms |

En kötü durumda derleme %52 yavaşlıyor ama mutlak fark 0,4 ms. Havuz
binlerce girdiye çıkarsa ilk-bayt kovalı bir hash gerekir; şimdilik
gereksiz. `-DOPT_INTERN=0` ile kapatılabilir.

## `superk` metriği yanıltıcıydı — düzeltme

İlk ölçümde interning **kapalıyken** süperkomut sayısı daha yüksek
çıktı (350 vs 304) ve bu "interning kapsamı düşürüyor" gibi göründü.
Sebep: sayaç *kapsam oranı* değil **örnek sayısı** sayıyor. Kapalıyken
toplam komut da fazla (407 vs 312), dolayısıyla füzyon örneği de fazla.
Doğru metrik bytecode boyutu ve dağıtım sayısı — ikisi de interning
lehine. Metriği okurken `komut` satırıyla birlikte değerlendirmek gerekiyor.

## Yol boyunca bulunan üç sessiz taşma

Derin özyinelemedeki çerçeve taşmasıyla **aynı sınıf**: sınır denetimi
yok, sonuç çökme değil sessiz bellek bozulması.

| kaynak | sınır | denetimsiz davranış |
|---|---|---|
| token dizisi | 4096 | parser dizinin dışına taşıyor → segfault |
| düğüm arenası | 8192 | komşu belleğe düğüm yazılıyor |
| bytecode tamponu | 8192 | komşu belleğe komut yazılıyor |
| sabit havuzu | 8192 | komşu belleğe sabit yazılıyor |

Hepsine denetim eklendi. Token dizisinde ayrıca kritik bir ayrıntı vardı:
**sadece durmak yetmiyor.** Parser `TOK_EOF` nöbetçisini arayarak
ilerliyor; nöbetçi yazılmazsa dizinin dışına taşıyor. Artık son yuvaya
zorla EOF yazılıp kaynak sonlandırılıyor.

```
2000 deyim (token sınırını aşıyor) : temiz hata, rc=1   (önce segfault)
700 deyim (sığıyor)                : 245350 = sum(1..700)  ✓
```

## Kendi hatam: A0 ezme

`emit_tok`'un başına sınır denetimini koyarken `A0`'ı ezdim — oysa A0
token türünü taşıyordu. Sonuç: **her token tipi çöp oldu**, en basit
program bile "satır 1: beklenmeyen sözcük" verdi.

n=50, n=100, n=700 hepsi aynı şekilde çöktüğü için önce "boyut sorunu"
sandım; boyutla ilgisi olmadığını görünce doğru yere baktım. Diğer üç
denetimde argümanlar zaten slota dökülmüş olduğu için aynı hata orada
yoktu — kontrol ettim.

Ders: bir fonksiyonun başına kod eklerken argüman registerlarının hâlâ
canlı olduğunu unutmamak. i386'daki `RV == A0` çakışmasıyla akraba bir
tuzak.

## Yeni benchmark programı

```
bench/gen_manyconst.py > bench/programs/manyconst.al
```

300 tekrarlı literal + sıcak döngü. Sabit havuzu indeksinin füzyonu
nasıl tıkadığını gösteren deterministik iş yükü; regression olarak
saklanmalı.

---

# Aşama 12: Tamsayı Taşması — sarmak yerine hata

## Neden `tanım64` değil

Öneri: 64-bit değerler için `tanim64`, `metin64` gibi son ekli anahtar
kelimeler; gerekçe i386'da taşma önlemi.

Önce bir düzeltme: **32-bit sınır i386'dan gelmiyor.** Değer slotu
`{u32 etiket, u32 yük}` ve bu **her iki mimaride de aynı** — x86_64'te
de tamsayılar 32 bit. Aşama 3'teki tasarım kararı, mimari kısıt değil.

Üç itiraz:

1. **Uygulama ayrıntısını dile sızdırır.** `tanim64`, programcıya
   "VM'in yük alanı 32 bit" bilgisini öğrenmeye zorlar.
2. **Taşmayı önlemez, erteler.** `tanim64` 2⁶³'te taşar. Amaç önlemse
   doğru araçlar: taşmada hata fırlatmak veya bignum'a terfi.
3. **Komut setini ikiye katlar.** Her aritmetiğin `_64` varyantı ya da
   çalışma anında genişlik denetimi — hem de sıcak döngüde.

`metin64` ise olmayan bir sorunu çözer: dizgi uzunluğu zaten `u32`,
yani 4 GB sınır.

**Fikrin haklı olduğu yer:** OS geliştirme için `u8/u16/u32/u64`
zorunlu — MMIO register'ları ve sayfa tablosu girdileri sabit genişlik
ister. Orada açık genişlik kusur değil, gereklilik.

**Sentez önerisi:** anahtar kelime varyantı değil **tip notasyonu** —
`tanim x: u64 = 5`. Aynı bilgi, integer specialization'ın (`ADD_II`)
ihtiyaç duyduğu tip kanıtının ta kendisi. Tek mekanizma, iki fayda.

## Şimdi yapılan: taşmada hata fırlatma

Asıl derdin (taşma önlemi) için ucuz ve doğrudan çözüm. Son üç aşamada
avladığımız "sessiz yanlış cevap" sınıfının bir üyesi daha:

```
yazdir 2000000000 + 2000000000  ->  calisma hatasi: tamsayi tasmasi
tanim x = 100000  yazdir x * x  ->  calisma hatasi: tamsayi tasmasi
t = t + i  (100.000 tur)        ->  calisma hatasi: tamsayi tasmasi
```

Önceden hepsi sessizce sarıyordu.

### Nasıl

İşlem bilerek **32-bit bayrak üreten** biçimde yapılıyor: 64-bit
registerda 64-bit toplama yapılırsa 32-bit taşma görülmez.

```
x86_64/i386 : addl / subl / negl / imull  +  jo
aarch64     : adds / subs / negs          +  b.vs
              smull ile 64-bit çarpım, sonra sxtw ile karşılaştırma
arm32       : adds / subs / rsbs          +  bvs
              smull + cmp rhi, rlo asr #31
```

Çarpımda `smull` bayrak üretmediği için tam çarpım hesaplanıp 32-bite
işaret genişletilmiş haliyle karşılaştırılıyor.

Bağlanan 10 nokta: `ADD SUB MUL NEG ADDK SUBK ADD_SETG ADD_SETL
ADDK_SETG INCGLOBAL`.

## Rapor

```
optimizasyon    : tamsayı taşması denetimi (doğruluk, hız değil)
iş yükü         : loop20m (5 dağıtım/tur, aritmetik yoğun)
VM dispatch     : değişmedi (100.000.012)
bytecode        : değişmedi
donanım sayaçları: ÖLÇÜLEMEDİ (perf yok)
doğruluk        : tests/run.sh + tests/verify.sh geçti
```

| | denetim KAPALI | denetim AÇIK | delta |
|---|---|---|---|
| x86_64 | 153,57 ms | 160,26 ms | **+4,4%** |
| i386 | 152,92 ms | 153,55 ms | +0,4% (std 7,2 — gürültü içinde) |

x86_64'te %4,4 ölçülebilir maliyet; i386'da fark gürültünün altında.
Aritmetik yoğun bir iş yükünde bile tek haneli. `-DOPT_OVFCHK=0` ile
kapatılabilir ama **varsayılan açık** — sessiz yanlış cevap, %4,4'ten
pahalıdır.

## Benchmark'ın kendisi taşıyormuş

`loop20m.al` şuydu:

```
iken i < 20000000 { toplam = toplam + i  i = i + 1 }
```

Toplam ≈ 2×10¹⁴, 32-bit'e sığmıyor. Program sessizce `1642668640`
üretiyordu ve bunu Aşama 5'ten beri benchmark olarak kullanıyorduk.
Taşma denetimi eklenince ortaya çıktı.

Yeni sürüm komut karışımını **aynen** koruyor (GETGLOBAL2 + ADD_SETG +
INCGLOBAL + GETG_CONST + JLT = 5 dağıtım/tur) ama taşmıyor:

```
tanim bir = 1
iken i < 20000000 { toplam = bir + bir  i = i + 1 }
```

Dağıtım sayısı doğrulandı: 100.000.012 — eskisiyle birebir aynı.

## Eksik: girdi yok

Doğru tespit. Şu an dil hiçbir şey okuyamıyor. Gereken:

| iş | maliyet |
|---|---|
| konsol girdisi (`oku()`) | düşük — `os_read` **zaten var**, 9 hedefte yazılmış, hiç kullanılmamış |
| metin dosyası | orta — HAL'e `os_open`/`os_close` eklemek gerekir (9 hedef × 2 fonksiyon) |
| ikili dosya | orta-yüksek — etiketli değer dizisi değil, **bayt tamponu** nesne türü (`O_BUF`) gerekir |

Sıra önerim: önce `oku()` (HAL zaten hazır), sonra `O_BUF` + dosya G/Ç.
`O_BUF` ikili dosya, dizgi kodlaması ve ileride MMIO için ortak temel.

---

# Aşama 13: Konsol Girdisi

## Önce bir düzeltme

Aşama 12'de "`os_read` zaten var, 9 hedefte yazılmış, hiç kullanılmamış"
demiştim. **Yanlıştı.** Aşama 0'da HAL tasarımında listelemişim ama
yalnızca `os_write` / `os_alloc` / `os_exit` uygulanmış. Gerçek maliyet
9 hedefe `os_read` yazmaktı:

| | syscall / API |
|---|---|
| Linux x86_64 / i386 / aarch64 / arm | `0` / `3` / `63` / `3` |
| macOS x86_64 / aarch64 | `0x2000003` / `x16 = 3` |
| Windows ×3 | `ReadFile` + `GetStdHandle(-10)` → `g_handles[0]` |

`g_handles[0]` daha önce kullanılmıyordu; artık stdin.

## Tamponlu okuma

`os_read` blok okur, satır değil. Bayt başına bir syscall doğru ama
yavaş olurdu (4 KB'lik satır = 4096 syscall). 4 KB'lik tampon
bosaldıkça dolduruluyor.

```
100.000 satır okuma: 9 ms
```

Kritik ayrıntı: `os_read` hata durumunda `-errno` döner. **İşaretsiz
karşılaştırılırsa devasa pozitif görünür** ve EOF hiç algılanmaz.
Karşılaştırma işaretli (`BLE`).

## Yeni gövde fonksiyonları

| Türkçe | English | döndürür |
|---|---|---|
| `oku()` | `read()` / `input()` | satır (dizgi), EOF'ta `boş` |
| `sayi(s)` | `num(s)` | tamsayı, çözülemezse `boş` |

```
yazdir "adin ne?"
tanim ad = oku()
yazdir "merhaba, " + ad + "!"
tanim y = sayi(oku())
yazdir "gelecek yil " + yazi(y + 1) + " olacaksin"
```

```
$ printf 'Mehmet\n41\n' | ./build/linux-x86_64
adin ne?
merhaba, Mehmet!
kac yasindasin?
gelecek yil 42 olacaksin
```

## `sayi("abc")` önce 0 dönüyordu

İlk uygulamada rakam bulunamayınca `0` dönüyordu — tam da son dört
aşamada avladığımız **sessiz yanlış cevap** sınıfı. Kullanıcı girdisi
söz konusu olduğunda özellikle tehlikeli: `sayi(oku())` kullanıcı
saçmaladığında sessizce 0 üretirdi.

Artık hiç rakam okunmazsa `boş` dönüyor:

```
sayi("")        -> bos        sayi("-7")     -> -7
sayi("   ")     -> bos        sayi("0042x")  -> 42
sayi("-")       -> bos        sayi("  -123abc") -> -123
sayi("abc")     -> bos        sayi(5)        -> bos   (dizgi degil)
```

CR (`\r`) atılıyor, yani CRLF'li girdi sorunsuz: `"ilk satir\r\n"` →
uzunluk 9.

## Test altyapısı düzeltmesi

`tests/check_expand.sh` yanlış alarm veriyordu: `.ascii "  addk  : "`
metnindeki "add" komut sanılıp "stringify kazası" raporlanıyordu.
Gerçek bir yanlış pozitif — veri satırları artık dışlanıyor.

Ayrıca tüm testler `< /dev/null` ile çalışıyor, çünkü demo artık girdi
okuyor ve testler stdin'de asılı kalmamalı.

## Rapor

```
optimizasyon    : yok (yeni yetenek)
iş yükü         : 100.000 satır okuma = 9 ms (tamponlu)
donanım sayaçları: ÖLÇÜLEMEDİ (perf yok)
doğruluk        : tests/run.sh + tests/verify.sh + check_expand.sh geçti,
                  x86_64 ↔ i386 çıktıları birebir aynı
```

## Hâlâ eksik

| iş | gereken |
|---|---|
| metin dosyası | HAL'e `os_open` / `os_close` (9 hedef × 2) |
| ikili dosya | **bayt tamponu** nesne türü `O_BUF` — etiketli değer dizisi ham bayt için uygun değil |
| dosyaya yazma | `os_write` var, yalnız fd yönetimi gerekiyor |

`O_BUF` ikili G/Ç, dizgi kodlaması ve ileride MMIO için ortak temel;
tek başına bir aşamayı hak ediyor.

---

# Aşama 14: Metin Dosyası G/Ç

## Kapsam kararı

`oku()` fd 0'a ve tek küresel tampona bağlı. Rastgele dosya tanıtıcıları
için dosya başına tampon, yani bir `O_FILE` nesne türü gerekirdi. Bunun
yerine **bütün-dosya** API'si seçildi:

```
yazf(yol, metin)   ->  doğru / yanlış
dosya(yol)         ->  dosyanın tamamı dizgi olarak, hata: boş
```

Aç-oku-kapat tek çağrıda olduğu için dosya tanıtıcısı nesnesi gerekmiyor.
İngilizce adlar: `write(...)`, `readfile(...)`.

```
tanim ok = yazf("/tmp/a.txt", "merhaba dosya\nikinci satir\n")   -> dogru
tanim icerik = dosya("/tmp/a.txt")
yazdir uzunluk(icerik)                                          -> 27
yazdir dosya("/tmp/yok")                                        -> bos
yazdir yazf("/kok/izin/yok.txt", "x")                           -> yanlis
```

## HAL'e iki fonksiyon (9 hedef)

| | open | close |
|---|---|---|
| Linux x86_64 / i386 / aarch64 / arm | `openat` 257 / 295 / 56 / 322 | 3 / 6 / 57 / 6 |
| macOS x86_64 / aarch64 | `0x2000005` / `x16=5` | `0x2000006` / `x16=6` |
| Windows ×3 | `CreateFileA` | `CloseHandle` |

**`openat` bilinçli tercih:** aarch64 Linux'ta `open` syscall'i **yok**,
yalnız `openat` var. `openat(AT_FDCWD, ...)` dört mimaride de çalışıyor,
tek kod yolu.

Windows'ta `CreateFileA` HANDLE döndürür, fd değil. `g_handles`
8 yuvaya çıkarıldı; açık dosya yuva 3'e konuyor. **Aynı anda tek dosya** —
bütün-dosya API'si için yeterli, sınır belgelendi.

## Dizgiler artık NUL ile bitiyor

`open()` C dizgisi ister. `str_new` artık veri sonuna açıkça `0` yazıyor;
`heap_alloc` zaten uzunluk+1 bayt ayırdığı için bu bayt sınırlar içinde.
Yan fayda: dizgiler C API'lerine doğrudan verilebilir — Windows
`CreateFileA` ve ileride bare-metal katmanı için de gerekli.

## Sabit tampon, bilinçli

`FILE_BUF_SIZE = 64 KB`. Büyüyen tamponla `str_concat` zinciri O(n²)
olurdu; sabit sınır öngörülebilir. Aşan dosya kırpılıyor.

Test sırasında sınırların tutarsız olduğu ortaya çıktı: demo yığını da
64 KB'ydi, 64 KB'lik tek parça dizgi sığmıyordu. Sonuç **çökme değil
temiz hata** oldu (`yigin doldu`) — Aşama 11'de eklenen sınır
denetimlerinin karşılığı. Demo yığını 1 MB'a çıkarıldı.

## Rapor

```
optimizasyon    : yok (yeni yetenek)
iş yükü         : yazma + geri okuma, 6000 baytlık dosya, 100 KB kırpma
donanım sayaçları: ÖLÇÜLEMEDİ (perf yok)
doğruluk        : tests/run.sh + verify.sh + check_expand.sh geçti,
                  x86_64 ↔ i386 çıktıları birebir aynı,
                  hata yolları (yok dosya / izin yok) doğru
```

## Girdi/çıktı durumu

| iş | durum |
|---|---|
| konsol girdisi `oku()` | ✅ tamponlu, 100 K satır / 9 ms |
| dizgi → sayı `sayi()` | ✅ çözülemezse `boş` |
| metin dosyası okuma/yazma | ✅ bütün-dosya API'si |
| ikili dosya | ❌ **bayt tamponu `O_BUF` gerekiyor** |
| birden fazla açık dosya | ❌ `O_FILE` nesne türü gerekiyor |

`O_BUF` hâlâ tek başına bir aşama: ham bayt dizisi, ikili G/Ç, dizgi
kodlaması ve ileride MMIO için ortak temel.

---

# Aşama 15: Sınır Denetimi — "güvenli mi?" sorusuna ölçümle cevap

## Soru

"Tampon limiti kaç, güvenli mi?" — iddia etmek yerine test ettim.
**Beşi de güvenli değildi.**

| test | önce | sonra |
|---|---|---|
| 8000 baytlık dizgi değişmezi | 8000 döndü, `g_strbuf` 4096 → **taşma** | kırpılır, hata, yürütme iptal |
| 200 `kır` (MAX_BREAKS 64) | sessiz → **taşma** | `cok fazla kir/devam` |
| 40 iç içe döngü (MAX_LOOPS 16) | sessiz → **taşma** | `dongu ic ice gecme sinirin asti` |
| 300 küresel (MAX_GLOBALS 256) | 299 döndü → **taşma** | `cok fazla kuresel degisken` |
| 3000 iç içe parantez | rc=116, **makine yığını** taştı | derinlik sınırı, yürütme iptal |

Aşama 11'de dört tabloyu (token, düğüm, bytecode, sabit) denetlemiştim
ama bu beşi gözden kaçmıştı. Ders: **denetimi tablo tablo değil,
envanter çıkarıp topluca yapmak gerekiyor.**

## Parser özyinelemesi farklı bir sınıf

Diğerleri bizim tablolarımızdı; bu **makine yığını**. Kendi
denetimlerimiz yakalamaz. `MAX_PARSE_DEPTH = 200` eklendi; sınıra
gelince hata verilip bir token tüketiliyor (ilerleme garantisi).

## Bir de gerçek bir dil hatası çıktı

Sınır testi yazarken `s = s + s` denedim — **"tür uyuşmazlığı"** verdi.

`ADD_SETG` süperkomutu (Aşama 7) `op_add`'in yerini alıyor ama yalnızca
tamsayı yolunu taşıyordu. `op_add`'in **dizgi birleştirme** yolu
kopyalanmamıştı. Yani:

```
yazdir "a" + "b"      çalışıyordu   (PRINT, füzyon yok)
tanim s = "a" + "b"   çalışıyordu   (DEFGLOBAL, füzyon yok)
s = s + s             BOZUKTU       (ADD + SETGLOBAL_P → ADD_SETG)
```

Aşama 7'den beri var, hiçbir test yakalamamış — demo programında
birleştirme hep `yazdir` içindeydi. `ADD_SETL` de aynı şekilde bozuktu.

**Ders:** bir süperkomut, yerini aldığı komutun **bütün** yollarını
taşımak zorunda. Yeni füzyon eklerken kontrol listesi: kaynak komutun
kaç dalı var, hepsi taşındı mı?

`tests/verify.sh`'e regresyon testi eklendi.

## Çıkış kodu 0/1

Program hata **sayısını** döndürüyordu; 136 hata → rc=136 ve bu
`128+sinyal` ile karışıyordu. Test betiği çökme sanıyordu. Artık
0 (temiz) veya 1 (hata var).

## Yeni: derleme hatası varken yürütme yok

Sözcük/ayrıştırma/derleme hatası varsa VM hiç çalıştırılmıyor. Bozuk
kaynaktan üretilen bytecode'u çalıştırmak, hatanın üzerine anlamsız bir
çalışma hatası yığıyordu (3000 parantez → "cagrilabilir degil").

## Güncel sınır tablosu

| kaynak | sınır | aşılırsa |
|---|---|---|
| dizgi değişmezi | 4000 bayt | kırpılır + hata |
| token | 4096 | EOF nöbetçisi + hata |
| AST düğümü | 8192 | hata |
| bytecode | 8192 komut | hata |
| sabit havuzu | 8192 | hata |
| küresel değişken | 256 | hata |
| yerel değişken (kapsam) | 64 | hata |
| `kır` / `devam` (döngü başına) | 64 | hata |
| iç içe döngü | 16 | hata |
| fonksiyon | 1024 | hata |
| ayrıştırıcı derinliği | 200 | hata |
| çağrı derinliği | 1024 | çalışma hatası |
| değer yığını | 64 KB | çalışma hatası |
| nesne yığını | 1 MB (ana program belirler) | çalışma hatası |
| tutamak | 4096 nesne | çalışma hatası |
| dosya okuma | 64 KB | kırpılır |
| konsol satırı | 4000 bayt | kırpılır |

**Hiçbiri sessiz bozulma üretmiyor.** Doğrulaması:

```bash
tests/limits.sh     # 8 sınır durumu, hepsi rc=1 + açık ileti
```

## Rapor

```
optimizasyon    : yok (doğruluk)
iş yükü         : tests/limits.sh (8 durum)
donanım sayaçları: ÖLÇÜLEMEDİ (perf yok)
doğruluk        : run.sh + verify.sh + limits.sh + check_expand.sh geçti
                  x86_64 ↔ i386 birebir aynı
```

---

# Aşama 16: Güvenlik — Kanarya + Fuzzer

## Sorun

Son iki denetimde **beş taşma buldum, ikisini de ancak elle arayarak**.
Bu yöntem ölçeklenmiyor: her yeni kod yeni delik açabilir ve gözle
tarama er geç kaçırır.

İki yapısal önlem, sırası önemli:

## 1. Kanarya — sessiz bozulmayı gürültülü hataya çevirir

Her sabit tampona `GUARD_PAD = 16` bayt fazla ayrılıyor, sonuna
`0x7E57C0DE` yazılıyor, dört kontrol noktasında doğrulanıyor
(sözcük / ayrıştırma / derleme / yürütme sonrası).

**Taşmayı önlemez.** Ama Aşama 15'te gördüğümüz "8000 baytlık dizgi
4096'lık tampona sessizce sığdı" durumunu artık şuna çevirir:

```
GUARD BOZULDU: g_strbuf (kontrol noktasi 1)
```

20 tampon korunuyor: `g_strbuf g_inbuf g_filebuf g_stack g_gvals
g_frames g_loc g_gname g_fns g_loopst g_loopbb g_loopcb g_brk g_cont
g_objs g_hfree g_map g_tgt g_numbuf g_chbuf`.

Kanaryanın kendisi test edildi: `-DTEST_GUARD=1` bilerek bozuyor,
ateşlediği doğrulandı. **Hiç ateşlenmeyen bir denetleyici test
edilmemiş demektir** — bu kural artık üçüncü kez işe yaradı.

Maliyet: 20 × 16 = 320 bayt BSS, çalışma zamanında sıfır (kontrol
noktaları dört kez, program başına). `loop20m` 136 ms — ölçüm
gürültüsü içinde.

## 2. Fuzzer — elle bulunamayanı bulur

```bash
python3 tests/fuzz.py --n 60 --seed 1            # x86_64
python3 tests/fuzz.py --n 40 --seed 7 --arch i386
```

Üretim: rastgele token çorbası + geçerli tohum programların mutasyonu
(bayt çevirme, silme, parça çoğaltma, sözcük ekleme, derin iç içe
parantez). **Determinist** — `--seed` ile sonuçlar yeniden üretilebilir.

Başarısızlık ölçütü (hepsi gözlemlenebilir, tahmin yok):

- sinyalle ölüm (`rc >= 128`)
- zaman aşımı
- `GUARD BOZULDU` — kanarya ihlali
- `dogrulama HATASI` — bozuk bytecode üretildi
- 0/1 dışında çıkış kodu

Derleme hatası, çalışma hatası ve sınır aşımı **başarı** sayılıyor —
bozuk girdide temiz şikâyet doğru davranıştır.

Başarısız girdi bulunca satır satır küçültülüp `tests/fuzz-fail-*.al`
olarak kaydediliyor.

**Sonuç: 135 durum (3 tohum × 2 mimari), 0 başarısız.**

## Kanaryanın ilk bulduğu şey

Kanaryaları bağlar bağlamaz demo programı `hata : 1` verdi (önce 0'dı).
Sebep kanarya değildi — özet çıktısı sayesinde görülen gerçek bir hata:

```
nesne  : 4096      ← tutamak tablosu doldu
gc turu: 0         ← ama GC hiç calismadi
```

Aşama 14'te dosya tamponu için yığını 64 KB → 1 MB çıkarmıştım. GC
**yalnızca yığın alanı dolunca** tetikleniyordu; yığın büyüyünce
tutamaklar önce bitiyor ve `heap_alloc` sessizce hata veriyordu.

Düzeltme: tutamak tükendiğinde de GC çalışıyor. Tutamaklar da yığın
alanı gibi geri kazanılabilir bir kaynak — ikisi ayrı ayrı tetikleyici
olmalı.

**Ders: bir kaynağın sınırını büyütmek, ona bağlı diğer kaynakların
dengesini bozar.** Sınırlar birlikte gözden geçirilmeli.

## Bugünkü tehdit modeli — dürüst değerlendirme

Şu an güvenilmeyen girdi yalnızca `oku()` ve `dosya()` içeriği; kaynak
program derleme anında gömülü. Yani saldırı yüzeyi dar.

**Player mimarisine geçildiğinde bu değişecek:** `.bc` dosyası
güvenilmeyen girdi olacak ve `verify_meta` bir hata ayıklama aracı
değil **güvenlik sınırı** hâline gelecek. Aşama 9'da yazdığımız pass
(atlama hedefi, sabit/küresel/yerel indeksi, fonksiyon girişi, işlem
kodu geçerliliği) tam da bunun için gerekli. Erken yapılmış olması
şans değil, doğru sıralamaydı.

## Rapor

```
optimizasyon    : yok (güvenlik/doğruluk)
iş yükü         : fuzz 135 durum, limits 8 durum, verify 12 durum
çalışma maliyeti : ölçülemedi (gürültü içinde) — loop20m 136 ms
bellek maliyeti  : 320 bayt BSS
donanım sayaçları: ÖLÇÜLEMEDİ (perf yok)
doğruluk        : run.sh + verify.sh + limits.sh + check_expand.sh +
                  fuzz.py hepsi geçti, x86_64 ↔ i386 birebir
```

## Sırada ne var (güvenlik ekseninde)

| iş | değer |
|---|---|
| `mprotect` ile gerçek koruma sayfası | kanaryadan güçlü: taşma anında yakalanır, sonradan değil |
| `-static-pie` varsayılan (ASLR) | 0 yer değiştirme kaydımız var, bedava |
| sürekli fuzzing (uzun koşu, çok tohum) | asıl kazanç sayıda |
| `.bc` doğrulayıcısını sertleştirmek | player mimarisi için ön koşul |

---

# Aşama 17: Tür Özelleşmesi — motoru yazmadan tavanı ölçmek

GPT'nin listesinde 4-6. maddeler: statik tür çıkarımı, `ADD_II`
özelleşmesi, quickening. Motoru yazmadan önce **kazancın tavanını**
ölçtüm: bütün tür denetimlerini kaldıran (güvensiz, yalnız ölçüm için)
bir varyant.

## Ölçüm

```
                    denetimli   DENETIMSIZ    tavan
loop20m x86_64      133,76 ms   122,80 ms     %8,2
loop20m i386        131,94 ms   126,11 ms     %4,4
fib     x86_64       10,49 ms    10,01 ms     %4,6
```

`-DOPT_TYPECHK=0` ile üretiliyor. Bu **tavan** — gerçek özelleşme
bunun altında kalır, çünkü:

1. Çıkarım yalnızca **kanıtlanabilen** yerlerde ateşlenir. Hot loop'taki
   `toplam` ve `i` global; türlerini kanıtlamak için değişken bazlı
   sabit-nokta analizi gerekir ve her atama kanıtı bozabilir.
2. `ADD_II` **süperkomut füzyonlarını bozar.** `ADD_SETG` yerine
   `ADD_II` üretilirse füzyon zinciri kopar — ki füzyonlar %53 kazanç
   sağlamıştı, özelleşmenin tavanı %8. Füzyonları korumak için
   `ADD_SETG_II`, `INCGLOBAL_II`, `JLT_II`, `ADDK_SETG_II`... gerekir:
   **komut seti neredeyse iki katına çıkar.**

## Karar: yapılmıyor

GPT'nin kendi kuralı: *"Eğer ölçülebilir kazanım yoksa veya
correctness/regression riski varsa değişiklik zorunlu olarak kabul
edilmesin."* Tavan %8, gerçek kazanç muhtemelen %3-5, bedeli komut
setinin iki katına çıkması ve her yeni füzyonun iki varyantta
sürdürülmesi.

Madde 4, 5, 6 **ertelendi**. Ölçüm dosyada duruyor; koşullar değişirse
(örneğin tip notasyonu `tanim x: u64` eklenirse çıkarım bedava gelir)
yeniden bakılır.

Bu, "motoru yaz sonra ölç" yerine "ölç sonra yazma" örneği — birkaç
yüz satır assembly ve kalıcı bir bakım yükü tasarruf edildi.

## Yolda: kendi eklediğim güvenlik regresyonu

Tavanı ölçerken static-pie denedim ve **bağlanmadı**:

```
warning: relocation in read-only section `.rodata'
read-only segment has dynamic relocations
```

Sebep Aşama 16'da eklediğim **kanarya tablosu**: `.rodata`'da mutlak
adres tutuyordu. Aşama 2'den beri koruduğumuz **"sıfır yer değiştirme
kaydı"** değişmezini kendi eklemem kırmıştı.

Bu değişmez tali bir detay değil:
- Android/Termux'ta PIE zorunlu olabiliyor
- İleride çekirdek imajı istediği adrese yüklenebilmeli
- ASLR için gerekli

**Düzeltme:** tablo `.bss`'e alındı ve `guard_init` tarafından
PC-göreli `LEA_SYM` ile **çalışma anında** dolduruluyor. Statik veride
tek bir mutlak adres kalmadı.

```
static-pie reloc : 0   ✅
no-pie     reloc : 0   ✅
```

**Ders:** korunan bir değişmez teste bağlı değilse er geç kırılır.
`tests/verify.sh`'e beşinci test eklendi: static-pie bağlanıyor mu,
0 reloc mu, çalışıyor mu.

## static-pie maliyeti (ASLR)

```
no-pie      154,53 ms   (std 1,71)
static-pie  156,97 ms   (std 10,98)
```

Fark %1,6 ama static-pie ölçümünün standart sapması 10,98 — yani
**anlamlı bir fark ölçülemedi**. Varsayılanı değiştirmek için daha
kararlı bir ortamda tekrar ölçmek gerekir; şimdilik `-static -no-pie`
varsayılan kalıyor, static-pie test altında ve elle seçilebilir.

**i386'da static-pie çalışmıyor:** `LEA_SYM` orada `movl $sym, reg`
(mutlak adres). PIC yapmak GOT/EBX düzeni gerektirir — ayrı bir iş.

## Rapor

```
optimizasyon    : yok (ölçüm sonucu ERTELENDI)
iş yükü         : loop20m + fib, OPT_TYPECHK=1 vs 0
tavan           : %8,2 (x86_64) / %4,4 (i386) / %4,6 (fib)
gerçek beklenen : %3-5, komut seti iki katı bedeliyle
donanım sayaçları: ÖLÇÜLEMEDİ (perf yok)
doğruluk        : run.sh + verify.sh (5 test) + limits.sh + fuzz(30) geçti
                  sıfır reloc değişmezi artık test altında
```

## GPT listesinin durumu

| # | iş | durum |
|---|---|---|
| 1 | benchmark harness | ✅ Aşama 8 |
| 2 | hardware counters | ⚠️ perf yok — dağıtım sayacıyla ikame edildi |
| 3 | integer specialization | ❌ **ölçüldü, ertelendi** (tavan %8) |
| 4 | local-slot optimization | ⏸ ölçüm gerekli; hot loop global kullanıyor |
| 5 | TOS caching | ⏸ sıradaki aday |
| 6 | hot-slot allocation | ❌ darboğaz yuva değil sabit havuzuydu; interning çözdü |
| 7 | yeni süperkomutlar | ✅ Aşama 7, 10 |
| 8 | string/object optimizasyonu | ⏸ |
| 9 | OS/bare-metal | ⏸ player mimarisiyle birlikte |

---

# Aşama 18: Yönlendirme Savunması (control-flow hijack)

Kanarya **tespit** eder, sonradan. Soru şuydu: taşmanın kontrolü ele
geçirmesini **engelleyemez miyiz?** Sistemi bu gözle denetledim ve
**üç gerçek primitif** buldum.

## 1. `optable` taşması — en ciddisi, düzeltmesi bedava

```
NEXT:  and w24, INS, #0xff     ← opcode 0..255
       ldrsw x24, [x25, x24, lsl #2]
```

Opcode 8 bite maskeleniyordu ama tabloda **55 girdi** vardı.
55-255 arası bir opcode tablonun dışını okuyup `.text`'ten çöp offset
alıyor ve **keyfî adrese sıçrıyordu**. Bozuk bytecode ya da bellek
bozulması bunu tetikleyebilirdi.

**Düzeltme: tabloyu 256'ya doldur**, boş yuvalar `op_bad`'e gitsin.

```
.rept 256 - OP_COUNT
.long op_bad - SYM(optable)
.endr
```

**Çalışma zamanı maliyeti sıfır** — ek denetim yok, geçersiz opcode
doğal olarak temiz hataya gidiyor. 1 KB `.text`. Aynı düzeltme
`nat_fns` için de yapıldı (gövde indeksi bir sabitin yükünden geliyor
ve doğrulayıcı yük *değerini* denetlemiyordu).

## 2. `SET_PC` sınırsızdı

Altı çağrı yerinde atlama hedefi doğrudan `g_code + idx*4` oluyordu.
Derleme anında `verify_meta` denetliyor ama **çalışma anındaki**
bozulmaya karşı savunma yoktu. `MAX_CODE` sabit olduğu için tek
karşılaştırma yeterli.

## 3. `obj_ptr` tutamak denetimi yoktu — en güçlü veri primitifi

```
obj_ptr(h):  g_objs[h]  →  isaretci  →  dereference
```

Sınır denetimi yoktu. Bozuk bir tutamak `g_objs` dışından **işaretçi
okuyup dereference ediyordu**: keyfî okuma/yazma.

Düzeltme: `h < MAX_OBJS` ve boş yuva denetimi. Geçersizse **0 değil,
sıfırlanmış kukla nesne** dönüyor — çünkü bazı çağıranlar sonucu
denetlemeden dereference ediyor; sıfır nesne "tür 0" görünüp
çağıranın kendi tür denetimine takılıyor. Null dereference yok.

## Doğrulama: saldırganın elde edeceğini taklit et

Derleme sonrası bytecode kasıtlı bozuluyor (`-DTEST_HIJACK=n`):

| test | bozma | sonuç |
|---|---|---|
| 1 | opcode 200 (tablo dışı) | `gecersiz islem kodu`, rc=1 |
| 2 | `JMP 60000` (kod dışı) | `atlama hedefi kod disinda`, rc=1 |
| 3 | tutamak 999999 | `tur uyusmazligi`, rc=1 |

Üçü de iki mimaride, **çökme yok, kontrol devri yok**.
`tests/verify.sh`'e 5. test olarak eklendi.

## Maliyet — aynı oturumda A/B

Farklı oturumlarda ölçmek yanıltıcı (bu dersi bir kez almıştık), o
yüzden `-DOPT_CFI=0/1` ile aynı koşuda:

| iş yükü | savunmalı | savunmasız | delta |
|---|---|---|---|
| loop20m x86_64 | 153,60 ms | 152,21 ms | +0,9% |
| loop20m i386 | 155,00 | 153,46 | +1,0% |
| fib x86_64 | 10,17 | 9,95 | +2,2% |

**%1-2.** `optable` doldurması bundan bağımsız ve tamamen bedava.

Keyfî kod çalıştırma primitifini %1-2'ye kapatmak açık ara iyi bir
takas. Varsayılan açık; `OPT_CFI=0` yalnız ölçüm içindir.

## Güvenlik durumu — dürüst özet

| katman | durum |
|---|---|
| kod işaretçisi tabloları yazılabilir mi | ❌ hepsi `.text` / `.rodata` |
| tablo dışına indeksleme | ✅ 256'ya doldurma ile imkânsız |
| PC kod tamponu dışına | ✅ sınır denetimi |
| tutamak → keyfî işaretçi | ✅ sınır denetimi + kukla nesne |
| tampon taşması tespiti | ✅ kanarya (20 tampon, 4 kontrol noktası) |
| kaynak sınırları | ✅ 15 sınır, hepsi temiz hata (`tests/limits.sh`) |
| tamsayı taşması | ✅ hata fırlatır |
| ASLR | ⚠️ static-pie çalışıyor (0 reloc) ama varsayılan değil; i386'da yok |
| W^X / NX | ⚠️ ölçülmedi, `-z noexecstack` eklenmeli |
| gerçek koruma sayfası (mprotect) | ❌ kanaryadan güçlü olurdu, yapılmadı |
| fuzzing | ✅ 165 durum, 0 başarısız |

**Bugünkü tehdit modeli:** güvenilmeyen girdi yalnız `oku()` ve
`dosya()` içeriği; kaynak derleme anında gömülü. Saldırı yüzeyi dar.

**Player mimarisinde değişecek:** `.bc` güvenilmeyen girdi olacak.
O zaman bu üç savunma zorunlu hâle gelir — `verify_meta` yükleme
denetimi, `optable` doldurması tablo taşmasına karşı, `obj_ptr`
denetimi bozuk tutamaklara karşı. Player'a geçmeden bunların hepsinin
yerinde olması iyi oldu.

## Rapor

```
optimizasyon    : yok (güvenlik)
iş yükü         : loop20m + fib, OPT_CFI=1 vs 0 aynı oturumda
maliyet         : %0,9 (loop20m x86_64), %1,0 (i386), %2,2 (fib)
                  optable/nat_fns doldurması: sıfır
donanım sayaçları: ÖLÇÜLEMEDİ (perf yok)
doğruluk        : run + verify(6 grup) + limits(8) + fuzz(30) + expand geçti
```

---

# Aşama 19: Yerel Erişim Optimizasyonu — ve ölçüm yönteminin kendisi

GPT'nin listesinde madde 5: `INCLOCAL`, `ADDLOCAL`, `ADDLOCAL_SETLOCAL`
gibi komutlarla yerel değişken sıcak yolunu hızlandırmak.

## Önce soru: yerel erişim küreselden gerçekten pahalı mı?

```
op_getglobal:                op_getlocal:
  GETOPD(A0W)                  GETOPD(A0W)
  SHLI(A0, 3)                  SHLI(A0, 3)
  LEA_SYM(A1, g_gvals)   ←     ADD(A0, VF)
  ADD(A0, A1)                  VPUSH(A0, A1)
  VPUSH(A0, A1)
```

**Tek fark bir `LEA_SYM`.** Yerel, tabanı (`VF`) zaten registerdan
alıyor. Yani "yerel daha hızlı" avantajının tamamı bu tek komut.

Ve **`VC` — Aşama 0'da sabit havuzu için ayırdığım sanal register —
VM'de hiç kullanılmıyordu** (0 referans). Yani komut çoğaltmadan,
küresel tabanını registera koyarak aynı kazanç alınabilirdi.

Uyguladım (`GVALS`/`GCONSTS` makroları, x86_64'te `VC`=r14 ve
`VK`=r8, aarch64'te x22/x27; i386'da boş register yok).

## Ölçüm: kazanç yok

```
60M tur, CPU zamanı, 20 tekrar (x86_64)
  registerli   466,78 ms   (min 458,65)
  LEA ile      468,88 ms   (min 458,43)
  fark %0,45 — gürültünün altında
```

**Varsayılan kapatıldı.** Mekanizma duruyor ama `VC` ve `VK` serbest —
TOS caching bu iki registeri istiyor ve beklenen kazancı daha büyük.
Ölçülemeyen bir iyileştirme için kıt kaynağı harcamak yanlış takas.

**GPT madde 5 böylece çözülüyor:** yerel ile küresel arasındaki tüm
fark tek bir LEA ve o bile ölçülemiyor. `INCLOCAL`/`ADDLOCAL` daha az
kazandırırdı, karşılığında komut seti büyürdü. **Yapılmıyor.**

## Asıl bulgu: ölçüm yöntemi bozuktu

A/B ölçümünde i386 tarafında %3,3 fark göründü. Ama i386'da `HAVE_VC`
tanımlı değil — **iki ikili aynı kodu çalıştırıyordu.** Yani o %3,3
tamamen gürültüydü.

Duvar saati bu paylaşımlı konteynerde güvenilmez. Harness **CPU
zamanına** çevrildi (`getrusage(RUSAGE_CHILDREN)` farkı):

```
                     duvar saati    CPU zamanı
std (60M koşu)       67,78 ms       6,12 ms
```

Gürültü 11 kat azaldı. Kalan taban gürültü ~%1-2 — yani **bu ortamda
%2'nin altındaki hiçbir iyileştirme doğrulanamaz.** Bu, ne
deneyeceğimizi de belirliyor: marjinal optimizasyonlar burada
kanıtlanamaz, ölçülebilir olan işlere odaklanmak gerekiyor.

Önceki aşamaların sayıları duvar saatiyle alınmıştı; büyük farklar
(%40-53) gürültünün çok üstünde olduğu için geçerliliğini koruyor.
Küçük farklar (VCOPY %35 gibi) da öyle. Ama %1-3 aralığındaki
sonuçlara (static-pie, CFI maliyeti) CPU zamanıyla tekrar bakılmalı.

## TOS caching için register basıncı (GPT madde 6, adım 3)

Kod yazmadan yapılan analiz:

| mimari | VP/VS/VF | kullanılan | boş | TOS için |
|---|---|---|---|---|
| x86_64 | rbx r12 r13 | r15(INS) | r8 r9 r14 | **3 — rahat** |
| aarch64 | x19 x20 x21 | x24(INS) | x22 x27 x28 | **3 — rahat** |
| arm32 | r4 r5 r6 | r10(INS) | r8 | **1** |
| i386 | esi edi ebx | — | ebp* | **1** (ebp `.bss`'e taşınırsa) |

TOS caching iki register ister (etiket + yük).

**Sonuç: tam TOS caching yalnız 64-bit hedeflerde mümkün.** 32-bit'te
ya tek register (yalnız yük, etiket bellekte) ya da hiç.

Bu, projede ilk kez VM'i mimariye göre gerçekten ayrıştırmak demek.
Yapılacaksa bilinçli yapılmalı ve önce 64-bit'te prototiplenip
ölçülmeli — çünkü %2'nin altında çıkarsa hiç yapmamak gerekir.

## Rapor

```
optimizasyon    : taban registeri (ÖLÇÜLDÜ, VARSAYILAN KAPALI)
                  GPT madde 5 (INCLOCAL/ADDLOCAL) YAPILMADI
iş yükü         : 60M tur, CPU zamanı, 20 tekrar
sonuç           : %0,45 — gürültü tabanının (%1-2) altında
harness         : duvar saati -> CPU zamanı, gürültü 11 kat azaldı
donanım sayaçları: ÖLÇÜLEMEDİ (perf yok)
doğruluk        : run + verify + limits(8) + fuzz(25) + expand geçti
```

Bu üst üste **ikinci "ölç, yapma"** sonucu (önceki: integer
specialization). Yöntemin işlediğinin göstergesi — yazılmayan her
satır, bakılmayacak bir bakım yükü.

---

# Aşama 20: TOS Caching — vekil ölçümle karar

TOS caching'e girmeden önce şu şüphe vardı: **süperkomutlarımız TOS'un
kazancını zaten yemiş olabilir mi?** Çünkü füzyonlar ara yığın
trafiğinin çoğunu kaldırdı.

Doğrudan TOS yazmak ~50 işleyiciyi yeni bir değişmeze göre yeniden
yazmak demek. Önce **vekil ölçüm**: aynı deyimin yığın trafiğini
**tamamen** kaldıran bir süperkomut yazıp bakalım.

## ACCG — `gvals[a] += gvals[b]`, yığına hiç dokunmaz

`GETGLOBAL2(a,b) + ADD_SETG(c)` → `ACCG(a,b)` (yalnız `c == a` iken).
`x = x + y` birikimi yaygın bir desen, uydurma bir örnek değil.

```
accum.al (20M tur, CPU zamanı, 15 tekrar)
  x86_64   159,04 -> 141,91 ms   %10,8
  i386     158,13 -> 137,19 ms   %13,2
  dağıtım  100.000.012 -> 80.000.012  (%20 az)
```

## Bu TOS caching için ne anlama geliyor

ACCG bu deyimin yığın trafiğinin **tamamını** kaldırdı ve %11-13
kazandırdı. Ama bu kazancın büyük kısmı **dağıtım azalmasından**
(5→4, yani %20) geliyor, yığın trafiğinden değil.

TOS caching:
- dağıtım sayısını **hiç** azaltmaz
- yalnız en üst değerin bellek gidiş-gelişini kaldırır
- ve `pop-pop` desenlerinde TOS'u bellekten **yeniden doldurmak**
  gerekir, yani kazancın bir kısmını geri verir

Sıcak döngümüzün deseni tam da `push-push / pop-pop`:

```
GETGLOBAL2   push push     ← TOS: yine 2 depolama + 2 yükleme, kazanç yok
ADD_SETG     pop pop       ← TOS: 2 yükleme kazanır, ama sonra TOS'u
                             bellekten yeniden doldurmak gerekir
GETG_CONST   push push     ← kazanç yok
JLT          pop pop       ← aynı takas
```

**Sonuç: TOS caching bu VM'de yapılmıyor.** Beklenen kazanç %2'lik
ölçüm tabanının altında, bedeli ~50 işleyicinin yeniden yazılması ve
32-bit hedeflerde mimari ayrışma (register analizi: i386 ve arm32'de
iki register yok).

Üst üste **üçüncü "ölç, yapma"** kararı. Ama bu sefer yan ürün olarak
gerçek bir optimizasyon çıktı: **ACCG kalıyor**, %11-13 ölçüldü.

## Yolda: beşinci kez `RV == A0`

i386'da dizgi birleştirme `[]` üretti (boş dizi). Sebep:

```
CALL(str_concat)      ; RV = yeni tutamak
FILL(A0, 5)           ; x86_64: %rdi ← slot   RV(%rax) sağlam
                      ; i386:   %eax ← slot   RV YOK OLDU
ST32_OFF(A0, VAL_PAY, RVW)   ; adresi payload olarak yazdı
```

x86_64'te `RV=%rax` ve `A0=%rdi` **ayrı**; i386'da **ikisi de `%eax`**.
Bu yüzden hata yalnız i386'da çıkıyor ve x86_64 testleri temiz görünüyor.

Bu tuzağa **beşinci kez** düşüldü (Aşama 4, 11, 13, 15, 20). Artık
statik denetim var:

```bash
tests/lint.sh
```

Deseni tarıyor: `CALL(...)` → `FILL/MOVI/LEA_SYM/MOVR(A0, ...)` →
`RV` kullanımı. Beş vakanın hepsi bu desendi.

## Rapor

```
optimizasyon    : ACCG (KABUL EDILDI), TOS caching (REDDEDILDI)
iş yükü         : bench/programs/accum.al, 20M tur, CPU zamanı, 15 tekrar
ACCG kazancı    : %10,8 (x86_64) / %13,2 (i386)
dağıtım         : 100.000.012 -> 80.000.012 (%20 az)
TOS beklentisi  : ölçüm tabanının (%2) altında -> yapılmadı
donanım sayaçları: ÖLÇÜLEMEDİ (perf yok)
doğruluk        : run + verify(6 grup) + limits(8) + fuzz(25) + lint geçti
                  ACCG'nin üç dalı da test altında (dizgi/tamsayı/tür hatası)
```

## GPT listesinin son durumu

| # | iş | sonuç |
|---|---|---|
| 1 | benchmark harness | ✅ + CPU zamanına geçirildi |
| 2 | hardware counters | ⚠️ perf yok; dağıtım sayacı ikame |
| 3 | integer specialization | ❌ ölçüldü, tavan %8, ertelendi |
| 4 | local-slot optimization | ❌ ölçüldü, %0,45, yapılmadı |
| 5 | TOS caching | ❌ vekil ölçüldü, yapılmadı |
| 6 | hot-slot allocation | ❌ darboğaz sabit havuzuydu, interning çözdü |
| 7 | yeni süperkomutlar | ✅ ACCG dahil |
| 8 | string/object optimizasyonu | ⏸ sıradaki |
| 9 | OS/bare-metal + player | ⏸ hedef |

Üç reddin üçü de ölçümle. Kalan tek performans ekseni: dağıtım sayısını
azaltmak — ki ACCG bunu bir kez daha doğruladı. Bundan sonraki gerçek
sıçrama artımlı değil mimari olur (copy-and-patch JIT), ve o da player
mimarisiyle aynı temele oturuyor.

---

# Aşama 21: Dizgi Optimizasyonu — ölçüm nereyi gösterdi

GPT'nin 8. maddesi: string/object optimizasyonu. Yine tahmin etmeden,
önce **üç ayrı iş yükü** ölçüldü:

```
is yuku   sure       dagitim      ns/dagitim   GC turu
alloc     23,66 ms   1.600.010     ~15         97
strcat    53,93 ms      40.012   ~1350         30
strcmp     3,36 ms   2.100.014      ~1,6        0
```

Bu tablo her şeyi söylüyor:

- **`strcmp` normal hızda** (1,6 ns/dağıtım). Dizgi karşılaştırma
  darboğaz **değil** — yani GPT'nin de gündeme getirdiği "string
  interning ile `==`'i O(1) yapmak" **gereksiz.**
- **`strcat` dağıtım başına 1350 ns** — normalin ~800 katı. Bütün
  maliyet birleştirmenin **kopyalamasında**.
- `alloc` ise ayırma + GC ağırlıklı (97 GC turu).

## Sebep: bayt bayt kopyalama

`str_concat` `mem_copy_b` kullanıyordu ve o fonksiyon i386 uyumu için
sayacı çerçeve slotunda tutuyordu:

```
mcb_loop:
    FILL(A2, 0)      ← bayt basina bir YUKLEME
    BZ / DEC
    SPILL(0, A2)     ← bayt basina bir SAKLAMA
    LDB / STB / 2x ADDI
```

**Bayt başına ~6 işlem.**

## Düzeltme: iki aşamalı kopyalama

Kaynak ve hedef ikisi de `OBJ_DATA` ofsetinde başlıyor (8 hizalı), yani
büyük kısım **kelime kelime** kopyalanabilir:

```
parça 1: len1 & ~3 bayt  → mem_copy   (4 bayt/adım)
         len1 &  3 bayt  → mem_copy_b (artık)
parça 2: len2 bayt       → mem_copy_b (hedef ofseti hizasız olabilir)
```

`str_concat` bu arada baştan yazıldı — ilk denemem slot çakışmasıyla
bozuktu ve `"abc" + "de"` boş nesne üretiyordu. Kenar durumlar test
edildi: boş sol, boş sağ, hizasız uzunluk, döngüde birikim.

## Ölçüm

```
is yuku          bayt      kelime    kazanc
strcat x86_64   54,30 ms   15,53 ms   %71,4
strcat i386     54,40 ms   13,36 ms   %75,4
alloc  x86_64   23,70 ms   23,65 ms   %0,2
alloc  i386     23,20 ms   22,70 ms   %2,2
```

**3,5-4 kat hızlanma** birleştirme ağırlıklı iş yükünde.

`alloc`'ta fark yok — ve bu **doğru** sonuç: orada dizgiler kısa
(ortalama 7 bayt), maliyet ayırma ve GC'de. Kelime kopyalama yalnız
uzun dizgilerde önemli. Tek iş yükü ölçülseydi yanlış sonuca varılırdı.

## Yapılmayanlar ve neden

| aday | karar |
|---|---|
| dizgi interning (`==` O(1)) | ❌ `strcmp` zaten normal hızda, darboğaz değil |
| yerinde ekleme (`s = s + x` mutasyonla) | ❌ değer semantiğini bozar: `b = a; a = a + "y"` sonrası `b` değişirdi. Güvenli yapmak referans sayımı ister |
| rope / lazy concat | ❌ karmaşık; O(n²) sabiti 4 kat düştü, asıl sorun kalmadı |

`s = s + "x"` döngüsü hâlâ O(n²) — ama sabiti 4 kat küçüldü ve gerçek
çözüm (yerinde ekleme) değer semantiğini bozuyor. Dürüst durum: bu
desen pahalı kalıyor, dilin belgelenmiş bir sınırı.

## Rapor

```
optimizasyon    : str_concat kelime kelime kopyalama
iş yükü         : strcat (8000 birikim), alloc (200K kisa dizgi), strcmp
kazanç          : %71,4 (x86_64) / %75,4 (i386) — strcat
                  %0,2 / %2,2 — alloc (beklenen: dizgiler kisa)
                  strcmp'e dokunulmadi (zaten normal)
donanım sayaçları: ÖLÇÜLEMEDİ (perf yok)
doğruluk        : run + verify(6) + limits(8) + fuzz(25) + lint + expand geçti
                  kenar durumlar: bos sol/sag, hizasiz uzunluk, dongude birikim
```

---

# Aşama 22: `O_BUF` — Ham Bayt Tamponu

İkili dosya G/Ç, dizgi kodlaması ve ileride MMIO'nun ortak temeli.
Üçünü birden açtığı için tek başına bir aşamayı hak ediyordu.

## Neden yeni bir nesne türü

Dizi (`O_ARR`) 8 baytlık **etiketli değer** tutuyor — 256 baytlık bir
dosya 2 KB yer kaplar ve her eleman GC taramasına girer. Dizgi
(`O_STR`) değiştirilemez. İkili veri için ikisi de yanlış.

`O_BUF`: ham bayt dizisi, **değiştirilebilir**, içinde tutamak yok
(GC yalnızca taşır, taramaz).

## Sözdizimi — yeni operatör yok

Mevcut `[]` sözdizimi kullanılıyor; `op_index` ve `op_setidx`'e birer
dal eklendi:

```
tanim b = tampon(8)      // 8 bayt, sıfırlanmış
b[0] = 72
b[1] = 105
yazdir b[0]              → 72
yazdir uzunluk(b)        → 8
yazdir metin(b)          → "Hi" + 6 sıfır bayt
yazdir b                 → <tampon 8>
yazdir b[8]              → calisma hatasi: dizi sinirlari disinda
```

`b[i]` tamsayı döndürür (0-255), `b[i] = v` yalnız düşük baytı yazar.

## Gövde fonksiyonları

| Türkçe | English | işlev |
|---|---|---|
| `tampon(n)` | `buffer(n)` | n baytlık sıfırlanmış tampon |
| `ikili(yol)` | `readbin(path)` | ikili dosyayı tampon olarak oku |
| `yazikl(yol, t)` | `writebin(path, b)` | tamponu dosyaya yaz |
| `metin(t)` | `tostr(b)` | tamponu dizgiye çevir |

`uzunluk()` zaten `OBJ_LEN` okuduğu için tamponlarda da çalışıyor.

## İkili dosya turu

```
tanim b = tampon(256)
iken i < 256 { b[i] = i  i = i + 1 }
yazikl("/tmp/x.dat", b)      → dogru
tanim c = ikili("/tmp/x.dat")
uzunluk(c)                   → 256
c[0] c[128] c[255]           → 0 128 255
b == c                       → dogru
```

Dosya gerçekten 256 bayt, ilk baytlar `0 1 2 3 4 5 6 7`, son baytlar
`252 253 254 255`. **Tüm 256 bayt değeri** dosyadan geçiyor — NUL dahil.

`==` içerik karşılaştırıyor: `obj_eq` artık "aynı tür ve O_STR ya da
O_BUF ise içerik" kuralında. Diziler hâlâ tutamak eşitliğiyle
karşılaştırılıyor (derin karşılaştırma ayrı bir karar).

## İki hata, ikisi de sessiz

**1. `NT(6, NAT_RDB, "ikili")`** — "ikili" **5** harf. Uzunluk ön
elemesi tutmayınca ad çözülmüyor, `ikili` tanımsız küresele düşüyor ve
`ikili(...)` "cagrilabilir degil" veriyordu. Tablo doğru ama veri
yanlış — tabloların en sinsi hatası.

**2. `op_index` yaması sessizce uygulanmadı.** Python `replace`
eşleşmeyince hata vermez, sessizce hiçbir şey yapmaz. Kontrol için
`grep -c idx_buf` yaptım ve "2" gördüm — ama o **`sidx_buf`'un alt
dizisiydi**. İki yanlış üst üste gelince "uygulandı" sandım.

Ders: alt dize sayan bir kontrol, kontrol değildir. Doğrusu
`grep '^idx_buf:'` — çapa ile.

## Rapor

```
optimizasyon    : yok (yeni yetenek)
iş yükü         : 256 baytlık ikili dosya gidiş-dönüş, indeks, eşitlik
donanım sayaçları: ÖLÇÜLEMEDİ (perf yok)
doğruluk        : run + verify(7 grup) + limits(8) + fuzz(25) +
                  lint + expand geçti, x86_64 ↔ i386 birebir
```

## Girdi/çıktı durumu

| iş | durum |
|---|---|
| konsol girdisi | ✅ tamponlu |
| metin dosyası | ✅ bütün-dosya API'si |
| **ikili dosya** | ✅ **`O_BUF` ile** |
| birden fazla açık dosya | ❌ `O_FILE` gerekir |
| dizgi ↔ tampon | ✅ `metin()` (tek yön; `tampona()` henüz yok) |

## Kalan yol haritası

| iş | durum |
|---|---|
| bare-metal katmanı (`src/os/bare/os.S`) | temel hazır: 0 reloc, HAL soyut, yığın dışarıdan |
| player mimarisi (`.bc` + gömülü yürütücü) | cepte; `verify_meta` ön koşulu hazır |
| copy-and-patch JIT | tek kalan büyük performans sıçraması |

---

# Aşama 23: Bare-Metal Katmanı

Aşama 0'da kurduğumuz L1 soyutlamasının sınavı: **işletim sistemi
olmadan aynı dil, aynı VM.** Diğer ~9700 satıra dokunulmadı; yalnızca
`src/os/bare/os.S` (240 satır) ve bir bağlayıcı betiği eklendi.

```bash
./build.sh bare-x86_64
LOAD_ADDR=0x40000000 ./build.sh bare-aarch64
```

## HAL karşılıkları

| fonksiyon | bare-metal karşılığı |
|---|---|
| `os_write` | UART (x86: 16550 port 0x3F8, ARM: PL011 MMIO) |
| `os_read` | UART yoklamalı; veri yoksa 0 (EOF gibi) |
| `os_alloc` | bağlayıcıdan gelen 4 MB bölgede itme (bump) ayırıcı |
| `os_exit` | `cli; hlt` / `wfi` döngüsü |
| `os_open` / `os_close` | dosya sistemi yok → −1 |

Giriş: `_start` → yığın kur → **`.bss` sıfırla** → `lang_main` → `os_exit`.

`.bss` sıfırlama kritik: barındırılan yapıda bunu çekirdek yapıyordu.
Bare-metal'de atlanırsa bütün sayaçlar ve tablolar çöp değerle başlar —
sessiz ve tespiti zor bir hata sınıfı. `_start` bunu açıkça yapıyor.

## Doğrulama — ve ne DOĞRULANMADI

```bash
tests/bare.sh
```

| denetim | x86_64 | i386 |
|---|---|---|
| hiç `syscall`/`int $0x80` komutu yok | ✅ | ✅ |
| 0 yer değiştirme kaydı | ✅ | ✅ |
| çözülmemiş dış sembol yok (libc yok) | ✅ | ✅ |
| `_start`, `_heap_start/end`, `_stack_top`, `__bss_start/end` | ✅ | ✅ |
| dinamik bağımlılık yok | ✅ | ✅ |

Dört mimarinin makro genişletmesi de doğrulandı (`check_expand.sh`).

**ÇALIŞTIRILMADI.** Bu ortamda emülatör yok. Koşu doğrulaması sende:

```bash
qemu-system-x86_64 -kernel build/bare-x86_64 -nographic
qemu-system-aarch64 -M virt -cpu cortex-a53 -kernel build/bare-aarch64 -nographic
```

Statik denetimler "OS bağımsız mı" sorusunu cevaplıyor; "doğru
çalışıyor mu" sorusunu **cevaplamıyor**. Bunu ayırt etmek önemli.

## Boyut

```
bare-x86_64   71.136 bayt dosya   38.749 bayt .text
bare-i386     57.564 bayt         32.234 bayt
linux-x86_64  71.416 bayt         (karşılaştırma)
```

Barındırılan sürümle neredeyse aynı — çünkü fark yalnızca HAL. Dilin
tamamı (lexer, parser, derleyici, gözetleme deliği, doğrulayıcı, VM,
GC, dizgi/dizi/tampon, kanarya) **39 KB kodda**.

## Sınırlar

- Girdi bloklamıyor: `oku()` bare'de veri yoksa hemen `boş` döner.
  Gerçek bir çekirdekte burası kesme sürücüsüne bağlanır.
- Dosya sistemi yok: `dosya()` / `ikili()` `boş`, `yazf()` `yanlış`.
- Bellek 4 MB sabit; sayfalama, MMU, kesme yok.
- x86_64 imajı 32-bit korumalı kip/long mode geçişini **yapmıyor** —
  `-kernel` ile QEMU'nun multiboot yükleyicisi gerektirir ya da bir
  önyükleyici. Gerçek donanımda ek kurulum gerekir.

Bunlar eksiklik değil kapsam: HAL katmanının tuttuğunu göstermek
içindi ve tuttu.

## Rapor

```
optimizasyon    : yok (yeni platform)
eklenen         : src/os/bare/os.S (240 satır) + image.ld
değişen         : yalnızca config.inc (OS_BARE) ve build.sh
dokunulmayan    : ~9700 satır — L1 soyutlamasının karşılığı
doğrulama       : tests/bare.sh 10 denetim, check_expand 4 mimari
ÇALIŞTIRMA      : YAPILMADI (emülatör yok) — açıkça raporlanıyor
```

---

# Aşama 24: Bytecode Dosyası (.bc) ve Yürütücü

Player mimarisinin ilk yarısı: derleyici `.bc` üretir, ayrı bir
**yürütücü** okur ve çalıştırır.

```bash
# derle + kaydet
kaydet("/tmp/asmlang.bc")            // dilin içinden

# yürütücüyü derle (lexer/parser/derleyici YOK)
MODE_PLAYER=1 EXTRA_CFLAGS=-DMODE_PLAYER=1 ./build.sh linux-x86_64
```

## Ayrım gerçek

| | x86_64 | i386 |
|---|---|---|
| derleyici | 76.976 bayt | 61.340 |
| **yürütücü** | **44.672** | **36.200** |
| `.bc` | 484 bayt | 484 |

Yürütücü %42 küçük. Çıkarılan: lexer, parser, derleyici, gözetleme
deliği, AST yazıcısı, disassembler, istatistik. **Kalan:** `.bc`
yükleyici + **doğrulayıcı** + VM + çalışma zamanı.

Bunun için `g_code/g_consts/g_ncode/...` ve `code_at/code_put`
`src/vm/codebuf.S`'e taşındı — derleyici ile yürütücünün ortak zemini.

## Aynı `.bc`, iki mimari

Bütün alanlar `u32` ve dokuz hedef de little-endian olduğu için
x86_64'te üretilen `.bc` i386 yürütücüde **birebir aynı sonucu**
veriyor. Test bunu doğruluyor.

Dizgi sabitleri **ham bayt** olarak gömülüyor: havuzda tutamak var,
tutamak çalışma zamanı durumu, dosyaya yazılamaz. Yüklemede yeniden
nesne oluşturuluyor. Küresel **adları** yazılmıyor — indeksli
olduğumuz için gereksiz.

## Yükleyici bir GÜVENLİK sınırı

`.bc` **güvenilmeyen girdi**. Aşama 9'da yazdığımız `verify_meta`
artık hata ayıklama aracı değil, saldırı yüzeyinin savunması.

Fuzzer'ı yükleyiciye doğrulttum: **120 bozuk `.bc` → 6 çökme.**
Beklenen sonuç — sertleşmemişti. İkisi gerçek delikti:

**1. `T_FN` sabitinin yükü sınırsız.** Sabit havuzundaki bir
fonksiyon indeksi `g_fns[çöp]` okumasına dönüşüyordu → keyfî okuma.
Doğrulayıcı `g_fns[i].entry`'yi denetliyordu ama **sabitin kendisini
denetlemiyordu.**

Eklendi: sabit havuzu doğrulaması — etiket aralığı, `T_FN` yükü <
`g_nfn`, `T_NAT` yükü < `NAT_COUNT`, `T_OBJ` yükü < `g_nobj`.
Artı `op_call`'da çalışma anı sınır denetimi (derinlemesine savunma).

**2. `CALL`'ın argüman sayısı sınırsız.** `argc = 33536` olunca
`VS - argc*8` **yığının altına** iniyor ve orayı çağrılan sanıp
okuyordu → segfault. Bunu doğrulayıcı yakalayamaz: yığın derinliği
çalışma zamanı özelliğidir. `op_call` ve `op_array` artık argüman
sayısının yığın içinde kaldığını denetliyor.

## Sertleşme sonrası

```
360 bozuk .bc (3 tohum × 120)
  -> 0 çökme, 0 zaman aşımı, 334 temiz reddedildi, 26 geçerli kaldı
```

Hedefli bozmalar da temiz:

| bozma | sonuç |
|---|---|
| imza | `bc: gecersiz imza ya da surum` |
| sürüm | aynı |
| gövde tablosu damgası | `bc: govde tablosu uyusmuyor` |
| `ncode`/`nconst`/`nglob` | `bc: bolum boyutu sinir disinda` |
| kod dışı atlama | `dogrulama HATASI: atlama hedefi kod disinda` |
| geçersiz opcode | `dogrulama HATASI: gecersiz islem kodu` |

**Gövde tablosu damgası** özellikle önemli: derleyici ile yürütücünün
`NAT_COUNT`'u farklıysa `T_NAT` indeksleri kayar ve **sessizce yanlış
fonksiyon** çağrılırdı. Başlıkta damga var, uyuşmazsa reddediyor.

## Bulunan bir hata daha

Doğrulama hatası `rc=0` döndürüyordu — `g_verr` çıkış kodu toplamına
dahil değildi. Yani "bytecode doğrulaması başarısız" yazıp **başarı
kodu** dönüyorduk. Bir betikte bu sessizce yanlış davranış olurdu.

## Rapor

```
optimizasyon    : yok (yeni yetenek + güvenlik sertleştirme)
eklenen         : src/vm/bcfile.S, src/vm/codebuf.S, tests/bc.sh
yürütücü boyutu : 44.672 bayt (derleyicinin %58'i)
fuzz            : 120 bozuk .bc'de 6 çökme -> 360 bozuk .bc'de 0 çökme
doğruluk        : run + verify(7) + limits(8) + fuzz(25) + lint +
                  bare(10) + bc + expand hepsi geçti
```

## Yolda: iki test hatası daha

**1. Doğrulama hatası `rc=0` dönüyordu.** `g_verr` çıkış kodu
toplamına dahil değildi — "bytecode doğrulaması başarısız" yazıp
**başarı kodu** dönüyorduk. Bir betikte sessizce yanlış davranış.

**2. `tests/verify.sh` kaynak listesi eskimişti.** static-pie testi
elle yazılmış bir dosya listesi kullanıyordu; yeni dosyalar
(`codebuf.S`, `bcfile.S`) eklenince liste eksik kaldı ve test
"static-pie kırıldı" diye **yanlış alarm** verdi. Aynı bilgiyi iki
yerde tutmanın bedeli.

Düzeltme: `./build.sh kaynaklar` komutu eklendi, testler listeyi
oradan alıyor. Tek kaynak, eskime yok.

## Kalan

| iş | durum |
|---|---|
| `.bc`'yi ikiliye gömme (`.incbin`) | tek build bayrağı; ISO/çekirdek için doğru kip |
| `.bc`'yi exe sonuna ekleme | `os_seek` gerekir (9 hedef × 1) |
| argv/CLI | yol şu an sabit `/tmp/asmlang.bc` |
| copy-and-patch JIT | tek kalan büyük performans sıçraması |

---

# Aşama 25: Gömülü Bytecode — tek dosya, dosya sistemi yok

`.bc`'yi ikiliye gömme. Tek build bayrağı, ve **ISO/çekirdek için
doğru kip**: yükleyici hiçbir dosya sistemi çağrısı yapmıyor.

```bash
cp program.bc src/embed.bc
BC_EMBED=1 MODE_PLAYER=1 EXTRA_CFLAGS="-DMODE_PLAYER=1 -DBC_EMBED=1" \
  ./build.sh linux-x86_64
```

## Yükleyici kaynaktan bağımsızlaştı

`bc_load` ikiye bölündü:

| fonksiyon | iş |
|---|---|
| `bc_load(yol)` | dosyayı `g_filebuf`'a oku, sonra `bc_parse` |
| `bc_parse(veri, uzunluk)` | çözümleme — kaynağın nereden geldiğini bilmiyor |

Gömülü kip `.incbin` ile blobu `.rodata`'ya koyup doğrudan
`bc_parse`'a veriyor. Dosya yolu, `os_open`, `os_read` yok.

## Doğrulama: dosyayı silip çalıştır

```
rm /tmp/asmlang.bc
./build/emb
  merhaba, dunya!  42  720  [1, 2, 3, 42]  45
```

Çıktı dosyadan okuyan sürümle **birebir aynı**.

## Bare-metal + gömülü = çekirdek imajı

```
BC_EMBED=1 MODE_PLAYER=1 ... ./build.sh bare-x86_64

çekirdek imajı : 45.688 bayt
syscall komutu : 0
yer değiştirme : 0
```

İçinde: bytecode yürütücü + doğrulayıcı + GC + dizgi/dizi/tampon +
UART sürücüsü + **programın kendisi**. Dosya sistemi, libc, işletim
sistemi yok.

**Ama ÇALIŞTIRILMADI** — emülatör yok. Statik denetimler geçiyor;
koşu doğrulaması sende:

```bash
qemu-system-x86_64 -kernel build/bc-kernel -nographic
```

## Bir düzeltme: "0 dosya çağrısı" demiyorum

İlk bakışta `objdump`'ta 6 `os_open` çağrısı gördüm. Bunlar
**yükleyicinin değil**, dilin `dosya()` / `yazf()` / `ikili()` /
`yazikl()` gövde fonksiyonlarının. Bare-metal'de −1 dönüyorlar.

Doğru ifade: **yükleyici dosya sistemine dokunmuyor**; dilin dosya
fonksiyonları duruyor ama bare-metal'de çalışmıyor. "İkilide hiç
dosya çağrısı yok" demek yanlış olurdu.

## Boyutlar

| yapı | boyut |
|---|---|
| derleyici (tam) | 76.976 bayt |
| yürütücü (dosyadan) | 44.744 |
| yürütücü (gömülü) | 45.304 |
| bare-metal çekirdek (gömülü) | 45.688 |

Gömülü sürüm 560 bayt büyük: 484 baytlık bytecode + hizalama.

## Rapor

```
optimizasyon    : yok (yeni dağıtım kipi)
eklenen         : bc_parse ayrımı, BC_EMBED bayrağı, 2 test
doğrulama       : dosya silinmişken gömülü sürüm aynı çıktıyı verdi
                  bare+gömülü imaj: 0 syscall, 0 reloc
ÇALIŞTIRMA      : bare imaj YAPILMADI (emülatör yok)
doğruluk        : run + verify(7) + limits(8) + bc + bare(10) +
                  fuzz(20) + lint + expand hepsi geçti
```

## Player yol haritası — durum

| kip | durum |
|---|---|
| A) yürütücü + ayrı `.bc` | ✅ |
| B) `.bc` exe sonuna ekli | ⏸ `os_seek` gerekir (9 hedef × 1) |
| **C) `.bc` ikiliye gömülü** | ✅ **ISO/çekirdek için olan bu** |

---

# Aşama 26: Komut Satırı Argümanları

Sabit `/tmp/asmlang.bc` yolu bir eksiklikti. Argümanlar hem onu
düzeltiyor hem de kip B'nin (exe sonuna eklenmiş `.bc`) ön koşulu.

## Altı hedef bedava

Linux ve macOS'ta girişte yığın düzeni **aynı**:

```
[sp] = argc,  [sp+word] = argv[0], ..., NULL, envp...
```

Dört Linux + iki macOS hedefi tek kod yoluyla destekleniyor. Her
`_start`/`main` girişine 5-6 komut eklendi.

**Windows ve bare-metal'de `argc = 0`.** Windows `GetCommandLineA` ile
tek bir dizgi döndürüyor ve ayrıştırmak gerekiyor; bare-metal'de
argüman kavramı yok. Bu bir eksiklik ve gizlenmiyor — dokümante edildi,
`arg(i)` oralarda `boş` dönüyor.

## Dilde

```
yazdir argsay()          → arguman sayisi
yazdir arg(0)            → program yolu
yazdir arg(1)            → ilk arguman
yazdir arg(99)           → bos
```

İngilizce: `argc()`, `argv(i)`.

## Tam iş akışı artık gerçek

```
$ ./build/comp /tmp/a.bc          # derle, kaydet(arg(1))
  merhaba, dunya! 42 720 [1,2,3,42] 45
$ ./build/play /tmp/a.bc          # yurutucu
  merhaba, dunya! 42 720 [1,2,3,42] 45
$ ./build/play-i386 /tmp/a.bc     # ayni .bc, farkli mimari
  merhaba, dunya! 42 720 [1,2,3,42] 45
$ ./build/play /tmp/yok.bc
  bc: dosya acilamadi
```

## Yolda: koruma yanlış yere düştü

Yeni gövde fonksiyonlarını (`nat_argc`, `nat_arg`) eklerken çapa olarak
`/* native_index(...)` yorumunu kullandım. Ama Aşama 24'te
`#if !MODE_PLAYER` koruması **tam o yorumun önüne** konmuştu — yani
yeni fonksiyonlar korumanın içine düştü ve yürütücü yapısı
`undefined reference to nat_argc` verdi.

Derleyici yapısı sorunsuz derlendiği için ilk bakışta görünmedi; yalnız
`MODE_PLAYER=1` yapısında çıktı. **İki yapı kipi varsa ikisini de
derlemeden "oldu" denmez.**

Düzeltme: koruma `native_index`'in hemen önüne taşındı.

## Rapor

```
optimizasyon    : yok (yeni yetenek)
eklenen         : src/rt/args.S, argsay()/arg(), 6 giris noktasi yaması
kapsam          : Linux ×4 + macOS ×2 = 6 hedef
                  Windows + bare: argc = 0 (dokümante edilmiş eksiklik)
doğruluk        : run + verify(7) + limits(8) + bc(argv dahil) +
                  bare(10) + fuzz(20) + lint + expand hepsi geçti
```

## Player yol haritası

| kip | durum |
|---|---|
| A) yürütücü + ayrı `.bc` | ✅ yol argümandan |
| B) `.bc` exe sonuna ekli | ⏸ `os_seek` gerekir; argv[0] artık var |
| C) `.bc` ikiliye gömülü | ✅ ISO/çekirdek kipi |

---

# Aşama 27: JIT — Mekanizma ve Tasarım Kararı

## Önce: "copy-and-patch" bizde çalışmaz

Klasik copy-and-patch JIT, yorumlayıcı işleyicilerini **olduğu gibi**
kopyalar. Bizimkiler kopyalanamaz:

- `LEA_SYM` **PC-göreli** adresleme kullanıyor (`leaq ...(%rip)`,
  `adrp`) → başka adrese kopyalanınca yanlış yeri gösterir
- paylaşılan etiketlere (`vm_type_err`, `ve_true`) **göreli** dallanma
- her işleyici `NEXT` ile bitiyor

Gerçek copy-and-patch JIT'ler işleyicileri, yer değiştirme tablosu
olan **özel derlenmiş stencil**'ler olarak üretir. Bizde o altyapı yok.

**Seçilen yol: şablon JIT** — her bytecode komutu için makine kodu
üreten emitter. Bu aşama mekanizmayı kuruyor.

## `os_alloc_exec` — 9 hedef

| | çağrı |
|---|---|
| Linux ×4 | `mmap` `PROT_READ\|WRITE\|EXEC` |
| macOS x86_64 | `mmap` RWX |
| macOS aarch64 | `mmap` + **`MAP_JIT`** (entitlement ister) |
| Windows ×3 | `VirtualAlloc` `PAGE_EXECUTE_READWRITE` |
| bare-metal | itme ayırıcı (bellek zaten RWX) |

W^X uygulayan sistemlerde reddedilebilir → **0 döner**, çağıran
yorumlayıcıya düşer. Sessizce başarısız olmuyor.

## Mekanizma kanıtlandı

```
CALL(jit_init)
MOVI(A0, 0xb8); CALL(emit8)      # mov eax, imm32
MOVI(A0, 1234); CALL(emit32)
MOVI(A0, 0xc3); CALL(emit8)      # ret
CALL(jit_entry) -> CALL(jit_call)
```

```
x86_64 -> jit testi: uretilen kod dondurdu -> 1234
i386   -> jit testi: uretilen kod dondurdu -> 1234
```

Çalışma zamanında üretilen makine kodu iki mimaride de çalışıyor.
`tests/verify.sh`'e eklendi; W^X engeli varsa o da temiz raporlanıyor.

## Yolda: altıncı `RV == A0` — ve lint'in hiç çalışmadığı

`jit_init`'te:

```
CALL(os_alloc_exec)
BZ(RV, ji_no)
LEA_SYM(A0, SYM(g_jit_base))   ← i386'da RV(%eax) yok oldu
ST(A0, RV)                     ← adresi kendi uzerine yazdi
```

Altıncı kez. Ama asıl bulgu bu değil:

**Aşama 20'de yazdığım lint hiçbir zaman çalışmamış.** `awk` ile
yazılmıştı ve `\b` (kelime sınırı) kullanıyordu — **mawk'ta `\b`
kelime sınırı değil, backspace karakteri.** Kural hiçbir zaman
eşleşmedi; denetleyici her koşuda "temiz" dedi.

Yani yedi aşama boyunca çalıştığını sandığım bir denetleyici vardı ve
hiçbir şey denetlemiyordu. Kendi kuralımı kendime uygulamamıştım:
**hiç ateşlenmeyen bir denetleyici test edilmemiş demektir.**

Düzeltme — lint Python'a taşındı ve üç şey eklendi:

1. **`--selftest`**: hatalı ve temiz örnekleri gömülü tutuyor, her
   koşuda önce kendini sınıyor
2. RV'nin **ilk argüman** (yazma, güvenli) ile **sonraki argüman**
   (okuma, tehlikeli) ayrımı — ilk sürüm 10 yanlış pozitif veriyordu
3. `BZ(RV,...)` gibi denetimler RV'yi hâlâ canlı sayıyor; ilk awk
   sürümü bunu "tüketildi" sanıp gerçek hatayı kaçırırdı

Doğrulama: hata geri konunca yakalıyor, düzeltilince temiz, sıfır
yanlış pozitif.

## Sıradaki: şablon emitter

Beklenen kazanç büyük — dağıtım tamamen kalkıyor. Ama ölçmeden
söylemem. Plan, alışık olduğumuz sıra:

1. x86_64 için dar bir alt küme emitter'ı (tamsayı sıcak yolu:
   `GETGLOBAL2`, `ACCG`, `INCGLOBAL`, `GETG_CONST`, `JLT`, `JMP`)
2. Desteklenmeyen komut varsa **hiç JIT etme**, yorumlayıcıya düş —
   deopt gerekmez
3. Aynı değer yığını düzeni → çıktı birebir karşılaştırılabilir
4. `accum.al` ve `loop20m.al` üzerinde ölç
5. Kazanç ölçüm tabanının (%2) altındaysa **geri al**

## Rapor

```
optimizasyon    : yok (altyapı)
eklenen         : os_alloc_exec ×9, src/vm/jit.S, lint yeniden yazıldı
doğrulanan      : çalışma zamanı kod üretimi x86_64 + i386
düzeltilen      : 6. RV/A0 çakışması; lint'in kendisi (7 aşamadır ölüydü)
doğruluk        : run + verify(8 grup) + limits(8) + bare(10) +
                  fuzz(20) + lint(selftest'li) + expand geçti
```

---

# Aşama 28: Şablon JIT — çalışıyor, 2,4×

x86_64 için tamsayı sıcak yoluna şablon JIT. Yorumlayıcı dağıtımı
tamamen kalkıyor.

## Ölçüm

```
is yuku    yorumlayici     JIT      hizlanma
accum       144,85 ms    60,23 ms    2,40x   (%58)
loop20m     167,46 ms    77,42 ms    2,31x   (%54)
```

CPU zamanı, 15 tekrar, medyan. Bu, projedeki **en büyük tek kazanç** —
gözetleme deliğinin (%53) ve süperkomutların üstünde.

## Kapsam ve düşme (fallback)

Desteklenen: `CONST GETGLOBAL GETGLOBAL2 GETG_CONST DEFGLOBAL
SETGLOBAL_P POP ADD_SETG INCGLOBAL ACCG JMP JLT JGE PRINT HALT`.

**Desteklenmeyen tek bir komut varsa hiç JIT edilmez** — fonksiyon
çağrısı, dizgi, dizi içeren programlar doğrudan yorumlayıcıya gider.
Derleme aşamasında, hiç yan etki oluşmadan.

## Kodlama: mutlak adres, kasıtlı

Adresler JIT anında bilindiği için `movabs rax, imm64` ile gömülüyor.
Daha uzun kod üretir (24 bayt/push) ama kodlaması basit ve
**disassembler ile göze doğrulanabilir**. İlk sürümde doğruluk >
yoğunluk. `jit_dump()` üretilen kodu dosyaya yazıyor:

```
48 b8 00 90 cb d0 75 7f 00 00   movabs rax,0x7f75d0cb9000
8b 08                           mov    ecx,[rax]
89 0b                           mov    [rbx],ecx
8b 48 04                        mov    ecx,[rax+0x4]
89 4b 04                        mov    [rbx+0x4],ecx
48 83 c3 08                     add    rbx,0x8
```

Elle kodlanmış makine kodunu gözle doğrulamadan "çalışıyor" demek
kabul edilemezdi.

## Tasarım iddiam yanlıştı: deopt gerekiyormuş

Aşama 27'de "desteklenmeyen komut varsa hiç JIT etmeyiz, **deopt
gerekmez**" demiştim. Derleme zamanı için doğruydu. **Çalışma zamanı
için değildi.**

İlk sürümde üretilen kod tür hatası ya da taşma görünce 0 döndürüp
yorumlayıcıya bırakıyordu. Ama JIT o ana kadar **yan etkileri yapmış**
oluyordu ve yorumlayıcı programı baştan çalıştırınca çıktılar
tekrarlanıyordu:

```
program: yazdir 111 / yazdir 222 / (tasma)

JIT          : 111 | 222 | 111 | 222 | tasma      ← BOZUK
yorumlayici  : 111 | 222 | tasma
```

Bunu tahminle değil, test yazarak buldum.

**Düzeltme:** üretilen kod hatayı **kendisi** bildiriyor ve "işlendi"
dönüyor. Yorumlayıcıya düşme yalnızca derleme aşamasında, hiç yan etki
oluşmadan yapılabilir. Hata dizisi tam 18 bayt (`movabs`+`call`+
`mov eax,1`+`ret`), atlama ofsetleri buna göre.

## Denklik testi

```bash
tests/jit.sh
```

Dokuz program, her biri **JIT açık ve kapalı** çalıştırılıp çıktılar
karşılaştırılıyor: tamsayı döngüsü, birikim, taşma (yan etki
tekrarı!), tür hatası, desteklenmeyen üç durum, boş döngü, iç içe
döngü. Hepsi birebir aynı.

**Kural: JIT ile yorumlayıcının farklı davranması, hızlanmadan daha
önemli bir hatadır.**

## Sınırlar — dürüstçe

| | durum |
|---|---|
| mimari | yalnız **x86_64**. i386/ARM için ayrı emitter gerekir |
| fonksiyon çağrısı | desteklenmiyor → yorumlayıcı |
| dizgi/dizi/tampon | desteklenmiyor → yorumlayıcı |
| register tahsisi | yok; her şey bellekte, yorumlayıcıyla aynı düzen |
| kod yoğunluğu | mutlak adresler yüzünden şişkin |
| `fib` gibi çağrı ağırlıklı yükler | **hiç hızlanmıyor** |

Yani "2,4×" yalnız tamsayı sıcak döngüsü için. Genel bir hızlanma
değil ve öyle sunulmamalı.

## Rapor

```
optimizasyon    : x86_64 sablon JIT (tamsayi sicak yolu)
iş yükü         : accum, loop20m — CPU zamanı, 15 tekrar
kazanç          : 2,40x (accum) / 2,31x (loop20m)
kapsam          : 15 opcode, x86_64; digerleri yorumlayiciya duser
donanım sayaçları: ÖLÇÜLEMEDİ (perf yok)
doğruluk        : tests/jit.sh 9 program JIT==yorumlayici,
                  run + verify(8) + limits(8) + bare(10) + lint geçti
```

---

# Aşama 29: JIT Kapsamını Genişletme

Emitter çerçevesi kurulu olduğu için yeni opcode eklemek artık ucuz —
her biri birkaç satır.

Eklenenler (16): `JGT JLE SETGLOBAL NIL TRUE FALSE ADD SUB MUL
ADDK SUBK ADDK_SETG LT LE GT GE`.

Toplam kapsam **31 opcode**.

## Ölçüm

```
is yuku    yorumlayici     JIT     hizlanma
accum       142,49 ms    59,84 ms   2,38x
loop20m     165,51 ms    75,46 ms   2,19x
arith        58,06 ms    40,54 ms   1,43x
```

`arith` yeni eklenen opcode'ları kullanıyor (ADD/SUB/MUL, ADDK,
karşılaştırma, koşullu atlama). Kazanç daha küçük — çünkü orada
komut başına iş fazla, dağıtım payı düşük. Beklenen ve doğru sonuç.

## Yolda: Aşama 15'in aynısı, üçüncü kez

`OP_ADD`'i ekler eklemez `yazdir "a" + "b"` bozuldu:

```
JIT         : calisma hatasi: tur uyusmazligi
yorumlayici : ab
```

Sebep tanıdık: **`op_add`'in yorumlayıcıda DİZGİ BİRLEŞTİRME dalı var,
JIT yalnız tamsayı yolunu üretiyordu.** Bir hızlı yol, yerini aldığı
komutun **bütün** dallarını taşımak zorunda.

Bu hatayı üçüncü kez yaptım:
- Aşama 15: `ADD_SETG` dizgi dalını taşımıyordu
- Aşama 20: `ACCG` aynısı (test yazarken yakalandı)
- Aşama 29: JIT'in `ADD`'i aynısı

Üçünde de test yakaladı, hiçbirinde gözle görmedim.

**Çözüm — ucuz ve kanıtlanabilir:** sabit havuzunda `T_OBJ` varsa hiç
JIT etme. `OP_CALL` ve `OP_ARRAY` zaten desteklenmiyor, dolayısıyla
nesne değer yığına başka türlü giremez. Yani "JIT edilen programda
nesne yoktur" **statik olarak garanti** — çalışma anı kontrolü değil,
derleme anı kanıtı.

Alternatif (JIT'te dizgi yolunu da üretmek) daha fazla iş ve daha
fazla ıraksama riskiydi.

## Denklik testi 15 programa çıktı

`tests/jit.sh`: aritmetik, sabitli aritmetik, karşılaştırmalar, tüm
fused atlamalar, negatif/sınır değerler, çarpım taşması, iç içe döngü,
üç desteklenmeyen durum, taşmada yan etki tekrarı.

Her biri **JIT açık ve kapalı** çalıştırılıp çıktılar karşılaştırılıyor.

## Rapor

```
optimizasyon    : JIT kapsamı 15 -> 31 opcode
iş yükü         : accum, loop20m, arith — CPU zamanı, 12 tekrar
kazanç          : 2,38x / 2,19x / 1,43x
düzeltilen      : OP_ADD dizgi dalı ıraksaması (statik kanıtla kapatıldı)
doğruluk        : jit(15) + run + verify(8) + limits(8) + fuzz(20) + lint geçti
```

---

# Aşama 30: Üç Ucuz İş

Pahalı olanları (JIT'te fonksiyon çağrısı, i386 emitter, register
tahsisi) beklettik; ucuzdan ucuza gidiyoruz.

## 1. Çalıştırılamaz yığın (NX)

İkilide **hiç `GNU_STACK` başlığı yoktu**. Linux bu durumda eski
davranışa düşer ve yığını **çalıştırılabilir** sayar.

Saf assembly projelerinde kolayca gözden kaçan bir boşluk: derleyici
ürettiği kodda gcc `.note.GNU-stack` bölümünü kendisi ekler, bizde
eklemez. `abi.inc`'e eklendi (her `.S` dosyası dahil ettiği için her
nesne dosyası alıyor) + `-Wl,-z,noexecstack`.

```
önce:  (GNU_STACK basligi yok)
sonra: GNU_STACK ... RW
```

Linux ×2 ve bare-metal doğrulandı, teste bağlandı.

## 2. `tampona()` — dizgi → tampon

`metin()`'in tersi; ikisi birlikte dizgi ↔ ikili dönüşümünü
tamamlıyor.

```
tanim s = "Merhaba"
tanim b = tampona(s)
yazdir uzunluk(b)      → 7
yazdir metin(b) == s   → dogru
b[0] = 109
yazdir metin(b)        → merhaba
yazdir s               → Merhaba     ← DEGISMEDI
```

**Kopya semantiği**: tampon değiştirilebilir, kaynak dizgi değil.
`buf_new` GC tetikleyebildiği için kaynak **işaretçi değil tutamak**
olarak saklanıp ayırmadan sonra tazeleniyor.

## 3. Windows komut satırı

Aşama 26'da "Windows'ta `argc = 0`, dokümante edilmiş eksiklik"
demiştik. Kapatıldı: `GetCommandLineA` + kendi ayrıştırıcımız
(3 Windows hedefi).

**Ama Windows'ta çalıştıramıyorum.** Riskli olan kısım ayrıştırıcı,
`GetCommandLineA` çağrısı değil — bu yüzden ayrıştırıcıyı OS
korumasından çıkarıp **Linux'ta test edilebilir** bıraktım:

```
girdi : prog.exe  bir "iki uc" dort  "" bes
cikti : argc=6
        [prog.exe] [bir] [iki uc] [dort] [] [bes]
```

Tırnaklı parça tek argüman, boş `""` korunuyor, çoklu boşluk
atlanıyor. İki mimaride doğrulandı ve teste bağlandı.

**Dürüst durum:** ayrıştırıcı mantığı test altında; `GetCommandLineA`
bağlantısı ve Windows giriş noktası **çalıştırılmadı**.

## Rapor

```
optimizasyon    : yok (güvenlik + yetenek + boşluk kapatma)
eklenen         : NX yığın, tampona()/tobuf(), Windows argv
doğrulama       : verify.sh'e 3 test grubu (NX, kopya semantiği, cmdline)
ÇALIŞTIRILMADI  : Windows hedefleri (ayrıştırıcı mantığı Linux'ta test edildi)
doğruluk        : run + verify(11 grup) + limits(8) + jit(15) +
                  fuzz(15) + lint + bare(10) + expand hepsi geçti
```

## Kalan ucuz işler

| iş | maliyet |
|---|---|
| `os_seek` + kip B (`.bc` exe sonuna) | 9 hedef × 1 fonksiyon |
| JIT'e `JZ`/`JNZ`/`JEQ`/`JNE` | küçük ama `JEQ` nesne dalı ister |
| `O_FILE` (birden fazla açık dosya) | orta |

---

# Aşama 31: JIT Koşullular + Kip B (tek dosya)

## JIT: `JZ` / `JNZ` / `JZP` / `JNZP`

Doğruluk kuralı yorumlayıcıdan birebir alındı: yanlış = `boş`, ya da
`(mantıksal ve yük == 0)`. Diğer her şey doğru.

```
48 83 EB 08   sub rbx, 8
8B 03         mov eax, [rbx]      (etiket)
8B 4B 04      mov ecx, [rbx+4]    (yuk)
31 D2         xor edx, edx
83 F8 01      cmp eax, T_NIL
0F 94 C2      sete dl
83 F8 02      cmp eax, T_BOOL
75 05         jne +5
85 C9         test ecx, ecx
0F 94 C2      sete dl
84 D2         test dl, dl
```

`JZP`/`JNZP` (kısa devre `ve`/`veya`) aynı ama yığından atmıyor.

Kapsam **31 → 35 opcode**. Koşullu ağırlıklı iş yükü:

```
kosullu (2M tur, ve/veya)   yorumlayici 54,70 ms -> JIT 26,15 ms   2,09x
```

Özete `jit : 0/1` satırı eklendi — kapsam iddialarını **ölçebilmek**
için. "JIT ediliyor" demek yerine bakıp görüyoruz.

## `os_seek` — 9 hedef

| | çağrı |
|---|---|
| Linux x86_64/aarch64/arm | `lseek` (8 / 62 / 19) |
| Linux **i386** | `lseek` **yok** → `_llseek` (140), 64-bit ofset + ayrı sonuç tamponu |
| macOS ×2 | `lseek` |
| Windows ×3 | `SetFilePointerEx` / `SetFilePointer` |
| bare-metal | dosya sistemi yok → −1 |

İlk yazdığım i386 `_llseek` ve Windows `SetFilePointerEx` argüman
sıralaması **bozuktu** — özensizdim, ikisini de baştan yazdım.
`_llseek` özellikle tuzaklı: `ecx` yüksek 32 bit, `edx` düşük,
sonuç registerda değil **ayrı tamponda**.

## Kip B: `.bc` yürütücünün sonuna ekli

```bash
tools/append_bc.py yurutucu program.bc tekdosya
```

```
[ ...yurutucu... ][ ...bytecode... ][ u32 uzunluk ][ u32 "ASMT" ]
```

PE ve ELF yükleyicileri dosya sonundaki fazlalığı **yok sayar**, bu
yüzden aynı yöntem üç OS'ta da çalışıyor — tek kod yolu, RES'e gömmeye
gerek yok.

Yürütücü kendi yolunu `argv[0]`'dan buluyor (Aşama 26'nın karşılığı),
kendini açıyor, sondan 8 bayt okuyup imzayı doğruluyor, bytecode'a
geri sarıp okuyor.

```
$ tools/append_bc.py build/player /tmp/self.bc /tmp/tekdosya
  58104 bayt yurutucu + 480 bayt bytecode = 58592
$ /tmp/tekdosya                    # ARGUMANSIZ
  merhaba, dunya! 42 720 [1, 2, 3, 42] 45
```

Yükleme sırası: `argv[1]` verildiyse o dosya → yoksa kendi sonu →
yoksa varsayılan yol.

Bozuk füye testi: son bayt bozulunca çökme yok, temiz düşme.

## Player üç kipi de tamam

| kip | durum |
|---|---|
| A) yürütücü + ayrı `.bc` | ✅ yol argümandan |
| B) `.bc` exe sonuna ekli | ✅ **tek dosya, argümansız** |
| C) `.bc` ikiliye gömülü | ✅ ISO/çekirdek |

## Rapor

```
optimizasyon    : JIT kapsamı 31 -> 35 opcode
kazanç          : koşullu iş yükünde 2,09x
eklenen         : os_seek ×9, bc_load_self, tools/append_bc.py
düzeltilen      : i386 _llseek ve Windows SetFilePointerEx argüman sırası
doğruluk        : jit(18) + bc(tek dosya + bozuk füye) + run +
                  verify(11) + limits(8) + bare(10) + lint + expand geçti
```

---

# Aşama 32: JIT'i Bitirme — 49 opcode, ve iki yorumlayıcı hatası

Ucuz olan her şey eklendi. Kapsam **35 → 49 opcode**.

Eklenenler: yereller (`GETLOCAL SETLOCAL SETLOCAL_P GETLOCAL2
GETL_CONST ADD_SETL`), eşitlik (`EQ NE JEQ JNE`), `NEG`, `NOT`,
bölme (`DIV MOD`).

## Yereller neden ucuzdu

JIT edilen programda `OP_CALL` yok, dolayısıyla `VF` hiç değişmiyor ve
`run()` başında `VF = g_stack` olarak kuruluyor. Yani **yerel
değişkenin adresi JIT anında sabit** — küreseller gibi mutlak adresle
çözülüyor. (Çağrı desteği eklenirse bu geçersiz olur; `jit_compile`
`OP_CALL` görünce zaten JIT etmiyor.)

## Ölçüm

```
is yuku    yorumlayici     JIT      hizlanma
mixed      192,11 ms     16,08 ms   11,95x
accum      142,49        59,84       2,38x
loop20m    165,51        75,46       2,19x
kosullu     54,70        26,15       2,09x
arith       58,06        40,54       1,43x
```

`mixed` (yereller + `%` + eşitlik + koşullu) **12×**. Sebep: yorumlayıcı
tarafında `%` her seferinde `idivmod`'a çağrı yapıp kaydır-çıkar
döngüsü çalıştırıyor; JIT tek `idiv` komutu üretiyor. Yani buradaki
kazanç dağıtımdan değil, **algoritmadan** geliyor — dürüst olmak
gerekirse bu bir "JIT hızlanması" değil, yorumlayıcının bölme
uygulamasının yavaşlığı.

## Diferansiyel test iki YORUMLAYICI hatası buldu

JIT ile yorumlayıcıyı her programda karşılaştırmak, JIT'i değil
**yorumlayıcıyı** denetledi:

**1. Negatif bölenli her bölme çöp üretiyordu.**

```
100 / -5   ->  860675        (dogrusu -20)
-100 / -5  ->  860675        (dogrusu 20)
```

`idivmod`'da işaret hesabı için `A0` (bölünen) geçici olarak
kullanılıyor, sonra `FILL(A0, 0)` ile "geri yükleniyordu" — ama slot 0
o noktada **henüz yazılmamıştı**. Aşama 3'ten beri vardı; testlerim
yalnız negatif **bölünen** kullandığı için görünmedi.

**2. Kalanın işareti yanlıştı.**

C ve x86 `idiv` semantiğinde kalanın işareti **bölünenin** işaretini
izler, bölüm işaretini değil. `17 % -5 = 2` olmalı, kod `-2`
üretiyordu. JIT (`idiv`) doğru davranıyordu — ikisi ıraksıyordu.

Dokuz işaret kombinasyonu artık doğrulanıyor:
`3 2 -3 -2 -3 2 3 -2 -20`.

**Ders: iki bağımsız uygulamayı karşılaştırmak, tek uygulamayı test
etmekten güçlü.** JIT'i doğrulamak için yazdığım test, yorumlayıcının
dokuz aşamadır saklı duran hatasını buldu.

## Elle kodlamada iki hata

**Off-by-one:** eşitlik dizisinde `jne +8` yazmıştım, atlanacak blok
`mov(3) + cmp(3) + sete(3) = 9` bayttı. `sete`'nin ortasına düşüp
segfault veriyordu. Disassembler ile doğruladım:

```
c8: 75 09          jne 0xd3
...
d3: 48 83 eb 10    sub rbx,0x10     ← tam hedefte
```

**Fazla temkinlilik:** bölmede "bölen == −1 ise düş" yazmıştım, oysa
donanımda tuzak üreten tek durum `INT_MIN / -1`. `-2147483647 / -1`
gibi **geçerli** işlemleri de reddediyordum. Denetim daraltıldı.

## Denklik testi 24 programa çıktı

`tests/jit.sh`: aritmetik, sabitli aritmetik, karşılaştırmalar, tüm
fused atlamalar, koşullular, kısa devre, yerel değişkenler, eşitlik,
negatif/değil, bölme/kalan, sıfıra bölme, `INT_MIN / -1`, taşmada yan
etki tekrarı, üç desteklenmeyen durum, iç içe döngü, boş döngü.

## JIT'in son hali

| | |
|---|---|
| mimari | x86_64 (i386/ARM emitter yok) |
| opcode | 49 |
| desteklenmeyen | fonksiyon çağrısı, dizgi, dizi, tampon, gövde fonksiyonları |
| güvence | sabit havuzunda `T_OBJ` varsa hiç JIT edilmez |
| düşme | derleme anında (yan etkisiz); çalışma anı hatası JIT'te bildirilir |
| doğrulama | 24 program, JIT == yorumlayıcı |

## Rapor

```
optimizasyon    : JIT kapsamı 35 -> 49 opcode
kazanç          : 11,95x (mixed) / 2,38x (accum) / 2,19x (loop20m)
düzeltilen      : idivmod'da 2 YORUMLAYICI hatası (negatif bölen,
                  kalan işareti) + JIT'te off-by-one ve fazla temkinlilik
doğruluk        : jit(24) + run + verify(11) + limits(8) + bc +
                  bare(10) + fuzz(15) + lint + expand hepsi geçti
```

---

# Aşama 33: JIT'te Fonksiyon Çağrısı

Pahalı olan iş. Kapsam **49 → 53 opcode**; `CALL RET RETL RETK` eklendi.
Artık `fib` gibi çağrı ağırlıklı programlar da JIT ediliyor.

## Tasarım: yerel çağrı yığını

Yorumlayıcı dönüş bilgisini `g_frames`'te tutuyor. JIT **makinenin
kendi çağrı yığınını** kullanıyor:

| | yorumlayıcı | JIT |
|---|---|---|
| dönüş adresi | `g_frames[].retpc` (komut indeksi) | yerel yığın (`call`/`ret`) |
| çerçeve tabanı | `VF` registeri | `r12` (çağrı öncesi `push`) |
| hedef | `g_fns[i].entry` → `SET_PC` | `g_jit_fnmap[i]` → `call rax` |

Yığın etkisi **birebir aynı**: girişte `[çağrılan][arg0..argN-1]`,
çıkışta tek sonuç. Bu yüzden çıktılar karşılaştırılabiliyor.

Denetimler yorumlayıcıdakilerle aynı: çağrılabilir mi, arite,
özyineleme derinliği (`MAX_FRAMES`), yığın sınırları.

## Ölçüm

```
is yuku    yorumlayici     JIT      hizlanma
mixed      196,64 ms     18,49 ms   10,63x
fib          8,82         3,98       2,22x
accum      116,59        53,59       2,18x
```

`fib` artık JIT ediliyor — Aşama 10'da "çağrı ağırlıklı yükte
süperkomutlar %6 kazandırıyor" demiştik; JIT **2,2×** veriyor.

## Dört hata, üçünü test yakaladı

**1. `EB()` makrosu `A0`'ı ezer, `CALL` `A1`'i korumaz.**
Yer değiştirme değerlerini hesaplayıp sonra bayt üretmiştim; üretilen
kod çöp adres kullanıyordu. Her değer artık **önce slota** dökülüyor.

**2. `jx_emit_ret` komut indeksini kendi boş çerçeve slotundan
okuyordu.** Her `RET` rastgele davranıyor, değer yığınını bozuyordu.
**Kanarya yakaladı** (`GUARD BOZULDU: g_stack`) — Aşama 16'da
eklediğimiz mekanizma tam bu iş için vardı.

**3. Hata yolunda `ret` yalnız bir seviye geri dönüyordu.**
İç içe çağrıdan düşünce üst çağıranın JIT kodu **devam ediyordu**:

```
JIT         : 1 | cagri derinligi asildi | tur uyusmazligi   ← FAZLADAN
yorumlayici : 1 | cagri derinligi asildi
```

Düzeltme: `jit_run` çağrı sonrası `rsp` değerini saklıyor; hata dizisi
`mov rsp, [g_jit_sp]` ile yığını geri sarıp tek hamlede `jit_run`'a
dönüyor. Hata dizisi 18 → 31 bayt.

**4. Arite hata iletisi yorumlayıcınınkinden farklıydı** ("uyuşmuyor"
vs "uymuyor"). Küçük ama denklik testi yakaladı — ve doğrusu bu:
**iki uygulama aynı davranmalı, iletiler dahil.**

## Denklik testi 32 programa çıktı

Yeni eklenenler: fonksiyon çağrısı, iç içe çağrı + yerel, özyineleme
(fib, faktöriyel), derin özyineleme (900 seviye), çağrı derinliği
aşımı, arite uyuşmazlığı, çağrılamayan değer.

## JIT'in durumu

| | |
|---|---|
| mimari | x86_64 |
| opcode | **53** |
| destekleniyor | tamsayı aritmetiği, karşılaştırma, koşullu, döngü, yerel, **fonksiyon çağrısı, özyineleme** |
| desteklenmiyor | dizgi, dizi, tampon, gövde fonksiyonları (`uzunluk`, `yazi`, `oku`...) |
| güvence | sabit havuzunda `T_OBJ` veya `T_NAT` varsa hiç JIT edilmez |
| doğrulama | 32 program, JIT == yorumlayıcı |

## Rapor

```
optimizasyon    : JIT'te fonksiyon cagrisi (49 -> 53 opcode)
kazanç          : 10,63x (mixed) / 2,22x (fib) / 2,18x (accum)
düzeltilen      : 4 hata (makro klobber, slot okuma, yigin geri sarma,
                  ileti farki) - 3'unu test/kanarya yakaladi
doğruluk        : jit(32) + run + verify(11) + limits(8) + bc +
                  bare(10) + fuzz(15) + lint + expand hepsi geçti
```

---

# Aşama 34: JIT Seviyesinde Füzyon — ve tavanın ölçülmesi

## Önce: ne kadar yol kaldı?

Pahalı işe girişmeden önce **C referansı** ile tavanı ölçtüm:

```
etiketli + denetimli C  : 12 ms      ← JIT'in yaptığı işin aynısı
asmlang JIT             : 53,59 ms   ← 4,5 kat yavaş
asmlang yorumlayıcı     : 116,59 ms
```

`ref.c` bizim değer modelimizi birebir taklit ediyor: `{u32 etiket,
i32 yük}` yapıları, bellekte, tür denetimli, `__builtin_add_overflow`
ile taşma denetimli. Yani "elmayla elma".

**4,5 kat boşluk**, yani üretilen kod kalitesinde ciddi yer var —
pahalı iş buraya değer.

## Nerede kalmıştı: `GETG_CONST + JLT`

Sıcak döngüde ACCG ve INCGLOBAL zaten yığına dokunmuyordu. Kalan tek
trafik döngü koşuluydu: iki değeri yığına it, sonra ikisini de çekip
karşılaştır — 8 bellek işlemi.

**JIT seviyesinde füzyon:** `GETG_CONST(n,k) + Jcc` ve
`GETGLOBAL2(a,b) + Jcc` çiftleri tek karşılaştırmaya iniyor:

```
movabs rax, &gvals[n]
cmp dword [rax], 0 ; je +31         (tür denetimi)
movabs rcx, &consts[k]
cmp dword [rcx], 0 ; je +31
mov ecx, [rcx+4]
cmp [rax+4], ecx
jl  hedef
```

Yığına **hiç dokunmadan**. Yalnız `i+1` atlama hedefi değilse yutuluyor
(yoksa bir atlama bloğun ortasına düşerdi) — bunun için `g_jit_tgt`
haritası eklendi.

## Sonuç

```
is yuku    yorumlayici    JIT     hizlanma
mixed        235,04 ms   32,33 ms   7,27x
accum        182,21      62,11      2,93x
fib           14,23       5,10      2,79x
loop20m      201,66      76,22      2,65x
```

(Mutlak sayılar makine yüküne göre oynuyor; güvenilir olan **aynı
oturumda ölçülen oran**.)

## Üç hata, hepsi tanıdık

**1. Yardımcı fonksiyon çağıranın slotlarını okuyordu — ÜÇÜNCÜ kez.**
`jx_fused_cmp` `FILL(A0, 3)` ile *kendi* çerçevesinin slot 3'ünü
okuyordu; oradan çöp geliyordu. Aynısını `jx_emit_ret`'te de yapmıştım.
**Yardımcı fonksiyon çağıranın slotlarını göremez** — argüman olarak
geçmek zorunda.

**2. `jit_compile` `ENTER(6)` ile açılmışken slot 6-7 kullanıyordum**,
yani çerçevemin dışına yazıyordum.

**3. Koşul tersti.** Tür denetiminde `0x75` (jne) yazmıştım; etiket
doğruyken (0) hata yoluna düşüyordu. `0x74` (je) olmalıydı.
Disassembler ile buldum:

```
1af: 83 39 00    cmp DWORD PTR [rcx],0x0
1b2: 75 1f       jne 0x1d3        ← TERS: tur DOGRUYKEN hataya dusuyor
```

Elle makine kodu yazarken bu üçü de gözle görünmüyor; disassembler ve
denklik testi olmadan hiçbiri bulunamazdı.

## Yolda: yürütücü yapısı kırıldı

`jx_mark_tgts` `op_isjump` tablosunu kullanıyor, o da `opnames.inc`
içindeydi ve onu yalnız `disasm.S` dahil ediyordu — **yürütücüde
disassembler yok.** Tablo `opjump.inc`'e ayrıldı ve `codebuf.S`
(derleyici + yürütücü ortak) dahil ediyor.

`tests/bc.sh` yakaladı. İki yapı kipi olan bir projede tek kipi
derleyip "oldu" demek yine yetmedi.

## Kalan boşluk

```
C referansi : 12 ms
asmlang JIT : ~48-62 ms   -> hala ~4 kat
```

Kalan farkın kaynağı belli: her adres 10 baytlık `movabs` ile
gömülüyor ve değerler hâlâ bellekte. Sıradaki adımlar taban registeri
(`[r13+disp]` adresleme) ve gerçek register tahsisi — ikisi de pahalı
ve ayrı ölçülmeli.

## Rapor

```
optimizasyon    : JIT seviyesinde karşılaştırma füzyonu
tavan ölçümü    : C referansı 12 ms (aynı iş, aynı denetimler)
kazanç          : 7,27x (mixed) / 2,93x (accum) / 2,79x (fib) / 2,65x (loop20m)
kalan boşluk    : C'ye göre ~4 kat
düzeltilen      : 3 kodlama hatası + yürütücü yapı kırılması
doğruluk        : jit(32) + run + verify(11) + limits(8) + bc +
                  bare(10) + fuzz(15) + lint + expand — dokuz paket geçti
```

---

# Durum — dürüst değerlendirme

Bu bölüm "neler yapıldı" listesi değil, **neyin doğrulandığı ve
neyin doğrulanmadığı** kaydıdır.

## Doğrulanmış olan

| | |
|---|---|
| satır | 13.140 (assembly + tablolar) |
| bytecode opcode | 56 |
| JIT kapsamı | 53 opcode, x86_64 |
| test paketi | 9 (`run verify limits jit bc bare lint check_expand fuzz`) |
| gerçekten **çalıştırılan** hedef | **2** (linux-x86_64, linux-i386) |

Her iki mimaride de çıktılar birebir aynı. Yorumlayıcı ile JIT 32
programda birebir aynı. Bozuk `.bc` 360 durumda çökme üretmiyor.

## DOĞRULANMAMIŞ olan — bu ortamda mümkün değildi

| eksik | sebep |
|---|---|
| linux-aarch64 / linux-arm | cross derleyici **yok** |
| macOS ×2, Windows ×3 | cross derleyici **yok** |
| bare-metal koşusu | `qemu-system-*` **yok** (derleniyor, statik denetimler geçiyor) |
| donanım sayaçları | `perf` **yok** |

Yani "13 hedef" ifadesi **makro genişletme** doğrulamasıdır, çalışma
doğrulaması değil. Dokuz hedef hiç derlenmedi bile — yalnızca
önişlemciden geçirilip makro kazası olmadığı kontrol edildi.

Senin makinende `clang` + cross toolchain + `qemu` varsa gerçek
doğrulama mümkün:

```bash
./build.sh                      # tum hedefler
tests/run.sh                    # qemu/wine ile calistirma
qemu-system-x86_64 -kernel build/bare-x86_64 -nographic
```

## Bilinen eksikler (kapsam kararı, hata değil)

| | |
|---|---|
| JIT | yalnız x86_64; i386/ARM emitter yok |
| JIT | dizgi, dizi, tampon, gövde fonksiyonları desteklenmiyor → yorumlayıcıya düşer |
| JIT | register tahsisi yok; C referansına göre ~4 kat yavaş |
| dil | kayan nokta yok |
| dil | kapanış (closure) / üst değer yok |
| dil | `s = s + "x"` döngüsü O(n²) (sabiti 4 kat düşürüldü) |
| G/Ç | aynı anda tek açık dosya (`O_FILE` yok) |
| bare-metal | kesme, MMU, sayfalama yok; x86_64 long mode geçişi yapmıyor |
| Windows | `argv` ayrıştırıcısı test edildi ama Windows'ta **çalıştırılmadı** |

## Bulunan hatalar (kayıt)

Bu projede benim yaptığım ve **testlerin yakaladığı** hatalar:

| sınıf | kaç kez |
|---|---|
| i386 `RV == A0` çakışması | 6 |
| süperkomut/JIT'in bir dalı taşımaması (dizgi) | 3 |
| yardımcı fonksiyonun çağıranın slotunu okuması | 3 |
| sessiz taşma (sınır denetimi yok) | 8 tablo |
| elle makine kodunda ofset/koşul hatası | 3 |
| kendi "optimizasyonum"un gerileme çıkması | 1 (VCOPY, %35) |
| hiç çalışmayan denetleyici (lint, `\b` mawk'ta backspace) | 1 |

Ayrıca **yorumlayıcıda** 9 aşama saklı kalmış iki bölme hatası, JIT ile
diferansiyel test sayesinde bulundu.

## Sıradakiler (ölçülmedi, tahmin yok)

1. JIT'te taban registeri + register tahsisi — C'ye göre 4 kat boşluk var
2. i386 JIT emitter — mimari kapsamı
3. `O_FILE`, kapanışlar, kayan nokta — dil zenginliği
4. Bare-metal koşu doğrulaması — **sende**

---

# Aşama 35: JIT'i Ehlileştirmek

Aşama 34'te "C'ye göre ~4 kat" diye bırakmıştım. Kabul edilebilir
değildi. Bu aşamada üç yapısal düzeltme yapıldı ve **boşluk ölçülerek
ayrıştırıldı**.

## Önce: boşluk neyden oluşuyor?

`bench/ref2.c` eklendi — `ref.c` ile aynı iş, ama değerler `volatile`
ile **bellekte kalmaya zorlanıyor**, tıpkı bizim JIT'imizde olduğu gibi.
Bu, boşluğu ikiye ayırıyor:

```
C registerda (gcc -O2)    20,07 ms   1,00x
C BELLEKTE (volatile)     41,12 ms   2,05x   ← register tahsisinin payı
asmlang JIT (once)        63,74 ms   3,14x   ← bizim fazlalığımız 1,53x
```

Yani hedef netti: **1,53×'i kapatmak**, 2,05× ise ayrı ve çok daha
büyük bir iş (register tahsisi).

## 1. Taban registeri — `movabs` yığınına son

Her küresel erişim için 10 baytlık `movabs rax, adres` üretiliyordu.
`r13 = g_gvals` ile adres doğrudan bellek işlenenine katlanıyor:

```
once : movabs rax, 0x42ba20 ; cmp dword [rax], 0      (13 bayt, 2 komut)
simdi: cmp dword [r13+0x0], 0                          ( 8 bayt, 1 komut)
```

`r13` kodlaması `rbp` gibidir (mod=10, rm=101, SIB yok, REX.B şart).

## 2. Sabit katlama — sabitler değişmez

Sabit havuzu **çalışma zamanında değişmiyor**, yani etiketi ve değeri
JIT anında biliniyor. Tamsayı sabitler için hem tür denetimi hem bellek
okuması tamamen gereksiz:

```
once : movabs rcx, &consts[k] ; cmp [rcx],0 ; jne ; mov ecx,[rcx+4] ; add [rax+4],ecx
simdi: add dword [r13+0x14], 0x1
```

Döngü koşulu da öyle: `cmp dword [r13+0x14], 0x1312d00`.

## 3. Hata yolları satır dışı — asıl kazanç

Disassembler'da gördüğüm şey şuydu: **12 gerçek komutun arasına 39
komutluk ölü kod serpiştirilmişti.** Her tür denetimi kendi 31 baytlık
hata dizisini *sıcak yolun içine* koyuyordu. gcc hepsini döngü dışına
koyuyor.

Artık her hata türü için **tek ortak stub** kodun sonunda; denetimler
oraya 32-bit göreli dallanıyor.

```
dongu govdesi:  51 komut  ->  15 komut
uretilen kod  : 517 bayt  ->  ~330 bayt
```

Üretilen döngü (accum):

```
cmp DWORD PTR [r13+0x0],0x0 ; jne <stub>
cmp DWORD PTR [r13+0x8],0x0 ; jne <stub>
mov ecx,DWORD PTR [r13+0xc]
add DWORD PTR [r13+0x4],ecx ; jo <stub>
cmp DWORD PTR [r13+0x10],0x0 ; jne <stub>
add DWORD PTR [r13+0x14],0x1 ; jo <stub>
cmp DWORD PTR [r13+0x10],0x0 ; jne <stub>
cmp DWORD PTR [r13+0x14],0x1312d00 ; jl <govde>
```

## Sonuç

```
C registerda (gcc -O2)    20,07 ms   1,00x
C BELLEKTE (volatile)     41,12 ms   2,05x
asmlang JIT               49,98 ms   2,49x   ← 3,14x'ten
```

**Aynı bellek-yerleşik değer modeliyle C'nin ulaştığının 1,22×
yakınındayız.** Kalan 2,05× tamamen register tahsisi — ayrı ve büyük
bir iş.

Bütün iş yükleri:

```
is yuku    yorumlayici     JIT     hizlanma
mixed        232,17 ms   31,34 ms   7,41x
accum        179,20      49,42      3,63x
fib           14,24       4,60      3,09x
loop20m      201,21      74,27      2,71x
arith         66,60      32,88      2,03x
```

## Yapıp da işe yaramayan: blok içi tür denetimi elemesi

Aynı küreselin etiketi bir blokta iki kez denetleniyordu. Eleme
mekanizması yazıldı (kanıt kümesi; atlama hedefi, çağrı ve tür
bilinmeyen atamada geçersiz kılınıyor). Ölçüm:

```
mixed  %-0,9    arith  %-0,0    accum  %+0,9
```

**Kazanç yok.** Ve bunu önceden bilebilirdim: Aşama 17'de bütün tür
denetimlerini kaldırmanın tavanını **%8** ölçmüştüm. Elimdeki ölçümü
kullanmamışım. Mekanizma sağlam ve çalışma zamanı maliyeti sıfır olduğu
için duruyor, ama kazancı yok — dürüst kayıt bu.

Ayrıca rotasyonlu döngüde koşul ayrı bir temel blok olduğu için eleme
zaten ateşlenemiyor: koşula hem giriş `JMP`'inden hem gövdeden
gelinebiliyor.

## Bu aşamada yapılan hatalar

**1. Derinlik denetiminde `jbe +7`** yazmıştım; atlanacak blok
`0F 85 rel32` = **6 bayt**. Bir bayt kayıp komutun ortasına düşüyordu.
Özyineleme testleri yakaladı. Doğrusu `ja <stub>` — atlatma hiç gerekmiyor.

**2. Fonksiyon girişinde tür kanıtları silinmiyordu.** `g_jit_tgt`
yalnız bytecode atlamalarını işaretliyor; çağrı bytecode atlaması
değil. Metinsel olarak önceki koddan gelen kanıtlar fonksiyon gövdesine
sızıyordu — **soundness hatası**. Fonksiyon girişi de blok sınırı
olarak eklendi.

İkisi de denklik testiyle yakalandı, gözle değil.

## Rapor

```
optimizasyon    : taban registeri + sabit katlama + satir disi hata yollari
tavan olcumu    : bench/ref2.c (ayni is, volatile ile bellekte)
kazanc          : 3,14x -> 2,49x (C'ye gore); dongu govdesi 51 -> 15 komut
kalan bosluk    : 1,22x kod uretimi + 2,05x register tahsisi
yapilmayan      : blok ici tur elemesi olculdu, kazanc YOK (mekanizma duruyor)
dogruluk        : jit(32) + run + verify(11) + limits(8) + bc +
                  bare(10) + fuzz(15) + lint + expand — dokuz paket gecti
```

---

# Aşama 36: Dil Genişletme — `her`, bileşik atama, 13 gövde fonksiyonu

Denetimle başladım: `TOK_FOR` tanımlıydı, `her`/`for` anahtar kelimesi
sözcük tablosundaydı — ama **ayrıştırıcıda hiç yoktu.** `.` ve `:`
token'ları da tanımlı ama kullanılmıyor.

## 1. `her` — C tarzı döngü

```
her (tanim i = 0; i < 5; i += 1) { yazdir i }
her (; kosul; ) { ... }        // baslangic bos
her (;;) { ... kir }           // sonsuz
```

`BLOCK { baslangic ; FOR(kosul, govde, adim) }` olarak kuruluyor —
döngü değişkeni kendi kapsamında kalıyor.

Üretilen düzen (rotasyonlu):

```
    JMP kosul
govde: <govde>
adim:  <adim>       <- "devam" BURAYA gider
kosul: <kosul> ; JNZ govde
cikis:              <- "kir" buraya
```

**`devam`ın adıma gitmesi şart.** `iken` (while) için `devam` koşula
gidiyordu; aynı kod kullanılamaz — yoksa sayaç artmaz ve sonsuz
döngüye girer.

## 2. Bileşik atama

`+=` `-=` `*=` `/=` `%=` — ayrıştırıcıda `a += b` → `a = (a + b)`
olarak açılıyor. Dizgilerde de çalışıyor (`s += "cd"`).

`/=` için sözcük çözümleyiciye elle ekleme gerekti: `/` yorum tespiti
için ayrı ele alınıyor ve genel iki-karakterli operatör yoluna
(`op2_table`) girmiyor.

## 3. On üç gövde fonksiyonu

| | |
|---|---|
| matematik | `mutlak/abs` `en/min` `buy/max` `us/pow` |
| tür ve çıktı | `tur/type` `yaz/wr` (satır sonu koymaz) |
| dizi | `cikar/pop` `ters/reverse` `icerir/has` |
| dizgi | `parca/substr` `bul/find` `buyuk/upper` `kucuk/lower` |

`src/vm/natives2.S` olarak ayrı dosyada — `natives.S` çok büyümüştü ve
yama üzerine yama koymak bu projede birkaç kez sessiz hataya yol açtı.

## Bu aşamada yapılan hatalar

Bu aşama hata bakımından en yoğunuydu; hepsi kayıt:

**1. `N_FOR = 27` — `N_CONTINUE` ile çakıştı.** Bütün derleyici
bozuldu, demo bile çıktı vermedi.

**2. Düzeltirken `N_PROGRAM`'ı kaydırdım** — bu sefer `ast.inc` ile
`gen_tables.py`'deki `N` sözlüğü ayrıştı. Aynı numara **iki yerde**
tutuluyor.

**3. `TOK_PCTEQ = 50` — `TOK_ASSIGN` ile çakıştı.** Üçüncü kez aynı
sınıf. Bu sefer yazmadan önce boşluk kontrolü yaptım ve yakaladım.

**4. `SPILL(2, RV)` `node_set`'ten sonra** — `node_set` RV'yi ezer,
slot çöp aldı, sonra o çöp düğüm numarasına yazıldı → segfault.

**5. `her (;;)` iki noktalı virgülü birden yedi** — `sf_noinit`
gereksiz yere ilerletiyordu.

**6. `cur_type` sonucu `RV`'de döner, `A0`'da değil** — dört yerde
yanlış register okudum.

**7. Debug eklemem `str.replace` ile `cs_while`'a da girdi** (desen
ikisinde de vardı) ve çalışan `iken` döngüsünü de bozdu. Bir süre
`her`'i suçladım.

**8. `NT(3, ..., "ters")` — "ters" 4 harf.** Ad çözülmedi.

**9. `nat_mm`'de `BNZ(A2, ...)` karşılaştırma bayraklarını ezdi** —
`buy(3,9)` 3 döndürüyordu. Mod artık karşılaştırmadan **önce**
okunuyor.

**10. `str.replace` çapası eşleşmeyince sessizce hiçbir şey yapmadı** —
gövde fonksiyonları hiç eklenmediği hâlde derleme başarılı göründü.
Artık her eklemeden sonra `grep` ile doğruluyorum.

Onunun da testler ve disassembler yakaladı; hiçbirini gözle görmedim.
**Numara tabloları iki yerde tutulduğu sürece bu sınıf devam edecek** —
gerçek çözüm tek kaynaktan üretmek.

## Rapor

```
eklenen         : her(for), 5 bilesik atama, 13 govde fonksiyonu
                  src/vm/natives2.S, 2 test grubu
duzeltilen      : 10 hata (3'u numara cakismasi)
doğruluk        : run + verify(13 grup) + limits(8) + jit(32) + bc +
                  bare(10) + fuzz(15) + lint + expand — dokuz paket geçti
```

## Hâlâ eksik

`.` (alan erişimi), `:` (foreach `her x : dizi`), `++`/`--`,
`sirala/sort`, `dilim/slice`, `birlestir/join`, `kirp/trim`,
`yerine/replace`, `karekok/sqrt`, `rastgele/random`, kayan nokta.

---

# Aşama 37: `bul` genişletme, konsol, FFI

## Önce bir düzeltme

**`indexOf` zaten vardı**: `bul`/`find` dizgide alt dizginin indeksini
döndürüyor, bulunamazsa −1. Eksik olan dizilerde çalışmamasıydı —
eklendi.

```
bul("merhaba dunya", "dunya")  -> 8
bul([10, 20, 30], 20)          -> 1
bul([10, 20, 30], 99)          -> -1
baslar("merhaba", "mer")       -> dogru
biter("merhaba", "aba")        -> dogru
```

`baslar/startswith`, `biter/endswith` ayrı fonksiyon: `bul`'un özel
hâli ama tarama yapmadıkları için daha ucuz.

## Konsol

ANSI kaçış dizileriyle — **OS'a özel çağrı yok**, bare-metal'de UART'a
aynen gidiyor ve terminal emülatörü anlıyor.

```
temizle()            ekrani temizle, imleci basa al
imlec(satir, sutun)  1 tabanli konumlandirma
renk(n)              0 sifirla, 31 kirmizi, 32 yesil, ...
```

## FFI — kırmızı kalem doğru yerde

FFI **ikiye ayrılır** ve ikisinin sınırı tam olarak senin dediğin
yerden geçiyor:

| parça | Linux (statik) | Windows | macOS | bare-metal |
|---|---|---|---|---|
| **ham çağrı** (adrese atla) | ✅ | ✅ | ✅ | ✅ |
| kütüphane yükleme (`dlopen`) | ❌ | ✅ | ✅ | ❌ |

Yükleme kısmı işletim sistemi hizmeti. Bizim Linux ikilimiz **statik +
nostdlib**, `dlopen` yok — ve bare-metal'de kavram olarak yok.

**Bu aşamada yalnızca ham çağrı yapıldı** — ve OS geliştirmede lazım
olacak "saf makine kodu" ihtiyacının karşılığı tam olarak budur.

```
tanim k = tampon(6)
k[0]=184 k[1]=42 k[2]=0 k[3]=0 k[4]=0 k[5]=195   // mov eax,42 ; ret
tanim adr = makinekod(k)                          // calistirilabilir bellege kopyala
yazdir cagir(adr)                                 // -> 42
```

Argüman geçirme iki ABI'de de doğrulandı:

```
x86_64 SysV : lea rax,[rdi+rsi] ; ret  ->  cagir(f,20,22) = 42, cagir(f,100,5) = 105
i386  cdecl : mov eax,[esp+4] ; add eax,[esp+8] ; ret  ->  42
```

| fonksiyon | işlev |
|---|---|
| `cagir/call(adres, a0..a5)` | ham çağrı, 6 argümana kadar |
| `adres/addr(nesne)` | tampon/dizginin veri adresi |
| `makinekod/machcode(tampon)` | tamponu çalıştırılabilir belleğe kopyala |

**Uyarı:** çağrılan adres doğrulanmaz. Yanlış adres çökme demektir.
Bu bilinçli — amaç tam da doğrulanamayan şeyleri çağırabilmek.

## Bulunan sınır: 32-bit tamsayı işaretçi tutamıyor

x86_64'te `makinekod` doğru adresi döndürüyor ama **`cagir` çöküyordu**.
Sebep: `mmap` 0x7f7b… döndürüyor, dilin tamsayısı **32 bit**, adres
kırpılıyor (`0x4ED0A000`) ve o adrese atlanıyor. i386'da sorun yok
çünkü adresler zaten 32 bit.

Geçici çözüm: `os_alloc_exec` x86_64 Linux'ta `MAP_32BIT` kullanıyor,
yani çalıştırılabilir bellek 2 GB'ın altında.

**Ama bu genel çözüm değil.** 0x7f… adresindeki bir kütüphane
fonksiyonunu çağırmak hâlâ mümkün değil. Bu, `tanım64` tartışmasında
konuştuğumuz sınırın doğrudan sonucu: **64-bit hedeflerde gerçek FFI
için tamsayının genişlemesi gerekiyor** (tip notasyonu `tanim p: u64`
ya da işaretçi için ayrı bir değer türü).

## Yolda: gövde tablosu kaydı taşıyordu

`makinekod` (9 harf) ve `startswith` (10 harf) adları çözülmüyordu.
Sebep: tablo kaydı **16 bayt** — 4 (uzunluk) + 4 (indeks) = 8, ada
yalnızca **8 bayt** kalıyor. Daha uzun adlar sonraki kaydı eziyordu.

Kayıt 32 bayta çıkarıldı ve `native_index`'teki `uzunluk > 8 ise
reddet` ön eleme sınırı 24'e alındı. İkinci sınırı düzeltmeyi
unutmuştum, ad hâlâ çözülmüyordu — tablo boyutu iki yerde kodlanmış.

## Rapor

```
eklenen         : bul() dizilerde, baslar/biter, temizle/imlec/renk,
                  cagir/adres/makinekod (src/vm/ffi.S)
düzeltilen      : govde tablosu kayit boyutu (8 -> 24 bayt ad alani)
bilinen sinir   : 64-bit adres 32-bit tamsayiya sigmiyor (MAP_32BIT ile
                  gecici cozum; genel cozum tamsayi genisligi)
doğruluk        : run + verify(15 grup) + limits(8) + jit(32) + bc +
                  bare(10) + fuzz(15) + lint + expand — dokuz paket geçti
```

## Cepteki: OS için ham makine kodu

`makinekod()` + `cagir()` ikilisi disk okuma, CPUID gibi işler için
gereken temeli **zaten sağlıyor** — yükleyici de OS de gerekmiyor.
Bare-metal'de de çalışır (orada bellek zaten RWX).

Eksik olan, o makine kodunu **rahat yazmak**: satır içi assembler.
O ayrı bir aşama.

---

# Aşama 38: 64-bit Tamsayı

Aşama 12'de `tanım64` fikrine itiraz etmiştim; gerekçem "uygulama
ayrıntısını dile sızdırır" idi. Ama FFI'de somut bir duvara çarptık:
**64-bit adres 32-bit tamsayıya sığmıyor.** İtiraz ettiğim şey son
ekli anahtar kelimeydi; ihtiyacın kendisi haklıydı.

## Tasarım kararı: yük genişliği = makine kelimesi

```
x86_64 / aarch64 : 64-bit tamsayi, yuva 16 bayt
i386   / arm32   : 32-bit tamsayi, yuva  8 bayt  (degisiklik yok)
```

**Neden böyle:** 64-bit tamsayı 32-bit hedefte **iki register** ister
— her `ADD` bir `add/adc` çiftine döner ve bütün VM'in register düzeni
yeniden yazılır. Oysa 64-bit ihtiyacı (taşma payı, FFI işaretçisi)
zaten 64-bit hedeflerde. i386'da işaretçi de tamsayı da 32 bit; orada
kazanç yok, sadece bedel var.

Senin dediğin gibi: **x64'te bedavaya geliyor** — donanım zaten 64 bit,
`addq`/`imulq` ile `addl`/`imull` aynı hızda.

## Sonuç

```
x86_64:
  2147483647 + 1            -> 2147483648        (eskiden tasma)
  1000000 * 1000000         -> 1000000000000
  4611686018427387903       -> dogru basiyor
  4611686018427387903 * 4   -> tasma hatasi      (artik 2^63'te)
  0 - 9223372036854775807   -> dogru

i386:
  2147483647 + 1            -> tasma hatasi      (dogru davranis)
  4611686018427387903       -> "sayi degismezi sigmiyor" (derleme hatasi)
```

**Sığmayan sayı değişmezi artık sessizce sarmıyor.** i386'da
`4611686018427387903` yazınca `-1` üretiyordu; şimdi derleme hatası.

## `.bc` artık kelime genişliğine bağlı

Başlığa **kelime genişliği damgası** eklendi (sürüm 1 → 2). 64-bit
üretilen `.bc` 32-bit yürütücüde:

```
bc: kelime genisligi uyusmuyor (32/64 bit)
```

Sessizce yanlış çalışmasındansa açık ret. Bu, Aşama 24'teki gövde
tablosu damgasıyla aynı ilke.

## Ne dokunuldu

Etki alanı ölçülerek başlandı: 67 yük erişimi, 48 boyut, 44 işaretli
yükleme. Erişim biçimleri düzenli olduğu için mekanik dönüştürüldü:

| eski | yeni |
|---|---|
| `VAL_SIZE 8`, `VAL_PAY 4` | `2*WORD_SIZE`, `WORD_SIZE` |
| `LD32S_OFF(r, b, VAL_PAY)` | `LD_OFF(r, b, VAL_PAY)` (kelime) |
| `SHLI(r, 3)` (değer dizisi) | `SHLI(r, VAL_SHIFT)` |
| `VS, -4 / -8 / -12 / -16` | `VAL_SIZE`/`VAL_PAY` cinsinden |
| `addl`/`imull` + `jo` | `addq`/`imulq` + `jo` |

## Bu aşamada yapılan hatalar

**1. `VCOPY` 8 bayt kopyalıyordu** → yuva 16 bayt olunca yük
kayboldu, **bütün sabitler 0 göründü**. Tek yerde tanımlı hâle
getirildi.

**2. `SET_RES` yükü 32-bit yazıyordu** ama okuyucu 64-bit okuyordu →
üst yarı çöp. `arg(1)` bozuk tutamak döndürüyor, `kaydet(arg(1))`
sessizce başarısız oluyordu. **Ve `natives2.S` kendi kopyasını
taşıyordu** — aynı makro iki yerde.

**3. `pow10` tablosu 10 girdiliydi** → `10^12` basılamıyordu. Hem
`print_u32` hem `i32_to_str` etkilendi; sabit ortak başlığa taşındı.

**4. Kanarya `g_numbuf` taşmasını yakaladı** — 20 basamak 16 bayta
sığmıyor. Aşama 16'da eklediğimiz mekanizma tam bu iş içindi.

**5. Toplu dönüşüm `g_frames` ve `g_fns`'i değer yuvası sandı.**
İkisi de 8 baytlık ayrı yapı; `VAL_SHIFT` uygulanınca çağrı dönüşü ve
`.bc` fonksiyon tablosu bozuldu.

**6. Toplu dönüşüm `FILL(A0, 3)` ifadesini kaydırma sandı** ve
`FILL(A0, VAL_SHIFT)` yaptı — **slot numarası bozuldu**, `ters()`
çöktü. Metin üzerinden toplu değiştirmenin sınırı burası: bağlam
bilmeden yapılan dönüşüm sessizce anlam değiştirir.

## Maliyet

```
yorumlayici, 32-bit -> 64-bit yuva (farkli oturum, gurultu payi var)
  accum    130,14 -> 148,07 ms   %+14
  fib        9,80 ->  12,06 ms   %+23
  mixed    143,34 -> 247,08 ms   %+72
```

Yuva 8 → 16 bayt: **değer yığını kapasitesi yarıya indi**, bellek
trafiği arttı. `mixed`'deki büyük fark bölme ağırlıklı olmasından —
64-bit `idiv` 32-bit'ten belirgin yavaş.

Bu bedel bilinçli: taşma güvenliği ve FFI için ödendi. i386 hedefi
etkilenmedi.

## JIT şu an KAPALI

Üretilen kod 8 baytlık yuva ve 32-bit yük varsayıyor. **Yanlış kod
üretmektense JIT'i kapatıp yorumlayıcıya düşmek doğru davranış** —
`jit_compile` şimdilik 0 döndürüyor. Yeniden yazılması ayrı bir iş.

## Rapor

```
degisiklik      : yuk genisligi = makine kelimesi (64-bit x64/aarch64)
duzeltilen      : 6 hata (VCOPY, SET_RES, pow10, g_numbuf, iki toplu
                  donusum yanlisi)
eklenen         : .bc kelime genisligi damgasi, sayi degismezi tasma
                  denetimi
maliyet         : yorumlayicida %14-72 (is yukune gore), yigin
                  kapasitesi yariya indi
ACIK KALAN      : JIT devre disi
dogruluk        : run + verify + limits + bc + bare + fuzz + lint +
                  expand gecti; iki mimari BIREBIR ayni cikti
```

---

# Aşama 39: Sirenin Peşinden — 64-bit sonrası güvenlik denetimi

"x64 işlemini i386'da yapmak, güvenlik önlemi var mı?" sorusu haklıydı.
Değer 64 bite çıktıysa, **hâlâ 32-bit okunan her yer bir kırpma
açığıdır.** Tahminle değil test ederek denetledim.

## i386'da 64-bit taklidi — neden yapılmadı

Küçük bir düzeltme: .NET x86'da `Int64`'ü **dizi/pointer ile değil,
register çiftiyle** (EDX:EAX) yapıyor. x86'da `adc`/`sbb` komutları
tam bunun için var — elde biti donanımda taşınıyor, kaydırma değil.

i386'da bunu yapmak: her `ADD` bir `add/adc` çiftine, her `MUL`/`DIV`
bir yardımcı rutine döner; VM'in bütün register düzeni yeniden
yazılır. Ve i386'da işaretçi zaten 32 bit — asıl faydayı (FFI) vermez.
**Yapılmadı; cepte.**

## Denetim: 64-bit değeri indeks/boyut bekleyen her yere ver

```
l[buyuk]           -> dizi sinirlari disinda   (temiz)
b[buyuk] = 1       -> dizi sinirlari disinda   (temiz)
tampon(buyuk)      -> bos
parca(s, buyuk, 3) -> bos
arg(buyuk)         -> bos
```

Çökme yok, kanarya ihlali yok. Sınır denetimleri işaretsiz
karşılaştırma kullandığı için 64-bit değerler de yakalanıyor.

## Bulunan üç gerçek sorun

**1. FFI argümanı 8 baytlık adımla okunuyordu.** `nat_ffi` değer
yuvasını `SHLI(A0, 3)` ile indeksliyordu; yuva 16 bayt oldu.
Argümanlar yanlış yuvadan okunuyordu.

Düzeltildikten sonra **FFI gerçekten 64-bit**:

```
makinekod(...) -> adres 4 GB USTUNDE (dogru)
cagir(f, 20, 22)                -> 42
cagir(f, 1000000000000, 1)      -> 1000000000001
cagir(f, 4611686018427387903,1) -> 4611686018427387904
```

Ve **`MAP_32BIT` çözümü kalktı**. Aşama 37'de adres kırpılmasın diye
çalıştırılabilir belleği 2 GB altına zorluyorduk; Aşama 38 kök sebebi
ortadan kaldırdı, geçici çözüm silindi.

**2. `us(2, 4611686018427387903)` askıda kalıyordu** — 2^62 kere
dönüyordu. Bu bir hizmet reddi. Üs 64 ile sınırlandı (taşma zaten
64 adımda gerçekleşir, fazlası anlamsız).

**3. `us(2, 64)` sessizce 0 döndürüyordu** — taşmada sarıyordu.
Bizim en temel kuralımızı çiğniyordu; `MULOV` ile taşma denetimi
eklendi, artık `boş` dönüyor.

## Yanlış alarm — ve arkasından çıkan gerçek dil sorunu

Denetim sırasında `tur(buyuk)` "fonksiyon" döndürdü ve bir süre bunu
64-bit hatası sandım. Değildi: **`buyuk` benim Aşama 36'da eklediğim
gövde fonksiyonu** (`upper`). Kullanıcının `tanim buyuk = 5` tanımı
gömülü adı gölgelemiyordu:

```
tanim buyuk = 5
yazdir buyuk        -> <govde>        ← degiskeni KAYBETTI
```

Ad çözümleme sırası "yerel → gövde fonksiyonu → küresel" idi.
`global_find` eklendi (bulamazsa yeni yuva açmaz) ve sıra
**"yerel → var olan küresel → gövde fonksiyonu → yeni küresel"**
oldu.

```
tanim buyuk = 5
yazdir buyuk        -> 5              ← kullanici tanimi kazaniyor
yazdir buyuk("ab")  -> cagrilabilir degil
```

Dil büyüdükçe gömülü ad sayısı arttı; gölgeleme kuralı olmadan her
yeni gövde fonksiyonu kullanıcının değişken adını sessizce çalıyordu.

## Rapor

```
denetim         : 64-bit degerler tum indeks/boyut yollarinda
bulunan         : FFI arguman adimi, us() askida kalma, us() sessiz
                  tasma, gomulu ad golgeleme
kaldirilan      : MAP_32BIT gecici cozumu (kok sebep gitti)
doğruluk        : run + verify(17 grup) + limits + bc + bare + fuzz +
                  lint + expand — hepsi geçti
```

---

# Aşama 40: JIT Yeniden Tasarımı — Katman 1 ve 2

`docs/jit-tasarim.md` eklendi. Player ciddi bir iş olduğu için JIT'i
baştan, katmanlı ve kendini test eden bir yapıyla kuruyorum.

## Neden yeniden

Eski JIT'te bulunan hataların **hiçbiri mantık hatası değildi**:

| hata | sınıf |
|---|---|
| `EB()` `A0`'ı ezer, `CALL` `A1`'i korumaz | tesisat |
| yardımcı çağıranın çerçeve slotunu okur (×3) | tesisat |
| `ENTER(6)` ile slot 6-7 kullanımı | tesisat |
| `jne +8`, blok 9 bayt | elle ofset |
| `jbe +7`, blok 6 bayt | elle ofset |
| `0x75` yazılmış, `0x74` olmalı | ters koşul |

Hepsi "elle bayt yazmanın" doğrudan sonucu. **Aynı yapıyla devam
edilirse aynı hatalar tekrar üretilir.**

## Üç katman

```
Katman 3  bytecode -> yerel kod        (henuz yazilmadi)
Katman 2  jitlbl.S  etiket/yama        ✅
Katman 1  jitasm.S  komut kodlayici    ✅
```

Kural: **`jitasm.S` dışında tek bir opcode literali bulunmayacak.**

## Katman 1 — kodlayıcı

Tek zor kısım ModRM/SIB/REX. Tasarım kararı: **her zaman `mod=10`
(disp32), gerektiğinde açık SIB.**

- `mod=00` + `rm=101` → RIP-göreli (tuzak)
- `rbp`/`r13` `mod=00`'da kullanılamaz (özel durum)
- `rsp`/`r12` her zaman SIB ister (özel durum)

Hep disp32 kullanınca **özel durum kalmıyor** — tek kod yolu. Bedeli
birkaç bayt uzun kod; karşılığı kodlamanın *yapı gereği* doğru olması.

## Katman 2 — etiketler

Kodda bir daha atlama mesafesi **yazılmayacak**:

```
lbl_new()      -> etiket
lbl_jcc(cc, l) -> yer tutucu uret, kaydet
lbl_bind(l)    -> su anki konuma bagla
lbl_fix()      -> hepsini yamala
```

İleri ve geri atlama aynı mekanizma. Bağlanmamış etiket **hata**
olarak yakalanıyor.

## Öz testler — ve gerçekten ateşledikleri kanıtlandı

Her iki katman kendini sınıyor. Kodlayıcı testi bilinen komutları
üretip beklenen baytlarla karşılaştırıyor — SIB gerektiren `r12`
durumu dahil:

```
mov rax, [r13+0x10]     49 8b 85 10 00 00 00
mov rdx, [r12+0x04]     49 8b 94 24 04 00 00 00    <- SIB
cmp qword [r13+0x20], 5 49 81 bd 20 00 00 00 05 ...
movabs rsi, 0x1122334455667788
```

Kanıt: ModRM'de `mod` bitini bilerek düşürdüm →
`jitasm oz test: KALDI - kodlayici bozuk`. Düzeltince `GECTI`.
**Ateşlenmeyen bir denetleyici test edilmemiştir** kuralı, bu projede
lint'te bir kez ihmal edilmişti; burada baştan uygulandı.

## Yolda bulunan hata

Etiket nöbetçisi `-1` idi. `LD32` **sıfır genişletiyor** → `0xFFFFFFFF`
olarak okunuyor ve 64-bit `-1` ile eşleşmiyor. **Bağlanmamış etiket
yakalanmadan geçiyordu** — tam da bu katmanın önlemesi gereken hata.

Öz test yakaladı. Nöbetçi "konum + 1, 0 = bağlanmamış" kodlamasına
geçti; işaret sorunu tamamen ortadan kalktı.

## Rapor

```
eklenen         : docs/jit-tasarim.md, src/vm/jitasm.S, src/vm/jitlbl.S
                  iki oz test + verify.sh'e baglandi
kanitlanan      : oz testler kasitli bozmada ATESLIYOR
duzeltilen      : etiket nobetcisi isaret genisletme hatasi
doğruluk        : run + verify + lint + expand geçti
SIRADAKI        : Katman 3 (bytecode -> yerel kod)
```

---

# Aşama 41: JIT Katman 3 — çalışıyor

Katmanlı yapı tamamlandı ve JIT yeniden devrede.

```
Katman 3  jitcomp.S  bytecode -> yerel kod   ✅
Katman 2  jitlbl.S   etiket/yama             ✅
Katman 1  jitasm.S   komut kodlayici         ✅
```

**`jitcomp.S`'te tek bir opcode literali ve tek bir atlama mesafesi
yok.** Eski JIT'teki yedi hatanın tamamı bu iki şeyden geliyordu.

## Durum sözleşmesi — dosyanın başında yazılı

```
rbx = VS   deger yigini tepesi
r12 = VF   cerceve tabani
r13 = g_gvals tabani
rax, rcx, rdx, rsi, rdi = gecici, komut sinirinda ANLAMSIZ
```

`rbx`/`r12`/`r13` çağrılan-korumalı (SysV), yani çalışma zamanı
işlevlerimiz bozmuyor. Komut sınırında geçerli tek değişmez: `rbx`
doğru yığın tepesini gösterir.

Bütün erişimler `VAL_TAG`/`VAL_PAY`/`VAL_SIZE` cinsinden — genişlik
bir daha değişirse Katman 3 **dokunulmadan** çalışır.

## Sonuç

```
is yuku    yorumlayici     JIT     hizlanma   jit
accum        149,68 ms   58,47 ms   2,56x      1
loop20m      166,37       75,23     2,21x      1
mixed        247,73      247,78     1,00x      0   (bolme henuz yok)
```

32 programlık denklik testinin tamamı geçiyor. `mixed` JIT edilmiyor
çünkü `DIV`/`MOD` henüz eklenmedi — **doğru davranış**: desteklenmeyen
komut varsa hiç JIT edilmez, yorumlayıcıya düşülür.

## Üretilen kod

```
mov  DWORD PTR [rbx+0x0],0x0
mov  QWORD PTR [rbx+0x8],0x1
add  rbx,0x10
...
mov  ecx,DWORD PTR [rbx-0x20]
or   ecx,DWORD PTR [rbx-0x10]
jne  0x31d                      <- hata stubu, kodun SONUNDA
mov  rax,QWORD PTR [rbx-0x18]
add  rax,QWORD PTR [rbx-0x8]
jo   0x343
sub  rbx,0x10
mov  QWORD PTR [rbx-0x8],rax
```

## Yolda bulunanlar

**1. Kodlayıcı gereksiz REX üretiyordu.** W=0 ve düşük registerlarda
`0x40` baytı boşuna yazılıyordu (objdump `rex mov` diye gösteriyordu).
Kodlama açısından zararsız ama kod şişiriyor. REX artık yalnızca
gerekiyorsa üretiliyor.

**2. Etiket nöbetçisi işaret hatası** (Aşama 40'ta) — öz test yakaladı.

## Kalan opcode'lar

`DIV MOD EQ NE JEQ JNE JZ JNZ JZP JNZP NOT` ve yereller/çağrılar
(`GETLOCAL SETLOCAL CALL RET RETL RETK`). Hepsi aynı yapıyla
eklenecek: yalnız Katman 1-2 çağıran küçük işlevler.

Eskisinde bunlar 53 opcode'du; yenisinde şu an 27. **Kapsam değil
sağlamlık önce geldi** — çerçeve doğru olduğu için kalanı eklemek
mekanik.

## Rapor

```
eklenen         : src/vm/jitcomp.S (Katman 3), src/tables/jitreg.inc
kapsam          : 27 opcode (eskisi 53) - kalan mekanik
doğruluk        : jit(32 program) + run + verify + limits + bc +
                  bare + fuzz + lint — hepsi geçti
kazanç          : 2,56x (accum) / 2,21x (loop20m)
```

---

# Aşama 42: JIT Kapsamı Tamamlandı

Katmanlı yapı üzerine kalan opcode'lar eklendi. Kapsam **27 → 49**;
eski JIT ile aynı seviyede ama sağlam temelde.

Eklenenler: `DIV MOD EQ NE JEQ JNE JZ JNZ JZP JNZP NOT GETLOCAL
SETLOCAL SETLOCAL_P GETLOCAL2 GETL_CONST ADD_SETL CALL RET RETL RETK`.

## Ölçüm

```
is yuku    yorumlayici     JIT     hizlanma   jit
mixed        248,21 ms   33,89 ms   7,32x      1
accum        148,84       59,19     2,51x      1
loop20m      169,45       75,92     2,23x      1
fib           12,47        5,81     2,15x      1
arith         60,78       43,84     1,39x      1
```

**Beş iş yükü de JIT ediliyor.** 32 programlık denklik testinin
tamamı geçiyor.

## Yapının işe yaradığının kanıtı

Bu aşamada **iki hata** çıktı, ikisi de küçük ve tesisat cinsinden:

**1. `jer_konst`'ta `ja_b` `RV`'yi eziyordu.** `jc_ktag()` sonucu
`RV`'de dönüyor, sonra `ja_b` çağrılınca kayboluyordu. `dondur 1`
(RETK) `bos` üretiyordu. Değer önce slota dökülerek düzeltildi.

**2. Yorumlayıcıda `g_rem` 4 bayttı** — 64-bit kalan kırpılıyor,
negatif kalan işaretsiz görünüyordu: `(0-17) % 5` → `4294967294`.
**JIT doğruydu, yorumlayıcı yanlıştı.** Diferansiyel test yine
yorumlayıcı hatası buldu (Aşama 32'de de iki bölme hatası böyle
çıkmıştı).

Eski JIT'te bu aşamaya kadar **yedi** hata çıkmıştı; yenisinde iki.
Fark yapıdan: elle bayt yazılmadığı ve atlama mesafesi sayılmadığı
için o iki sınıf tamamen kapandı.

## Çağrı protokolü

Yorumlayıcı dönüş bilgisini `g_frames`'te tutar; JIT **makinenin
kendi çağrı yığınını** kullanır:

| | yorumlayıcı | JIT |
|---|---|---|
| dönüş adresi | `g_frames[].retpc` | yerel yığın (`call`/`ret`) |
| çerçeve tabanı | `VF` registeri | `r12`, çağrı öncesi `push` |
| hedef | `g_fns[i].entry` | `g_jc_fnmap[i]` |

Yığın **etkisi** birebir aynı, o yüzden çıktılar karşılaştırılabiliyor.
Denetimler de aynı: çağrılabilir mi, arite, özyineleme derinliği.

## Durum

| | |
|---|---|
| mimari | x86_64 |
| opcode | 49 |
| desteklenmeyen | dizgi, dizi, tampon, gövde fonksiyonları |
| güvence | sabit havuzunda `T_OBJ`/`T_NAT` varsa hiç JIT edilmez |
| doğrulama | 3 aşamalı: kodlayıcı öz testi, disassembler, 32 program denklik |

## Rapor

```
kapsam          : 27 -> 49 opcode
kazanç          : 7,32x (mixed) / 2,51x (accum) / 2,23x (loop20m) /
                  2,15x (fib) / 1,39x (arith)
duzeltilen      : RETK'te RV ezilmesi (JIT), g_rem genisligi (YORUMLAYICI)
doğruluk        : jit(32) + run + verify + limits + bc + bare +
                  fuzz + lint — sekiz paket geçti
```

---

# Aşama 43: Taban Dönüşümü ve Dizi/Dizgi Fonksiyonları

Kırmızı kalem "eğer yoksa" diyordu — **önce baktım.**

## Zaten vardı

| istenen | mevcut |
|---|---|
| tamsayı → dizgi | `yazi(42)` → `"42"` |
| dizgi → tamsayı | `sayi("42")` → `42` |
| tampon → dizgi | `metin(t)` |
| dizgi → tampon | `tampona(s)` |

Bunlar Aşama 13-22'de eklenmişti. Eklenmedi, doğrulandı.

## Gerçekten eksik olanlar — eklendi

```
hex(255)              -> "ff"
bin(10)               -> "1010"
taban(255, 8)         -> "377"
taban(35, 36)         -> "z"
hex(0 - 255)          -> "-ff"
tabandan("ff", 16)    -> 255
tabandan("1010", 2)   -> 1010'un ikilik karsiligi = 10
tabandan("xyz", 16)   -> bos   (cozulemedi)

birlestir(["a","b","c"], "-")  -> "a-b-c"
birlestir([1,2,3], ",")        -> "1,2,3"
bol("a-b-c", "-")              -> [a, b, c]
bol("abc", "")                 -> [a, b, c]   (karakterlere)
dilim([1,2,3,4,5], 1, 3)       -> [2, 3, 4]
dilim("merhaba", 2, 3)         -> "rha"
sirala([3,1,2])                -> [1, 2, 3]
```

Taban 2..36 arası; sınır dışı taban ve çözülemeyen dizgi `boş` döner
(sessizce yanlış sonuç yerine).

## Üç hata, üçü de test yakaladı

**1. `hex` ve `bin` aynı gövde indeksini paylaşıyordu** — ikisi de 16
tabanına gidiyordu. Ayrı indeks verildi.

**2. `birlestir` `i32_to_str` ile aynı tamponu kullanıyordu.**
`birlestir([1,2,3], ", ")` → `"3, 2, 3"`. Sayıyı dizgiye çevirmek
birikimi eziyordu. Ayrı tampon (`g_joinbuf`) verildi.

**3. Kanarya kaydında indeks 104 yazmışım** — tablo 11 girdilikti,
i386 çöküyordu. `GUARD_N` 12'ye çıkarıldı, indeks 11 oldu.

## `bol()` ve çöp toplayıcı

`str_new` **GC tetikleyebilir ve nesneleri taşıyabilir.** Bu yüzden
`bol()` işaretçi saklamıyor; her adımda **tutamaktan yeniden
çözüyor**. Aynı sınıf hata Aşama 21'de `str_concat`'te çıkmıştı.

Ayrıca yardımcı işlevler çağıranın çerçeve slotlarını göremediği için
(bu projede üç kez hata oldu) durum globalde tutuluyor.

## Rapor

```
denetim         : tamsayi<->dizgi ZATEN VARDI, eklenmedi
eklenen         : hex/bin/taban/tabandan, birlestir/bol/dilim/sirala
                  src/vm/natives3.S
duzeltilen      : paylasilan govde indeksi, paylasilan tampon,
                  kanarya indeks tasmasi
doğruluk        : verify(18 durum, 2 mimari) + run + limits + jit(32) +
                  bc + bare + fuzz + lint + expand — hepsi geçti
```

---

# Aşama 44: İşletim Sistemi Primitifleri

Proje denetlendi (dokuz paket, sıfır hata), bare-metal imaj temiz
(0 syscall, 0 yer değiştirme, 0 dış sembol) — OS'a geçildi.

Yine kırmızı kalemle: **port, cpuid, mmio hiçbiri yoktu.** Şimdiye
kadar OS işi yalnız `makinekod()` + `cagir()` ile, her erişim için
elle bayt yazarak yapılabiliyordu.

## Eklenen üç temel

```
bellek_oku(adres, genislik)         1/2/4/8 bayt
bellek_yaz(adres, deger, genislik)
port_oku(port, genislik)            x86 port G/C (1/2/4)
port_yaz(port, deger, genislik)
cpuid(yaprak)                       -> [eax, ebx, ecx, edx]
```

Doğrulama:

```
cpuid(0)               -> 4 eleman, yaprak 0x1f (gercek CPU degeri)
bellek_yaz(a, 4660, 2) ; bellek_oku(a, 2)  -> 4660
bellek_yaz(a, 305419896, 4) ; hex(...)     -> 12345678
bellek_oku(a, 3)       -> bos   (gecersiz genislik)
```

## Ayrıcalık sınırı — bilinerek çizildi

**Port G/Ç ayrıcalıklı bir işlemdir.** Barındırılan bir sistemde
(Linux/Windows/macOS) kullanıcı programı bunu yapamaz; denerse işlemci
hata verir.

Bu yüzden port işlevleri **yalnız bare-metal derlemede** var:

```
bare-x86_64   port_in sembolu VAR
bare-i386     port_in sembolu VAR
linux-x86_64  port_in sembolu YOK
linux-i386    port_in sembolu YOK
```

Barındırılan yapıda `port_oku(96,1)` çökmüyor, temiz `boş` dönüyor.
Bu ayrım teste bağlandı.

**Bellek erişimi doğrulanmaz** — verilen adres geçerli olmak zorunda.
Bilinçli: amaç tam da doğrulanamayan adreslere erişmek. `cagir()` ile
aynı risk sınıfında.

## Ciddi bir yapı hatası çıktı

`-DBARE=1` **yalnızca clang yolunda** ekleniyordu; gcc yolunda hiç
eklenmiyordu. Bu ortamda clang olmadığı için **bütün bare-metal
imajları `OS_BARE` tanımlı olmadan derlenmiş.**

Yani "bare-metal imaj" diye ürettiğimiz her şey aslında bare
yapılandırmasıyla derlenmemişti. Bayrak her iki yola taşındı.

Bunu port G/Ç testi ortaya çıkardı — **testin ateşlediğini kontrol
etmek** yine işe yaradı.

## Yeni lint kuralları

Gövde fonksiyonu adlarının uzunluğunu **elle sayıyordum** ve bir
defada yedi tanesini yanlış saydım (`bellek_oku` 11 yazmışım, 10
harf). Yanlış uzunlukta ad **hiç çözülmüyor** ve "çağrılabilir değil"
hatası veriyor — sebebi hiç belli olmuyor.

İki kural eklendi ve kasıtlı bozmayla **ateşledikleri kanıtlandı**:

```
NT UZUNLUK natives.inc:186  7 yazilmis, "cpuid" 5 harf
NAT_COUNT=49 ama natives.S'te 48 girdi var
```

## Rapor

```
eklenen         : src/vm/osprim.S (mmio, port G/C, cpuid)
                  16-bit erisim makrolari (4 mimari)
                  iki lint kurali (ates ettikleri kanitlandi)
duzeltilen      : -DBARE=1 gcc yolunda eksikti (butun bare imajlari
                  yanlis yapilandirmayla derleniyordu)
                  7 govde fonksiyonu ad uzunlugu
doğruluk        : run + verify(56 test) + limits + jit(32) + bc +
                  bare + fuzz + lint + expand — dokuz paket geçti
```

## Sıradaki OS adımları

`makinekod()` + `cagir()` + port G/Ç + MMIO + CPUID ile artık
şunlar **elle bayt yazmadan** yapılabilir:

- UART sürücüsü (port G/Ç zaten HAL'de var)
- ATA PIO disk okuma (port G/Ç)
- CPU özellik tespiti (CPUID)
- Aygıt belleği erişimi (MMIO)

Eksik olanlar: kesme tablosu (IDT), sayfalama, x86_64 long mode
geçişi, zamanlayıcı. Bunlar imaj tarafında (`src/os/bare/`), dil
tarafında değil.

---

# Aşama 45: Açılabilir İmaj, Ekran, Ses, Disk

OS katmanı gerçekten kullanılabilir hale getirildi.

## En önemlisi: imaj artık AÇILABİLİR

**Multiboot 1 başlığı yoktu** — yani ne GRUB ne de `qemu -kernel`
imajı yükleyebilirdi. "Bare-metal imaj" diye ürettiğimiz şey hiçbir
yerden başlatılamıyordu.

```
bare-x86_64  bayrak 0x00000007  toplam=OK  video 1024x768x32
bare-i386    bayrak 0x00000007  toplam=OK  video 1024x768x32
```

Bayrak 3 (video) ile **doğrusal çerçeve tamponu** isteniyor —
resim için şart. Yükleyici bilgi yapısının adresini `EBX`'te
bırakıyor; `_start` bunu yığını kurmadan **önce** saklıyor,
`mb_parse()` çözüyor.

## Donanım arayüzü

| işlev | ne yapar |
|---|---|
| `ekran()` | `[adres, genişlik, yükseklik, satır, bpp]` |
| `piksel(x,y,renk)` | 32 bpp tek piksel |
| `ekran_temizle(renk)` | tamponu doldur |
| `vga(x,y,karakter,renk)` | 80×25 metin (video kurulmasa da çalışır) |
| `ses(frekans)` / `ses_kapat()` | PC hoparlörü, PIT kanal 2 |
| `disk_oku(lba,sektör,tampon)` | ATA PIO, yoklamalı |

## Ayrıcalık sınırı teste bağlandı

```
bare-x86_64   port_in + ata_wait + fb_check  VAR
bare-i386     port_in + ata_wait + fb_check  VAR
linux-x86_64  hiçbiri YOK
linux-i386    hiçbiri YOK
```

Barındırılan yapıda yedi işlev de temiz `boş` dönüyor — çökmüyor.

## Bootloader için gereken üç parça hazır

1. Açılabilir imaj (multiboot)
2. `disk_oku(lba, n, tampon)`
3. `makinekod(tampon)` + `cagir(adres)`

İkinci aşamayı diskten belleğe alıp ona atlayan bir yükleyici artık
bu dilde yazılabilir. `ornekler/cekirdek.al` çalışan bir örnek.

## Bu aşamada yapılan hatalar

**1. Multiboot doğrulama betiğim yanlış ofsete bakıyordu.** Başlık
doğruydu, ben yanlış yerden okuyup "video alanları kaymış" sandım ve
doğru olan a.out alanlarını "düzelttim". Sonra ham baytları
dökünce görüldü. **Doğrulama aracının kendisi de yanlış olabilir.**

**2. Ekran/ses/disk adlarını tablo NÖBETÇİSİNDEN SONRA ekledim.**
Tarama nöbetçide duruyor, o yüzden yedi adın hiçbiri çözülmüyordu.
Lint bunu yakalayamaz — uzunluklar ve sayılar doğruydu, **yer**
yanlıştı.

**3. `ANDR` makrosu yok sandığım yerde `ANDI` yeterliydi.**

## DOĞRULANMADI — dürüst kayıt

Bu ortamda `qemu-system-*` yok. İmaj **statik olarak** doğrulanıyor:
multiboot başlığı geçerli, 0 syscall, 0 yer değiştirme, 11 gerçek
`in`/`out` komutu üretilmiş. Ama **hiç çalıştırılmadı.**

```bash
qemu-system-x86_64 -kernel build/bare-x86_64 -serial stdio
```

## Rapor

```
eklenen         : multiboot 1 basligi + cerceve tamponu cozumleme
                  src/vm/osdev.S (ekran, ses, disk)
                  ornekler/cekirdek.al + BENIOKU.md
                  bare testine multiboot + donanim ayrimi denetimi
duzeltilen      : dogrulama betigi ofseti, tablo nobetcisi yerlesimi
doğruluk        : run + verify + limits + jit(32) + bc + bare(19) +
                  fuzz + lint + expand — dokuz paket geçti
ACIK KALAN      : emulatorde CALISTIRILMADI (qemu yok)
```

---

# Aşama 46: C / C++ İşlevlerini Adla Çağırma

FFI'de ham çağrı vardı ama **adresi bulmanın yolu yoktu**.
`dlopen`/`dlsym` bizde yok: ikili statik + nostdlib, bare-metal'de
kavram bile yok.

Çözüm **statik bağlama**: C kodu imajla birlikte derlenir,
`src/tables/user_syms.inc` içinde tanıtılır, asmlang adla bulur.
Her hedefte çalışır — bare-metal dahil.

```
yazdir c("topla", 20, 22)     -> 42
yazdir c("kare", 7)           -> 49
tanim adr = cbul("kare")
yazdir cagir(adr, 9)          -> 81
yazdir hex(c("cpu_adi"))      -> 756e6547   ("Genu")
yazdir cbul("yokboyle")       -> bos        (cokmez)
```

Derleme:

```bash
USER_SRC="ornekler/c_ornek.c" EXTRA_CFLAGS="-DUSER_SYMS=1" \
  ./build.sh linux-x86_64
```

C++ için `extern "C"` şart, yoksa ad bozulur.

## Üç hata

**1. `.balign 48` — iki kuvveti değil**, assembler reddetti. 64 oldu.

**2. Tablonun başlangıcı 64'e hizalı değildi.** Kayıt adımı 48
çıkıyordu (`0x4141d0 → 0x414200`), tarama ikinci kaydı kaçırıyordu.
`.p2align 6` ile çözüldü.

**3. i386'da `%ecx` cdecl'de çağrılan-bozar.** Yığın temizliği
`%ecx`'e (argüman sayısı) güveniyordu; C işlevi onu ezince yığın
işaretçisi çöp kadar kaydırılıyor ve dönüşte çöküyordu. Artık
`%ebp`'den geri sarılıyor — hem doğru hem basit.

**Lint kuralı `CSYM`'e genişletildi** ve ateşlediği kanıtlandı
(`cpu_adi`'yi 8 yazmıştım, 7 harf).

## Rapor

```
eklenen         : src/tables/user_syms.inc, cbul()/c() govde islevleri
                  build.sh USER_SRC destegi
                  ornekler/c_ornek.c + kullanim belgesi
                  lint: CSYM uzunluk denetimi (ates ettigi kanitlandi)
duzeltilen      : tablo hizalamasi, i386 cdecl yigin temizligi
doğruluk        : run + verify + limits + jit(32) + bc + bare +
                  fuzz + lint + expand — dokuz paket geçti
```

---

# Aşama 47: QEMU Doğrulaması ve Üç Bare-Metal Hatası

"Çıktıyı gör" isteği doğru yöne işaret etti: çıktıyı ben göremem ama
**imajın kendisi rapor üretebilir.**

## `ornekler/onay.al` — dilin kendisinde yazılmış tanılama

Çekirdek içinde çalışıp seri porta 12 başlık basar. Raporun
görünüyor olması zaten sözcük çözümleyici + ayrıştırıcı + derleyici +
sanal makine + UART yolunun tamamının çalıştığının kanıtıdır.

```bash
tools/qemu.sh
```

## Üç gerçek hata bulundu

**1. `bare-x86_64` AÇILAMAZ.** Multiboot 1 çekirdeği **32-bit
korumalı modda** başlatır; bizim imaj ELF64. Doğrudan giremez.
Bugüne kadar "bare-metal imaj" diye ürettiğimiz x86_64 hedefi hiçbir
yerden başlatılamıyordu.

Uzun mod geçiş kodu (GDT, sayfa tabloları, `CR4.PAE`, `EFER.LME`,
`CR0.PG`) **yazılmadı** — test edemeyeceğim bir şeyi yazıp "oldu"
demek yerine açıkça belgeledim. **Açılabilir hedef `bare-i386`.**

**2. Multiboot sihri denetlenmiyordu.** Yükleyici `EAX`'e
`0x2BADB002` koyar. Denetlemeden `EBX`'i kullanıyorduk; multiboot
olmayan bir yoldan başlatılırsa `EBX` çöp olur ve `mb_parse` çöp
adres okur. Artık denetleniyor ve `acilis()` ile dile açılıyor.

**3. UART hiç başlatılmıyordu.** QEMU varsayılan olarak çalışır
durumda bırakıyor, o yüzden fark edilmemişti — **gerçek donanımda
çıktı hiç gelmezdi.** 115200 8N1 kurulumu eklendi. Tanılama
raporunun görünmesi tam da buna bağlıydı.

Üçü de teste bağlandı.

## Rapor

```
eklenen         : ornekler/onay.al (12 baslikli tanilama, dilde yazili)
                  tools/qemu.sh, acilis() govde islevi
                  bare testine UART + sihir denetimi
duzeltilen      : multiboot sihri denetlenmiyordu
                  UART hic kurulmuyordu
belgelenen      : bare-x86_64 acilamaz (uzun mod gecisi yok)
doğruluk        : dokuz paket geçti
```

---

# Aşama 48: Bare Kod Yolunu Gerçekten Çalıştırmak

Emülatör yok ve kurulamıyor (ağ kapalı, apt 403). **Bunu
değiştiremem.** Ama bare kod yolunun ayrıcalıklı **olmayan** kısmı
sıradan koddur ve çalıştırılabilir.

`BARE_SIM=1`: UART'ı `write()` sistem çağrısına yönlendirir, port
G/Ç'yi sahteler. Değişmeyen her şey aynen çalışır — bare'in kendi
itme ayırıcısı, `.bss` sıfırlama, `mb_parse`, dilin tamamı.

**QEMU'nun yerini tutmaz.** Test etmediği: gerçek açılış, gerçek
UART, gerçek port G/Ç, MMIO, disk, korumalı mod. Test ettiği: bare
HAL'in geri kalanı ve dilin tamamı.

## Sonuç: iki mimari de baştan sona çalışıyor

```
bare-x86_64                          bare-i386
3. cpuid    : VAR yaprak=31          3. cpuid    : VAR yaprak=31
4. port G/C : VAR                    4. port G/C : VAR
5. yigin    : TAMAM                  5. yigin    : TAMAM
6. cop topl.: TAMAM                  6. cop topl.: TAMAM
7. genislik : 64 bit                 7. genislik : 32 bit
8. fib(20)  : TAMAM                  8. fib(20)  : TAMAM
   guard 0, hata 0                      guard 0, hata 0
```

## Çalıştırınca çıkan üç hata

**1. İmajın kendi yığını ve öbeği hiçbir LOAD segmentinde değildi.**

```
LOAD segmenti : 0x100000 .. 0x194678
yigin         : 0x195000        <- DISARIDA
obek          : sonrasi         <- DISARIDA
```

Bare-metal'de RAM orada durduğu için "çalışıyor" görünür, ama
yükleyici o bölgeyi **ayırmaz**: modül ya da bellek haritası oraya
denk gelirse sessizce ezilir. Ayrıca imaj kendi bellek ayak izini
yanlış bildiriyordu. Yığın ve öbek `.bss` bölümünün içine alındı;
LOAD artık `0x4a5000` kapsıyor.

**Bu hata ancak çalıştırınca görülür** — statik denetimlerin hiçbiri
yakalayamazdı.

**2. i386 benzetiminde `%ebx` eziliyordu.** i386'da `VF = %ebx` ve
`%ebx` çağrılan-korumalı. Sistem çağrısı için kullanınca çerçeve
tabanı çöp oluyordu; ilk sayı basımında çöküyordu.

**3. `os_exit` `cli`/`hlt` yapıyordu** — ayrıcalıklı, benzetimde
çökme. Benzetimde gerçek çıkış yapıyor.

## Ne çalışıyor, ne çalışmıyor — dürüst tablo

| | durum |
|---|---|
| dil (sözcük→ayrıştırıcı→derleyici→VM) | ✅ bare yolunda **çalıştırıldı** |
| bare bellek ayırıcı, `.bss`, GC | ✅ **çalıştırıldı** |
| UART çıktısı | ✅ benzetimde; **gerçek 16550 denenmedi** |
| CPUID | ✅ **çalıştırıldı** (gerçek CPU değeri) |
| multiboot başlığı | ✅ statik geçerli; **açılış denenmedi** |
| port G/Ç, MMIO, VGA, grafik, disk, ses | ⚠️ kod var, **hiç çalıştırılmadı** |
| `bare-x86_64` açılışı | ❌ ELF64, multiboot 32-bit başlatır |

## Rapor

```
eklenen         : BARE_SIM (bare kod yolunu emulatorsuz calistirma)
                  bare testine gercek KOSU denetimi
duzeltilen      : yigin/obek LOAD segmenti disindaydi
                  i386 benzetiminde %ebx (VF) eziliyordu
                  os_exit benzetimde cokuyordu
doğruluk        : dokuz paket geçti; bare yolu iki mimaride koştu
```

---

# Aşama 49: QEMU'yu Ortama Getirme Yolu

Emülatör kurulamıyor (ağ kapalı, apt 403). Ama dosya yüklenebiliyor —
yani paketler dışarıdan gelirse doğrulama yapılabilir.

**Liste tahmin edilmedi:** kapsayıcının kendi paket verisinden
`apt-get --print-uris` ile çıkarıldı, sürümler birebir uyumlu.

```
tools/qemu-indir.sh   TEK DOSYA: liste gomulu, indirir, tek arsiv yapar
tools/qemu-kur.sh     yuklenen arsivi acar, sarmalayici yazar
```

Kurulum kök dizine dokunmaz; `/home/claude/qemu` altına açar ve
`LD_LIBRARY_PATH` + `-L .../qemu` ayarlayan bir sarmalayıcı üretir.

Ortam: **amd64, glibc 2.39, Ubuntu 24.04 noble, qemu 8.2.2**. Farklı
dağıtımdan paket alınırsa `glibc` uyumsuzluğu olur.

Paketler gelince doğrulanacaklar — şu an **hiç çalıştırılmamış** olan
kısım:

| | |
|---|---|
| gerçek multiboot açılışı | GRUB/QEMU imajı yükleyebiliyor mu |
| gerçek 16550 UART | rapor seri porta gerçekten çıkıyor mu |
| port G/Ç | `in`/`out` ring 0'da çalışıyor mu |
| VGA metin ekranı | 0xB8000'e yazım görünüyor mu |
| doğrusal çerçeve tamponu | yükleyici video kuruyor mu, piksel çiziliyor mu |
| ATA PIO | disk okuma |
| PC hoparlörü | ses |

`tools/qemu-indir.sh` Termux uyumlu hale getirildi: `bash`, `python`
ve `zip` gerektirmiyor (yalnız `curl`/`wget`), `dash` ve `sh` ile
sözdizimi doğrulandı, indirdiğini **tek dosyada** (`qemu-debs.tar.gz`,
~16 MB) paketliyor. `tools/qemu-kur.sh` hem arşiv hem tek tek `.deb`
kabul ediyor; sahte paketle uçtan uca sınandı.

---

# Aşama 50: GERÇEK EMÜLATÖRDE AÇILDI

Paketler yüklendi, QEMU 8.2.2 kuruldu, **bare-metal imaj gerçek
emülatörde açıldı ve on iki başlığın hepsi geldi.**

```
1.  multiboot yukleyici : VAR   bayraklar 0x24f
2.  cerceve tamponu     : YOK (QEMU video kurmuyor)
3.  cpuid               : VAR  yaprak=4  imza=756e6547
4.  port G/C            : VAR  port 0x61 = 0x30
5.  yigin ayirma        : TAMAM
6.  cop toplama         : TAMAM
7.  tamsayi genisligi   : 32 bit
8.  ozyineleme fib(20)  : TAMAM
9.  VGA metin ekrani    : YAZILDI
11. ATA PIO disk okuma  : OKUNDU  ilk iki bayt=eb 3c
12. PC hoparloru        : CALDI
    guard 0, hata 0
```

Disk testi gerçek bir imajla yapıldı: `/tmp/disk.img`'e `EB 3C 90 41`
yazıldı, çekirdek `eb 3c` okudu. **Gerçek ATA PIO, gerçek port G/Ç.**

## Çalıştırınca çıkan beş hata

Hiçbiri statik denetimle bulunamazdı.

**1. Multiboot bilgisi `.bss` sıfırlamadan ÖNCE yazılıyordu.**
Sıfırlama döngüsü `g_mbmagic`'i de kapsıyordu ve siliyordu —
"multiboot yükleyici YOK" diyordu. Artık sıfırlamadan sonra yazılıyor
(`EAX`/`EBX` yığında saklanıyor).

**2. QEMU'nun multiboot yükleyicisi video isteğini desteklemiyor.**
Bayrak 2 (`0x04`) görünce `multiboot knows VBE. we don't` deyip
açılışı **tamamen reddediyor**. GRUB destekliyor. Video bayrağı
varsayılan **kapalı** yapıldı; GRUB ile grafik isteyecekseniz
`-DMB_VIDEO=1`.

**3. i386 `port_in`'de genişlik ile port karışmıştı.** Port
numarasını `%edx`'e kopyalayıp onu genişlik sanıyordu; 1 ile
eşleşmediği için hep 32-bit `inl` yapıyordu. Port `0x61` için
`0x20302030` döndü — 8 bit olması gerekirken. Düzeltince `0x30`.

**4. `bare-x86_64` gerçekten açılamıyor** — QEMU'nun kendi sözleriyle:
`Cannot load x86-64 image, give a 32bit one.` Aşama 47'de tahmin
etmiştim, **doğrulandı**.

**5. Kurulum yolunda üç engel:** QEMU modül dizini (`accel-tcg`),
BIOS ve iPXE ayrı paketlerde (`-L` tek dizin alıyor), ağ kartı ROM'u
eksik (`-nic none`). `tools/qemu-kur.sh` üçünü de çözüyor.

## Onuncu test paketi

`tests/qemu.sh` — 14 denetim, gerçek emülatörde. QEMU yoksa
**atlanır**, başarısız sayılmaz.

```
imaj aciliyor / multiboot algilandi / gercek 16550 UART /
cpuid / port G/C ring 0 / obek / cop toplama / ozyineleme /
VGA / ATA PIO disk / hoparlor / kanarya / hata yok /
bare-x86_64 acilamiyor (sinir dogrulandi)
```

## Artık gerçekten doğrulanmış olanlar

| | önce | şimdi |
|---|---|---|
| multiboot açılışı | statik | ✅ **açıldı** |
| gerçek 16550 UART | denenmedi | ✅ **çalışıyor** |
| port G/Ç ring 0 | denenmedi | ✅ **çalışıyor** |
| VGA metin ekranı | denenmedi | ✅ **yazıldı** |
| ATA PIO disk | denenmedi | ✅ **okundu** |
| PC hoparlörü | denenmedi | ✅ **çaldı** |
| doğrusal çerçeve tamponu | denenmedi | ⚠️ GRUB gerekiyor |
| `bare-x86_64` açılışı | tahmin | ❌ **doğrulandı: açılamıyor** |

## Rapor

```
eklenen         : tests/qemu.sh (14 denetim, onuncu paket)
duzeltilen      : multiboot bilgisi bss ile siliniyordu
                  i386 port_in genislik/port karisikligi
                  video bayragi QEMU'yu reddettiriyordu
                  kurulum: modul dizini, BIOS yolu, ag karti
doğrulanan      : gercek acilis, UART, port G/C, VGA, ATA PIO, ses
doğruluk        : on paket gecti
```

---

# Aşama 51: Grafik — Yükleyiciye Gerek Kalmadan

Soru şuydu: GRUB mu, kendi boot'umuz mu? **Üçüncü bir yol daha iyi
çıktı.**

| yol | ne verir | maliyet |
|---|---|---|
| GRUB | multiboot VBE, gerçek donanımda standart | 5 paket daha |
| kendi boot'umuz | tam kontrol | korumalı moddan `int 0x10` çağrılamaz |
| **BGA doğrudan** | QEMU'da hemen | **sıfır** |

QEMU'nun standart VGA'sı (ve gerçek Bochs/QXL) **Bochs Graphics
Adapter** arayüzünü destekler: mod kurulumu `0x1CE`/`0x1CF`
portlarından yapılır, **16-bit BIOS çağrısına gerek yoktur.**

Bu önemli: multiboot çekirdeği 32-bit korumalı modda başlar ve oradan
`int 0x10` çağrılamaz. BGA ikisini de atlatıyor.

## Tamamen bu dilde yazıldı

`ornekler/grafik.al` — PCI taraması, BAR okuma, BGA kayıtları, piksel
yazımı. **Yeni gövde fonksiyonu eklenmedi**; yalnız `port_oku`,
`port_yaz`, `bellek_yaz`, `bellek_oku` kullanıldı.

```
BGA surumu     : b0c5
PCI VGA aygiti : 2
cerceve tamponu: fd000000
kurulan mod    : 640x480x32
cizim tamam    : mavi zemin + kirmizi/yesil/beyaz
```

## Ekran görüntüsüyle doğrulandı

QEMU'dan `screendump` alınıp pikseller okundu:

```
(  0,  0) (255,0,0)      kirmizi   OK
(  1,  0) (0,255,0)      yesil     OK
(  2,  0) (0,0,255)      mavi      OK
(300,100) (255,0,0)      yatay     OK
(100,300) (0,255,0)      dikey     OK
(200,200) (255,255,255)  capraz    OK
(400,400) (34,65,154)    zemin     OK
siyah olmayan piksel: 307200 / 307200
```

## Dört engel

**1. `0x80000000` 32-bit işaretli tamsayıya sığmıyor** — ne değişmez
olarak yazılabiliyor ne toplamayla kurulabiliyor (taşma hatası).
`0 - 2147483647 - 1` ile bit deseni kuruldu.

**2. Negatif değerde maskeleme ters çalışıyor.** BAR = `0xFD000008`
işaretli olarak negatif; kalanın işareti bölünenin işaretini izlediği
için `bar - (bar % 16)` 8 **çıkarmak yerine 8 ekliyor**. Kalan önce
pozitife çekilmeli. **Dilde bit operatörü olmaması burada acıttı.**

**3. `-display none` ile ekran yüzeyi güncellenmiyor** — `screendump`
boş çıkıyor. `-vnc none` gerekiyor.

**4. `-monitor stdio` ile misafir hiç başlamıyor.** Monitör ayrı
sokete alınmalı. Bunu ancak deneyerek gördük.

## Onuncu paket 15 denetime çıktı

```
imaj aciliyor / multiboot / gercek UART / cpuid / port G/C /
obek / cop toplama / ozyineleme / VGA metin / ATA PIO disk /
hoparlor / kanarya / hata yok / bare-x86_64 sinir /
GRAFIK: mod + 7 piksel + ekran dolu
```

## Eksik kalan: bit operatörleri

`&` `|` `^` `<<` `>>` **yok.** Donanım programlamada her yerde
gerekiyor; şimdilik bölme/çarpma/kalan ile dönülüyor ve bu hem
okunaksız hem işaret hatalarına açık (yukarıdaki 2. engel). Sıradaki
iş bu.

## GRUB hâlâ gerekli mi

Evet, ama farklı bir amaç için: **gerçek donanımda** ve BGA
desteklemeyen ekran kartlarında. `-DMB_VIDEO=1` ile derlenen imaj
GRUB'un kurduğu çerçeve tamponunu kullanır. QEMU'da BGA yeterli.

---

# Aşama 52: Bit İşlemleri

Aşama 51'de eksikliği acıtmıştı: BAR maskelemesi bölme/kalanla
yapılıyordu ve negatif değerde **ters çalışıyordu**.

```
&   bit ve        |   bit veya      ^   bit ozelveya
~   bit degil     <<  sola kaydir   >>  saga kaydir (ARITMETIK)
```

Öncelik C sırasında: `|` < `^` < `&` < `==` < `<` < `<<` < `+` < `*`

```
12 & 10        -> 8          ~0             -> -1
12 | 10        -> 14         ~5             -> -6
12 ^ 10        -> 6          255 & ~15      -> 240
1 << 4         -> 16         256 >> 4       -> 16
(0-16) >> 2    -> -4         (1<<8)|(1<<4)|1 -> 273
(3 & 1) == 1   -> dogru      1 << 100        -> hata
```

`>>` **aritmetik**: işaret korunur (`-16 >> 2 = -4`). Mantıksal
kaydırma için maskeleyin.

Kaydırma sayısı 0..genişlik-1 dışındaysa **hata** — davranış
mimariye göre değişeceği için sessiz sonuç üretmiyoruz.

## Grafik örneği sadeleşti

```
once :  tanim k = bar % 16
        eger k < 0 { k = k + 16 }      // isaret duzeltmesi
        tanim fb = bar - k
simdi:  tanim fb = bar & ~15

once :  tanim adr = 0 - 2147483647
        adr = adr - 1                  // 0x80000000 kurmak icin
simdi:  tanim adr = 1 << 31
```

QEMU'da aynı sonuç: 640×480×32, 7 piksel doğrulandı.

## Yolda çıkanlar

**1. `prec_table` 64 girdilikti**, yeni token'lar 63-68'de. 128'e
çıkarıldı.

**2. Sözcük çözümleyici yalnız `X=` biçimini biliyordu.** `<<`/`>>`
aynı karakterin iki kez gelmesi; ayrı yol gerekti.

**3. `optable` girdileri elle ekleniyor** ve unutulunca "geçersiz
işlem kodu" veriyor. Doldurma sayesinde çökme değil temiz hata —
Aşama 8'de eklenen güvenlik burada işe yaradı.

**4. Kaydırma sayacı x86'da `CL` olmak zorunda.** Çağıran `A2`'yi
(`rdx`) kullandığı için makro `rcx`'i saklayıp geri alıyor.

## JIT

`& | ^ ~` eklendi (kapsam 53 opcode). **Kaydırma JIT'te yok** —
sayaç `CL`'de olmalı ve sınır denetimi gerekiyor; desteklenmeyen
komut varsa zaten JIT edilmiyor, yorumlayıcıya düşüyor.

## Rapor

```
eklenen         : & | ^ ~ << >> (token, oncelik, opcode, VM, JIT)
                  4 mimariye bit makrolari
                  verify + jit testlerine bit gruplari
duzeltilen      : prec_table boyutu, cift karakter sozcuk cozumleme
doğruluk        : on paket geçti (QEMU dahil)
```

---

# Aşama 53: Kendi Önyükleyicimiz

GRUB araçları yok (`grub-mkrescue`, `xorriso` — hiçbiri). **"Gerekirse
yaz" dendi, yazıldı.**

`src/os/bare/boot.S` — 512 baytlık MBR önyükleyici. Gerçek modda
başlıyor, **VBE'yi orada kuruyor** (korumalı moddan `int 0x10`
çağrılamaz), korumalı moda geçip çekirdeğe multiboot yapısıyla
veriyor.

## Sonuç: diskten açılıyor, grafik çalışıyor

```
1.  multiboot yukleyici : VAR    bayraklar 0x1000
2.  cerceve tamponu     : VAR    1024x768x24
10. grafik cizim        : CIZILDI
    ekran goruntusu     : 1024x768, 786432/786432 piksel dolu
```

`-kernel` yolunda alamadığımız çerçeve tamponu artık var. **GRUB'a
gerek kalmadı.**

## Yedi hata — hepsi çalıştırınca çıktı

**1. `ljmpl` gerçek modda 32-bit atlama üretiyor** (`66 ea ...`).
İşlemci resetleniyordu, QEMU hiç çıktı vermeden çıkıyordu. `ljmp`
olmalı.

**2. `0x7C00` tabanlı bağlamak 16-bit yer değiştirmeye sığmıyor.**
Kod 0 tabanlı bağlanıp `DS=0x07C0` kullanılıyor.

**3. `#define`'lar kullanımdan sonra geliyordu** — cpp sıralı çalışır,
`mb_info` çözülmüyordu.

**4. `0x100000`'e atlıyordum ama giriş noktası orada değildi.**
Bağlayıcı `_start`'ı 38164 bayt ileriye koymuş. Adres artık ELF
başlığından okunup gömülüyor.

**5. GDT tabanı mutlak adres olmalı.** `DS=0x07C0` olduğu için
`gdt` sembolü 0x7C00 eklenmeden yazılıyordu; işlemci çöp GDT okuyup
resetleniyordu. İşaretler `123`'te duruyordu.

**6. Bootsector 512 baytı taşıyordu** (536). BIOS teletype yolu
atıldı; seri işaretler zaten daha güvenilir ve otomatik doğrulamada
görünüyor.

**7. VESA 0x118 kipi 24 bit veriyor**, `piksel()` yalnız 32 bit
kabul ediyordu. Çizim sessizce atlanıyor ama rapor **"CIZILDI"**
diyordu — yanıltıcı. Artık 24 ve 32 bit destekleniyor ve rapor dönüş
değerine bakıyor.

Yedincisi önemli: **rapor yalan söylüyordu.** Dönüş değerini
denetlemeyen bir tanılama, tanılama değildir.

## Araç tarafında

`-monitor stdio` + heredoc **anında** çalışıyor; ekran görüntüsü
çekirdek açılmadan alınıyordu. Ayrı sokete alınıp beklenmeli.

## QEMU paketi 19 denetime çıktı

```
... + kendi onyukleyicimiz: diskten acildi (GRUB yok)
    + onyukleyici VBE kipini kurdu (gercek modda)
    + cerceve tamponuna cizildi
    + ekran goruntusu: 1024x768, cizgiler dogru, ekran dolu
```

## Rapor

```
eklenen         : src/os/bare/boot.S (512 bayt MBR onyukleyici)
                  tools/disk-yap.py (acilabilir imaj uretir)
                  24 bit cerceve tamponu destegi
                  QEMU testine 4 denetim
duzeltilen      : 7 hata (hepsi calistirinca cikti)
doğrulanan      : diskten acilis, VBE, 1024x768 grafik
doğruluk        : on paket geçti (QEMU 19 denetim)
```

---

# Aşama 54: Klavye — ve Yedinci RV/A0 Çakışması

PS/2 klavye, **yoklamalı**. Kesme tablosu (IDT) gerekmez:
denetleyicinin durum kaydı yokluyor.

```
tus_var()   okunacak tus var mi (bloklamaz)
tus()       ASCII bekle (bloklar); tus(1) bloklamaz
tuskod()    ham tarama kodu
```

Ayrıca `os_read`'e bağlandı: bare-metal'de `oku()` hem seri porttan
hem klavyeden okuyor.

QEMU `sendkey` ile doğrulandı:

```
a=97   b=98   1=49   Shift+a=65   bosluk=32
```

Shift işliyor. Tarama kodu kümesi 1 (XT), US düzeni.

## Yedinci RV/A0 çakışması — ve lint'in neden kaçırdığı

```
CALL(kbd_ham)
MOVI(A0, -1)      <- i386'da A0 == RV == %eax
CMPR(RV, A0)      <- eax'i eax ile karsilastiriyor: HEP ESIT
```

Hiçbir tuş görülmüyordu. **Lint bunu yakalamadı** ve sebebi
öğretici: kuralda

```
TEST = (BZ|BNZ|CMPI|CMPR)\(\s*RVW?[,)]     # "RV hala canli"
```

satırı vardı. `CMPR(RV, A0)` bu desene uyduğu için "RV kullanılıyor,
demek ki canlı, güvenli" sayılıp **atlanıyordu**. Oysa A0 ezildiyse
RV canlı değildir.

İki düzeltme:
1. `CMPR` bu desenden çıkarıldı
2. "RV ilk argümandaysa yazılıyor demektir" varsayımı da yanlıştı —
   `CMPR`, `ST`, `STB` gibi makrolarda ilk argüman **kaynak**.
   `FIRST_IS_SRC` listesi eklendi.

Öz teste ikinci bir bozuk örnek kondu ve **ikisinin de ateşlediği
kanıtlandı**:

```
selftest: yazma-cakismasi YAKALANDI, KARSILASTIRMA-cakismasi YAKALANDI
```

Gerçek hatada da ateşliyor:

```
SUPHELI src/vm/klavye.S:113  CALL@107 -> A0 yazildi@112 -> CMPR(RV, A0)
```

**Ders:** denetleyicinin "güvenli" dediği durumları da sınamak
gerekiyor. Bu lint yedi aşama boyunca ölüydü (Aşama 27), sonra
çalışır hâle geldi, şimdi de **eksik** olduğu ortaya çıktı.

## Rapor

```
eklenen         : src/vm/klavye.S (PS/2, tarama kodu -> ASCII, shift)
                  ornekler/klavye.al, QEMU testine klavye denetimi
duzeltilen      : 7. RV/A0 cakismasi
                  lint kuralinin CMPR bosluğu (iki ayri varsayim yanlisti)
doğrulanan      : QEMU sendkey ile 5 tus, shift dahil
doğruluk        : on paket geçti (QEMU 20 denetim)
```

---

# Aşama 55: Fare — ve Sessiz Bir Dil Hatası

PS/2 fare, klavyeyle **aynı denetleyiciden** (8042), ikinci kanaldan.
Kesme (IRQ12) yerine yoklama: IDT gerekmiyor.

```
fare_kur()  baslat
fare_var()  yeni paket geldi mi
fare()      [x, y, dugmeler]
```

QEMU `mouse_move` / `mouse_button` ile doğrulandı:

```
mouse_move 10 5   -> x=10 y=5  dugme=0
mouse_move -3 2   -> x=7  y=7  dugme=0
mouse_button 1    -> x=7  y=7  dugme=1
mouse_move 20 0   -> x=27 y=7  dugme=0
```

Paket hizalaması bayrak baytının bit 3'üyle yapılıyor (hep 1 olmalı):
ilk bayt olmayan bir şeyi ilk bayt sanmamak için.

## `ornekler/imlec.al` — grafik + girdi birlikte

Çerçeve tamponuna imleç çizip fareyle hareket ettiriyor. Doğrulama
sadece "çalıştı" demiyor, **çizimin veriyle tutarlı olduğunu**
sınıyor:

```
paket 9
konum 730,542
ekran goruntusu: imlec (730,542)'de, TAM 19 beyaz piksel
```

19 = 10+10−1 (imlecin iki kolu). Eski konumların silindiği de
buradan anlaşılıyor.

## Yolda çıkan gerçek dil hatası

```
eger dogru {
  tanim G = 1024
  fonk f() { dondur G }
  yazdir f()          // 0 yazdiriyordu
}
```

Blok içinde `tanim G` **yerel** oluyor; fonksiyon derlenirken yerel
tablo sıfırlandığı için `G` bulunamıyor ve **küresel sanılıp 0
okunuyordu**. Kapanış (closure) yok — olması da gerekmiyor — ama
**sessizce yanlış cevap vermek kabul edilemez**.

`resolve_local` artık kuşatan kapsamı da tarıyor ve orada bulursa
ayrı bir sonuç döndürüyor:

```
derleyici hatasi (satir 6): fonksiyon disaridaki yerel degiskene
erisemez (kapanis yok)
```

Bu hatayı **fare imleci örneği ortaya çıkardı**: imleç çizilmiyordu
çünkü `G` sıfırdı. Gerçek bir program yazmadan görülmezdi.

## `bellek_oku/yaz` 3 bayt

24 bpp çerçeve tamponu için gerekiyordu; `bellek_yaz(adr, renk, 3)`
`bos` dönüyordu ve çizim sessizce atlanıyordu.

## Rapor

```
eklenen         : src/vm/fare.S (PS/2, paket toplama, konum)
                  ornekler/imlec.al, ornekler/fare.al
                  bellek_oku/yaz 3 bayt (24 bpp)
                  QEMU testine 3 fare denetimi
duzeltilen      : fonksiyondan kusatan yerele erisim SESSIZCE 0
                  okuyordu -> artik derleme hatasi
doğruluk        : on paket geçti (QEMU 23 denetim)
```
