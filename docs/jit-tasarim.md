# JIT Yeniden Tasarımı

## Neden yeniden

Aşama 38'de değer yuvası 8 → 16 bayta çıkınca JIT devre dışı bırakıldı.
Ama asıl sebep bu değil: **eski JIT'in yapısı hata üretiyordu.**

Eski JIT'te bulunan hataların tam listesi (hepsi test/kanarya yakaladı,
hiçbirini gözle görmedim):

| hata | sınıf |
|---|---|
| `EB()` makrosu `A0`'ı ezer, `CALL` `A1`'i korumaz | tesisat |
| `jx_emit_ret` çağıranın çerçeve slotunu okur | tesisat |
| `jx_fused_cmp` aynısı | tesisat |
| `jit_compile` `ENTER(6)` ile slot 6-7 kullanır | tesisat |
| `jne +8`, atlanacak blok 9 bayt | elle ofset |
| `jbe +7`, blok 6 bayt | elle ofset |
| `0x75` (jne) yazılmış, `0x74` (je) olmalı | ters koşul |

**Hiçbiri mantık hatası değil.** Hepsi "elle bayt yazmanın" doğrudan
sonucu. Aynı yapıyla devam edersek aynı hatalar tekrar üretilir.

## Tasarım: üç katman

```
Katman 3  jitcomp.S   bytecode -> yerel kod (opcode basina bir islev)
Katman 2  jitlbl.S    etiket/yama yonetimi (elle ofset YOK)
Katman 1  jitasm.S    komut kodlayici (tek yerde, kendini test eden)
```

Kural: **`jitasm.S` disinda tek bir opcode literali bulunmayacak.**

## Katman 1 — komut kodlayıcı

Tek zor kısım ModRM/SIB/REX. Bunu bir kez doğru yazıp her yerde
kullanmak, hataların tamamını ortadan kaldırır.

Tasarım kararı: **her zaman `mod=10` (disp32), gerektiğinde açık SIB.**

- `mod=00` ile `rm=101` RIP-göreli anlamına gelir → tuzak
- `rbp`/`r13` (`rm=101`) `mod=00`'da kullanılamaz → özel durum
- `rsp`/`r12` (`rm=100`) her zaman SIB ister → özel durum

Hep disp32 kullanınca **özel durum kalmıyor**: tek kod yolu.
Bedeli birkaç bayt daha uzun kod; karşılığı kodlamanın
*yapı gereği* doğru olması.

```
rex   = 0x48 | ((reg>>3)&1)<<2 | ((base>>3)&1)
opcode
modrm = 0x80 | ((reg&7)<<3) | (base&7)
[SIB 0x24  eger (base&7)==4]
disp32
```

## Katman 2 — etiketler

Elle ofset sayılmayacak. Arayüz:

```
lbl_new()        -> yeni etiket
lbl_jcc(cc, l)   -> "0F cc rel32" uret, yamalanmak uzere kaydet
lbl_jmp(l)       -> "E9 rel32"
lbl_bind(l)      -> etiketi SU ANKI konuma bagla
lbl_fix()        -> butun bekleyen atlamalari yamala
```

İleri ve geri atlama aynı mekanizma. `jne +31` gibi bir sayı
kodda hiç geçmeyecek.

## Katman 3 — derleyici

Her bytecode komutu için bir işlev; yalnızca katman 1-2 çağırır.
Değer yuvası erişimleri `VAL_SIZE`/`VAL_PAY`/`VAL_SHIFT` cinsinden
yazılır, böylece genişlik bir daha değişirse burası dokunulmaz kalır.

## Doğrulama üç aşamalı

1. **Kodlayıcı öz testi** (`jitasm_selftest`): bilinen komut
   dizilerini üretip beklenen baytlarla karşılaştırır. Kodlayıcı
   bozulursa derleme aşamasında değil, ilk koşuda yakalanır.
2. **Disassembler doğrulaması**: `jit_dump()` + `objdump`.
3. **Denklik testi** (`tests/jit.sh`): her program JIT açık ve kapalı
   çalıştırılıp çıktılar karşılaştırılır. **JIT ile yorumlayıcının
   farklı davranması, hızlanmadan daha önemli bir hatadır.**

## Kapsam (ilk sürüm)

Eskisiyle aynı: tamsayı sıcak yolu + fonksiyon çağrısı.
Dizgi/dizi/tampon/gövde fonksiyonu içeren program **hiç JIT edilmez**
(sabit havuzunda `T_OBJ`/`T_NAT` varsa derleme aşamasında düşülür —
yan etki oluşmadan).

## Ne değişmeyecek

- Hata yolları satır dışı (Aşama 35'te ölçüldü: sıcak yolu 51 → 15
  komuta indirdi)
- Taban registeri `r13 = g_gvals`
- Sabit katlama (sabitler çalışma zamanında değişmez)
- Çağrı için yerel yığın (`call`/`ret`), `r12 = VF`
