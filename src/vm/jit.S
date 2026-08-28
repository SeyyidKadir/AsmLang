/* jit.S - calisma zamani kod uretimi (baslangic)
 *
 * TASARIM NOTU - neden "copy-and-patch" DEGIL:
 * Klasik copy-and-patch, yorumlayici isleyicilerini oldugu gibi
 * kopyalar. Bizimkiler kopyalanamaz:
 *   - LEA_SYM PC-goreli adresleme kullaniyor (leaq ...(%rip) / adrp)
 *     -> baska adrese kopyalaninca yanlis yeri gosterir
 *   - paylasilan etiketlere (vm_type_err, ve_true) goreli dalliyorlar
 *   - her isleyici NEXT ile bitiyor
 * Gercek copy-and-patch JIT'ler isleyicileri OZEL derlenmis, yer
 * degistirme tablosu olan "stencil"ler olarak uretir.
 *
 * Bizim yolumuz SABLON JIT: her bytecode komutu icin makine kodu
 * ureten emitter. Bu dosya once MEKANIZMAYI kuruyor:
 * calistirilabilir bellek + bayt uretimi + cagirma.
 */
#include "../abi.inc"
#include "../tables/opcodes.inc"

#define JIT_BUF_SIZE 65536

    .bss
    .p2align 3
    .globl SYM(g_jit_base)
SYM(g_jit_base): .space 8
    .globl SYM(g_jit_pos)
SYM(g_jit_pos):  .space 4
    .globl SYM(g_jit_cap)
SYM(g_jit_cap):  .space 4

    SECT_TEXT

/* jit_init() -> RV = 1 tamam / 0 (W^X engeli: cagiran yorumlayiciya duser) */
FUNC(jit_init)
    ENTER(1)
    LEA_SYM(A0, SYM(g_jit_base))
    LD(A0, A0)
    BNZ(A0, ji_ok)
    MOVI(A0, JIT_BUF_SIZE)
    CALL(os_alloc_exec)
    BZ(RV, ji_no)
    MOVR(A1, RV)                    /* i386'da RV == A0: LEA_SYM(A0,..)
                                       isaretciyi ezerdi (altinci kez) */
    LEA_SYM(A0, SYM(g_jit_base))
    ST(A0, A1)
    MOVI(A0, JIT_BUF_SIZE)
    LEA_SYM(A1, SYM(g_jit_cap))
    ST32_OFF(A1, 0, A0W)
ji_ok:
    MOVI(A0, 0)
    LEA_SYM(A1, SYM(g_jit_pos))
    ST32_OFF(A1, 0, A0W)
    MOVI(RV, 1)
    LEAVE_
    RET
ji_no:
    MOVI(RV, 0)
    LEAVE_
    RET
ENDFUNC(jit_init)

/* emit8(A0 = bayt) -> RV = 1 tamam / 0 tampon doldu */
FUNC(emit8)
    ENTER(2)
    SPILL(0, A0)
    LEA_SYM(A0, SYM(g_jit_pos))
    LD32(A1W, A0)
    LEA_SYM(A0, SYM(g_jit_cap))
    LD32(A0W, A0)
    CMPR(A1, A0)
    BHS(e8_full)
    SPILL(1, A1)
    LEA_SYM(A0, SYM(g_jit_base))
    LD(A0, A0)
    FILL(A1, 1)
    ADD(A0, A1)
    FILL(A2, 0)
    STB(A0, A2B)
    FILL(A0, 1)
    INC(A0)
    LEA_SYM(A1, SYM(g_jit_pos))
    ST32_OFF(A1, 0, A0W)
    MOVI(RV, 1)
    LEAVE_
    RET
e8_full:
    MOVI(RV, 0)
    LEAVE_
    RET
ENDFUNC(emit8)

/* emit32(A0 = deger) - dusuk baytdan yuksege (little-endian) */
FUNC(emit32)
    ENTER(2)
    SPILL(0, A0)
    MOVI(A0, 4)
    SPILL(1, A0)
e32_loop:
    FILL(A0, 1)
    BZ(A0, e32_done)
    DEC(A0)
    SPILL(1, A0)
    FILL(A0, 0)
    ANDI(A0, 255)
    CALL(emit8)
    FILL(A0, 0)
    SHRI(A0, 8)
    SPILL(0, A0)
    B(e32_loop)
e32_done:
    LEAVE_
    RET
ENDFUNC(emit32)

/* jit_entry() -> RV = uretilen kodun baslangic adresi */
FUNC(jit_entry)
    ENTER(1)
    LEA_SYM(A0, SYM(g_jit_base))
    LD(RV, A0)
    LEAVE_
    RET
ENDFUNC(jit_entry)

/* jit_call(A0 = adres) -> RV = uretilen kodun donus degeri */
FUNC(jit_call)
    ENTER(1)
    MOVR(A2, A0)
    CALLR(A2)
    LEAVE_
    RET
ENDFUNC(jit_call)
