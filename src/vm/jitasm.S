/* jitasm.S - x86-64 komut kodlayici (Katman 1)
 *
 * KURAL: bu dosyanin DISINDA tek bir opcode literali bulunmayacak.
 *
 * Eski JIT'te bulunan hatalarin hepsi elle bayt yazmanin sonucuydu:
 * ters kosul (0x75 yerine 0x74), yanlis atlama ofseti (+8 yerine +9),
 * makronun register ezmesi. Kodlamayi tek yere toplayip kendini test
 * ettirmek bu sinifi kapatiyor.
 *
 * TASARIM KARARI: her zaman mod=10 (disp32), gerektiginde acik SIB.
 *   mod=00 + rm=101 -> RIP-goreli (tuzak)
 *   rbp/r13 (rm=101) mod=00'da kullanilamaz (ozel durum)
 *   rsp/r12 (rm=100) her zaman SIB ister (ozel durum)
 * Hep disp32 kullanilinca OZEL DURUM KALMIYOR. Bedeli birkac bayt
 * daha uzun kod; karsiligi kodlamanin yapi geregi dogru olmasi.
 */
#include "../abi.inc"
#include "../tables/opcodes.inc"
#include "../tables/jitreg.inc"

/* register numaralari -> src/tables/jitreg.inc */

/* kosul kodlari -> src/tables/jitreg.inc (jitcomp da kullaniyor) */

    SECT_TEXT

#if defined(ARCH_X86_64)

/* ja_b(A0 = bayt) */
FUNC(ja_b)
    ENTER(1)
    CALL(emit8)
    LEAVE_
    RET
ENDFUNC(ja_b)

/* ja_d(A0 = 32 bit) */
FUNC(ja_d)
    ENTER(1)
    CALL(emit32)
    LEAVE_
    RET
ENDFUNC(ja_d)

/* ja_q(A0 = 64 bit) */
FUNC(ja_q)
    ENTER(1)
    SPILL(0, A0)
    CALL(emit32)
    FILL(A0, 0)
    SHRI(A0, 32)
    CALL(emit32)
    LEAVE_
    RET
ENDFUNC(ja_q)

/* ja_rex(A0 = W, A1 = reg, A2 = base)
 * REX = 0100 W R X B ; R = reg'in 4. biti, B = base'in 4. biti.
 * Index kullanilmiyor (X = 0). W=1 ise 64-bit islem. */
FUNC(ja_rex)
    ENTER(1)
    SHLI(A0, 3)                     /* W -> bit 3 */
    SHRI(A1, 3)
    ANDI(A1, 1)
    SHLI(A1, 2)                     /* R -> bit 2 */
    ORR(A0, A1)
    SHRI(A2, 3)
    ANDI(A2, 1)                     /* B -> bit 0 */
    ORR(A0, A2)
    /* REX yalnizca GEREKIYORSA: W=0 ve butun registerlar dusukse
     * 0x40 uretmek gereksiz bayt (objdump "rex mov" diye gosteriyor).
     * Kodlama acisindan zararsiz ama kod sisiyor. */
    BZ(A0, jr_skip)
    ORI(A0, 0x40)
    CALL(emit8)
jr_skip:
    LEAVE_
    RET
ENDFUNC(ja_rex)

/* ja_mem(A0 = W, A1 = opcode, A2 = reg, A3 = base, [slot] disp)
 * Bellek islenenli komut: REX + opcode + ModRM(mod=10) + [SIB] + disp32
 * disp global uzerinden gecirilir (dort argumanimiz var, besinci yok). */
    .bss
    .p2align 3
SYM(g_ja_disp): .space 8
SYM(g_ja_imm):  .space 8
    SECT_TEXT

/* ja_disp(A0) - bir sonraki ja_mem icin yer degistirmeyi ayarla */
FUNC(ja_disp)
    ENTER(1)
    LEA_SYM(A1, SYM(g_ja_disp))
    ST(A1, A0)
    LEAVE_
    RET
ENDFUNC(ja_disp)

FUNC(ja_mem)
    ENTER(4)
    SPILL(0, A0)                    /* W */
    SPILL(1, A1)                    /* opcode */
    SPILL(2, A2)                    /* reg */
    SPILL(3, A3)                    /* base */
    FILL(A0, 0); FILL(A1, 2); FILL(A2, 3)
    CALL(ja_rex)
    FILL(A0, 1)
    CALL(emit8)
    /* ModRM: mod=10, reg, rm=base */
    FILL(A0, 2); ANDI(A0, 7); SHLI(A0, 3)
    FILL(A1, 3); ANDI(A1, 7)
    ORR(A0, A1)
    ORI(A0, 0x80)
    CALL(emit8)
    /* rm=100 (rsp/r12) SIB ister: scale=0 index=100(yok) base=100 */
    FILL(A0, 3); ANDI(A0, 7)
    CMPI(A0, 4)
    BNE(jm_nosib)
    MOVI(A0, 0x24)
    CALL(emit8)
jm_nosib:
    LEA_SYM(A0, SYM(g_ja_disp))
    LD(A0, A0)
    CALL(emit32)
    LEAVE_
    RET
ENDFUNC(ja_mem)

/* ja_rr(A0 = W, A1 = opcode, A2 = reg, A3 = rm)
 * Register-register: REX + opcode + ModRM(mod=11) */
FUNC(ja_rr)
    ENTER(4)
    SPILL(0, A0)
    SPILL(1, A1)
    SPILL(2, A2)
    SPILL(3, A3)
    FILL(A0, 0); FILL(A1, 2); FILL(A2, 3)
    CALL(ja_rex)
    FILL(A0, 1)
    CALL(emit8)
    FILL(A0, 2); ANDI(A0, 7); SHLI(A0, 3)
    FILL(A1, 3); ANDI(A1, 7)
    ORR(A0, A1)
    ORI(A0, 0xC0)
    CALL(emit8)
    LEAVE_
    RET
ENDFUNC(ja_rr)

/* ---------- adlandirilmis komutlar ---------- */

/* movabs reg, imm64   ->  REX.W B8+r imm64 */
FUNC(ja_mov_r_imm64)
    ENTER(2)
    SPILL(0, A0)                    /* reg */
    SPILL(1, A1)                    /* imm */
    MOVI(A0, 1)                     /* W = 1 */
    MOVI(A1, 0)                     /* R = 0 (reg alani yok) */
    FILL(A2, 0)                     /* B = reg>>3 */
    CALL(ja_rex)
    FILL(A0, 0); ANDI(A0, 7); ADDI(A0, 0xB8)
    CALL(emit8)
    FILL(A0, 1)
    CALL(ja_q)
    LEAVE_
    RET
ENDFUNC(ja_mov_r_imm64)

/* mov reg64, [base+disp]   ->  REX.W 8B /r */
FUNC(ja_mov_r_m)
    ENTER(3)
    SPILL(0, A0); SPILL(1, A1); SPILL(2, A2)
    FILL(A0, 2); CALL(ja_disp)
    MOVI(A0, 1); MOVI(A1, 0x8B); FILL(A2, 0); FILL(A3, 1)
    CALL(ja_mem)
    LEAVE_
    RET
ENDFUNC(ja_mov_r_m)

/* mov [base+disp], reg64   ->  REX.W 89 /r */
FUNC(ja_mov_m_r)
    ENTER(3)
    SPILL(0, A0); SPILL(1, A1); SPILL(2, A2)
    FILL(A0, 1); CALL(ja_disp)
    MOVI(A0, 1); MOVI(A1, 0x89); FILL(A2, 2); FILL(A3, 0)
    CALL(ja_mem)
    LEAVE_
    RET
ENDFUNC(ja_mov_m_r)

/* mov reg32, [base+disp]   ->  8B /r  (W=0) */
FUNC(ja_mov32_r_m)
    ENTER(3)
    SPILL(0, A0); SPILL(1, A1); SPILL(2, A2)
    FILL(A0, 2); CALL(ja_disp)
    MOVI(A0, 0); MOVI(A1, 0x8B); FILL(A2, 0); FILL(A3, 1)
    CALL(ja_mem)
    LEAVE_
    RET
ENDFUNC(ja_mov32_r_m)

/* mov [base+disp], reg32   ->  89 /r  (W=0) */
FUNC(ja_mov32_m_r)
    ENTER(3)
    SPILL(0, A0); SPILL(1, A1); SPILL(2, A2)
    FILL(A0, 1); CALL(ja_disp)
    MOVI(A0, 0); MOVI(A1, 0x89); FILL(A2, 2); FILL(A3, 0)
    CALL(ja_mem)
    LEAVE_
    RET
ENDFUNC(ja_mov32_m_r)

/* alu reg64, reg64 : A0 = opcode (01 add, 29 sub, 39 cmp, 85 test) */
FUNC(ja_alu_rr)
    ENTER(3)
    SPILL(0, A0); SPILL(1, A1); SPILL(2, A2)
    MOVI(A0, 1); FILL(A1, 0); FILL(A2, 2); FILL(A3, 1)
    CALL(ja_rr)                     /* reg=src, rm=dst */
    LEAVE_
    RET
ENDFUNC(ja_alu_rr)

/* alu [base+disp], reg64 */
FUNC(ja_alu_mr)
    ENTER(4)
    SPILL(0, A0); SPILL(1, A1); SPILL(2, A2); SPILL(3, A3)
    FILL(A0, 2); CALL(ja_disp)
    MOVI(A0, 1); FILL(A1, 0); FILL(A2, 3); FILL(A3, 1)
    CALL(ja_mem)
    LEAVE_
    RET
ENDFUNC(ja_alu_mr)

/* alu reg64, [base+disp] : opcode 03 add, 2B sub, 3B cmp */
FUNC(ja_alu_rm)
    ENTER(4)
    SPILL(0, A0); SPILL(1, A1); SPILL(2, A2); SPILL(3, A3)
    FILL(A0, 3); CALL(ja_disp)
    MOVI(A0, 1); FILL(A1, 0); FILL(A2, 1); FILL(A3, 2)
    CALL(ja_mem)
    LEAVE_
    RET
ENDFUNC(ja_alu_rm)

/* grup 1 imm32: A0 = /digit (0 add, 5 sub, 7 cmp), A1 = base,
 * A2 = disp, A3 = imm32.  REX.W 81 /d disp32 imm32 */
FUNC(ja_grp1_mi)
    ENTER(4)
    SPILL(0, A0); SPILL(1, A1); SPILL(2, A2); SPILL(3, A3)
    FILL(A0, 2); CALL(ja_disp)
    MOVI(A0, 1); MOVI(A1, 0x81); FILL(A2, 0); FILL(A3, 1)
    CALL(ja_mem)
    FILL(A0, 3)
    CALL(emit32)
    LEAVE_
    RET
ENDFUNC(ja_grp1_mi)

/* mov qword [base+disp], imm32 (isaret genisletilir) -> REX.W C7 /0 */
FUNC(ja_mov_m_imm32)
    ENTER(3)
    SPILL(0, A0); SPILL(1, A1); SPILL(2, A2)
    FILL(A0, 1); CALL(ja_disp)
    MOVI(A0, 1); MOVI(A1, 0xC7); MOVI(A2, 0); FILL(A3, 0)
    CALL(ja_mem)
    FILL(A0, 2)
    CALL(emit32)
    LEAVE_
    RET
ENDFUNC(ja_mov_m_imm32)

/* mov dword [base+disp], imm32 (32-bit, etiket alani icin) -> C7 /0 */
FUNC(ja_mov32_m_imm32)
    ENTER(3)
    SPILL(0, A0); SPILL(1, A1); SPILL(2, A2)
    FILL(A0, 1); CALL(ja_disp)
    MOVI(A0, 0); MOVI(A1, 0xC7); MOVI(A2, 0); FILL(A3, 0)
    CALL(ja_mem)
    FILL(A0, 2)
    CALL(emit32)
    LEAVE_
    RET
ENDFUNC(ja_mov32_m_imm32)

/* lea reg64, [base+disp] -> REX.W 8D /r */
FUNC(ja_lea)
    ENTER(3)
    SPILL(0, A0); SPILL(1, A1); SPILL(2, A2)
    FILL(A0, 2); CALL(ja_disp)
    MOVI(A0, 1); MOVI(A1, 0x8D); FILL(A2, 0); FILL(A3, 1)
    CALL(ja_mem)
    LEAVE_
    RET
ENDFUNC(ja_lea)

/* imul reg64, reg64 -> REX.W 0F AF /r */
FUNC(ja_imul_rr)
    ENTER(2)
    SPILL(0, A0); SPILL(1, A1)
    MOVI(A0, 1); FILL(A1, 0); FILL(A2, 1)
    CALL(ja_rex)
    MOVI(A0, 0x0F); CALL(emit8)
    MOVI(A0, 0xAF); CALL(emit8)
    FILL(A0, 0); ANDI(A0, 7); SHLI(A0, 3)
    FILL(A1, 1); ANDI(A1, 7)
    ORR(A0, A1)
    ORI(A0, 0xC0)
    CALL(emit8)
    LEAVE_
    RET
ENDFUNC(ja_imul_rr)

/* push/pop reg64 -> [REX.B] 50+r / 58+r */
FUNC(ja_push)
    ENTER(1)
    SPILL(0, A0)
    CMPI(A0, 8)
    BLO(jp_norex)
    MOVI(A0, 0x41); CALL(emit8)
jp_norex:
    FILL(A0, 0); ANDI(A0, 7); ADDI(A0, 0x50)
    CALL(emit8)
    LEAVE_
    RET
ENDFUNC(ja_push)

FUNC(ja_pop)
    ENTER(1)
    SPILL(0, A0)
    CMPI(A0, 8)
    BLO(jo_norex)
    MOVI(A0, 0x41); CALL(emit8)
jo_norex:
    FILL(A0, 0); ANDI(A0, 7); ADDI(A0, 0x58)
    CALL(emit8)
    LEAVE_
    RET
ENDFUNC(ja_pop)

/* call reg64 -> [REX.B] FF /2 */
FUNC(ja_call_r)
    ENTER(1)
    SPILL(0, A0)
    CMPI(A0, 8)
    BLO(jc_norex)
    MOVI(A0, 0x41); CALL(emit8)
jc_norex:
    MOVI(A0, 0xFF); CALL(emit8)
    FILL(A0, 0); ANDI(A0, 7); ORI(A0, 0xD0)
    CALL(emit8)
    LEAVE_
    RET
ENDFUNC(ja_call_r)

FUNC(ja_ret)
    ENTER(1)
    MOVI(A0, 0xC3)
    CALL(emit8)
    LEAVE_
    RET
ENDFUNC(ja_ret)

/* setcc reg8 (yalniz rax..rdi) -> 0F 9x C0+r */
FUNC(ja_setcc)
    ENTER(2)
    SPILL(0, A0)                    /* cc */
    SPILL(1, A1)                    /* reg */
    MOVI(A0, 0x0F); CALL(emit8)
    FILL(A0, 0); ORI(A0, 0x90); CALL(emit8)
    FILL(A0, 1); ANDI(A0, 7); ORI(A0, 0xC0); CALL(emit8)
    LEAVE_
    RET
ENDFUNC(ja_setcc)

/* movzx reg32, reg8 -> 0F B6 /r */
FUNC(ja_movzx)
    ENTER(2)
    SPILL(0, A0); SPILL(1, A1)
    MOVI(A0, 0x0F); CALL(emit8)
    MOVI(A0, 0xB6); CALL(emit8)
    FILL(A0, 0); ANDI(A0, 7); SHLI(A0, 3)
    FILL(A1, 1); ANDI(A1, 7)
    ORR(A0, A1)
    ORI(A0, 0xC0)
    CALL(emit8)
    LEAVE_
    RET
ENDFUNC(ja_movzx)

/* grup 1 imm32, REGISTER islenenli: A0 = /digit, A1 = reg, A2 = imm32
 * REX.W 81 /d C0+r imm32   (add/sub/cmp reg64, imm32) */
FUNC(ja_grp1_ri)
    ENTER(3)
    SPILL(0, A0); SPILL(1, A1); SPILL(2, A2)
    MOVI(A0, 1); MOVI(A1, 0); FILL(A2, 1)
    CALL(ja_rex)
    MOVI(A0, 0x81); CALL(emit8)
    FILL(A0, 0); ANDI(A0, 7); SHLI(A0, 3)
    FILL(A1, 1); ANDI(A1, 7)
    ORR(A0, A1)
    ORI(A0, 0xC0)
    CALL(emit8)
    FILL(A0, 2); CALL(emit32)
    LEAVE_
    RET
ENDFUNC(ja_grp1_ri)

/* mov reg64, reg64 : A0 = hedef, A1 = kaynak  ->  REX.W 89 /r */
FUNC(ja_mov_rr)
    ENTER(2)
    SPILL(0, A0); SPILL(1, A1)
    MOVI(A0, 0x89); FILL(A1, 0); FILL(A2, 1)
    CALL(ja_alu_rr)
    LEAVE_
    RET
ENDFUNC(ja_mov_rr)

/* xor reg32, reg32 (sifirlama) -> 31 /r */
FUNC(ja_xor32)
    ENTER(2)
    SPILL(0, A0); SPILL(1, A1)
    MOVI(A0, 0x31); FILL(A1, 1); FILL(A2, 0)
    MOVI(A3, 0)
    FILL(A2, 1); FILL(A3, 0)
    MOVI(A0, 0); MOVI(A1, 0x31)
    CALL(ja_rr)
    LEAVE_
    RET
ENDFUNC(ja_xor32)

/* neg reg64 -> REX.W F7 /3 */
FUNC(ja_neg)
    ENTER(1)
    SPILL(0, A0)
    MOVI(A0, 1); MOVI(A1, 0); FILL(A2, 0)
    CALL(ja_rex)
    MOVI(A0, 0xF7); CALL(emit8)
    FILL(A0, 0); ANDI(A0, 7); ORI(A0, 0xD8)
    CALL(emit8)
    LEAVE_
    RET
ENDFUNC(ja_neg)

/* idiv reg64 -> REX.W F7 /7   (rdx:rax / reg) */
FUNC(ja_idiv)
    ENTER(1)
    SPILL(0, A0)
    MOVI(A0, 1); MOVI(A1, 0); FILL(A2, 0)
    CALL(ja_rex)
    MOVI(A0, 0xF7); CALL(emit8)
    FILL(A0, 0); ANDI(A0, 7); ORI(A0, 0xF8)
    CALL(emit8)
    LEAVE_
    RET
ENDFUNC(ja_idiv)

/* cqo (rax -> rdx:rax isaret genisletme) -> REX.W 99 */
FUNC(ja_cqo)
    ENTER(1)
    MOVI(A0, 0x48); CALL(emit8)
    MOVI(A0, 0x99); CALL(emit8)
    LEAVE_
    RET
ENDFUNC(ja_cqo)

/* ================== OZ TEST ==================
 * Kodlayici bozulursa DERLEME degil ILK KOSU yakalasin.
 * Bilinen komut dizisi uretilip beklenen baytlarla karsilastirilir.
 */
    SECT_RODATA
    .p2align 4
ja_expect:
    /* mov rax, [r13+0x10]      49 8b 85 10 00 00 00 */
    .byte 0x49, 0x8b, 0x85, 0x10, 0x00, 0x00, 0x00
    /* mov [rbx+0x08], rcx      48 89 8b 08 00 00 00 */
    .byte 0x48, 0x89, 0x8b, 0x08, 0x00, 0x00, 0x00
    /* mov rdx, [r12+0x04]      49 8b 94 24 04 00 00 00   (SIB!) */
    .byte 0x49, 0x8b, 0x94, 0x24, 0x04, 0x00, 0x00, 0x00
    /* add rax, rcx             48 01 c8 */
    .byte 0x48, 0x01, 0xc8
    /* cmp qword [r13+0x20], 5  49 81 bd 20 00 00 00 05 00 00 00 */
    .byte 0x49, 0x81, 0xbd, 0x20, 0x00, 0x00, 0x00, 0x05, 0x00, 0x00, 0x00
    /* movabs rsi, 0x1122334455667788 */
    .byte 0x48, 0xbe, 0x88, 0x77, 0x66, 0x55, 0x44, 0x33, 0x22, 0x11
    /* add rbx, 16             48 81 c3 10 00 00 00 */
    .byte 0x48, 0x81, 0xc3, 0x10, 0x00, 0x00, 0x00
    /* mov rdi, rbx             48 89 df */
    .byte 0x48, 0x89, 0xdf
    /* neg rax                  48 f7 d8 */
    .byte 0x48, 0xf7, 0xd8
    /* cqo                      48 99 */
    .byte 0x48, 0x99
    /* idiv rcx                 48 f7 f9 */
    .byte 0x48, 0xf7, 0xf9
    /* ret */
    .byte 0xc3
    .equ ja_expect_len, . - ja_expect

ja_ok:  .ascii "jitasm oz test: GECTI\n"
    .equ ja_ok_len, . - ja_ok
ja_bad: .ascii "jitasm oz test: KALDI - kodlayici bozuk\n"
    .equ ja_bad_len, . - ja_bad
    SECT_TEXT

/* jitasm_selftest() -> RV = 1 tamam / 0 bozuk */
FUNC(jitasm_selftest)
    ENTER(3)
    CALL(jit_init)
    BZ(RV, jst_skip)
    /* mov rax, [r13+0x10] */
    MOVI(A0, R_AX); MOVI(A1, R_13); MOVI(A2, 0x10); CALL(ja_mov_r_m)
    /* mov [rbx+0x08], rcx */
    MOVI(A0, R_BX); MOVI(A1, 0x08); MOVI(A2, R_CX); CALL(ja_mov_m_r)
    /* mov rdx, [r12+0x04]  - SIB gerektiren durum */
    MOVI(A0, R_DX); MOVI(A1, R_12); MOVI(A2, 0x04); CALL(ja_mov_r_m)
    /* add rax, rcx */
    MOVI(A0, 0x01); MOVI(A1, R_AX); MOVI(A2, R_CX); CALL(ja_alu_rr)
    /* cmp qword [r13+0x20], 5 */
    MOVI(A0, 7); MOVI(A1, R_13); MOVI(A2, 0x20); MOVI(A3, 5)
    CALL(ja_grp1_mi)
    /* movabs rsi, 0x1122334455667788 */
    MOVI(A0, R_SI)
    LEA_SYM(A1, ja_bigval)
    LD(A1, A1)
    CALL(ja_mov_r_imm64)
    /* add rbx, 16 */
    MOVI(A0, 0); MOVI(A1, R_BX); MOVI(A2, 16); CALL(ja_grp1_ri)
    /* mov rdi, rbx */
    MOVI(A0, R_DI); MOVI(A1, R_BX); CALL(ja_mov_rr)
    /* neg rax */
    MOVI(A0, R_AX); CALL(ja_neg)
    /* cqo */
    CALL(ja_cqo)
    /* idiv rcx */
    MOVI(A0, R_CX); CALL(ja_idiv)
    CALL(ja_ret)
    /* karsilastir */
    LEA_SYM(A0, SYM(g_jit_pos))
    LD32(A0W, A0)
    CMPI(A0, ja_expect_len)
    BNE(jst_bad)
    MOVI(A0, 0)
    SPILL(0, A0)
jst_cmp:
    FILL(A0, 0)
    CMPI(A0, ja_expect_len)
    BHS(jst_good)
    LEA_SYM(A1, SYM(g_jit_base))
    LD(A1, A1)
    LDB_IDX(A2W, A1, A0)
    SPILL(1, A2)
    LEA_SYM(A1, ja_expect)
    FILL(A0, 0)
    LDB_IDX(A1W, A1, A0)
    FILL(A2, 1)
    CMPR(A1, A2)
    BNE(jst_bad)
    FILL(A0, 0); INC(A0); SPILL(0, A0)
    B(jst_cmp)
jst_good:
    LEA_SYM(A0, ja_ok); MOVI(A1, ja_ok_len); CALL(print_str)
    CALL(jit_init)                  /* tamponu sifirla */
    MOVI(RV, 1)
    LEAVE_
    RET
jst_bad:
    LEA_SYM(A0, ja_bad); MOVI(A1, ja_bad_len); CALL(print_str)
    CALL(jit_init)
    MOVI(RV, 0)
    LEAVE_
    RET
jst_skip:
    MOVI(RV, 1)                     /* W^X: kodlayici test edilemedi */
    LEAVE_
    RET
ENDFUNC(jitasm_selftest)

    SECT_RODATA
    .p2align 3
ja_bigval:
    PTR 0x1122334455667788
    SECT_TEXT

#endif /* ARCH_X86_64 */
