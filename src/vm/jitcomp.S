/* jitcomp.S - bytecode -> yerel kod (Katman 3)
 *
 * YALNIZCA Katman 1 (jitasm) ve Katman 2 (jitlbl) cagrilir.
 * Bu dosyada tek bir opcode literali ve tek bir atlama mesafesi
 * BULUNMAZ. Eski JIT'teki hatalarin tamami bu iki seyden geliyordu.
 *
 * ================== DURUM SOZLESMESI ==================
 *
 * Uretilen kodda registerlar:
 *   rbx = VS   deger yigini tepesi (ilk BOS yuva)
 *   r12 = VF   cerceve tabani (yereller icin)
 *   r13 = g_gvals tabani
 *   rax, rcx, rdx, rsi, rdi = gecici, komut sinirinda ANLAMSIZ
 *
 * rbx/r12/r13 cagrilan-korumali (SysV): calisma zamani islevlerimiz
 * (print_val vb.) bunlari bozmaz.
 *
 * Komut sinirinda gecerli olan tek degismez: rbx dogru yigin
 * tepesini gosterir, r12/r13 sabittir.
 *
 * Deger yuvasi 16 bayt: {u32 etiket, u32 dolgu, i64 yuk}.
 * Butun erisimler VAL_TAG / VAL_PAY / VAL_SIZE cinsinden yazilir;
 * genislik bir daha degisirse burasi DOKUNULMADAN calisir.
 *
 * ================== HATA YOLLARI ==================
 *
 * Her hata turu icin kodun SONUNDA tek bir stub var; denetimler
 * oraya etiketle dallanir (Asama 35'te olculdu: satir disi hata
 * yollari sicak yolu 51 -> 15 komuta indirdi).
 *
 * Calisma ani hatasinda YORUMLAYICIYA DUSULMEZ: o ana kadar yan
 * etki olusmus olabilir (Asama 28'de olculdu: cikti tekrarlaniyordu).
 * Uretilen kod hatayi kendisi bildirir, yigini geri sarar ve doner.
 */
#include "../abi.inc"
#include "../tables/opcodes.inc"
#include "../tables/jitreg.inc"

/* jitcomp kisaltmalari (jitreg.inc uzerinden) */
#define J_AX  R_AX
#define J_CX  R_CX
#define J_DX  R_DX
#define J_BX  R_BX
#define J_SI  R_SI
#define J_DI  R_DI
#define J_12  R_12
#define J_13  R_13

#define J_VS  J_BX
#define J_VF  J_12
#define J_GV  J_13

/* hata turleri (stub dizisi) */
#define E_TYPE  0
#define E_OVF   1
#define E_DIV   2
#define E_CALL  3
#define E_ARITY 4
#define E_DEPTH 5
#define E_RANGE 6
#define E_STACK 7
#define E_N     8

    .bss
    .p2align 2
    .globl SYM(g_jc_stub)
SYM(g_jc_stub):  .space E_N * 4          /* hata stublarinin etiketleri */
    .globl SYM(g_jc_map)
SYM(g_jc_map):   .space (MAX_CODE + 1) * 4   /* komut -> etiket */
    .globl SYM(g_jc_ok)
SYM(g_jc_ok):    .space 4
/* fonksiyon indeksi -> uretilen kod adresi */
    .p2align 3
    .globl SYM(g_jc_fnmap)
SYM(g_jc_fnmap): .space MAX_FRAMES * 8
/* ozyineleme derinligi: JIT yerel cagri yigini kullaniyor, MAX_FRAMES
 * denetimini kendimiz yapmaliyiz (yoksa derin ozyineleme MAKINE
 * yiginini tasirir). */
    .globl SYM(g_jc_depth)
SYM(g_jc_depth): .space 8

    SECT_TEXT

#if defined(ARCH_X86_64)

/* ---------- kucuk yardimcilar ---------- */

/* jc_bail(A0 = hata turu, A1 = kosul kodu) - stub'a kosullu dallan */
FUNC(jc_bail)
    ENTER(2)
    SPILL(1, A1)
    SHLI(A0, 2)
    LEA_SYM(A1, SYM(g_jc_stub))
    ADD(A0, A1)
    LD32(A0W, A0)
    SPILL(0, A0)
    FILL(A0, 1)
    FILL(A1, 0)
    CALL(lbl_jcc)
    LEAVE_
    RET
ENDFUNC(jc_bail)

/* jc_gvaddr(A0 = yuva) -> RV = g_gvals icindeki ofset */
FUNC(jc_gvaddr)
    ENTER(1)
    SHLI(A0, VAL_SHIFT)
    MOVR(RV, A0)
    LEAVE_
    RET
ENDFUNC(jc_gvaddr)

/* jc_push_from(A0 = taban reg, A1 = ofset)
 * [rbx] <- [taban+ofset] (etiket 32 bit + yuk 64 bit), rbx += VAL_SIZE */
FUNC(jc_push_from)
    ENTER(2)
    SPILL(0, A0)
    SPILL(1, A1)
    MOVI(A0, J_CX); FILL(A1, 0); FILL(A2, 1); ADDI(A2, VAL_TAG)
    CALL(ja_mov32_r_m)
    MOVI(A0, J_VS); MOVI(A1, VAL_TAG); MOVI(A2, J_CX)
    CALL(ja_mov32_m_r)
    MOVI(A0, J_CX); FILL(A1, 0); FILL(A2, 1); ADDI(A2, VAL_PAY)
    CALL(ja_mov_r_m)
    MOVI(A0, J_VS); MOVI(A1, VAL_PAY); MOVI(A2, J_CX)
    CALL(ja_mov_m_r)
    MOVI(A0, 0); MOVI(A1, J_VS); MOVI(A2, VAL_SIZE)
    CALL(ja_grp1_ri)                /* add rbx, VAL_SIZE */
    LEAVE_
    RET
ENDFUNC(jc_push_from)

/* jc_pop_to(A0 = taban reg, A1 = ofset)
 * rbx -= VAL_SIZE ; [taban+ofset] <- [rbx] */
FUNC(jc_pop_to)
    ENTER(2)
    SPILL(0, A0)
    SPILL(1, A1)
    MOVI(A0, 5); MOVI(A1, J_VS); MOVI(A2, VAL_SIZE)
    CALL(ja_grp1_ri)                /* sub rbx, VAL_SIZE */
    MOVI(A0, J_CX); MOVI(A1, J_VS); MOVI(A2, VAL_TAG)
    CALL(ja_mov32_r_m)
    FILL(A0, 0); FILL(A1, 1); ADDI(A1, VAL_TAG); MOVI(A2, J_CX)
    CALL(ja_mov32_m_r)
    MOVI(A0, J_CX); MOVI(A1, J_VS); MOVI(A2, VAL_PAY)
    CALL(ja_mov_r_m)
    FILL(A0, 0); FILL(A1, 1); ADDI(A1, VAL_PAY); MOVI(A2, J_CX)
    CALL(ja_mov_m_r)
    LEAVE_
    RET
ENDFUNC(jc_pop_to)

/* jc_pushi(A0 = etiket, A1 = yuk)  - sabit cifti dogrudan it */
FUNC(jc_pushi)
    ENTER(2)
    SPILL(0, A0)
    SPILL(1, A1)
    MOVI(A0, J_VS); MOVI(A1, VAL_TAG); FILL(A2, 0)
    CALL(ja_mov32_m_imm32)
    MOVI(A0, J_VS); MOVI(A1, VAL_PAY); FILL(A2, 1)
    CALL(ja_mov_m_imm32)
    MOVI(A0, 0); MOVI(A1, J_VS); MOVI(A2, VAL_SIZE)
    CALL(ja_grp1_ri)
    LEAVE_
    RET
ENDFUNC(jc_pushi)

/* jc_need_int2() - tepedeki IKI degerin etiketi 0 mi
 *   mov ecx, [rbx - 2*VAL_SIZE + VAL_TAG]
 *   or  ecx, [rbx -   VAL_SIZE + VAL_TAG]      (32 bit)
 *   jne -> tur stubu
 * NOT: "or" 32-bit olmali; etiket alani 32 bit. */
FUNC(jc_need_int2)
    ENTER(1)
    MOVI(A0, J_CX); MOVI(A1, J_VS); MOVI(A2, VAL_TAG - 2*VAL_SIZE)
    CALL(ja_mov32_r_m)
    /* or ecx, [rbx + d]  ->  0B /r (W=0) */
    MOVI(A0, VAL_TAG - VAL_SIZE); CALL(ja_disp)
    MOVI(A0, 0); MOVI(A1, 0x0B); MOVI(A2, J_CX); MOVI(A3, J_VS)
    CALL(ja_mem)
    MOVI(A0, E_TYPE); MOVI(A1, CC_NE); CALL(jc_bail)
    LEAVE_
    RET
ENDFUNC(jc_need_int2)

/* jc_need_int1() - tepedeki degerin etiketi 0 mi */
FUNC(jc_need_int1)
    ENTER(1)
    MOVI(A0, 7); MOVI(A1, J_VS); MOVI(A2, VAL_TAG - VAL_SIZE); MOVI(A3, 0)
    CALL(ja_grp1_mi)                /* cmp qword [rbx+d], 0 -- 32 bit yeter */
    MOVI(A0, E_TYPE); MOVI(A1, CC_NE); CALL(jc_bail)
    LEAVE_
    RET
ENDFUNC(jc_need_int1)

/* jc_stubs() - hata stublarini kodun SONUNA koy */
FUNC(jc_stubs)
    ENTER(3)
    MOVI(A0, 0)
    SPILL(0, A0)
js_loop:
    FILL(A0, 0)
    CMPI(A0, E_N)
    BHS(js_done)
    /* etiketi buraya bagla */
    FILL(A0, 0); SHLI(A0, 2)
    LEA_SYM(A1, SYM(g_jc_stub)); ADD(A0, A1)
    LD32(A0W, A0)
    CALL(lbl_bind)
    /* movabs rax, yardimci ; call rax */
    FILL(A0, 0)
    CMPI(A0, E_TYPE);  BEQ(js_t)
    CMPI(A0, E_OVF);   BEQ(js_o)
    CMPI(A0, E_DIV);   BEQ(js_d)
    CMPI(A0, E_CALL);  BEQ(js_c)
    CMPI(A0, E_ARITY); BEQ(js_a)
    CMPI(A0, E_DEPTH); BEQ(js_p)
    CMPI(A0, E_RANGE); BEQ(js_r)
    LEA_SYM(A1, SYM(jit_err_stack)); B(js_e)
js_t: LEA_SYM(A1, SYM(jit_err_type));  B(js_e)
js_o: LEA_SYM(A1, SYM(jit_err_ovf));   B(js_e)
js_d: LEA_SYM(A1, SYM(jit_err_div));   B(js_e)
js_c: LEA_SYM(A1, SYM(jit_err_call));  B(js_e)
js_a: LEA_SYM(A1, SYM(jit_err_arity)); B(js_e)
js_p: LEA_SYM(A1, SYM(jit_err_depth)); B(js_e)
js_r: LEA_SYM(A1, SYM(jit_err_range))
js_e:
    MOVI(A0, J_AX)
    CALL(ja_mov_r_imm64)
    MOVI(A0, J_AX)
    CALL(ja_call_r)
    /* yigini geri sar: mov rax, [g_jit_sp] ; mov rsp, rax */
    MOVI(A0, J_AX)
    LEA_SYM(A1, SYM(g_jit_sp))
    CALL(ja_mov_r_imm64)
    MOVI(A0, J_AX); MOVI(A1, J_AX); MOVI(A2, 0)
    CALL(ja_mov_r_m)
    /* mov rsp, rax  ->  REX.W 89 /r, reg=rax, rm=rsp(4) */
    MOVI(A0, 4); MOVI(A1, J_AX)
    CALL(ja_mov_rr)
    /* mov eax, 1 ; ret  -> B8 imm32 */
    MOVI(A0, 0xB8); CALL(ja_b)
    MOVI(A0, 1);    CALL(ja_d)
    CALL(ja_ret)
    FILL(A0, 0); INC(A0); SPILL(0, A0)
    B(js_loop)
js_done:
    LEAVE_
    RET
ENDFUNC(jc_stubs)

#endif /* ARCH_X86_64 */

#if defined(ARCH_X86_64)

/* =====================================================================
 * jc_compile() -> RV = 1 basarili / 0 (JIT edilemedi)
 *
 * Iki gecis yok: etiket katmani ileri atlamalari kendisi yamaliyor.
 *   1) her bytecode komutu icin bir ETIKET olustur
 *   2) sirayla derle, atlamalar etiketle yapilir
 *   3) hata stublari
 *   4) lbl_fix
 *
 * Slotlar: 0=i 1=ncode 2=ins 3=op 4=opd 5=gecici
 * ===================================================================== */
FUNC(jc_compile)
    ENTER(7)
    MOVI(A0, 0)
    LEA_SYM(A1, SYM(g_jc_ok)); ST32_OFF(A1, 0, A0W)
    CALL(jit_init)
    BZ(RV, jcc_no)
    CALL(lbl_reset)
    CALL(jx_mark_fns)               /* hangi komut fonksiyon govdesinde */
    MOVI(A0, 0)
    LEA_SYM(A1, SYM(g_jc_depth)); ST(A1, A0)

    /* --- nesne/govde sabiti varsa HIC JIT etme ---
     * OP_CALL ve OP_ARRAY desteklenmedigi icin nesne deger yigina
     * baska turlu giremez: "JIT edilen programda nesne yoktur"
     * statik garanti. */
    MOVI(A0, 0)
    SPILL(0, A0)
jcc_scan:
    LEA_SYM(A0, SYM(g_nconst)); LD32(A0W, A0)
    FILL(A1, 0)
    CMPR(A1, A0)
    BHS(jcc_scanned)
    FILL(A0, 0); SHLI(A0, VAL_SHIFT)
    LEA_SYM(A1, SYM(g_consts)); LD(A1, A1); ADD(A0, A1)
    LD32(A0W, A0)
    CMPI(A0, T_OBJ); BEQ(jcc_no)
    CMPI(A0, T_NAT); BEQ(jcc_no)
    FILL(A0, 0); INC(A0); SPILL(0, A0)
    B(jcc_scan)
jcc_scanned:

    /* --- her komut icin etiket, her hata turu icin etiket --- */
    LEA_SYM(A0, SYM(g_ncode)); LD32(A0W, A0); SPILL(1, A0)
    MOVI(A0, 0); SPILL(0, A0)
jcc_mk:
    FILL(A0, 0); FILL(A1, 1)
    CMPR(A0, A1)
    BHI(jcc_mkstub)
    CALL(lbl_new)
    SPILL(5, RV)
    FILL(A0, 0); SHLI(A0, 2)
    LEA_SYM(A1, SYM(g_jc_map)); ADD(A0, A1)
    FILL(A1, 5); ST32_OFF(A0, 0, A1W)
    FILL(A0, 0); INC(A0); SPILL(0, A0)
    B(jcc_mk)
jcc_mkstub:
    MOVI(A0, 0); SPILL(0, A0)
jcc_mks:
    FILL(A0, 0)
    CMPI(A0, E_N)
    BHS(jcc_body)
    CALL(lbl_new)
    SPILL(5, RV)
    FILL(A0, 0); SHLI(A0, 2)
    LEA_SYM(A1, SYM(g_jc_stub)); ADD(A0, A1)
    FILL(A1, 5); ST32_OFF(A0, 0, A1W)
    FILL(A0, 0); INC(A0); SPILL(0, A0)
    B(jcc_mks)

    /* --- govde --- */
jcc_body:
    MOVI(A0, 0); SPILL(0, A0)
jcc_loop:
    FILL(A0, 0); FILL(A1, 1)
    CMPR(A0, A1)
    BHS(jcc_fin)
    /* komutun etiketini buraya bagla */
    FILL(A0, 0); SHLI(A0, 2)
    LEA_SYM(A1, SYM(g_jc_map)); ADD(A0, A1)
    LD32(A0W, A0)
    CALL(lbl_bind)
    /* komutu coz */
    FILL(A0, 0)
    CALL(code_at)
    SPILL(2, RV)
    MOVR(A0, RV); ANDI(A0, 255); SPILL(3, A0)
    FILL(A0, 2); SHRI(A0, 16); SPILL(4, A0)
    LEA_SYM(A1, SYM(g_jc_opd)); ST32_OFF(A1, 0, A0W)
    FILL(A0, 0)
    LEA_SYM(A1, SYM(g_jc_idx)); ST32_OFF(A1, 0, A0W)
    FILL(A0, 3)
    CALL(jc_one)
    BZ(RV, jcc_no)
    FILL(A0, 0); INC(A0); SPILL(0, A0)
    B(jcc_loop)

jcc_fin:
    /* son etiket (atlama hedefi olabilir) + kapanis */
    FILL(A0, 1); SHLI(A0, 2)
    LEA_SYM(A1, SYM(g_jc_map)); ADD(A0, A1)
    LD32(A0W, A0)
    CALL(lbl_bind)
    MOVI(A0, 0xB8); CALL(ja_b)
    MOVI(A0, 1);    CALL(ja_d)
    CALL(ja_ret)
    CALL(jc_stubs)
    CALL(lbl_fix)
    BZ(RV, jcc_no)
    CALL(jc_fnmap)
    MOVI(A0, 1)
    LEA_SYM(A1, SYM(g_jc_ok)); ST32_OFF(A1, 0, A0W)
    MOVI(RV, 1)
    LEAVE_
    RET
jcc_no:
    MOVI(RV, 0)
    LEAVE_
    RET
ENDFUNC(jc_compile)

/* jc_one(A0 = opkod) -> RV = 1 desteklendi / 0 desteklenmiyor
 * Islenen jc_compile'in slot 4'unde DEGIL: burada global uzerinden
 * gecirilir (cagiranin slotunu okumak bu projede uc kez hata oldu). */
    .bss
    .p2align 2
SYM(g_jc_opd):  .space 4
SYM(g_jc_idx):  .space 4
    SECT_TEXT

FUNC(jc_one)
    ENTER(3)
    SPILL(0, A0)
    LEA_SYM(A1, SYM(g_jc_opd))
    LD32(A1W, A1)
    SPILL(1, A1)                    /* islenen */

    FILL(A0, 0)
    CMPI(A0, OP_HALT);        BEQ(j1_halt)
    CMPI(A0, OP_POP);         BEQ(j1_pop)
    CMPI(A0, OP_NIL);         BEQ(j1_nil)
    CMPI(A0, OP_TRUE);        BEQ(j1_true)
    CMPI(A0, OP_FALSE);       BEQ(j1_false)
    CMPI(A0, OP_CONST);       BEQ(j1_const)
    CMPI(A0, OP_GETGLOBAL);   BEQ(j1_getg)
    CMPI(A0, OP_DEFGLOBAL);   BEQ(j1_setg)
    CMPI(A0, OP_SETGLOBAL_P); BEQ(j1_setg)
    CMPI(A0, OP_ADD);         BEQ(j1_add)
    CMPI(A0, OP_SUB);         BEQ(j1_sub)
    CMPI(A0, OP_MUL);         BEQ(j1_mul)
    CMPI(A0, OP_PRINT);       BEQ(j1_print)
    CMPI(A0, OP_SETGLOBAL);   BEQ(j1_setg_keep)
    CMPI(A0, OP_GETGLOBAL2);  BEQ(j1_getg2)
    CMPI(A0, OP_GETG_CONST);  BEQ(j1_ggc)
    CMPI(A0, OP_ADDK);        BEQ(j1_addk)
    CMPI(A0, OP_SUBK);        BEQ(j1_subk)
    CMPI(A0, OP_ADD_SETG);    BEQ(j1_addsetg)
    CMPI(A0, OP_ADDK_SETG);   BEQ(j1_addksetg)
    CMPI(A0, OP_INCGLOBAL);   BEQ(j1_incg)
    CMPI(A0, OP_ACCG);        BEQ(j1_accg)
    CMPI(A0, OP_LT);          BEQ(j1_lt)
    CMPI(A0, OP_LE);          BEQ(j1_le)
    CMPI(A0, OP_GT);          BEQ(j1_gt)
    CMPI(A0, OP_GE);          BEQ(j1_ge)
    CMPI(A0, OP_JMP);         BEQ(j1_jmp)
    CMPI(A0, OP_JLT);         BEQ(j1_jlt)
    CMPI(A0, OP_JLE);         BEQ(j1_jle)
    CMPI(A0, OP_JGT);         BEQ(j1_jgt)
    CMPI(A0, OP_JGE);         BEQ(j1_jge)
    CMPI(A0, OP_NEG);         BEQ(j1_neg)
    CMPI(A0, OP_DIV);         BEQ(j1_div)
    CMPI(A0, OP_MOD);         BEQ(j1_mod)
    CMPI(A0, OP_EQ);          BEQ(j1_eq)
    CMPI(A0, OP_NE);          BEQ(j1_ne)
    CMPI(A0, OP_JEQ);         BEQ(j1_jeq)
    CMPI(A0, OP_JNE);         BEQ(j1_jne)
    CMPI(A0, OP_JZ);          BEQ(j1_jz)
    CMPI(A0, OP_JNZ);         BEQ(j1_jnz)
    CMPI(A0, OP_JZP);         BEQ(j1_jzp)
    CMPI(A0, OP_JNZP);        BEQ(j1_jnzp)
    CMPI(A0, OP_NOT);         BEQ(j1_not)
    CMPI(A0, OP_BAND);        BEQ(j1_band)
    CMPI(A0, OP_BOR);         BEQ(j1_bor)
    CMPI(A0, OP_BXOR);        BEQ(j1_bxor)
    CMPI(A0, OP_BNOT);        BEQ(j1_bnot)
    CMPI(A0, OP_GETLOCAL);    BEQ(j1_getl)
    CMPI(A0, OP_SETLOCAL);    BEQ(j1_setl_keep)
    CMPI(A0, OP_SETLOCAL_P);  BEQ(j1_setl)
    CMPI(A0, OP_GETLOCAL2);   BEQ(j1_getl2)
    CMPI(A0, OP_GETL_CONST);  BEQ(j1_glc)
    CMPI(A0, OP_ADD_SETL);    BEQ(j1_addsetl)
    CMPI(A0, OP_CALL);        BEQ(j1_call)
    CMPI(A0, OP_RET);         BEQ(j1_ret)
    CMPI(A0, OP_RETL);        BEQ(j1_retl)
    CMPI(A0, OP_RETK);        BEQ(j1_retk)
    B(j1_no)

j1_halt:
    MOVI(A0, 0xB8); CALL(ja_b)
    MOVI(A0, 1);    CALL(ja_d)
    CALL(ja_ret)
    B(j1_ok)

j1_pop:
    MOVI(A0, 5); MOVI(A1, J_VS); MOVI(A2, VAL_SIZE)
    CALL(ja_grp1_ri)
    B(j1_ok)

j1_nil:
    MOVI(A0, T_NIL);  MOVI(A1, 0); CALL(jc_pushi); B(j1_ok)
j1_true:
    MOVI(A0, T_BOOL); MOVI(A1, 1); CALL(jc_pushi); B(j1_ok)
j1_false:
    MOVI(A0, T_BOOL); MOVI(A1, 0); CALL(jc_pushi); B(j1_ok)

j1_const:
    /* sabitler CALISMA ZAMANINDA DEGISMEZ: etiket ve deger JIT
     * aninda biliniyor, bellek okumasi gereksiz. */
    FILL(A0, 1); SHLI(A0, VAL_SHIFT)
    LEA_SYM(A1, SYM(g_consts)); LD(A1, A1); ADD(A0, A1)
    SPILL(2, A0)
    LD32(A0W, A0)
    SPILL(0, A0)                    /* etiket */
    FILL(A1, 2); LD_OFF(A1, A1, VAL_PAY)
    FILL(A0, 0)
    CALL(jc_pushi)
    B(j1_ok)

j1_getg:
    FILL(A0, 1); CALL(jc_gvaddr)
    MOVI(A0, J_GV); MOVR(A1, RV)
    CALL(jc_push_from)
    B(j1_ok)

j1_setg:
    FILL(A0, 1); CALL(jc_gvaddr)
    MOVI(A0, J_GV); MOVR(A1, RV)
    CALL(jc_pop_to)
    B(j1_ok)

j1_add:
    MOVI(A0, 0x01); CALL(jc_arith); B(j1_ok)
j1_sub:
    MOVI(A0, 0x29); CALL(jc_arith); B(j1_ok)
j1_mul:
    MOVI(A0, 0xAF); CALL(jc_arith); B(j1_ok)

j1_print:
    /* rdi = rbx - VAL_SIZE ; call print_val ; edi = 10 ; call print_ch */
    MOVI(A0, J_DI); MOVI(A1, J_VS); MOVI(A2, -VAL_SIZE)
    CALL(ja_lea)
    MOVI(A0, J_AX); LEA_SYM(A1, SYM(print_val)); CALL(ja_mov_r_imm64)
    MOVI(A0, J_AX); CALL(ja_call_r)
    MOVI(A0, J_DI); MOVI(A1, 10); CALL(ja_mov_r_imm64)
    MOVI(A0, J_AX); LEA_SYM(A1, SYM(print_ch)); CALL(ja_mov_r_imm64)
    MOVI(A0, J_AX); CALL(ja_call_r)
    MOVI(A0, 5); MOVI(A1, J_VS); MOVI(A2, VAL_SIZE)
    CALL(ja_grp1_ri)
    B(j1_ok)

j1_setg_keep:
    /* yazar ama yigindan ATMAZ */
    FILL(A0, 1); CALL(jc_gvaddr); SPILL(2, RV)
    MOVI(A0, J_CX); MOVI(A1, J_VS); MOVI(A2, VAL_TAG - VAL_SIZE)
    CALL(ja_mov32_r_m)
    MOVI(A0, J_GV); FILL(A1, 2); ADDI(A1, VAL_TAG); MOVI(A2, J_CX)
    CALL(ja_mov32_m_r)
    MOVI(A0, J_CX); MOVI(A1, J_VS); MOVI(A2, VAL_PAY - VAL_SIZE)
    CALL(ja_mov_r_m)
    MOVI(A0, J_GV); FILL(A1, 2); ADDI(A1, VAL_PAY); MOVI(A2, J_CX)
    CALL(ja_mov_m_r)
    B(j1_ok)

j1_getg2:
    FILL(A0, 1); ANDI(A0, 255); CALL(jc_gvaddr)
    MOVI(A0, J_GV); MOVR(A1, RV); CALL(jc_push_from)
    FILL(A0, 1); SHRI(A0, 8); CALL(jc_gvaddr)
    MOVI(A0, J_GV); MOVR(A1, RV); CALL(jc_push_from)
    B(j1_ok)

j1_ggc:
    FILL(A0, 1); ANDI(A0, 255); CALL(jc_gvaddr)
    MOVI(A0, J_GV); MOVR(A1, RV); CALL(jc_push_from)
    FILL(A0, 1); SHRI(A0, 8); CALL(jc_kpush)
    B(j1_ok)

j1_addk:
    MOVI(A0, 0); CALL(jc_kop); B(j1_ok)
j1_subk:
    MOVI(A0, 1); CALL(jc_kop); B(j1_ok)

j1_addsetg:
    MOVI(A0, 0x01); CALL(jc_arith)
    FILL(A0, 1); CALL(jc_gvaddr)
    MOVI(A0, J_GV); MOVR(A1, RV); CALL(jc_pop_to)
    B(j1_ok)

j1_addksetg:
    FILL(A0, 1); ANDI(A0, 255)
    LEA_SYM(A1, SYM(g_jc_opd)); ST32_OFF(A1, 0, A0W)
    MOVI(A0, 0); CALL(jc_kop)
    FILL(A0, 1); SHRI(A0, 8); CALL(jc_gvaddr)
    MOVI(A0, J_GV); MOVR(A1, RV); CALL(jc_pop_to)
    B(j1_ok)

j1_incg:
    /* gvals[n].pay += consts[k].pay  - yigina dokunmaz */
    FILL(A0, 1); ANDI(A0, 255); CALL(jc_gvaddr); SPILL(2, RV)
    MOVI(A0, 7); MOVI(A1, J_GV); FILL(A2, 2); ADDI(A2, VAL_TAG); MOVI(A3, 0)
    CALL(ja_grp1_mi)
    MOVI(A0, E_TYPE); MOVI(A1, CC_NE); CALL(jc_bail)
    FILL(A0, 1); SHRI(A0, 8); CALL(jc_kval)
    MOVR(A1, RV)
    MOVI(A0, 0); FILL(A2, 2); ADDI(A2, VAL_PAY)
    MOVR(A3, A1); MOVI(A1, J_GV)
    CALL(ja_grp1_mi)
    MOVI(A0, E_OVF); MOVI(A1, CC_O); CALL(jc_bail)
    B(j1_ok)

j1_accg:
    /* gvals[a].pay += gvals[b].pay */
    FILL(A0, 1); ANDI(A0, 255); CALL(jc_gvaddr); SPILL(2, RV)
    MOVI(A0, 7); MOVI(A1, J_GV); FILL(A2, 2); ADDI(A2, VAL_TAG); MOVI(A3, 0)
    CALL(ja_grp1_mi)
    MOVI(A0, E_TYPE); MOVI(A1, CC_NE); CALL(jc_bail)
    FILL(A0, 1); SHRI(A0, 8); CALL(jc_gvaddr); SPILL(3, RV)
    MOVI(A0, 7); MOVI(A1, J_GV); FILL(A2, 3); ADDI(A2, VAL_TAG); MOVI(A3, 0)
    CALL(ja_grp1_mi)
    MOVI(A0, E_TYPE); MOVI(A1, CC_NE); CALL(jc_bail)
    MOVI(A0, J_CX); MOVI(A1, J_GV); FILL(A2, 3); ADDI(A2, VAL_PAY)
    CALL(ja_mov_r_m)
    MOVI(A0, 0x01); MOVI(A1, J_GV); FILL(A2, 2); ADDI(A2, VAL_PAY); MOVI(A3, J_CX)
    CALL(ja_alu_mr)
    MOVI(A0, E_OVF); MOVI(A1, CC_O); CALL(jc_bail)
    B(j1_ok)

j1_lt:
    MOVI(A0, CC_L);  CALL(jc_cmp_bool); B(j1_ok)
j1_le:
    MOVI(A0, CC_LE); CALL(jc_cmp_bool); B(j1_ok)
j1_gt:
    MOVI(A0, CC_G);  CALL(jc_cmp_bool); B(j1_ok)
j1_ge:
    MOVI(A0, CC_GE); CALL(jc_cmp_bool); B(j1_ok)

j1_jmp:
    FILL(A0, 1); CALL(jc_tgt); MOVR(A0, RV); CALL(lbl_jmp); B(j1_ok)
j1_jlt:
    MOVI(A0, CC_L);  CALL(jc_cmp_jmp); B(j1_ok)
j1_jle:
    MOVI(A0, CC_LE); CALL(jc_cmp_jmp); B(j1_ok)
j1_jgt:
    MOVI(A0, CC_G);  CALL(jc_cmp_jmp); B(j1_ok)
j1_jge:
    MOVI(A0, CC_GE); CALL(jc_cmp_jmp); B(j1_ok)

j1_neg:
    CALL(jc_need_int1)
    MOVI(A0, J_AX); MOVI(A1, J_VS); MOVI(A2, VAL_PAY - VAL_SIZE)
    CALL(ja_mov_r_m)
    MOVI(A0, J_AX); CALL(ja_neg)
    MOVI(A0, E_OVF); MOVI(A1, CC_O); CALL(jc_bail)
    MOVI(A0, J_VS); MOVI(A1, VAL_PAY - VAL_SIZE); MOVI(A2, J_AX)
    CALL(ja_mov_m_r)
    B(j1_ok)

j1_div:
    MOVI(A0, 0); CALL(jc_divmod); B(j1_ok)
j1_mod:
    MOVI(A0, 1); CALL(jc_divmod); B(j1_ok)

j1_eq:
    MOVI(A0, 0); CALL(jc_eq_push); B(j1_ok)
j1_ne:
    MOVI(A0, 1); CALL(jc_eq_push); B(j1_ok)
j1_jeq:
    MOVI(A0, 0); CALL(jc_eq_jmp); B(j1_ok)
j1_jne:
    MOVI(A0, 1); CALL(jc_eq_jmp); B(j1_ok)

j1_jz:
    MOVI(A0, 1); MOVI(A1, 1); CALL(jc_truth_jmp); B(j1_ok)
j1_jnz:
    MOVI(A0, 0); MOVI(A1, 1); CALL(jc_truth_jmp); B(j1_ok)
j1_jzp:
    MOVI(A0, 1); MOVI(A1, 0); CALL(jc_truth_jmp); B(j1_ok)
j1_jnzp:
    MOVI(A0, 0); MOVI(A1, 0); CALL(jc_truth_jmp); B(j1_ok)

j1_not:
    MOVI(A0, 0); CALL(jc_falsy)     /* dl = yanlis mi, yigindan ATMAZ */
    MOVI(A0, J_DX); MOVI(A1, J_DX); CALL(ja_movzx)
    MOVI(A0, J_VS); MOVI(A1, VAL_TAG - VAL_SIZE); MOVI(A2, T_BOOL)
    CALL(ja_mov32_m_imm32)
    MOVI(A0, J_VS); MOVI(A1, VAL_PAY - VAL_SIZE); MOVI(A2, J_DX)
    CALL(ja_mov_m_r)
    B(j1_ok)

j1_getl:
    FILL(A0, 1); SHLI(A0, VAL_SHIFT)
    MOVR(A1, A0); MOVI(A0, J_VF)
    CALL(jc_push_from)
    B(j1_ok)
j1_setl:
    FILL(A0, 1); SHLI(A0, VAL_SHIFT)
    MOVR(A1, A0); MOVI(A0, J_VF)
    CALL(jc_pop_to)
    B(j1_ok)
j1_setl_keep:
    FILL(A0, 1); SHLI(A0, VAL_SHIFT); SPILL(2, A0)
    MOVI(A0, J_CX); MOVI(A1, J_VS); MOVI(A2, VAL_TAG - VAL_SIZE)
    CALL(ja_mov32_r_m)
    MOVI(A0, J_VF); FILL(A1, 2); ADDI(A1, VAL_TAG); MOVI(A2, J_CX)
    CALL(ja_mov32_m_r)
    MOVI(A0, J_CX); MOVI(A1, J_VS); MOVI(A2, VAL_PAY - VAL_SIZE)
    CALL(ja_mov_r_m)
    MOVI(A0, J_VF); FILL(A1, 2); ADDI(A1, VAL_PAY); MOVI(A2, J_CX)
    CALL(ja_mov_m_r)
    B(j1_ok)
j1_getl2:
    FILL(A0, 1); ANDI(A0, 255); SHLI(A0, VAL_SHIFT)
    MOVR(A1, A0); MOVI(A0, J_VF); CALL(jc_push_from)
    FILL(A0, 1); SHRI(A0, 8); SHLI(A0, VAL_SHIFT)
    MOVR(A1, A0); MOVI(A0, J_VF); CALL(jc_push_from)
    B(j1_ok)
j1_glc:
    FILL(A0, 1); ANDI(A0, 255); SHLI(A0, VAL_SHIFT)
    MOVR(A1, A0); MOVI(A0, J_VF); CALL(jc_push_from)
    FILL(A0, 1); SHRI(A0, 8); CALL(jc_kpush)
    B(j1_ok)
j1_addsetl:
    MOVI(A0, 0x01); CALL(jc_arith)
    FILL(A0, 1); SHLI(A0, VAL_SHIFT)
    MOVR(A1, A0); MOVI(A0, J_VF)
    CALL(jc_pop_to)
    B(j1_ok)

j1_call:
    FILL(A0, 1); CALL(jc_emit_call); B(j1_ok)
j1_ret:
    MOVI(A0, 0); CALL(jc_emit_ret); B(j1_ok)
j1_retl:
    MOVI(A0, 1); CALL(jc_emit_ret); B(j1_ok)
j1_retk:
    MOVI(A0, 2); CALL(jc_emit_ret); B(j1_ok)

/* Bit islemleri: tasma denetimi YOK (amac bit deseni).
 * Kaydirma JIT'te YOK: sayac CL'de olmali ve sinir denetimi
 * gerekiyor; desteklenmeyen komut varsa zaten JIT edilmiyor. */
j1_band:
    MOVI(A0, 0x21); CALL(jc_bitop); B(j1_ok)
j1_bor:
    MOVI(A0, 0x09); CALL(jc_bitop); B(j1_ok)
j1_bxor:
    MOVI(A0, 0x31); CALL(jc_bitop); B(j1_ok)
j1_bnot:
    CALL(jc_need_int1)
    MOVI(A0, J_AX); MOVI(A1, J_VS); MOVI(A2, VAL_PAY - VAL_SIZE)
    CALL(ja_mov_r_m)
    /* not rax -> REX.W F7 /2 */
    MOVI(A0, 0x48); CALL(ja_b)
    MOVI(A0, 0xF7); CALL(ja_b)
    MOVI(A0, 0xD0); CALL(ja_b)
    MOVI(A0, J_VS); MOVI(A1, VAL_PAY - VAL_SIZE); MOVI(A2, J_AX)
    CALL(ja_mov_m_r)
    B(j1_ok)

j1_ok:
    MOVI(RV, 1)
    LEAVE_
    RET
j1_no:
    MOVI(RV, 0)
    LEAVE_
    RET
ENDFUNC(jc_one)

/* jc_arith(A0 = 0x01 add / 0x29 sub / 0xAF imul)
 *   <tur denetimi>
 *   mov rax, [rbx-2*VAL_SIZE+VAL_PAY]
 *   op  rax, [rbx-VAL_SIZE+VAL_PAY]      (imul icin ayri kodlama)
 *   jo  -> tasma stubu
 *   sub rbx, VAL_SIZE
 *   mov [rbx-VAL_SIZE+VAL_PAY], rax
 */
FUNC(jc_arith)
    ENTER(2)
    SPILL(0, A0)
    CALL(jc_need_int2)
    MOVI(A0, J_AX); MOVI(A1, J_VS); MOVI(A2, VAL_PAY - 2*VAL_SIZE)
    CALL(ja_mov_r_m)
    FILL(A0, 0)
    CMPI(A0, 0xAF)
    BEQ(jar_mul)
    /* add/sub rax, [rbx+d] : 03 / 2B */
    FILL(A0, 0)
    CMPI(A0, 0x01)
    BNE(jar_sub)
    MOVI(A0, 0x03); B(jar_rm)
jar_sub:
    MOVI(A0, 0x2B)
jar_rm:
    MOVI(A1, J_AX); MOVI(A2, J_VS); MOVI(A3, VAL_PAY - VAL_SIZE)
    CALL(ja_alu_rm)
    B(jar_ovf)
jar_mul:
    MOVI(A0, J_CX); MOVI(A1, J_VS); MOVI(A2, VAL_PAY - VAL_SIZE)
    CALL(ja_mov_r_m)
    MOVI(A0, J_AX); MOVI(A1, J_CX)
    CALL(ja_imul_rr)
jar_ovf:
    MOVI(A0, E_OVF); MOVI(A1, CC_O); CALL(jc_bail)
    MOVI(A0, 5); MOVI(A1, J_VS); MOVI(A2, VAL_SIZE)
    CALL(ja_grp1_ri)
    MOVI(A0, J_VS); MOVI(A1, VAL_PAY - VAL_SIZE); MOVI(A2, J_AX)
    CALL(ja_mov_m_r)
    /* etiket zaten T_INT: birinci islenenin etiketi yerinde kaliyor */
    LEAVE_
    RET
ENDFUNC(jc_arith)

#endif

#if defined(ARCH_X86_64)

/* jc_kval(A0 = sabit indeksi) -> RV = sabitin YUKU
 * Sabitler calisma zamaninda degismez: deger JIT aninda biliniyor. */
FUNC(jc_kval)
    ENTER(1)
    SHLI(A0, VAL_SHIFT)
    LEA_SYM(A1, SYM(g_consts)); LD(A1, A1); ADD(A0, A1)
    LD_OFF(RV, A0, VAL_PAY)
    LEAVE_
    RET
ENDFUNC(jc_kval)

/* jc_ktag(A0 = sabit indeksi) -> RV = etiket */
FUNC(jc_ktag)
    ENTER(1)
    SHLI(A0, VAL_SHIFT)
    LEA_SYM(A1, SYM(g_consts)); LD(A1, A1); ADD(A0, A1)
    LD32(RVW, A0)
    LEAVE_
    RET
ENDFUNC(jc_ktag)

/* jc_kpush(A0 = sabit indeksi) - sabiti dogrudan it */
FUNC(jc_kpush)
    ENTER(2)
    SPILL(0, A0)
    CALL(jc_ktag)
    SPILL(1, RV)
    FILL(A0, 0)
    CALL(jc_kval)
    MOVR(A1, RV)
    FILL(A0, 1)
    CALL(jc_pushi)
    LEAVE_
    RET
ENDFUNC(jc_kpush)

/* jc_kop(A0 = 0 topla / 1 cikar) - tepedeki tamsayiya sabiti uygula */
FUNC(jc_kop)
    ENTER(2)
    SPILL(0, A0)
    CALL(jc_need_int1)
    LEA_SYM(A0, SYM(g_jc_opd)); LD32(A0W, A0)
    CALL(jc_kval)
    SPILL(1, RV)
    /* add/sub qword [rbx + VAL_PAY - VAL_SIZE], imm32
     * Sabit 32 bite sigmiyorsa registera al. */
    FILL(A0, 1)
    SHRI(A0, 31)
    BNZ(A0, jk_big)
    FILL(A0, 0)
    BNZ(A0, jk_sub)
    MOVI(A0, 0); B(jk_mi)
jk_sub:
    MOVI(A0, 5)
jk_mi:
    MOVI(A1, J_VS); MOVI(A2, VAL_PAY - VAL_SIZE); FILL(A3, 1)
    CALL(ja_grp1_mi)
    B(jk_ovf)
jk_big:
    MOVI(A0, J_CX); FILL(A1, 1); CALL(ja_mov_r_imm64)
    FILL(A0, 0)
    BNZ(A0, jk_bsub)
    MOVI(A0, 0x01); B(jk_bmr)
jk_bsub:
    MOVI(A0, 0x29)
jk_bmr:
    MOVI(A1, J_VS); MOVI(A2, VAL_PAY - VAL_SIZE); MOVI(A3, J_CX)
    CALL(ja_alu_mr)
jk_ovf:
    MOVI(A0, E_OVF); MOVI(A1, CC_O); CALL(jc_bail)
    LEAVE_
    RET
ENDFUNC(jc_kop)

/* jc_cmp2() - tepedeki iki tamsayiyi karsilastir, ikisini de at.
 * Bayraklar KORUNUR: rbx guncellemesi karsilastirmadan ONCE. */
FUNC(jc_cmp2)
    ENTER(1)
    CALL(jc_need_int2)
    MOVI(A0, J_AX); MOVI(A1, J_VS); MOVI(A2, VAL_PAY - 2*VAL_SIZE)
    CALL(ja_mov_r_m)
    MOVI(A0, J_CX); MOVI(A1, J_VS); MOVI(A2, VAL_PAY - VAL_SIZE)
    CALL(ja_mov_r_m)
    MOVI(A0, 5); MOVI(A1, J_VS); MOVI(A2, 2*VAL_SIZE)
    CALL(ja_grp1_ri)                /* sub rbx, 2*VAL_SIZE (bayrak bozar) */
    MOVI(A0, 0x39); MOVI(A1, J_AX); MOVI(A2, J_CX)
    CALL(ja_alu_rr)                 /* cmp rax, rcx  -> bayraklar */
    LEAVE_
    RET
ENDFUNC(jc_cmp2)

/* jc_cmp_bool(A0 = kosul kodu) - karsilastir, sonucu mantiksal it */
FUNC(jc_cmp_bool)
    ENTER(1)
    SPILL(0, A0)
    CALL(jc_cmp2)
    FILL(A0, 0); MOVI(A1, J_AX); CALL(ja_setcc)
    MOVI(A0, J_AX); MOVI(A1, J_AX); CALL(ja_movzx)
    MOVI(A0, J_VS); MOVI(A1, VAL_TAG); MOVI(A2, T_BOOL)
    CALL(ja_mov32_m_imm32)
    MOVI(A0, J_VS); MOVI(A1, VAL_PAY); MOVI(A2, J_AX)
    CALL(ja_mov_m_r)
    MOVI(A0, 0); MOVI(A1, J_VS); MOVI(A2, VAL_SIZE)
    CALL(ja_grp1_ri)
    LEAVE_
    RET
ENDFUNC(jc_cmp_bool)

/* jc_tgt(A0 = bytecode indeksi) -> RV = o komutun etiketi */
FUNC(jc_tgt)
    ENTER(1)
    SHLI(A0, 2)
    LEA_SYM(A1, SYM(g_jc_map)); ADD(A0, A1)
    LD32(RVW, A0)
    LEAVE_
    RET
ENDFUNC(jc_tgt)

/* jc_cmp_jmp(A0 = kosul kodu) - karsilastir ve dallan */
FUNC(jc_cmp_jmp)
    ENTER(2)
    SPILL(0, A0)
    CALL(jc_cmp2)
    LEA_SYM(A0, SYM(g_jc_opd)); LD32(A0W, A0)
    CALL(jc_tgt)
    SPILL(1, RV)
    FILL(A0, 0)
    FILL(A1, 1)
    CALL(lbl_jcc)
    LEAVE_
    RET
ENDFUNC(jc_cmp_jmp)

#endif

#if defined(ARCH_X86_64)

/* jc_divmod(A0 = 0 bolum / 1 kalan)
 * Donanimda tuzak ureten TEK durum INT_MIN / -1; ikisi birden
 * denetlenir. Sifira bolme ayri stub. */
FUNC(jc_divmod)
    ENTER(2)
    SPILL(0, A0)
    CALL(jc_need_int2)
    MOVI(A0, J_CX); MOVI(A1, J_VS); MOVI(A2, VAL_PAY - VAL_SIZE)
    CALL(ja_mov_r_m)                /* rcx = bolen */
    MOVI(A0, 0x85); MOVI(A1, J_CX); MOVI(A2, J_CX)
    CALL(ja_alu_rr)                 /* test rcx, rcx */
    MOVI(A0, E_DIV); MOVI(A1, CC_E); CALL(jc_bail)
    /* bolen == -1 ve bolunen == INT_MIN ise tasma */
    CALL(lbl_new)
    SPILL(1, RV)
    MOVI(A0, 7); MOVI(A1, J_CX); MOVI(A2, -1)
    CALL(ja_grp1_ri)                /* cmp rcx, -1 */
    MOVI(A0, CC_NE); FILL(A1, 1); CALL(lbl_jcc)
    MOVI(A0, J_AX)
    LEA_SYM(A1, jc_intmin); LD(A1, A1)
    CALL(ja_mov_r_imm64)
    MOVI(A0, 0x39); MOVI(A1, J_VS); MOVI(A2, VAL_PAY - 2*VAL_SIZE); MOVI(A3, J_AX)
    CALL(ja_alu_mr)                 /* cmp [bolunen], rax */
    MOVI(A0, E_OVF); MOVI(A1, CC_E); CALL(jc_bail)
    FILL(A0, 1); CALL(lbl_bind)
    /* bol */
    MOVI(A0, J_AX); MOVI(A1, J_VS); MOVI(A2, VAL_PAY - 2*VAL_SIZE)
    CALL(ja_mov_r_m)
    CALL(ja_cqo)
    MOVI(A0, J_CX); CALL(ja_idiv)
    MOVI(A0, 5); MOVI(A1, J_VS); MOVI(A2, VAL_SIZE)
    CALL(ja_grp1_ri)
    FILL(A0, 0)
    BNZ(A0, jdm_mod)
    MOVI(A0, J_VS); MOVI(A1, VAL_PAY - VAL_SIZE); MOVI(A2, J_AX)
    CALL(ja_mov_m_r)
    LEAVE_
    RET
jdm_mod:
    MOVI(A0, J_VS); MOVI(A1, VAL_PAY - VAL_SIZE); MOVI(A2, J_DX)
    CALL(ja_mov_m_r)
    LEAVE_
    RET
ENDFUNC(jc_divmod)

/* jc_eq_flag() - tepedeki iki degerin esitligini rdx'e (0/1) koyar,
 * IKISINI DE yigindan atar.
 * JIT edilen programda nesne olamaz (sabit taramasiyla garanti),
 * dolayisiyla esitlik = etiket ayni VE yuk ayni. */
FUNC(jc_eq_flag)
    ENTER(1)
    CALL(lbl_new)
    SPILL(0, RV)
    MOVI(A0, J_DX); MOVI(A1, J_DX); CALL(ja_xor32)
    MOVI(A0, J_CX); MOVI(A1, J_VS); MOVI(A2, VAL_TAG - 2*VAL_SIZE)
    CALL(ja_mov32_r_m)
    MOVI(A0, VAL_TAG - VAL_SIZE); CALL(ja_disp)
    MOVI(A0, 0); MOVI(A1, 0x3B); MOVI(A2, J_CX); MOVI(A3, J_VS)
    CALL(ja_mem)                    /* cmp ecx, [rbx+d] */
    MOVI(A0, CC_NE); FILL(A1, 0); CALL(lbl_jcc)
    MOVI(A0, J_AX); MOVI(A1, J_VS); MOVI(A2, VAL_PAY - 2*VAL_SIZE)
    CALL(ja_mov_r_m)
    MOVI(A0, 0x3B); MOVI(A1, J_AX); MOVI(A2, J_VS); MOVI(A3, VAL_PAY - VAL_SIZE)
    CALL(ja_alu_rm)                 /* cmp rax, [rbx+d] */
    MOVI(A0, CC_NE); FILL(A1, 0); CALL(lbl_jcc)
    MOVI(A0, 0xB8 + J_DX); CALL(ja_b)
    MOVI(A0, 1); CALL(ja_d)         /* mov edx, 1 */
    FILL(A0, 0); CALL(lbl_bind)
    MOVI(A0, 5); MOVI(A1, J_VS); MOVI(A2, 2*VAL_SIZE)
    CALL(ja_grp1_ri)
    LEAVE_
    RET
ENDFUNC(jc_eq_flag)

/* jc_eq_push(A0 = 0 esit / 1 esit degil) */
FUNC(jc_eq_push)
    ENTER(1)
    SPILL(0, A0)
    CALL(jc_eq_flag)
    FILL(A0, 0)
    BZ(A0, jep_st)
    MOVI(A0, 6); MOVI(A1, J_DX); MOVI(A2, 1)
    CALL(ja_grp1_ri)                /* xor rdx, 1 */
jep_st:
    MOVI(A0, J_VS); MOVI(A1, VAL_TAG); MOVI(A2, T_BOOL)
    CALL(ja_mov32_m_imm32)
    MOVI(A0, J_VS); MOVI(A1, VAL_PAY); MOVI(A2, J_DX)
    CALL(ja_mov_m_r)
    MOVI(A0, 0); MOVI(A1, J_VS); MOVI(A2, VAL_SIZE)
    CALL(ja_grp1_ri)
    LEAVE_
    RET
ENDFUNC(jc_eq_push)

/* jc_eq_jmp(A0 = 0 JEQ / 1 JNE) */
FUNC(jc_eq_jmp)
    ENTER(2)
    SPILL(0, A0)
    CALL(jc_eq_flag)
    MOVI(A0, 0x85); MOVI(A1, J_DX); MOVI(A2, J_DX)
    CALL(ja_alu_rr)                 /* test rdx, rdx */
    LEA_SYM(A0, SYM(g_jc_opd)); LD32(A0W, A0)
    CALL(jc_tgt)
    SPILL(1, RV)
    FILL(A0, 0)
    BZ(A0, jej_eq)
    MOVI(A0, CC_E); B(jej_go)
jej_eq:
    MOVI(A0, CC_NE)
jej_go:
    FILL(A1, 1)
    CALL(lbl_jcc)
    LEAVE_
    RET
ENDFUNC(jc_eq_jmp)

/* jc_falsy(A0 = 1 ise yigindan at) - dl = "yanlis mi"
 * Kural yorumlayicidan birebir: yanlis = bos, ya da (mantiksal ve 0). */
FUNC(jc_falsy)
    ENTER(2)
    SPILL(0, A0)
    CALL(lbl_new)
    SPILL(1, RV)
    MOVI(A0, J_CX); MOVI(A1, J_VS); MOVI(A2, VAL_TAG - VAL_SIZE)
    CALL(ja_mov32_r_m)
    MOVI(A0, J_DX); MOVI(A1, J_DX); CALL(ja_xor32)
    MOVI(A0, 7); MOVI(A1, J_CX); MOVI(A2, T_NIL)
    CALL(ja_grp1_ri)
    MOVI(A0, CC_E); MOVI(A1, J_DX); CALL(ja_setcc)
    MOVI(A0, 7); MOVI(A1, J_CX); MOVI(A2, T_BOOL)
    CALL(ja_grp1_ri)
    MOVI(A0, CC_NE); FILL(A1, 1); CALL(lbl_jcc)
    MOVI(A0, 7); MOVI(A1, J_VS); MOVI(A2, VAL_PAY - VAL_SIZE); MOVI(A3, 0)
    CALL(ja_grp1_mi)
    MOVI(A0, CC_E); MOVI(A1, J_DX); CALL(ja_setcc)
    FILL(A0, 1); CALL(lbl_bind)
    FILL(A0, 0)
    BZ(A0, jf_keep)
    MOVI(A0, 5); MOVI(A1, J_VS); MOVI(A2, VAL_SIZE)
    CALL(ja_grp1_ri)
jf_keep:
    LEAVE_
    RET
ENDFUNC(jc_falsy)

/* jc_truth_jmp(A0 = 1 yanlissa atla / 0 dogruysa, A1 = 1 ise at) */
FUNC(jc_truth_jmp)
    ENTER(3)
    SPILL(0, A0)
    MOVR(A0, A1)
    CALL(jc_falsy)
    MOVI(A0, 0x84); CALL(ja_b)
    MOVI(A0, 0xD2); CALL(ja_b)      /* test dl, dl */
    LEA_SYM(A0, SYM(g_jc_opd)); LD32(A0W, A0)
    CALL(jc_tgt)
    SPILL(1, RV)
    FILL(A0, 0)
    BZ(A0, jtj_true)
    MOVI(A0, CC_NE); B(jtj_go)      /* yanlissa atla: dl != 0 */
jtj_true:
    MOVI(A0, CC_E)                  /* dogruysa atla: dl == 0 */
jtj_go:
    FILL(A1, 1)
    CALL(lbl_jcc)
    LEAVE_
    RET
ENDFUNC(jc_truth_jmp)

    SECT_RODATA
    .p2align 3
jc_intmin:
    PTR 0x8000000000000000
    SECT_TEXT

#endif

#if defined(ARCH_X86_64)

/* ================== FONKSIYON CAGRISI ==================
 *
 * Yorumlayici donus bilgisini g_frames'te tutar; JIT MAKINENIN
 * kendi cagri yigini kullanir. Yigin ETKISI birebir ayni:
 *   girisde  [cagrilan][arg0..argN-1]
 *   cikista  [sonuc]
 *
 * Yigin duzeni cagri sirasinda: [hedef adres][eski r12]
 */
FUNC(jc_emit_call)
    ENTER(4)
    SPILL(0, A0)                    /* argc */
    /* cagrilanin etiketi T_FN mi */
    FILL(A0, 0); INC(A0); SHLI(A0, VAL_SHIFT)
    MOVI(A1, 0); SUB(A1, A0)
    SPILL(1, A1)                    /* -(argc+1)*VAL_SIZE */
    MOVI(A0, J_AX); MOVI(A1, J_VS); FILL(A2, 1); ADDI(A2, VAL_TAG)
    CALL(ja_mov32_r_m)
    MOVI(A0, 7); MOVI(A1, J_AX); MOVI(A2, T_FN)
    CALL(ja_grp1_ri)
    MOVI(A0, E_CALL); MOVI(A1, CC_NE); CALL(jc_bail)
    /* fonksiyon indeksi -> rcx */
    MOVI(A0, J_CX); MOVI(A1, J_VS); FILL(A2, 1); ADDI(A2, VAL_PAY)
    CALL(ja_mov_r_m)
    /* arite denetimi: g_fns[idx].arite == argc mi */
    MOVI(A0, J_AX); LEA_SYM(A1, SYM(g_fns)); CALL(ja_mov_r_imm64)
    /* mov edx, [rax + rcx*8 + 4] : SIB gerektiriyor, elle degil
     * lea rax, [rax + rcx*8] yerine shl+add ile: */
    MOVI(A0, 0xC1); CALL(ja_b)      /* shl rcx, 3 -> REX.W C1 /4 ib */
    MOVI(A0, 0xE1); CALL(ja_b)
    MOVI(A0, 3);    CALL(ja_b)
    MOVI(A0, 0x01); MOVI(A1, J_AX); MOVI(A2, J_CX)
    CALL(ja_alu_rr)                 /* add rax, rcx  (rax = &g_fns[idx]) */
    MOVI(A0, J_DX); MOVI(A1, J_AX); MOVI(A2, 4)
    CALL(ja_mov32_r_m)              /* edx = arite */
    MOVI(A0, 7); MOVI(A1, J_DX); FILL(A2, 0)
    CALL(ja_grp1_ri)
    MOVI(A0, E_ARITY); MOVI(A1, CC_NE); CALL(jc_bail)
    /* hedef adres: g_jc_fnmap[idx] ; rcx zaten idx*8 */
    MOVI(A0, J_AX); LEA_SYM(A1, SYM(g_jc_fnmap)); CALL(ja_mov_r_imm64)
    MOVI(A0, 0x01); MOVI(A1, J_AX); MOVI(A2, J_CX)
    CALL(ja_alu_rr)
    MOVI(A0, J_AX); MOVI(A1, J_AX); MOVI(A2, 0)
    CALL(ja_mov_r_m)
    MOVI(A0, 0x85); MOVI(A1, J_AX); MOVI(A2, J_AX)
    CALL(ja_alu_rr)
    MOVI(A0, E_CALL); MOVI(A1, CC_E); CALL(jc_bail)
    /* derinlik denetimi */
    MOVI(A0, J_DX); LEA_SYM(A1, SYM(g_jc_depth)); CALL(ja_mov_r_imm64)
    MOVI(A0, J_CX); MOVI(A1, J_DX); MOVI(A2, 0); CALL(ja_mov_r_m)
    MOVI(A0, 0); MOVI(A1, J_CX); MOVI(A2, 1); CALL(ja_grp1_ri)
    MOVI(A0, J_DX); MOVI(A1, 0); MOVI(A2, J_CX); CALL(ja_mov_m_r)
    MOVI(A0, 7); MOVI(A1, J_CX); MOVI(A2, MAX_FRAMES); CALL(ja_grp1_ri)
    MOVI(A0, E_DEPTH); MOVI(A1, CC_G); CALL(jc_bail)
    /* VF sakla, yenisini kur, cagir */
    MOVI(A0, J_VF); CALL(ja_push)
    FILL(A0, 0); SHLI(A0, VAL_SHIFT)
    MOVI(A1, 0); SUB(A1, A0)
    MOVI(A0, J_VF); MOVI(A2, J_VS)
    MOVR(A3, A1)
    MOVI(A1, J_VS)
    MOVR(A2, A3)
    CALL(ja_lea)                    /* lea r12, [rbx - argc*VAL_SIZE] */
    MOVI(A0, J_AX); CALL(ja_call_r)
    MOVI(A0, J_VF); CALL(ja_pop)
    MOVI(A0, J_DX); LEA_SYM(A1, SYM(g_jc_depth)); CALL(ja_mov_r_imm64)
    MOVI(A0, J_CX); MOVI(A1, J_DX); MOVI(A2, 0); CALL(ja_mov_r_m)
    MOVI(A0, 5); MOVI(A1, J_CX); MOVI(A2, 1); CALL(ja_grp1_ri)
    MOVI(A0, J_DX); MOVI(A1, 0); MOVI(A2, J_CX); CALL(ja_mov_m_r)
    LEAVE_
    RET
ENDFUNC(jc_emit_call)

/* jc_emit_ret(A0 = 0 yigindan / 1 yerelden / 2 sabitten)
 *   mov rbx, r12 ; sub rbx, VAL_SIZE ; sonucu yaz ; add rbx, VAL_SIZE
 *   mov eax, 1 ; ret
 * En dis seviyedeki RET yorumlayicida HALT: orada yigin oynatilmaz. */
FUNC(jc_emit_ret)
    ENTER(2)
    SPILL(0, A0)
    /* sonucu rcx(etiket) / rax(yuk) icine al */
    FILL(A0, 0)
    CMPI(A0, 1); BEQ(jer_loc)
    CMPI(A0, 2); BEQ(jer_konst)
    MOVI(A0, J_CX); MOVI(A1, J_VS); MOVI(A2, VAL_TAG - VAL_SIZE)
    CALL(ja_mov32_r_m)
    MOVI(A0, J_AX); MOVI(A1, J_VS); MOVI(A2, VAL_PAY - VAL_SIZE)
    CALL(ja_mov_r_m)
    B(jer_store)
jer_loc:
    LEA_SYM(A0, SYM(g_jc_opd)); LD32(A0W, A0); SHLI(A0, VAL_SHIFT)
    SPILL(1, A0)
    MOVI(A0, J_CX); MOVI(A1, J_VF); FILL(A2, 1); ADDI(A2, VAL_TAG)
    CALL(ja_mov32_r_m)
    MOVI(A0, J_AX); MOVI(A1, J_VF); FILL(A2, 1); ADDI(A2, VAL_PAY)
    CALL(ja_mov_r_m)
    B(jer_store)
jer_konst:
    LEA_SYM(A0, SYM(g_jc_opd)); LD32(A0W, A0)
    CALL(jc_ktag)
    SPILL(1, RV)                    /* etiket - ja_b RV'yi ezer */
    MOVI(A0, 0xB8 + J_CX); CALL(ja_b)
    FILL(A0, 1); CALL(ja_d)         /* mov ecx, etiket */
    LEA_SYM(A0, SYM(g_jc_opd)); LD32(A0W, A0)
    CALL(jc_kval)
    MOVI(A0, J_AX); MOVR(A1, RV); CALL(ja_mov_r_imm64)
jer_store:
    /* govde icinde miyiz? en dis RET = HALT */
    LEA_SYM(A0, SYM(g_jc_idx)); LD32(A0W, A0)
    LEA_SYM(A1, SYM(g_in_fn))
    LDB_IDX(A0W, A1, A0)
    BZ(A0, jer_top)
    MOVI(A0, J_VS); MOVI(A1, J_VF); CALL(ja_mov_rr)
    MOVI(A0, 5); MOVI(A1, J_VS); MOVI(A2, VAL_SIZE); CALL(ja_grp1_ri)
    MOVI(A0, J_VS); MOVI(A1, VAL_TAG); MOVI(A2, J_CX); CALL(ja_mov32_m_r)
    MOVI(A0, J_VS); MOVI(A1, VAL_PAY); MOVI(A2, J_AX); CALL(ja_mov_m_r)
    MOVI(A0, 0); MOVI(A1, J_VS); MOVI(A2, VAL_SIZE); CALL(ja_grp1_ri)
jer_top:
    MOVI(A0, 0xB8); CALL(ja_b)
    MOVI(A0, 1);    CALL(ja_d)
    CALL(ja_ret)
    LEAVE_
    RET
ENDFUNC(jc_emit_ret)

#endif

#if defined(ARCH_X86_64)
/* jc_fnmap() - fonksiyon indeksi -> uretilen kod adresi tablosu */
FUNC(jc_fnmap)
    ENTER(3)
    MOVI(A0, 0)
    SPILL(0, A0)
jfm_loop:
    LEA_SYM(A0, SYM(g_nfn)); LD32(A0W, A0)
    FILL(A1, 0)
    CMPR(A1, A0)
    BHS(jfm_done)
    FILL(A0, 0); SHLI(A0, 3)
    LEA_SYM(A1, SYM(g_fns)); ADD(A0, A1)
    LD32(A0W, A0)                   /* giris komut indeksi */
    SHLI(A0, 2)
    LEA_SYM(A1, SYM(g_jc_map)); ADD(A0, A1)
    LD32(A0W, A0)                   /* etiket */
    SHLI(A0, 2)
    LEA_SYM(A1, SYM(g_lbl_pos)); ADD(A0, A1)
    LD32(A0W, A0)
    BZ(A0, jfm_next)                /* baglanmamis */
    DEC(A0)                         /* +1 kodlamasi */
    LEA_SYM(A1, SYM(g_jit_base)); LD(A1, A1)
    ADD(A0, A1)
    SPILL(1, A0)
    FILL(A0, 0); SHLI(A0, 3)
    LEA_SYM(A1, SYM(g_jc_fnmap)); ADD(A0, A1)
    FILL(A1, 1)
    ST(A0, A1)
jfm_next:
    FILL(A0, 0); INC(A0); SPILL(0, A0)
    B(jfm_loop)
jfm_done:
    LEAVE_
    RET
ENDFUNC(jc_fnmap)
#endif

#if defined(ARCH_X86_64)
/* jc_bitop(A0 = 0x21 and / 0x09 or / 0x31 xor)
 * Tur denetimi + iki islenen, tasma denetimi yok. */
FUNC(jc_bitop)
    ENTER(1)
    SPILL(0, A0)
    CALL(jc_need_int2)
    MOVI(A0, J_AX); MOVI(A1, J_VS); MOVI(A2, VAL_PAY - 2*VAL_SIZE)
    CALL(ja_mov_r_m)
    MOVI(A0, J_CX); MOVI(A1, J_VS); MOVI(A2, VAL_PAY - VAL_SIZE)
    CALL(ja_mov_r_m)
    FILL(A0, 0); MOVI(A1, J_AX); MOVI(A2, J_CX)
    CALL(ja_alu_rr)
    MOVI(A0, 5); MOVI(A1, J_VS); MOVI(A2, VAL_SIZE)
    CALL(ja_grp1_ri)
    MOVI(A0, J_VS); MOVI(A1, VAL_PAY - VAL_SIZE); MOVI(A2, J_AX)
    CALL(ja_mov_m_r)
    LEAVE_
    RET
ENDFUNC(jc_bitop)
#endif
