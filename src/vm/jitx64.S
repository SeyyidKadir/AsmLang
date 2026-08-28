/* jitx64.S - x86_64 sablon JIT emitter
 *
 * KAPSAM: yalniz tamsayi sicak yolu. Desteklenmeyen TEK bir komut bile
 * varsa HIC JIT edilmez, yorumlayiciya dusulur. Boylece deopt gerekmez
 * ve semantik farki imkansiz hale gelir.
 *
 * REGISTER MODELI (SysV, cagrilan-korumali olanlar kaydediliyor):
 *   rbx = VS   (deger yigini tepesi)
 *   rax, rcx   = gecici
 * Adresler JIT aninda BILINDIGI icin mutlak (movabs imm64) gomuluyor.
 * Daha uzun kod uretir ama kodlama basit ve dogrulanabilir - ilk
 * surumde dogruluk > yogunluk.
 *
 * Deger yigini duzeni yorumlayiciyla AYNI: cikti birebir
 * karsilastirilabilir.
 */
#include "../abi.inc"
#include "../tables/opcodes.inc"

    .bss
    .p2align 2
    .globl SYM(g_jit_ok)
SYM(g_jit_ok):   .space 4        /* 1 = program JIT edilebildi */
    .globl SYM(g_jit_map)
SYM(g_jit_map):  .space (MAX_CODE + 1) * 4   /* bytecode idx -> kod ofseti */
    .globl SYM(g_jit_fix)
SYM(g_jit_fix):  .space MAX_CODE * 8         /* {kod ofseti, hedef idx} */
    .globl SYM(g_jit_nfix)
SYM(g_jit_nfix): .space 4
/* fonksiyon indeksi -> uretilen kodun adresi */
    .p2align 3
    .globl SYM(g_jit_fnmap)
SYM(g_jit_fnmap): .space MAX_FRAMES * 8
/* Ozyineleme derinligi: JIT yerel cagri yigini kullaniyor, bu yuzden
 * MAX_FRAMES denetimini kendimiz yapmaliyiz (yoksa derin ozyineleme
 * MAKINE yiginini tasirir). */
    .globl SYM(g_jit_depth)
SYM(g_jit_depth): .space 4
/* jit_run icindeki cagri sonrasi rsp degeri.
 * Hata yolunda IC ICE cagrilardan tek hamlede cikmak icin sart:
 * duz "ret" yalnizca bir seviye geri doner ve yurutme yanlis yerden
 * DEVAM eder (olculdu: derinlik hatasindan sonra ikinci bir tur
 * hatasi basildi). */
    .p2align 3
    .globl SYM(g_jit_sp)
SYM(g_jit_sp): .space 8
    .globl SYM(g_jit_kval)
SYM(g_jit_kval): .space 4
/* Blok icinde "bu kuresel TAMSAYI oldugu KANITLANDI" kumesi.
 * Ayni degiskenin etiketi ayni temel blokta birden fazla kez
 * denetleniyordu (INCGLOBAL + karsilastirma). Bir kez kanitlandiktan
 * sonra, o bloga baska yerden girilmedigi ve deger degismedigi surece
 * tekrar denetlemek gereksiz.
 * SIFIRLANDIGI yerler: her atlama HEDEFI (baska yerden girilebilir),
 * her cagri (cagrilan kureselleri degistirebilir), turu bilinmeyen
 * her kuresel atamasi. */
    .globl SYM(g_jit_int)
SYM(g_jit_int):  .space MAX_GLOBALS + 1
/* --- HATA YOLLARI SATIR DISI ---
 * Hata dizileri (31 bayt) sicak yolun ICINE serpistiriliyordu:
 * 12 gercek komutun arasinda 39 komutluk olu kod. Bu hem I-cache'i
 * hem komut getirmeyi bozuyor. gcc hepsini dongu DISINA koyuyor;
 * olculen fark 1,53x idi.
 * Artik her hata turu icin TEK ortak stub var, denetimler oraya
 * 32-bit goreli dallaniyor. */
    .p2align 3
    .globl SYM(g_jit_stub)
SYM(g_jit_stub):  .space 8 * 4           /* stub kod ofsetleri */
    .globl SYM(g_jit_sfix)
SYM(g_jit_sfix):  .space MAX_CODE * 8    /* {yer tutucu ofseti, stub no} */
    .globl SYM(g_jit_nsfix)
SYM(g_jit_nsfix): .space 4
/* komut indeksi bir FONKSIYON GOVDESI icinde mi */
    .globl SYM(g_in_fn)
SYM(g_in_fn):    .space MAX_CODE + 1
/* atlama hedefi mi: JIT seviyesindeki fuzyon yalniz hedef OLMAYAN
 * komutlari yutabilir (yoksa atlama ortada bir yere duser) */
    .globl SYM(g_jit_tgt)
SYM(g_jit_tgt):  .space MAX_CODE + 1

    SECT_TEXT

#if defined(ARCH_X86_64)

/* --- kucuk yardimcilar --- */

/* eb(A0) - tek bayt */
#define EB(v)   MOVI(A0, v); CALL(emit8)

/* Hata dizisi TAM 18 bayt (movabs+call+mov eax,1+ret); atlama
 * ofsetleri buna gore yaziliyor. */
/* Hata dizisi TAM 31 bayt:
 *   48 B8 imm64   movabs rax, yardimci    (10)
 *   FF D0         call rax                ( 2)
 *   48 B8 imm64   movabs rax, g_jit_sp    (10)
 *   48 8B 20      mov rsp, [rax]          ( 3)
 *   B8 01000000   mov eax, 1              ( 5)
 *   C3            ret                     ( 1)
 * rsp geri sarildigi icin ret DOGRUDAN jit_run'a doner. */
#define BAIL_LEN 31

/* jx_abs(A0 = 64-bit adres) : movabs %rax, imm64 */
FUNC(jx_abs)
    ENTER(1)
    SPILL(0, A0)
    EB(0x48)
    EB(0xB8)
    FILL(A0, 0)
    CALL(emit32)                    /* dusuk 32 bit */
    FILL(A0, 0)
    SHRI(A0, 32)
    CALL(emit32)                    /* yuksek 32 bit */
    LEAVE_
    RET
ENDFUNC(jx_abs)

/* jx_push_rax() : [rbx] <- [rax] (8 bayt), rbx += 8
 *   8B 08         mov ecx, [rax]
 *   89 0B         mov [rbx], ecx
 *   8B 48 04      mov ecx, [rax+4]
 *   89 4B 04      mov [rbx+4], ecx
 *   48 83 C3 08   add rbx, 8
 */
FUNC(jx_push_rax)
    ENTER(1)
    EB(0x8B); EB(0x08)
    EB(0x89); EB(0x0B)
    EB(0x8B); EB(0x48); EB(0x04)
    EB(0x89); EB(0x4B); EB(0x04)
    EB(0x48); EB(0x83); EB(0xC3); EB(0x08)
    LEAVE_
    RET
ENDFUNC(jx_push_rax)

/* jx_pop_to_rax() : rbx -= 8, [rax] <- [rbx]
 *   48 83 EB 08   sub rbx, 8
 *   8B 0B         mov ecx, [rbx]
 *   89 08         mov [rax], ecx
 *   8B 4B 04      mov ecx, [rbx+4]
 *   89 48 04      mov [rax+4], ecx
 */
FUNC(jx_pop_to_rax)
    ENTER(1)
    EB(0x48); EB(0x83); EB(0xEB); EB(0x08)
    EB(0x8B); EB(0x0B)
    EB(0x89); EB(0x08)
    EB(0x8B); EB(0x4B); EB(0x04)
    EB(0x89); EB(0x48); EB(0x04)
    LEAVE_
    RET
ENDFUNC(jx_pop_to_rax)

/* gval_addr(A0 = yuva) -> RV = mutlak adres */
FUNC(jx_gval)
    ENTER(1)
    SHLI(A0, 3)
    LEA_SYM(A1, SYM(g_gvals))
    ADD(A0, A1)
    MOVR(RV, A0)
    LEAVE_
    RET
ENDFUNC(jx_gval)

/* jx_mark_tgts() - atlama hedeflerini isaretle */
FUNC(jx_mark_tgts)
    ENTER(3)
    MOVI(A0, 0)
    SPILL(0, A0)
mt_clr:
    LEA_SYM(A0, SYM(g_ncode))
    LD32(A0W, A0)
    FILL(A1, 0)
    CMPR(A1, A0)
    BHI(mt_scan)
    LEA_SYM(A0, SYM(g_jit_tgt))
    FILL(A1, 0)
    ADD(A0, A1)
    MOVI(A2, 0)
    STB(A0, A2B)
    FILL(A0, 0); INC(A0); SPILL(0, A0)
    B(mt_clr)
mt_scan:
    MOVI(A0, 0)
    SPILL(0, A0)
mt_loop:
    LEA_SYM(A0, SYM(g_ncode))
    LD32(A0W, A0)
    FILL(A1, 0)
    CMPR(A1, A0)
    BHS(mt_done)
    FILL(A0, 0)
    CALL(code_at)
    SPILL(1, RV)
    MOVR(A0, RV)
    ANDI(A0, 255)
    LEA_SYM(A1, SYM(op_isjump))
    LDB_IDX(A0W, A1, A0)
    BZ(A0, mt_next)
    FILL(A0, 1)
    SHRI(A0, 16)
    LEA_SYM(A1, SYM(g_ncode))
    LD32(A1W, A1)
    CMPR(A0, A1)
    BHI(mt_next)
    LEA_SYM(A1, SYM(g_jit_tgt))
    ADD(A1, A0)
    MOVI(A2, 1)
    STB(A1, A2B)
mt_next:
    FILL(A0, 0); INC(A0); SPILL(0, A0)
    B(mt_loop)
mt_done:
    LEAVE_
    RET
ENDFUNC(jx_mark_tgts)

/* jx_mark_fns() - hangi komutlarin fonksiyon govdesi icinde oldugunu
 * isaretler.
 *
 * Derleyici her fonksiyonu su duzende uretiyor:
 *     JMP over ; <govde> ; over: ...
 * yani govde [entry, over) araligi ve over, entry-1'deki JMP'nin
 * hedefi. Bu bilgi RET'i dogru uretmek icin sart:
 *   - govde icinde RET  -> yerel "ret" (cagirana don)
 *   - en dis seviyede RET -> yorumlayicida HALT anlamina geliyor
 */
FUNC(jx_mark_fns)
    ENTER(4)
    MOVI(A0, 0)
    SPILL(0, A0)
mf_clr:
    LEA_SYM(A0, SYM(g_ncode))
    LD32(A0W, A0)
    FILL(A1, 0)
    CMPR(A1, A0)
    BHI(mf_scan)
    LEA_SYM(A0, SYM(g_in_fn))
    FILL(A1, 0)
    ADD(A0, A1)
    MOVI(A2, 0)
    STB(A0, A2B)
    FILL(A0, 0); INC(A0); SPILL(0, A0)
    B(mf_clr)
mf_scan:
    MOVI(A0, 0)
    SPILL(0, A0)                    /* fonksiyon indeksi */
mf_fn:
    LEA_SYM(A0, SYM(g_nfn))
    LD32(A0W, A0)
    FILL(A1, 0)
    CMPR(A1, A0)
    BHS(mf_done)
    FILL(A0, 0)
    SHLI(A0, 3)
    LEA_SYM(A1, SYM(g_fns))
    ADD(A0, A1)
    LD32(A0W, A0)                   /* giris */
    SPILL(1, A0)
    BZ(A0, mf_next)
    DEC(A0)
    CALL(code_at)                   /* girisin oncesindeki komut */
    MOVR(A0, RV)
    MOVR(A1, A0)
    ANDI(A1, 255)
    CMPI(A1, OP_JMP)
    BNE(mf_next)
    SHRI(A0, 16)
    SPILL(2, A0)                    /* govde sonu (over) */
    FILL(A0, 1)
    SPILL(3, A0)
mf_body:
    FILL(A0, 3)
    FILL(A1, 2)
    CMPR(A0, A1)
    BHS(mf_next)
    LEA_SYM(A1, SYM(g_in_fn))
    ADD(A1, A0)
    MOVI(A2, 1)
    STB(A1, A2B)
    FILL(A0, 3); INC(A0); SPILL(3, A0)
    B(mf_body)
mf_next:
    FILL(A0, 0); INC(A0); SPILL(0, A0)
    B(mf_fn)
mf_done:
    LEAVE_
    RET
ENDFUNC(jx_mark_fns)

/* jx_local(A0 = yuva) -> RV = mutlak adres
 * JIT edilen programda OP_CALL yok, dolayisiyla VF hic degismiyor ve
 * run() basinda VF = g_stack olarak kuruluyor. Yani yerel degiskenin
 * adresi JIT aninda SABIT. Cagri destegi eklenirse bu gecersiz olur -
 * o yuzden jit_compile OP_CALL gorunce zaten JIT etmiyor. */
/* ================== TABAN REGISTERI: r13 = g_gvals ==================
 * Her kuresel erisim icin 10 baytlik "movabs rax, adres" uretmek hem
 * kod boyutunu hem komut sayisini sisiriyordu. r13 tabanla adres
 * dogrudan bellek islenenine katlaniyor: [r13 + n*8 + ofs].
 *
 * r13 kodlamasi rbp gibidir: mod=10, rm=101, SIB yok, disp32 var.
 * REX.B (0x41) sart.
 */

/* jx_jstub(A0 = jcc ikinci bayti, A1 = stub no)
 * "0F cc rel32" uret, hedefi stub yamalama listesine kaydet. */
FUNC(jx_jstub)
    ENTER(3)
    SPILL(0, A0)
    SPILL(1, A1)
    EB(0x0F)
    FILL(A0, 0); CALL(emit8)
    CALL(jx_here)
    SPILL(2, RV)
    MOVI(A0, 0); CALL(emit32)
    LEA_SYM(A0, SYM(g_jit_nsfix))
    LD32(A1W, A0)
    MOVR(A2, A1); INC(A2)
    ST32_OFF(A0, 0, A2W)
    MOVR(A0, A1); SHLI(A0, 3)
    LEA_SYM(A1, SYM(g_jit_sfix)); ADD(A0, A1)
    FILL(A1, 2); ST32_OFF(A0, 0, A1W)
    FILL(A1, 1); ST32_OFF(A0, 4, A1W)
    LEAVE_
    RET
ENDFUNC(jx_jstub)

/* jx_emit_stubs() - alti hata stubunu kodun SONUNA koy */
FUNC(jx_emit_stubs)
    ENTER(2)
    MOVI(A0, 0)
    SPILL(0, A0)
jes_l:
    FILL(A0, 0)
    CMPI(A0, 6)
    BHS(jes_fix)
    CALL(jx_here)
    SPILL(1, RV)
    FILL(A0, 0); SHLI(A0, 2)
    LEA_SYM(A1, SYM(g_jit_stub)); ADD(A0, A1)
    FILL(A1, 1); ST32_OFF(A0, 0, A1W)
    FILL(A0, 0)
    CMPI(A0, 0); BEQ(jes_t)
    CMPI(A0, 1); BEQ(jes_o)
    CMPI(A0, 2); BEQ(jes_d)
    CMPI(A0, 3); BEQ(jes_c)
    CMPI(A0, 4); BEQ(jes_a)
    LEA_SYM(A0, SYM(jit_err_depth)); B(jes_e)
jes_t: LEA_SYM(A0, SYM(jit_err_type));  B(jes_e)
jes_o: LEA_SYM(A0, SYM(jit_err_ovf));   B(jes_e)
jes_d: LEA_SYM(A0, SYM(jit_err_div));   B(jes_e)
jes_c: LEA_SYM(A0, SYM(jit_err_call));  B(jes_e)
jes_a: LEA_SYM(A0, SYM(jit_err_arity))
jes_e:
    CALL(jx_abs)
    EB(0xFF); EB(0xD0)
    LEA_SYM(A0, SYM(g_jit_sp)); CALL(jx_abs)
    EB(0x48); EB(0x8B); EB(0x20)
    EB(0xB8); MOVI(A0, 1); CALL(emit32)
    EB(0xC3)
    FILL(A0, 0); INC(A0); SPILL(0, A0)
    B(jes_l)
jes_fix:
    MOVI(A0, 0)
    SPILL(0, A0)
jes_p:
    LEA_SYM(A0, SYM(g_jit_nsfix))
    LD32(A0W, A0)
    FILL(A1, 0)
    CMPR(A1, A0)
    BHS(jes_done)
    FILL(A0, 0); SHLI(A0, 3)
    LEA_SYM(A1, SYM(g_jit_sfix)); ADD(A0, A1)
    LD32(A1W, A0)                   /* yer tutucu ofseti */
    SPILL(1, A1)
    LD32_OFF(A2W, A0, 4)            /* stub no */
    SHLI(A2, 2)
    LEA_SYM(A1, SYM(g_jit_stub)); ADD(A2, A1)
    LD32(A2W, A2)                   /* stub ofseti */
    FILL(A0, 1); ADDI(A0, 4)
    SUB(A2, A0)                     /* goreli */
    LEA_SYM(A0, SYM(g_jit_base)); LD(A0, A0)
    FILL(A1, 1); ADD(A0, A1)
    ST32_OFF(A0, 0, A2W)
    FILL(A0, 0); INC(A0); SPILL(0, A0)
    B(jes_p)
jes_done:
    LEAVE_
    RET
ENDFUNC(jx_emit_stubs)

/* jx_int_clr() - butun kanitlari sil (blok sinirinda / cagrida) */
FUNC(jx_int_clr)
    ENTER(1)
    MOVI(A0, 0)
    SPILL(0, A0)
jic_l:
    FILL(A0, 0)
    CMPI(A0, MAX_GLOBALS)
    BHS(jic_d)
    LEA_SYM(A1, SYM(g_jit_int))
    ADD(A1, A0)
    MOVI(A2, 0)
    STB(A1, A2B)
    FILL(A0, 0); INC(A0); SPILL(0, A0)
    B(jic_l)
jic_d:
    LEAVE_
    RET
ENDFUNC(jx_int_clr)

/* jx_int_set(A0 = yuva) - kanitlandi olarak isaretle */
FUNC(jx_int_set)
    ENTER(1)
    CMPI(A0, MAX_GLOBALS)
    BHS(jis_d)
    LEA_SYM(A1, SYM(g_jit_int))
    ADD(A1, A0)
    MOVI(A2, 1)
    STB(A1, A2B)
jis_d:
    LEAVE_
    RET
ENDFUNC(jx_int_set)

/* jx_int_one(A0 = yuva) - tek kuresele ait kaniti sil */
FUNC(jx_int_one)
    ENTER(1)
    CMPI(A0, MAX_GLOBALS)
    BHS(jio_d)
    LEA_SYM(A1, SYM(g_jit_int))
    ADD(A1, A0)
    MOVI(A2, 0)
    STB(A1, A2B)
jio_d:
    LEAVE_
    RET
ENDFUNC(jx_int_one)

/* jx_need_int(A0 = yuva) - gerekiyorsa tur denetimi uret
 * Kanit varsa HIC KOD URETMEZ. */
FUNC(jx_need_int)
    ENTER(1)
    SPILL(0, A0)
#if !defined(OPT_JIT_TYPEELIM) || OPT_JIT_TYPEELIM
    LEA_SYM(A1, SYM(g_jit_int))
    LDB_IDX(A2W, A1, A0)
    BNZ(A2, jni_done)
#endif
    FILL(A0, 0); CALL(jx_gv_tag0)
    MOVI(A0, 0x85); MOVI(A1, 0); CALL(jx_jstub)     /* jne -> tur stubu */
    FILL(A0, 0); CALL(jx_int_set)
jni_done:
    LEAVE_
    RET
ENDFUNC(jx_need_int)

/* jx_d32(A0 = yuva, A1 = alan ofseti) - disp32 yaz */
FUNC(jx_d32)
    ENTER(1)
    SHLI(A0, 3)
    ADD(A0, A1)
    CALL(emit32)
    LEAVE_
    RET
ENDFUNC(jx_d32)

/* cmp dword [r13 + n*8 + ofs], 0     -> 41 83 BD d32 00 */
FUNC(jx_gv_tag0)
    ENTER(1)
    SPILL(0, A0)
    EB(0x41); EB(0x83); EB(0xBD)
    FILL(A0, 0); MOVI(A1, 0); CALL(jx_d32)
    EB(0x00)
    LEAVE_
    RET
ENDFUNC(jx_gv_tag0)

/* mov ecx, [r13 + n*8 + 4]           -> 41 8B 8D d32 */
FUNC(jx_gv_ld_ecx)
    ENTER(1)
    SPILL(0, A0)
    EB(0x41); EB(0x8B); EB(0x8D)
    FILL(A0, 0); MOVI(A1, 4); CALL(jx_d32)
    LEAVE_
    RET
ENDFUNC(jx_gv_ld_ecx)

/* add [r13 + n*8 + 4], ecx           -> 41 01 8D d32 */
FUNC(jx_gv_add_ecx)
    ENTER(1)
    SPILL(0, A0)
    EB(0x41); EB(0x01); EB(0x8D)
    FILL(A0, 0); MOVI(A1, 4); CALL(jx_d32)
    LEAVE_
    RET
ENDFUNC(jx_gv_add_ecx)

/* cmp [r13 + n*8 + 4], ecx           -> 41 39 8D d32 */
FUNC(jx_gv_cmp_ecx)
    ENTER(1)
    SPILL(0, A0)
    EB(0x41); EB(0x39); EB(0x8D)
    FILL(A0, 0); MOVI(A1, 4); CALL(jx_d32)
    LEAVE_
    RET
ENDFUNC(jx_gv_cmp_ecx)

/* add dword [r13 + n*8 + 4], imm32   -> 41 81 85 d32 imm32 */
FUNC(jx_gv_add_imm)
    ENTER(2)
    SPILL(0, A0)
    SPILL(1, A1)
    EB(0x41); EB(0x81); EB(0x85)
    FILL(A0, 0); MOVI(A1, 4); CALL(jx_d32)
    FILL(A0, 1); CALL(emit32)
    LEAVE_
    RET
ENDFUNC(jx_gv_add_imm)

/* cmp dword [r13 + n*8 + 4], imm32   -> 41 81 BD d32 imm32 */
FUNC(jx_gv_cmp_imm)
    ENTER(2)
    SPILL(0, A0)
    SPILL(1, A1)
    EB(0x41); EB(0x81); EB(0xBD)
    FILL(A0, 0); MOVI(A1, 4); CALL(jx_d32)
    FILL(A0, 1); CALL(emit32)
    LEAVE_
    RET
ENDFUNC(jx_gv_cmp_imm)

/* jx_kint(A0 = sabit indeksi) -> RV = 1 ise TAMSAYI, deger g_jit_kval'de
 * Sabitler DEGISMEZ: etiketleri ve degerleri JIT aninda biliniyor.
 * Bu yuzden sabitin tur denetimi ve bellek okumasi tamamen gereksiz. */
FUNC(jx_kint)
    ENTER(1)
    SHLI(A0, 3)
    LEA_SYM(A1, SYM(g_consts))
    LD(A1, A1)
    ADD(A0, A1)
    SPILL(0, A0)
    LD32(A1W, A0)
    BNZ(A1, jk_no)
    FILL(A0, 0)
    LD32_OFF(A0W, A0, VAL_PAY)
    LEA_SYM(A1, SYM(g_jit_kval))
    ST32_OFF(A1, 0, A0W)
    MOVI(RV, 1)
    LEAVE_
    RET
jk_no:
    MOVI(RV, 0)
    LEAVE_
    RET
ENDFUNC(jx_kint)

/* jx_local_off(A0 = yuva) : [r12 + yuva*8] adresini rax'e koy
 *   49 8D 84 24 <disp32>   lea rax, [r12 + disp32]
 * VF artik CALISMA ANINDA degisiyor (cagri destegi), bu yuzden yerel
 * adresi mutlak gomulemez - r12'ye goreli uretiliyor. */
FUNC(jx_local_off)
    ENTER(1)
    SHLI(A0, 3)
    SPILL(0, A0)
    EB(0x49); EB(0x8D); EB(0x84); EB(0x24)
    FILL(A0, 0)
    CALL(emit32)
    LEAVE_
    RET
ENDFUNC(jx_local_off)

/* const_addr(A0 = indeks) -> RV = mutlak adres */
FUNC(jx_const)
    ENTER(1)
    SHLI(A0, 3)
    LEA_SYM(A1, SYM(g_consts))
    LD(A1, A1)
    ADD(A0, A1)
    MOVR(RV, A0)
    LEAVE_
    RET
ENDFUNC(jx_const)

#endif /* ARCH_X86_64 */

#if defined(ARCH_X86_64)

/* jx_ret(A0 = donus degeri) : mov eax, imm32 ; jmp epilog
 * Basitlik icin epilog yerine dogrudan ret: cagiran (jit_run)
 * rbx'i kendisi kurtariyor. */
FUNC(jx_ret)
    ENTER(1)
    SPILL(0, A0)
    EB(0xB8)
    FILL(A0, 0)
    CALL(emit32)
    EB(0xC3)
    LEAVE_
    RET
ENDFUNC(jx_ret)

/* jx_here() -> RV = uretilen kodun su anki ofseti */
FUNC(jx_here)
    ENTER(1)
    LEA_SYM(A0, SYM(g_jit_pos))
    LD32(RVW, A0)
    LEAVE_
    RET
ENDFUNC(jx_here)

/* jx_fix(A0 = hedef bytecode indeksi)
 * 32-bit goreli atlama yer tutucusu yaz, yamalanmak uzere kaydet. */
FUNC(jx_fix)
    ENTER(2)
    SPILL(0, A0)
    CALL(jx_here)
    SPILL(1, RV)                    /* yer tutucunun ofseti */
    MOVI(A0, 0)
    CALL(emit32)
    LEA_SYM(A0, SYM(g_jit_nfix))
    LD32(A1W, A0)
    MOVR(A2, A1)
    INC(A2)
    ST32_OFF(A0, 0, A2W)
    MOVR(A0, A1)
    SHLI(A0, 3)
    LEA_SYM(A1, SYM(g_jit_fix))
    ADD(A0, A1)
    FILL(A1, 1)
    ST32_OFF(A0, 0, A1W)
    FILL(A1, 0)
    ST32_OFF(A0, 4, A1W)
    LEAVE_
    RET
ENDFUNC(jx_fix)

/* jx_patch() - butun goreli atlamalari yamala */
FUNC(jx_patch)
    ENTER(4)
    MOVI(A0, 0)
    SPILL(0, A0)
jp_loop:
    LEA_SYM(A0, SYM(g_jit_nfix))
    LD32(A0W, A0)
    FILL(A1, 0)
    CMPR(A1, A0)
    BHS(jp_done)
    FILL(A0, 0)
    SHLI(A0, 3)
    LEA_SYM(A1, SYM(g_jit_fix))
    ADD(A0, A1)
    LD32(A1W, A0)                   /* yer tutucu ofseti */
    SPILL(1, A1)
    LD32_OFF(A2W, A0, 4)            /* hedef bytecode indeksi */
    SHLI(A2, 2)
    LEA_SYM(A1, SYM(g_jit_map))
    ADD(A2, A1)
    LD32(A2W, A2)                   /* hedefin kod ofseti */
    SPILL(2, A2)
    /* goreli = hedef - (yer tutucu + 4) */
    FILL(A0, 1)
    ADDI(A0, 4)
    FILL(A1, 2)
    SUB(A1, A0)
    SPILL(3, A1)
    /* dogrudan tampona yaz */
    LEA_SYM(A0, SYM(g_jit_base))
    LD(A0, A0)
    FILL(A1, 1)
    ADD(A0, A1)
    FILL(A1, 3)
    ST32_OFF(A0, 0, A1W)
    FILL(A0, 0)
    INC(A0)
    SPILL(0, A0)
    B(jp_loop)
jp_done:
    LEAVE_
    RET
ENDFUNC(jx_patch)

#endif

#if defined(ARCH_X86_64)

/* =====================================================================
 * jit_compile() -> RV = 1 basarili / 0 (desteklenmeyen komut ya da
 *                       calistirilabilir bellek yok)
 *
 * Iki gecis:
 *   1) her bytecode komutu icin kod uret, g_jit_map[i] = kod ofseti
 *   2) goreli atlamalari yamala
 *
 * Slotlar: 0=i 1=n 2=ins 3=op 4=opd 5=gecici
 * ===================================================================== */
FUNC(jit_compile)
    ENTER(8)
    /* --- GECICI: 64-bit deger modeline gore YENIDEN YAZILMALI ---
     * Uretilen kod 8 baytlik yuva ve 32-bit yuk varsayiyor. Yuva 16
     * bayta cikti, yuk kelime genisliginde. Yanlis kod uretmektense
     * JIT'i kapatip yorumlayiciya dusmek DOGRU davranis. */
    MOVI(RV, 0)
    LEAVE_
    RET   /* fuzyon slot 6-7 kullaniyor: ENTER(6) ile cerceve
                * DISINA yaziliyordu */
    MOVI(A0, 0)
    LEA_SYM(A1, SYM(g_jit_ok)); ST32_OFF(A1, 0, A0W)
    LEA_SYM(A1, SYM(g_jit_nfix)); ST32_OFF(A1, 0, A0W)
    LEA_SYM(A1, SYM(g_jit_nsfix)); ST32_OFF(A1, 0, A0W)
    CALL(jit_init)
    BZ(RV, jc_no)

    /* --- NESNE DENETIMI ---
     * OP_ADD'in yorumlayicida DIZGI BIRLESTIRME dali var; JIT yalniz
     * tamsayi yolunu uretiyor. Aşama 15'te ADD_SETG ile ayni hataya
     * dusulmustu: bir hizli yol, yerini aldigi komutun BUTUN dallarini
     * tasimak zorunda.
     *
     * Ucuz ve KANITLANABILIR cozum: sabit havuzunda T_OBJ varsa hic
     * JIT etme. Cagri (OP_CALL) ve dizi (OP_ARRAY) zaten
     * desteklenmiyor, dolayisiyla nesne deger yigina baska turlu
     * giremez. Yani "JIT edilen programda nesne yoktur" statik olarak
     * garanti. */
    MOVI(A0, 0)
    SPILL(0, A0)
jc_scan:
    LEA_SYM(A0, SYM(g_nconst))
    LD32(A0W, A0)
    FILL(A1, 0)
    CMPR(A1, A0)
    BHS(jc_scanned)
    FILL(A0, 0)
    SHLI(A0, 3)
    LEA_SYM(A1, SYM(g_consts))
    LD(A1, A1)
    ADD(A0, A1)
    LD32(A0W, A0)
    CMPI(A0, T_OBJ)
    BEQ(jc_no)
    CMPI(A0, T_NAT)
    BEQ(jc_no)                      /* govde fonksiyonlari JIT'te yok */
    FILL(A0, 0)
    INC(A0)
    SPILL(0, A0)
    B(jc_scan)
jc_scanned:
    CALL(jx_mark_fns)
    CALL(jx_mark_tgts)
    CALL(jx_int_clr)
    MOVI(A0, 0)
    LEA_SYM(A1, SYM(g_jit_depth))
    ST32_OFF(A1, 0, A0W)

    MOVI(A0, 0)
    SPILL(0, A0)
    LEA_SYM(A0, SYM(g_ncode))
    LD32(A0W, A0)
    SPILL(1, A0)

jc_loop:
    FILL(A0, 0)
    FILL(A1, 1)
    CMPR(A0, A1)
    BHS(jc_fin)
    /* g_jit_map[i] = simdiki kod ofseti */
    CALL(jx_here)
    SPILL(5, RV)
    FILL(A0, 0)
    SHLI(A0, 2)
    LEA_SYM(A1, SYM(g_jit_map))
    ADD(A0, A1)
    FILL(A1, 5)
    ST32_OFF(A0, 0, A1W)

    /* Bu komut bir atlama HEDEFI ise buraya baska yerden de
     * girilebilir: blok ici kanitlar gecersiz. */
    FILL(A0, 0)
    LEA_SYM(A1, SYM(g_jit_tgt))
    LDB_IDX(A2W, A1, A0)
    BNZ(A2, jc_clr)
    /* Fonksiyon GIRISI de blok siniri: cagri her yerden gelebilir,
     * metinsel olarak onceki koddan gelen kanitlar gecersiz.
     * g_jit_tgt bunu isaretlemez (cagri bytecode atlamasi degil). */
    FILL(A0, 0)
    LEA_SYM(A1, SYM(g_in_fn))
    LDB_IDX(A2W, A1, A0)
    BZ(A2, jc_notgt)
    FILL(A0, 0)
    BZ(A0, jc_clr)
    DEC(A0)
    LEA_SYM(A1, SYM(g_in_fn))
    LDB_IDX(A2W, A1, A0)
    BNZ(A2, jc_notgt)               /* onceki de govdedeyse giris degil */
jc_clr:
    CALL(jx_int_clr)
jc_notgt:
    FILL(A0, 0)
    CALL(code_at)
    SPILL(2, RV)
    MOVR(A0, RV)
    ANDI(A0, 255)
    SPILL(3, A0)
    FILL(A0, 2)
    SHRI(A0, 16)
    SPILL(4, A0)

    /* --- JIT SEVIYESINDE FUZYON ---
     * "iki degeri it, sonra karsilastirip dalla" deseni yigina hic
     * dokunmadan tek karsilastirmaya iniyor. Sicak dongudeki son
     * yigin trafigi buydu (C referansiyla arayi 4,5 kattan kapatmak
     * icin). Yalniz i+1 atlama HEDEFI DEGILSE yutulabilir. */
    FILL(A0, 3)
    CMPI(A0, OP_GETG_CONST);  BEQ(jc_try_fuse)
    CMPI(A0, OP_GETGLOBAL2);  BEQ(jc_try_fuse)
    B(jc_nofuse)
jc_try_fuse:
    FILL(A0, 0)
    INC(A0)
    LEA_SYM(A1, SYM(g_ncode))
    LD32(A1W, A1)
    CMPR(A0, A1)
    BHS(jc_nofuse)
    LEA_SYM(A1, SYM(g_jit_tgt))
    LDB_IDX(A2W, A1, A0)
    BNZ(A2, jc_nofuse)              /* hedefse yutma */
    CALL(code_at)
    SPILL(6, RV)
    MOVR(A0, RV)
    ANDI(A0, 255)
    SPILL(7, A0)
    CMPI(A0, OP_JLT); BEQ(jc_fuse)
    CMPI(A0, OP_JLE); BEQ(jc_fuse)
    CMPI(A0, OP_JGT); BEQ(jc_fuse)
    CMPI(A0, OP_JGE); BEQ(jc_fuse)
    B(jc_nofuse)
jc_fuse:
    FILL(A0, 3)                     /* op  */
    FILL(A1, 4)                     /* opd */
    FILL(A2, 6)                     /* atlama komutu */
    CALL(jx_fused_cmp)
    FILL(A0, 0); INC(A0); SPILL(0, A0)   /* atlama komutunu da yut */
    CALL(jx_here)
    SPILL(5, RV)
    FILL(A0, 0); SHLI(A0, 2)
    LEA_SYM(A1, SYM(g_jit_map)); ADD(A0, A1)
    FILL(A1, 5); ST32_OFF(A0, 0, A1W)
    B(jc_next)
jc_nofuse:

    FILL(A0, 3)
    CMPI(A0, OP_CONST);       BEQ(jc_const)
    CMPI(A0, OP_GETGLOBAL);   BEQ(jc_getg)
    CMPI(A0, OP_GETGLOBAL2);  BEQ(jc_getg2)
    CMPI(A0, OP_GETG_CONST);  BEQ(jc_ggc)
    CMPI(A0, OP_DEFGLOBAL);   BEQ(jc_setg)
    CMPI(A0, OP_SETGLOBAL_P); BEQ(jc_setg)
    CMPI(A0, OP_POP);         BEQ(jc_pop)
    CMPI(A0, OP_ADD_SETG);    BEQ(jc_addsetg)
    CMPI(A0, OP_INCGLOBAL);   BEQ(jc_incg)
    CMPI(A0, OP_ACCG);        BEQ(jc_accg)
    CMPI(A0, OP_JMP);         BEQ(jc_jmp)
    CMPI(A0, OP_JLT);         BEQ(jc_jlt)
    CMPI(A0, OP_JGE);         BEQ(jc_jge)
    CMPI(A0, OP_JGT);         BEQ(jc_jgt)
    CMPI(A0, OP_JLE);         BEQ(jc_jle)
    CMPI(A0, OP_SETGLOBAL);   BEQ(jc_setg_keep)
    CMPI(A0, OP_NIL);         BEQ(jc_nil)
    CMPI(A0, OP_TRUE);        BEQ(jc_true)
    CMPI(A0, OP_FALSE);       BEQ(jc_false)
    CMPI(A0, OP_ADD);         BEQ(jc_add)
    CMPI(A0, OP_SUB);         BEQ(jc_sub)
    CMPI(A0, OP_MUL);         BEQ(jc_mul)
    CMPI(A0, OP_ADDK);        BEQ(jc_addk)
    CMPI(A0, OP_SUBK);        BEQ(jc_subk)
    CMPI(A0, OP_ADDK_SETG);   BEQ(jc_addksetg)
    CMPI(A0, OP_LT);          BEQ(jc_lt)
    CMPI(A0, OP_LE);          BEQ(jc_le)
    CMPI(A0, OP_GT);          BEQ(jc_gt)
    CMPI(A0, OP_GE);          BEQ(jc_ge)
    CMPI(A0, OP_JZ);          BEQ(jc_jz)
    CMPI(A0, OP_JNZ);         BEQ(jc_jnz)
    CMPI(A0, OP_GETLOCAL);    BEQ(jc_getl)
    CMPI(A0, OP_SETLOCAL);    BEQ(jc_setl_keep)
    CMPI(A0, OP_SETLOCAL_P);  BEQ(jc_setl)
    CMPI(A0, OP_GETLOCAL2);   BEQ(jc_getl2)
    CMPI(A0, OP_GETL_CONST);  BEQ(jc_glc)
    CMPI(A0, OP_ADD_SETL);    BEQ(jc_addsetl)
    CMPI(A0, OP_EQ);          BEQ(jc_eq)
    CMPI(A0, OP_NE);          BEQ(jc_ne)
    CMPI(A0, OP_JEQ);         BEQ(jc_jeq)
    CMPI(A0, OP_JNE);         BEQ(jc_jne)
    CMPI(A0, OP_CALL);        BEQ(jc_call)
    CMPI(A0, OP_RET);         BEQ(jc_ret)
    CMPI(A0, OP_RETL);        BEQ(jc_retl)
    CMPI(A0, OP_RETK);        BEQ(jc_retk)
    CMPI(A0, OP_DIV);         BEQ(jc_div)
    CMPI(A0, OP_MOD);         BEQ(jc_mod)
    CMPI(A0, OP_NEG);         BEQ(jc_neg)
    CMPI(A0, OP_NOT);         BEQ(jc_not)
    CMPI(A0, OP_JZP);         BEQ(jc_jzp)
    CMPI(A0, OP_JNZP);        BEQ(jc_jnzp)
    CMPI(A0, OP_PRINT);       BEQ(jc_print)
    CMPI(A0, OP_HALT);        BEQ(jc_halt)
    B(jc_no)                        /* desteklenmeyen: hic JIT etme */

jc_const:
    FILL(A0, 4); CALL(jx_const); MOVR(A0, RV); CALL(jx_abs)
    CALL(jx_push_rax)
    B(jc_next)

jc_getg:
    FILL(A0, 4); CALL(jx_gval); MOVR(A0, RV); CALL(jx_abs)
    CALL(jx_push_rax)
    B(jc_next)

jc_getg2:
    FILL(A0, 4); ANDI(A0, 255); CALL(jx_gval); MOVR(A0, RV); CALL(jx_abs)
    CALL(jx_push_rax)
    FILL(A0, 4); SHRI(A0, 8);   CALL(jx_gval); MOVR(A0, RV); CALL(jx_abs)
    CALL(jx_push_rax)
    B(jc_next)

jc_ggc:
    FILL(A0, 4); ANDI(A0, 255); CALL(jx_gval);  MOVR(A0, RV); CALL(jx_abs)
    CALL(jx_push_rax)
    FILL(A0, 4); SHRI(A0, 8);   CALL(jx_const); MOVR(A0, RV); CALL(jx_abs)
    CALL(jx_push_rax)
    B(jc_next)

jc_setg:
    /* yigindan geliyor: turu BILINMIYOR -> kanit gecersiz */
    FILL(A0, 4); CALL(jx_int_one)
    FILL(A0, 4); CALL(jx_gval); MOVR(A0, RV); CALL(jx_abs)
    CALL(jx_pop_to_rax)
    B(jc_next)

jc_pop:
    /* 48 83 EB 08   sub rbx, 8 */
    EB(0x48); EB(0x83); EB(0xEB); EB(0x08)
    B(jc_next)

jc_addsetg:
    /* iki tamsayiyi topla, gvals[n]'e yaz. Tur denetimi: iki etiket
     * de 0 olmali; degilse 0 dondurup yorumlayiciya birak. */
    CALL(jx_typecheck2)
    /* 8B 43 F4      mov eax, [rbx-12]   (birinci yuk) */
    EB(0x8B); EB(0x43); EB(0xF4)
    /* 03 43 FC      add eax, [rbx-4]    (ikinci yuk) */
    EB(0x03); EB(0x43); EB(0xFC)
    /* 0F 80 rel32   jo  -> tasma cikisi */
    CALL(jx_overflow_exit)
    /* 48 83 EB 10   sub rbx, 16 */
    EB(0x48); EB(0x83); EB(0xEB); EB(0x10)
    /* movabs rcx, &gvals[n] ; mov dword [rcx], 0 ; mov [rcx+4], eax */
    FILL(A0, 4); CALL(jx_gval); MOVR(A0, RV); CALL(jx_abs_rcx)
    EB(0xC7); EB(0x01); MOVI(A0, 0); CALL(emit32)
    EB(0x89); EB(0x41); EB(0x04)
    FILL(A0, 4); CALL(jx_int_set)
    B(jc_next)

jc_incg:
    /* gvals[n].pay += consts[k].pay
     * Sabit tamsayiysa: tur denetimi + bellek okumasi GEREKSIZ,
     * "add dword [r13+d], imm32" tek komut. */
    FILL(A0, 4); ANDI(A0, 255); SPILL(5, A0)
    FILL(A0, 5); CALL(jx_need_int)
    FILL(A0, 4); SHRI(A0, 8)
    CALL(jx_kint)
    BZ(RV, jci_slow)
    LEA_SYM(A0, SYM(g_jit_kval)); LD32(A1W, A0)
    FILL(A0, 5); CALL(jx_gv_add_imm)
    CALL(jx_overflow_exit)
    FILL(A0, 5); CALL(jx_int_set)
    B(jc_next)
jci_slow:
    FILL(A0, 4); SHRI(A0, 8); CALL(jx_const); MOVR(A0, RV); CALL(jx_abs_rcx)
    EB(0x8B); EB(0x49); EB(0x04)
    FILL(A0, 5); CALL(jx_gv_add_ecx)
    CALL(jx_overflow_exit)
    FILL(A0, 5); CALL(jx_int_set)
    B(jc_next)

jc_accg:
    /* gvals[a].pay += gvals[b].pay - ikisi de taban registeriyle */
    FILL(A0, 4); ANDI(A0, 255); SPILL(5, A0)
    FILL(A0, 5); CALL(jx_need_int)
    FILL(A0, 4); SHRI(A0, 8); SPILL(6, A0)
    FILL(A0, 6); CALL(jx_need_int)
    FILL(A0, 6); CALL(jx_gv_ld_ecx)
    FILL(A0, 5); CALL(jx_gv_add_ecx)
    CALL(jx_overflow_exit)
    FILL(A0, 5); CALL(jx_int_set)
    B(jc_next)

jc_jmp:
    EB(0xE9)
    FILL(A0, 4); CALL(jx_fix)
    B(jc_next)

jc_jlt:
    CALL(jx_cmp2)
    /* 0F 8C rel32   jl */
    EB(0x0F); EB(0x8C)
    FILL(A0, 4); CALL(jx_fix)
    B(jc_next)

jc_jge:
    CALL(jx_cmp2)
    /* 0F 8D rel32   jge */
    EB(0x0F); EB(0x8D)
    FILL(A0, 4); CALL(jx_fix)
    B(jc_next)

jc_jgt:
    CALL(jx_cmp2); EB(0x0F); EB(0x8F); FILL(A0, 4); CALL(jx_fix); B(jc_next)
jc_jle:
    CALL(jx_cmp2); EB(0x0F); EB(0x8E); FILL(A0, 4); CALL(jx_fix); B(jc_next)

jc_setg_keep:
    /* SETGLOBAL: yazar ama YIGINDAN ATMAZ */
    FILL(A0, 4); CALL(jx_int_one)
    FILL(A0, 4); CALL(jx_gval); MOVR(A0, RV); CALL(jx_abs)
    EB(0x8B); EB(0x4B); EB(0xF8)            /* mov ecx, [rbx-8]  */
    EB(0x89); EB(0x08)                      /* mov [rax], ecx    */
    EB(0x8B); EB(0x4B); EB(0xFC)            /* mov ecx, [rbx-4]  */
    EB(0x89); EB(0x48); EB(0x04)            /* mov [rax+4], ecx  */
    B(jc_next)

jc_nil:
    MOVI(A0, T_NIL);  MOVI(A1, 0); CALL(jx_pushi); B(jc_next)
jc_true:
    MOVI(A0, T_BOOL); MOVI(A1, 1); CALL(jx_pushi); B(jc_next)
jc_false:
    MOVI(A0, T_BOOL); MOVI(A1, 0); CALL(jx_pushi); B(jc_next)

jc_add:
    MOVI(A0, 0); CALL(jx_binop); B(jc_next)
jc_sub:
    MOVI(A0, 1); CALL(jx_binop); B(jc_next)
jc_mul:
    MOVI(A0, 2); CALL(jx_binop); B(jc_next)

jc_addk:
    FILL(A0, 4); MOVI(A1, 0); CALL(jx_kop); B(jc_next)
jc_subk:
    FILL(A0, 4); MOVI(A1, 1); CALL(jx_kop); B(jc_next)

jc_addksetg:
    /* ADDK_SETG (k | n<<8): tepe + consts[k] -> gvals[n], tepe atilir */
    FILL(A0, 4); ANDI(A0, 255); MOVI(A1, 0); CALL(jx_kop)
    EB(0x48); EB(0x83); EB(0xEB); EB(0x08)  /* sub rbx, 8 */
    FILL(A0, 4); SHRI(A0, 8); CALL(jx_gval); MOVR(A0, RV); CALL(jx_abs_rcx)
    EB(0xC7); EB(0x01); MOVI(A0, 0); CALL(emit32)   /* mov [rcx], T_INT */
    EB(0x89); EB(0x41); EB(0x04)                    /* mov [rcx+4], eax */
    FILL(A0, 4); SHRI(A0, 8); CALL(jx_int_set)
    B(jc_next)

jc_lt:
    MOVI(A0, 0x9C); CALL(jx_cmp_bool); B(jc_next)   /* setl  */
jc_le:
    MOVI(A0, 0x9E); CALL(jx_cmp_bool); B(jc_next)   /* setle */
jc_gt:
    MOVI(A0, 0x9F); CALL(jx_cmp_bool); B(jc_next)   /* setg  */
jc_ge:
    MOVI(A0, 0x9D); CALL(jx_cmp_bool); B(jc_next)   /* setge */

jc_jz:
    /* yanlissa atla: dl != 0 -> jnz */
    CALL(jx_falsy)
    EB(0x0F); EB(0x85); FILL(A0, 4); CALL(jx_fix); B(jc_next)
jc_jnz:
    /* dogruysa atla: dl == 0 -> jz */
    CALL(jx_falsy)
    EB(0x0F); EB(0x84); FILL(A0, 4); CALL(jx_fix); B(jc_next)

jc_getl:
    FILL(A0, 4); CALL(jx_local_off)
    CALL(jx_push_rax); B(jc_next)
jc_setl:
    FILL(A0, 4); CALL(jx_local_off)
    CALL(jx_pop_to_rax); B(jc_next)
jc_setl_keep:
    FILL(A0, 4); CALL(jx_local_off)
    EB(0x8B); EB(0x4B); EB(0xF8)
    EB(0x89); EB(0x08)
    EB(0x8B); EB(0x4B); EB(0xFC)
    EB(0x89); EB(0x48); EB(0x04)
    B(jc_next)
jc_getl2:
    FILL(A0, 4); ANDI(A0, 255); CALL(jx_local_off)
    CALL(jx_push_rax)
    FILL(A0, 4); SHRI(A0, 8);   CALL(jx_local_off)
    CALL(jx_push_rax); B(jc_next)
jc_glc:
    FILL(A0, 4); ANDI(A0, 255); CALL(jx_local_off)
    CALL(jx_push_rax)
    FILL(A0, 4); SHRI(A0, 8);   CALL(jx_const); MOVR(A0, RV); CALL(jx_abs)
    CALL(jx_push_rax); B(jc_next)
jc_addsetl:
    CALL(jx_typecheck2)
    EB(0x8B); EB(0x43); EB(0xF4)
    EB(0x03); EB(0x43); EB(0xFC)
    CALL(jx_overflow_exit)
    EB(0x48); EB(0x83); EB(0xEB); EB(0x10)
    FILL(A0, 4); CALL(jx_local_off)
    EB(0x48); EB(0x89); EB(0xC1)            /* mov rcx, rax */
    EB(0xC7); EB(0x01); MOVI(A0, 0); CALL(emit32)
    EB(0x89); EB(0x41); EB(0x04)
    B(jc_next)

jc_eq:
    MOVI(A0, 0x94); CALL(jx_eqcmp); B(jc_next)      /* sete  */
jc_ne:
    MOVI(A0, 0x95); CALL(jx_eqcmp); B(jc_next)      /* setne */
jc_jeq:
    CALL(jx_eqflags)
    EB(0x0F); EB(0x84); FILL(A0, 4); CALL(jx_fix); B(jc_next)
jc_jne:
    CALL(jx_eqflags)
    EB(0x0F); EB(0x85); FILL(A0, 4); CALL(jx_fix); B(jc_next)

jc_call:
    /* cagrilan kureselleri degistirebilir -> butun kanitlar gecersiz */
    CALL(jx_int_clr)
    FILL(A0, 4)
    CALL(jx_emit_call)
    B(jc_next)

jc_ret:
    /* sonuc yigin tepesinde: [rbx-8] */
    EB(0x8B); EB(0x43); EB(0xF8)            /* mov eax, [rbx-8] */
    EB(0x8B); EB(0x4B); EB(0xFC)            /* mov ecx, [rbx-4] */
    FILL(A0, 0)
    CALL(jx_emit_ret)
    B(jc_next)
jc_retl:
    FILL(A0, 4); CALL(jx_local_off)         /* rax = &yerel[n] */
    EB(0x8B); EB(0x48); EB(0x04)            /* mov ecx, [rax+4] */
    EB(0x8B); EB(0x00)                      /* mov eax, [rax]   */
    FILL(A0, 0)
    CALL(jx_emit_ret)
    B(jc_next)
jc_retk:
    FILL(A0, 4); CALL(jx_const); MOVR(A0, RV); CALL(jx_abs)
    EB(0x8B); EB(0x48); EB(0x04)
    EB(0x8B); EB(0x00)
    FILL(A0, 0)
    CALL(jx_emit_ret)
    B(jc_next)

jc_div:
    MOVI(A0, 0); CALL(jx_divmod); B(jc_next)
jc_mod:
    MOVI(A0, 1); CALL(jx_divmod); B(jc_next)

jc_neg:
    /* NEED_INT1 + negl + tasma */
    EB(0x83); EB(0x7B); EB(0xF8); EB(0x00)
    MOVI(A0, 0x85); MOVI(A1, 0); CALL(jx_jstub)
    EB(0x8B); EB(0x43); EB(0xFC)            /* mov eax, [rbx-4] */
    EB(0xF7); EB(0xD8)                      /* neg eax          */
    CALL(jx_overflow_exit)
    EB(0x89); EB(0x43); EB(0xFC)
    B(jc_next)

jc_not:
    /* yanlis ise dogru, degilse yanlis (yigindan atmadan yerinde) */
    CALL(jx_falsy_peek)
    EB(0x0F); EB(0x95); EB(0xC0)            /* setne al  -> dl!=0 ise 1 */
    EB(0x0F); EB(0xB6); EB(0xC0)            /* movzx eax, al */
    EB(0xC7); EB(0x43); EB(0xF8); MOVI(A0, T_BOOL); CALL(emit32)
    EB(0x89); EB(0x43); EB(0xFC)
    B(jc_next)

jc_jzp:
    CALL(jx_falsy_peek)
    EB(0x0F); EB(0x85); FILL(A0, 4); CALL(jx_fix); B(jc_next)
jc_jnzp:
    CALL(jx_falsy_peek)
    EB(0x0F); EB(0x84); FILL(A0, 4); CALL(jx_fix); B(jc_next)

jc_print:
    /* rdi = rbx - 8 ; call print_val ; rdi = 10 ; call print_ch ; rbx -= 8 */
    EB(0x48); EB(0x89); EB(0xDF)            /* mov rdi, rbx */
    EB(0x48); EB(0x83); EB(0xEF); EB(0x08)  /* sub rdi, 8   */
    LEA_SYM(A0, SYM(print_val)); CALL(jx_call_abs)
    EB(0xBF); MOVI(A0, 10); CALL(emit32)    /* mov edi, 10  */
    LEA_SYM(A0, SYM(print_ch)); CALL(jx_call_abs)
    EB(0x48); EB(0x83); EB(0xEB); EB(0x08)  /* sub rbx, 8   */
    B(jc_next)

jc_halt:
    MOVI(A0, 1)
    CALL(jx_ret)
    B(jc_next)

jc_next:
    FILL(A0, 0)
    INC(A0)
    SPILL(0, A0)
    B(jc_loop)

jc_fin:
    /* son komuttan sonra da bir harita girdisi (atlama hedefi olabilir) */
    CALL(jx_here)
    SPILL(5, RV)
    FILL(A0, 1); SHLI(A0, 2)
    LEA_SYM(A1, SYM(g_jit_map)); ADD(A0, A1)
    FILL(A1, 5); ST32_OFF(A0, 0, A1W)
    MOVI(A0, 1)
    CALL(jx_ret)
    CALL(jx_emit_stubs)
    CALL(jx_patch)
    /* fonksiyon indeksi -> uretilen kod adresi tablosunu doldur */
    MOVI(A0, 0)
    SPILL(0, A0)
jc_fnmap:
    LEA_SYM(A0, SYM(g_nfn))
    LD32(A0W, A0)
    FILL(A1, 0)
    CMPR(A1, A0)
    BHS(jc_fnmapped)
    FILL(A0, 0)
    SHLI(A0, 3)
    LEA_SYM(A1, SYM(g_fns))
    ADD(A0, A1)
    LD32(A0W, A0)                   /* giris komut indeksi */
    SHLI(A0, 2)
    LEA_SYM(A1, SYM(g_jit_map))
    ADD(A0, A1)
    LD32(A0W, A0)                   /* kod ofseti */
    LEA_SYM(A1, SYM(g_jit_base))
    LD(A1, A1)
    ADD(A0, A1)                     /* mutlak adres */
    SPILL(5, A0)
    FILL(A0, 0)
    SHLI(A0, 3)
    LEA_SYM(A1, SYM(g_jit_fnmap))
    ADD(A0, A1)
    FILL(A1, 5)
    ST(A0, A1)
    FILL(A0, 0); INC(A0); SPILL(0, A0)
    B(jc_fnmap)
jc_fnmapped:
    MOVI(A0, 1)
    LEA_SYM(A1, SYM(g_jit_ok)); ST32_OFF(A1, 0, A0W)
    MOVI(RV, 1)
    LEAVE_
    RET
jc_no:
    MOVI(RV, 0)
    LEAVE_
    RET
ENDFUNC(jit_compile)

#endif

#if defined(ARCH_X86_64)

/* --- hata cikislari ---
 * Uretilen kod tur uyusmazligi ya da tasma gorunce 0 dondurur.
 * Cagiran (jit_run) bunu gorup YORUMLAYICIYA duser: boylece hata
 * iletisi ve tam semantik yorumlayicidan gelir, JIT'te tekrarlanmaz.
 */

/* jx_abs_rcx(A0 = adres) : movabs %rcx, imm64 */
FUNC(jx_abs_rcx)
    ENTER(1)
    SPILL(0, A0)
    EB(0x48); EB(0xB9)
    FILL(A0, 0); CALL(emit32)
    FILL(A0, 0); SHRI(A0, 32); CALL(emit32)
    LEAVE_
    RET
ENDFUNC(jx_abs_rcx)

/* jx_call_abs(A0 = fonksiyon adresi) : movabs rax,f ; call rax */
FUNC(jx_call_abs)
    ENTER(1)
    CALL(jx_abs)
    EB(0xFF); EB(0xD0)
    LEAVE_
    RET
ENDFUNC(jx_call_abs)

/* --- CALISMA ANI HATASI: yorumlayiciya DUSULMEZ ---
 *
 * Ilk tasarimda uretilen kod hata gorunce 0 dondurup yorumlayiciya
 * birakiyordu. YANLISTI: JIT o ana kadar yan etkileri yapmis oluyor
 * (yazdir vb.) ve yorumlayici programi BASTAN calistirinca ciktilar
 * TEKRARLANIYORDU. Olculdu: "111|222|111|222|tasma".
 *
 * Dogrusu: uretilen kod hatayi KENDISI bildirir ve 1 (islendi) doner.
 * Yorumlayiciya dusme yalnizca DERLEME aninda, hic yan etki
 * olusmadan yapilabilir.
 */
    SECT_RODATA
jx_e_type: .ascii "calisma hatasi: tur uyusmazligi\n"
    .equ jx_e_type_len, . - jx_e_type
jx_e_ovf:  .ascii "calisma hatasi: tamsayi tasmasi\n"
    .equ jx_e_ovf_len, . - jx_e_ovf
jx_e_div:  .ascii "calisma hatasi: sifira bolme\n"
    .equ jx_e_div_len, . - jx_e_div
jx_e_call: .ascii "calisma hatasi: cagrilabilir degil\n"
    .equ jx_e_call_len, . - jx_e_call
jx_e_ar:   .ascii "calisma hatasi: arguman sayisi uymuyor\n"
    .equ jx_e_ar_len, . - jx_e_ar
jx_e_dep:  .ascii "calisma hatasi: cagri derinligi asildi\n"
    .equ jx_e_dep_len, . - jx_e_dep
    SECT_TEXT





    ENTER(1)
    LEA_SYM(A0, jx_e_call); MOVI(A1, jx_e_call_len); CALL(print_str)
    LEA_SYM(A0, SYM(g_rterr)); LD32(A1W, A0); INC(A1); ST32_OFF(A0, 0, A1W)
    LEAVE_
    RET




FUNC(jit_err_type)
    ENTER(1)
    LEA_SYM(A0, jx_e_type); MOVI(A1, jx_e_type_len); CALL(print_str)
    LEA_SYM(A0, SYM(g_rterr)); LD32(A1W, A0); INC(A1); ST32_OFF(A0, 0, A1W)
    LEAVE_
    RET
ENDFUNC(jit_err_type)

FUNC(jit_err_ovf)
    ENTER(1)
    LEA_SYM(A0, jx_e_ovf); MOVI(A1, jx_e_ovf_len); CALL(print_str)
    LEA_SYM(A0, SYM(g_rterr)); LD32(A1W, A0); INC(A1); ST32_OFF(A0, 0, A1W)
    LEAVE_
    RET
ENDFUNC(jit_err_ovf)

FUNC(jit_err_div)
    ENTER(1)
    LEA_SYM(A0, jx_e_div); MOVI(A1, jx_e_div_len); CALL(print_str)
    LEA_SYM(A0, SYM(g_rterr)); LD32(A1W, A0); INC(A1); ST32_OFF(A0, 0, A1W)
    LEAVE_
    RET
ENDFUNC(jit_err_div)

FUNC(jit_err_call)
    ENTER(1)
    LEA_SYM(A0, jx_e_call); MOVI(A1, jx_e_call_len); CALL(print_str)
    LEA_SYM(A0, SYM(g_rterr)); LD32(A1W, A0); INC(A1); ST32_OFF(A0, 0, A1W)
    LEAVE_
    RET
ENDFUNC(jit_err_call)

FUNC(jit_err_arity)
    ENTER(1)
    LEA_SYM(A0, jx_e_ar); MOVI(A1, jx_e_ar_len); CALL(print_str)
    LEA_SYM(A0, SYM(g_rterr)); LD32(A1W, A0); INC(A1); ST32_OFF(A0, 0, A1W)
    LEAVE_
    RET
ENDFUNC(jit_err_arity)

FUNC(jit_err_depth)
    ENTER(1)
    LEA_SYM(A0, jx_e_dep); MOVI(A1, jx_e_dep_len); CALL(print_str)
    LEA_SYM(A0, SYM(g_rterr)); LD32(A1W, A0); INC(A1); ST32_OFF(A0, 0, A1W)
    LEAVE_
    RET
ENDFUNC(jit_err_depth)

/* jx_bail(A0 = yardimci fonksiyon adresi) - TAM 18 bayt:
 *   48 B8 imm64   movabs rax, yardimci   (10)
 *   FF D0         call rax               ( 2)
 *   B8 01000000   mov eax, 1             ( 5)
 *   C3            ret                    ( 1)
 * Uzunluk sabit oldugu icin atlama ofsetleri BAIL_LEN ile yazilir. */
FUNC(jx_bail)
    ENTER(1)
    CALL(jx_abs)
    EB(0xFF); EB(0xD0)
    LEA_SYM(A0, SYM(g_jit_sp)); CALL(jx_abs)
    EB(0x48); EB(0x8B); EB(0x20)            /* mov rsp, [rax] */
    EB(0xB8); MOVI(A0, 1); CALL(emit32)
    EB(0xC3)
    LEAVE_
    RET
ENDFUNC(jx_bail)

/* jx_typecheck2() : [rbx-16] ve [rbx-8] etiketleri 0 mi
 *   8B 43 F0      mov eax, [rbx-16]
 *   0B 43 F8      or  eax, [rbx-8]
 *   74 02         jz  +2      (tamam, atla)
 *   <exit0: 3 bayt>
 */
FUNC(jx_typecheck2)
    ENTER(1)
    EB(0x8B); EB(0x43); EB(0xF0)
    EB(0x0B); EB(0x43); EB(0xF8)
    MOVI(A0, 0x85); MOVI(A1, 0); CALL(jx_jstub)
    LEAVE_
    RET
ENDFUNC(jx_typecheck2)

/* jx_typecheck_rax() : [rax] etiketi 0 mi
 *   83 38 00      cmp dword [rax], 0
 *   74 03         jz +3
 *   <exit0>
 */
FUNC(jx_typecheck_rax)
    ENTER(1)
    EB(0x83); EB(0x38); EB(0x00)
    MOVI(A0, 0x85); MOVI(A1, 0); CALL(jx_jstub)
    LEAVE_
    RET
ENDFUNC(jx_typecheck_rax)

/* jx_bail_ne() : bir onceki cmp esit degilse yorumlayiciya dus
 *   74 03         jz +3
 *   <exit0>
 */
FUNC(jx_bail_ne)
    ENTER(1)
    MOVI(A0, 0x85); MOVI(A1, 0); CALL(jx_jstub)
    LEAVE_
    RET
ENDFUNC(jx_bail_ne)

/* jx_overflow_exit() : tasma bayragi varsa yorumlayiciya dus
 *   71 03         jno +3
 *   <exit0>
 */
FUNC(jx_overflow_exit)
    ENTER(1)
    MOVI(A0, 0x80); MOVI(A1, 1); CALL(jx_jstub)     /* jo -> tasma stubu */
    LEAVE_
    RET
ENDFUNC(jx_overflow_exit)

/* jx_cmp2() : iki tamsayiyi karsilastir, ikisini de yigindan at
 *   <typecheck2>
 *   8B 43 F4      mov eax, [rbx-12]
 *   3B 43 FC      cmp eax, [rbx-4]
 *   48 83 EB 10   sub rbx, 16
 * Bayraklar korunur (sub rbx bayrak degistirir!) -> once sub, sonra cmp
 */
FUNC(jx_cmp2)
    ENTER(1)
    CALL(jx_typecheck2)
    EB(0x8B); EB(0x43); EB(0xF4)            /* mov eax, [rbx-12] */
    EB(0x8B); EB(0x4B); EB(0xFC)            /* mov ecx, [rbx-4]  */
    EB(0x48); EB(0x83); EB(0xEB); EB(0x10)  /* sub rbx, 16       */
    EB(0x39); EB(0xC8)                      /* cmp eax, ecx      */
    LEAVE_
    RET
ENDFUNC(jx_cmp2)

#endif

#if defined(ARCH_X86_64)
/* jit_dump(A0 = yol) - uretilen kodu dosyaya yaz (objdump ile
 * dogrulamak icin). Elle kodlanmis makine kodunu GOZLE dogrulamak
 * sart; tahminle yazmak kabul edilemez. */
FUNC(jit_dump)
    ENTER(2)
    MOVI(A1, 1)
    CALL(os_open)
    MOVR(A0, RV)
    CMPI(A0, 0)
    BLT(jd_no)
    SPILL(0, A0)
    LEA_SYM(A1, SYM(g_jit_base))
    LD(A1, A1)
    LEA_SYM(A2, SYM(g_jit_pos))
    LD32(A2W, A2)
    FILL(A0, 0)
    CALL(os_write)
    FILL(A0, 0)
    CALL(os_close)
    MOVI(RV, 1)
    LEAVE_
    RET
jd_no:
    MOVI(RV, 0)
    LEAVE_
    RET
ENDFUNC(jit_dump)

/* jit_run() -> RV = 1 JIT calisti / 0 yorumlayiciya dus
 * rbx (VS) cagrilan-korumali: kaydet, yigin tabanini ver, geri al. */
FUNC(jit_run)
    ENTER(2)
    LEA_SYM(A0, SYM(g_jc_ok))
    LD32(A0W, A0)
    BZ(A0, jr_no)
    pushq %rbx
    pushq %r12
    leaq SYM(g_stack)(%rip), %rbx
    movq %rbx, %r12                     /* VF = yigin tabani */
    leaq SYM(g_gvals)(%rip), %r13       /* taban registeri */
    pushq %r13
    leaq SYM(g_gvals)(%rip), %r13       /* taban registeri */
    leaq -8(%rsp), %rax                 /* cagri sonrasi rsp */
    movq %rax, SYM(g_jit_sp)(%rip)
    leaq SYM(g_jit_base)(%rip), %rax
    movq (%rax), %rax
    call *%rax
    popq %r13
    popq %r12
    popq %rbx
    LEAVE_
    RET
jr_no:
    MOVI(RV, 0)
    LEAVE_
    RET
ENDFUNC(jit_run)
#endif

#if defined(ARCH_X86_64)

/* jx_falsy() : tepedeki degeri al, "yanlis mi" bayragini dl'e koy
 * Yorumlayicidaki kural: yanlis = T_NIL, ya da (T_BOOL ve yuk == 0).
 * Digerlerinin hepsi dogru.
 *   48 83 EB 08   sub rbx, 8
 *   8B 03         mov eax, [rbx]        (etiket)
 *   8B 4B 04      mov ecx, [rbx+4]      (yuk)
 *   31 D2         xor edx, edx
 *   83 F8 01      cmp eax, T_NIL
 *   0F 94 C2      sete dl
 *   83 F8 02      cmp eax, T_BOOL
 *   75 05         jne +5
 *   85 C9         test ecx, ecx
 *   0F 94 C2      sete dl
 *   84 D2         test dl, dl           -> ZF=0 ise YANLIS
 */
FUNC(jx_falsy)
    ENTER(1)
    EB(0x48); EB(0x83); EB(0xEB); EB(0x08)
    EB(0x8B); EB(0x03)
    EB(0x8B); EB(0x4B); EB(0x04)
    EB(0x31); EB(0xD2)
    EB(0x83); EB(0xF8); EB(T_NIL)
    EB(0x0F); EB(0x94); EB(0xC2)
    EB(0x83); EB(0xF8); EB(T_BOOL)
    EB(0x75); EB(0x05)
    EB(0x85); EB(0xC9)
    EB(0x0F); EB(0x94); EB(0xC2)
    EB(0x84); EB(0xD2)
    LEAVE_
    RET
ENDFUNC(jx_falsy)

/* jx_falsy_peek() : jx_falsy ile ayni ama YIGINDAN ATMAZ
 * (kisa devre: JZP/JNZP degeri yiginda birakir) */
FUNC(jx_falsy_peek)
    ENTER(1)
    EB(0x8B); EB(0x43); EB(0xF8)            /* mov eax, [rbx-8]  */
    EB(0x8B); EB(0x4B); EB(0xFC)            /* mov ecx, [rbx-4]  */
    EB(0x31); EB(0xD2)
    EB(0x83); EB(0xF8); EB(T_NIL)
    EB(0x0F); EB(0x94); EB(0xC2)
    EB(0x83); EB(0xF8); EB(T_BOOL)
    EB(0x75); EB(0x05)
    EB(0x85); EB(0xC9)
    EB(0x0F); EB(0x94); EB(0xC2)
    EB(0x84); EB(0xD2)
    LEAVE_
    RET
ENDFUNC(jx_falsy_peek)

/* jx_divmod(A0 = 0 bolum / 1 kalan)
 *   <typecheck2>
 *   8B 4B FC      mov ecx, [rbx-4]      (bolen)
 *   85 C9         test ecx, ecx
 *   75 <BAIL>     jnz +BAIL             (sifirsa duser)
 *   <bail: sifira bolme>
 *   8B 43 F4      mov eax, [rbx-12]     (bolunen)
 *   99            cdq                   (isaret genisletme)
 *   F7 F9         idiv ecx              (eax=bolum, edx=kalan)
 *   48 83 EB 08   sub rbx, 8
 *   89 43 FC / 89 53 FC   mov [rbx-4], eax|edx
 * NOT: INT_MIN / -1 donanimda tuzak uretir; yorumlayici da tasma
 * hatasi veriyor. Bolen -1 ise once tasma denetimine dusuruluyor.
 */
FUNC(jx_divmod)
    ENTER(1)
    SPILL(0, A0)
    CALL(jx_typecheck2)
    EB(0x8B); EB(0x4B); EB(0xFC)
    EB(0x85); EB(0xC9)
    MOVI(A0, 0x84); MOVI(A1, 2); CALL(jx_jstub)     /* jz -> sifira bolme */
    /* Donanimda tuzak ureten TEK durum: INT_MIN / -1.
     * Ilk yazdigimda "bolen == -1" yeterli sandim ve -2147483647 / -1
     * gibi GECERLI islemleri de reddediyordum. Ikisini birden denetle:
     *   83 F9 FF            cmp ecx, -1
     *   75 1B               jne +27   (cmp 7 + jne 2 + bail 18)
     *   81 7B F4 <INT_MIN>  cmp dword [rbx-12], 0x80000000
     *   75 12               jne +18   (bail)
     *   <bail 18>
     */
    EB(0x83); EB(0xF9); EB(0xFF)
    EB(0x75); EB(7 + 6)                     /* bolen -1 degilse atla */
    EB(0x81); EB(0x7B); EB(0xF4)
    EB(0x00); EB(0x00); EB(0x00); EB(0x80)
    MOVI(A0, 0x84); MOVI(A1, 1); CALL(jx_jstub)     /* jz -> tasma */
    EB(0x8B); EB(0x43); EB(0xF4)
    EB(0x99)
    EB(0xF7); EB(0xF9)
    EB(0x48); EB(0x83); EB(0xEB); EB(0x08)
    FILL(A0, 0)
    BNZ(A0, jd_mod)
    EB(0x89); EB(0x43); EB(0xFC)            /* bolum */
    B(jd_done)
jd_mod:
    EB(0x89); EB(0x53); EB(0xFC)            /* kalan */
jd_done:
    LEAVE_
    RET
ENDFUNC(jx_divmod)

/* jx_emit_call(A0 = arguman sayisi)
 *
 * Cagri duzeni yorumlayicidakiyle AYNI yigin etkisine sahip:
 *   girisde:  [cagrilan][arg0..argN-1]   rbx sonrasinda
 *   cikista:  [sonuc]                    rbx = eski - argc*8
 * Fark: donus adresi g_frames'te degil YEREL CAGRI YIGININDA.
 * r12 = VF; cagri oncesi saklanip sonra geri aliniyor.
 *
 * Denetimler (yorumlayicidakilerle ayni): cagrilabilir mi, arite,
 * ozyineleme derinligi. Bunlar CALISMA ANI denetimleri; hata olursa
 * uretilen kod kendisi bildirir (yorumlayiciya DUSULMEZ - o ana kadar
 * yan etki olusmus olabilir).
 */
FUNC(jx_emit_call)
    ENTER(4)
    SPILL(0, A0)                    /* argc */
    FILL(A0, 0); INC(A0); SHLI(A0, 3)
    MOVI(A1, 0); SUB(A1, A0)
    SPILL(1, A1)                    /* -(argc+1)*8 : cagrilanin yeri */
    FILL(A0, 0); SHLI(A0, 3)
    MOVI(A1, 0); SUB(A1, A0)
    SPILL(2, A1)                    /* -argc*8 : ilk arguman = yeni VF */

    /* --- cagrilanin etiketi T_FN mi ---
     * DIKKAT: EB() makrosu A0'i ezer ve CALL A1'i korumaz. Bu yuzden
     * her yer degistirme degeri ONCE slota dokuluyor, bayt uretimi
     * SONRA yapiliyor. Ilk yazdigimda bu sirayi bozmustum ve uretilen
     * kod cop adres kullaniyordu. */
    EB(0x8B); EB(0x83)
    FILL(A0, 1); CALL(emit32)                       /* mov eax,[rbx+d] */
    EB(0x83); EB(0xF8); EB(T_FN)
    MOVI(A0, 0x85); MOVI(A1, 3); CALL(jx_jstub)

    /* --- fonksiyon indeksi --- */
    EB(0x8B); EB(0x8B)
    FILL(A0, 1); ADDI(A0, 4); CALL(emit32)          /* mov ecx,[rbx+d+4] */

    /* --- arite denetimi --- */
    LEA_SYM(A0, SYM(g_fns)); CALL(jx_abs)
    EB(0x8B); EB(0x54); EB(0xC8); EB(0x04)          /* mov edx,[rax+rcx*8+4] */
    EB(0x81); EB(0xFA)
    FILL(A0, 0); CALL(emit32)                       /* cmp edx, argc */
    MOVI(A0, 0x85); MOVI(A1, 4); CALL(jx_jstub)

    /* --- hedef adres (push'tan ONCE: bail yigini bozmasin) --- */
    LEA_SYM(A0, SYM(g_jit_fnmap)); CALL(jx_abs)
    EB(0x48); EB(0x8B); EB(0x04); EB(0xC8)          /* mov rax,[rax+rcx*8] */
    EB(0x48); EB(0x85); EB(0xC0)
    MOVI(A0, 0x84); MOVI(A1, 3); CALL(jx_jstub)

    /* --- derinlik denetimi (yerel yigin tasmasini onler) --- */
    EB(0x50)                                        /* push rax (hedef) */
    LEA_SYM(A0, SYM(g_jit_depth)); CALL(jx_abs_rcx)
    EB(0xFF); EB(0x01)                              /* inc dword [rcx] */
    EB(0x81); EB(0x39)
    MOVI(A0, MAX_FRAMES); CALL(emit32)              /* cmp [rcx], MAX */
    MOVI(A0, 0x87); MOVI(A1, 5); CALL(jx_jstub)     /* ja -> derinlik stubu
                                                     * (once "jbe +7" ile
                                                     * atlatiyordum ama blok
                                                     * 6 bayt: 1 bayt kayiyor
                                                     * ve ORTASINA dusuyordu) */

    /* --- VF sakla, yeni VF, cagir, geri al ---
     * Yigin sirasi: [hedef adres][eski r12]
     *   41 54         push r12
     *   4C 8D A3 d32  lea r12, [rbx - argc*8]
     *   48 8B 44 24 08 mov rax, [rsp+8]   (hedef adresi tazele)
     *   FF D0         call rax
     *   41 5C         pop r12
     *   48 83 C4 08   add rsp, 8          (hedef adresi at)
     */
    EB(0x41); EB(0x54)
    EB(0x4C); EB(0x8D); EB(0xA3)
    FILL(A0, 2); CALL(emit32)
    EB(0x48); EB(0x8B); EB(0x44); EB(0x24); EB(0x08)
    EB(0xFF); EB(0xD0)
    EB(0x41); EB(0x5C)
    EB(0x48); EB(0x83); EB(0xC4); EB(0x08)
    LEA_SYM(A0, SYM(g_jit_depth)); CALL(jx_abs_rcx)
    EB(0xFF); EB(0x09)                              /* dec dword [rcx] */
    LEAVE_
    RET
ENDFUNC(jx_emit_call)

/* jx_emit_ret() : sonuc eax(etiket)/ecx(yuk) icinde
 *   4C 89 E3      mov rbx, r12          (VS = VF)
 *   48 83 EB 08   sub rbx, 8            (cagrilan yuvasi atilir)
 *   89 03         mov [rbx], eax
 *   89 4B 04      mov [rbx+4], ecx
 *   48 83 C3 08   add rbx, 8
 *   B8 01000000   mov eax, 1
 *   C3            ret
 * En dis seviyedeki RET yorumlayicida HALT demek: orada yigin
 * oynatilmadan dogrudan donuluyor.
 */
/* jx_emit_ret(A0 = komut indeksi)
 * DIKKAT: indeks ARGUMAN olarak gelmeli. Ilk yazdigimda kendi
 * cercevemin slot 0'indan okuyordum - orasi bos, yani her RET
 * rastgele davraniyordu ve deger yiginini bozuyordu. Kanarya yakaladi. */
FUNC(jx_emit_ret)
    ENTER(1)
    MOVR(A1, A0)
    LEA_SYM(A0, SYM(g_in_fn))
    LDB_IDX(A0W, A0, A1)
    BZ(A0, jer_top)
    EB(0x4C); EB(0x89); EB(0xE3)
    EB(0x48); EB(0x83); EB(0xEB); EB(0x08)
    EB(0x89); EB(0x03)
    EB(0x89); EB(0x4B); EB(0x04)
    EB(0x48); EB(0x83); EB(0xC3); EB(0x08)
jer_top:
    EB(0xB8); MOVI(A0, 1); CALL(emit32)
    EB(0xC3)
    LEAVE_
    RET
ENDFUNC(jx_emit_ret)

/* jx_fused_cmp() - slot 3=op, 4=opd, 6=atlama komutu, 7=atlama opkodu
 *
 * GETG_CONST(n,k) + Jcc  ->  gvals[n] ile consts[k] dogrudan
 * GETGLOBAL2(a,b) + Jcc  ->  gvals[a] ile gvals[b] dogrudan
 *
 *   48 B8 <adr1>   movabs rax, birinci
 *   83 38 00       cmp dword [rax], 0      (tur denetimi)
 *   75 <BAIL> ...
 *   48 B9 <adr2>   movabs rcx, ikinci
 *   83 39 00       cmp dword [rcx], 0
 *   75 <BAIL> ...
 *   8B 49 04       mov ecx, [rcx+4]
 *   39 48 04       cmp [rax+4], ecx
 *   0F 8x rel32    jcc hedef
 */
/* DIKKAT: op/opd/atlama ARGUMAN olarak gelir. Cagiranin cerceve
 * slotlarini kendi cercevemden okumak bu projede UCUNCU kez yapilan
 * hata (jx_emit_ret, jx_fused_cmp). Yardimci fonksiyon cagiranin
 * slotlarini GOREMEZ. */
/* jx_fused_cmp(A0 = op, A1 = opd, A2 = atlama komutu)
 *
 * "iki degeri it, sonra karsilastirip dalla" -> tek karsilastirma.
 * Taban registeri ve sabit katlamayla en iyi durumda IKI komut:
 *     cmp dword [r13+d], 0     ; tur denetimi
 *     cmp dword [r13+d+4], imm ; karsilastirma
 *     jcc hedef
 */
FUNC(jx_fused_cmp)
    ENTER(5)
    SPILL(0, A0)
    SPILL(1, A1)
    SPILL(2, A2)
    MOVR(A0, A2); ANDI(A0, 255); SPILL(3, A0)
    FILL(A0, 1); ANDI(A0, 255); SPILL(4, A0)    /* birinci yuva */
    FILL(A0, 4); CALL(jx_need_int)
    FILL(A0, 0)
    CMPI(A0, OP_GETG_CONST)
    BNE(fc_g2)
    /* sabit: katlanabiliyorsa dogrudan imm32 ile karsilastir */
    FILL(A0, 1); SHRI(A0, 8)
    CALL(jx_kint)
    BZ(RV, fc_kslow)
    LEA_SYM(A0, SYM(g_jit_kval)); LD32(A1W, A0)
    FILL(A0, 4); CALL(jx_gv_cmp_imm)
    B(fc_jmp)
fc_kslow:
    FILL(A0, 1); SHRI(A0, 8); CALL(jx_const); MOVR(A0, RV); CALL(jx_abs_rcx)
    EB(0x83); EB(0x39); EB(0x00)
    MOVI(A0, 0x85); MOVI(A1, 0); CALL(jx_jstub)
    EB(0x8B); EB(0x49); EB(0x04)
    FILL(A0, 4); CALL(jx_gv_cmp_ecx)
    B(fc_jmp)
fc_g2:
    FILL(A0, 1); SHRI(A0, 8); SPILL(1, A0)
    FILL(A0, 1); CALL(jx_need_int)
    FILL(A0, 1); CALL(jx_gv_ld_ecx)
    FILL(A0, 4); CALL(jx_gv_cmp_ecx)
fc_jmp:
    EB(0x0F)
    FILL(A0, 3)
    CMPI(A0, OP_JLT); BEQ(fc_lt)
    CMPI(A0, OP_JLE); BEQ(fc_le)
    CMPI(A0, OP_JGT); BEQ(fc_gt)
    MOVI(A0, 0x8D); B(fc_emit)
fc_lt:
    MOVI(A0, 0x8C); B(fc_emit)
fc_le:
    MOVI(A0, 0x8E); B(fc_emit)
fc_gt:
    MOVI(A0, 0x8F)
fc_emit:
    CALL(emit8)
    FILL(A0, 2); SHRI(A0, 16)
    CALL(jx_fix)
    LEAVE_
    RET
ENDFUNC(jx_fused_cmp)

/* jx_eqflags() : iki degeri karsilastir, ZF = esitlik. Yigindan atar.
 * JIT edilen programda T_OBJ olamaz (sabit havuzu taranarak garanti
 * edildi), dolayisiyla esitlik = (etiket ayni VE yuk ayni).
 *   8B 43 F0      mov eax, [rbx-16]   (etiket1)
 *   3B 43 F8      cmp eax, [rbx-8]    (etiket2)
 *   75 08         jne +8  -> esit degil (ZF=0 kalir)
 *   8B 43 F4      mov eax, [rbx-12]
 *   3B 43 FC      cmp eax, [rbx-4]
 *   48 83 EB 10   sub rbx, 16   (bayraklari BOZAR -> once degil sonra? )
 * DIKKAT: sub rbx bayrak degistirir. Bu yuzden karsilastirma sonucu
 * once dl'e alinip yigin sonra kirpiliyor.
 */
FUNC(jx_eqflags)
    ENTER(1)
    EB(0x31); EB(0xD2)                      /* xor edx, edx */
    EB(0x8B); EB(0x43); EB(0xF0)            /* mov eax,[rbx-16] */
    EB(0x3B); EB(0x43); EB(0xF8)            /* cmp eax,[rbx-8]  */
    /* Etiketler farkliysa yuk karsilastirmasini ATLA.
     * Atlanacak: mov(3) + cmp(3) + sete(3) = 9 bayt.
     * Ilk yazdigimda 8 yazmistim ve sete'nin ORTASINA dusuyordu
     * -> segfault. Elle kodlamada ofset saymak sart. */
    EB(0x75); EB(0x09)                      /* jne +9 (dl=0)    */
    EB(0x8B); EB(0x43); EB(0xF4)            /* mov eax,[rbx-12] */
    EB(0x3B); EB(0x43); EB(0xFC)            /* cmp eax,[rbx-4]  */
    EB(0x0F); EB(0x94); EB(0xC2)            /* sete dl          */
    EB(0x48); EB(0x83); EB(0xEB); EB(0x10)  /* sub rbx, 16      */
    EB(0x84); EB(0xD2)                      /* test dl, dl -> ZF=0 ise ESIT */
    EB(0x0F); EB(0x95); EB(0xC2)            /* setne dl         */
    EB(0x80); EB(0xFA); EB(0x01)            /* cmp dl, 1  -> ZF = esitlik */
    LEAVE_
    RET
ENDFUNC(jx_eqflags)

/* jx_eqcmp(A0 = setcc ikinci baytı) : esitlik sonucunu bool olarak it */
FUNC(jx_eqcmp)
    ENTER(1)
    SPILL(0, A0)
    CALL(jx_eqflags)
    EB(0x0F); FILL(A0, 0); CALL(emit8); EB(0xC0)
    EB(0x0F); EB(0xB6); EB(0xC0)
    EB(0xC7); EB(0x03); MOVI(A0, T_BOOL); CALL(emit32)
    EB(0x89); EB(0x43); EB(0x04)
    EB(0x48); EB(0x83); EB(0xC3); EB(0x08)
    LEAVE_
    RET
ENDFUNC(jx_eqcmp)

/* jx_pushi(A0 = etiket, A1 = yuk) : sabit ciftini dogrudan it
 *   C7 03 <tag>      mov dword [rbx], tag
 *   C7 43 04 <pay>   mov dword [rbx+4], pay
 *   48 83 C3 08      add rbx, 8
 */
FUNC(jx_pushi)
    ENTER(2)
    SPILL(0, A0)
    SPILL(1, A1)
    EB(0xC7); EB(0x03); FILL(A0, 0); CALL(emit32)
    EB(0xC7); EB(0x43); EB(0x04); FILL(A0, 1); CALL(emit32)
    EB(0x48); EB(0x83); EB(0xC3); EB(0x08)
    LEAVE_
    RET
ENDFUNC(jx_pushi)

/* jx_binop(A0 = aritmetik opkod baytlari icin secici)
 * 0 = add, 1 = sub, 2 = imul
 * Iki tamsayiyi al, isle, biri geri it. Tasma denetimi dahil.
 *   <typecheck2>
 *   8B 43 F4      mov eax, [rbx-12]
 *   03/2B 43 FC   add/sub eax, [rbx-4]      | 0F AF 43 FC  imul eax,[rbx-4]
 *   <overflow bail>
 *   48 83 EB 08   sub rbx, 8
 *   89 43 FC      mov [rbx-4], eax
 */
FUNC(jx_binop)
    ENTER(1)
    SPILL(0, A0)
    CALL(jx_typecheck2)
    EB(0x8B); EB(0x43); EB(0xF4)
    FILL(A0, 0)
    CMPI(A0, 1); BEQ(jb_sub)
    CMPI(A0, 2); BEQ(jb_mul)
    EB(0x03); EB(0x43); EB(0xFC)
    B(jb_tail)
jb_sub:
    EB(0x2B); EB(0x43); EB(0xFC)
    B(jb_tail)
jb_mul:
    EB(0x0F); EB(0xAF); EB(0x43); EB(0xFC)
jb_tail:
    CALL(jx_overflow_exit)
    EB(0x48); EB(0x83); EB(0xEB); EB(0x08)
    EB(0x89); EB(0x43); EB(0xFC)
    LEAVE_
    RET
ENDFUNC(jx_binop)

/* jx_kop(A0 = sabit indeksi, A1 = 0 topla / 1 cikar)
 * Tepedeki tamsayiya sabiti ekle/cikar (ADDK / SUBK).
 *   <typecheck1: [rbx-8] etiketi 0 mi>
 *   movabs rcx, &consts[k]
 *   8B 49 04      mov ecx, [rcx+4]
 *   8B 43 FC      mov eax, [rbx-4]
 *   01/29 C8      add/sub eax, ecx
 *   <overflow bail>
 *   89 43 FC      mov [rbx-4], eax
 * NOT: SUBK yorumlayicida "tepe - sabit" degil "sabit'ten sonra
 * gelen" siralamayi kullaniyor; ayni sirayi koruyoruz.
 */
FUNC(jx_kop)
    ENTER(2)
    SPILL(0, A0)
    SPILL(1, A1)
    /* typecheck: [rbx-8] etiketi 0 mi */
    EB(0x83); EB(0x7B); EB(0xF8); EB(0x00)
    MOVI(A0, 0x85); MOVI(A1, 0); CALL(jx_jstub)
    FILL(A0, 0); CALL(jx_const); MOVR(A0, RV); CALL(jx_abs_rcx)
    EB(0x8B); EB(0x49); EB(0x04)
    EB(0x8B); EB(0x43); EB(0xFC)
    FILL(A0, 1)
    BNZ(A0, jk_sub)
    EB(0x01); EB(0xC8)
    B(jk_tail)
jk_sub:
    EB(0x29); EB(0xC8)
jk_tail:
    CALL(jx_overflow_exit)
    EB(0x89); EB(0x43); EB(0xFC)
    LEAVE_
    RET
ENDFUNC(jx_kop)

/* jx_cmp_bool(A0 = setcc ikinci baytı) : iki tamsayiyi karsilastir,
 * sonucu T_BOOL olarak it.
 *   <jx_cmp2>  (karsilastirir ve rbx -= 16)
 *   0F 9x C0      setcc al
 *   0F B6 C0      movzx eax, al
 *   C7 03 01000000 mov dword [rbx], T_BOOL
 *   89 43 04      mov [rbx+4], eax
 *   48 83 C3 08   add rbx, 8
 */
FUNC(jx_cmp_bool)
    ENTER(1)
    SPILL(0, A0)
    CALL(jx_cmp2)
    EB(0x0F); FILL(A0, 0); CALL(emit8); EB(0xC0)
    EB(0x0F); EB(0xB6); EB(0xC0)
    EB(0xC7); EB(0x03); MOVI(A0, T_BOOL); CALL(emit32)
    EB(0x89); EB(0x43); EB(0x04)
    EB(0x48); EB(0x83); EB(0xC3); EB(0x08)
    LEAVE_
    RET
ENDFUNC(jx_cmp_bool)

#endif
