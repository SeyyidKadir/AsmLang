/* peephole.S - komut cifti birlestirme
 *
 * Amac: "bir islem icin kirk takla" durumunu kesmek. Ornek dongu govdesi
 * derleyiciden 15 komut cikiyordu:
 *
 *   toplam = toplam + i   GETGLOBAL GETGLOBAL ADD SETGLOBAL POP
 *   i = i + 1             GETGLOBAL CONST ADD SETGLOBAL POP
 *   i < 5000000           GETGLOBAL CONST LT JZ  ... JMP
 *
 * Birlestirmeden sonra 11. Her birlestirme bir DAGITIM eksiltiyor -
 * bytecode VM'inde en pahali sey dagitimdir (dolayli dallanma).
 *
 * Uc gecis:
 *   0. atlama hedeflerini isaretle
 *   1. cift birlestir, eski->yeni indeks haritasi kur
 *   2. atlama islenenlerini yeni indekslere cevir
 *
 * Kritik kural: ikinci komut bir atlama HEDEFI ise birlestirilmez -
 * yoksa disaridan gelen atlama birlesik komutun ortasina duser.
 */
#include "../abi.inc"
#include "../tables/opcodes.inc"
/* op_isjump disasm.S icinde tanimli; burada yalnizca basvuru */

    .bss
    .p2align 3
    .globl SYM(g_map)
SYM(g_map):   .space ((MAX_CODE + 1) * 4) + GUARD_PAD    /* eski indeks -> yeni indeks */
    .globl SYM(g_tgt)
SYM(g_tgt):   .space (MAX_CODE + 1) + GUARD_PAD          /* atlama hedefi mi */
    .globl SYM(g_nfuse)
SYM(g_nfuse): .space 4
/* Kural onceligi. Asama 0'da yalnizca DAR kurallar calisir; acgozlu
 * GETG_CONST/GETL_CONST ancak Asama 1'de devreye girer.
 * Sebep: "GETGLOBAL i; CONST 1" cifti hemen yutulursa
 * CONST+ADD -> ADDK -> ADDK_SETG -> INCGLOBAL zinciri hic olusamiyor
 * ve "i = i + 1" tek komut yerine iki komut kaliyor. Olculdu: %13 kayip. */
    .globl SYM(g_phase)
SYM(g_phase): .space 4

    SECT_TEXT

/* ins_op(A0 = komut) -> RV = islem kodu */
FUNC(ins_op)
    ENTER(1)
    ANDI(A0, 255)
    MOVR(RV, A0)
    LEAVE_
    RET
ENDFUNC(ins_op)

/* mk_ins(A0 = kaynak komut (islenen buradan), A1 = yeni islem kodu) -> RV
 * ANDI ile 0xFFFF0000 maskesi ARM32'de kodlanamaz; iki kaydirma tasinabilir.
 */
FUNC(mk_ins)
    ENTER(1)
    SHRI(A0, 16)
    SHLI(A0, 16)
    ORR(A0, A1)
    MOVR(RV, A0)
    LEAVE_
    RET
ENDFUNC(mk_ins)

/* fuse(A0 = komut a, A1 = komut b) -> RV = birlesik komut, olmazsa 0
 * Slotlar: 0=a 1=b 2=opa 3=opb
 */
FUNC(fuse)
    ENTER(4)
    SPILL(0, A0)
    SPILL(1, A1)
    ANDI(A0, 255)
    SPILL(2, A0)
    MOVR(A0, A1)
    ANDI(A0, 255)
    SPILL(3, A0)

    /* ---- atama + POP ---- */
    CMPI(A0, OP_POP)
    BNE(fz_ret)
    FILL(A0, 2)
    CMPI(A0, OP_SETGLOBAL)
    BEQ(fz_sgp)
    CMPI(A0, OP_SETLOCAL)
    BEQ(fz_slp)
    B(fz_super)
fz_sgp:
    FILL(A0, 0)
    MOVI(A1, OP_SETGLOBAL_P)
    CALL(mk_ins)
    LEAVE_
    RET
fz_slp:
    FILL(A0, 0)
    MOVI(A1, OP_SETLOCAL_P)
    CALL(mk_ins)
    LEAVE_
    RET
    /* ---- donus dizisi: GETLOCAL/CONST + RET ---- */
fz_ret:
    CMPI(A0, OP_RET)
    BNE(fz_jz)
    FILL(A0, 2)
    CMPI(A0, OP_GETLOCAL); BEQ(fz_retl)
    CMPI(A0, OP_CONST);    BEQ(fz_retk)
    B(fz_no)
fz_retl:
    MOVI(A1, OP_RETL); B(fz_takea)
fz_retk:
    MOVI(A1, OP_RETK)
fz_takea:
    SPILL(2, A1)
    FILL(A0, 0)                     /* islenen a'dan */
    FILL(A1, 2)
    CALL(mk_ins)
    LEAVE_
    RET

    /* ---- karsilastirma + JZ  ->  tersine cevrilmis atlama ---- */
fz_jz:
    CMPI(A0, OP_JZ)
    BEQ(fz_jz_inv)
    CMPI(A0, OP_JNZ)
    BNE(fz_add)
    /* karsilastirma + JNZ -> dogrudan atlama (dongu geri kenari) */
    FILL(A0, 2)
    CMPI(A0, OP_LT); BEQ(fz_jlt)
    CMPI(A0, OP_LE); BEQ(fz_jle)
    CMPI(A0, OP_GT); BEQ(fz_jgt)
    CMPI(A0, OP_GE); BEQ(fz_jge)
    CMPI(A0, OP_EQ); BEQ(fz_jeq)
    CMPI(A0, OP_NE); BEQ(fz_jne)
    B(fz_super)
fz_jz_inv:
    FILL(A0, 2)
    CMPI(A0, OP_LT); BEQ(fz_jge)
    CMPI(A0, OP_LE); BEQ(fz_jgt)
    CMPI(A0, OP_GT); BEQ(fz_jle)
    CMPI(A0, OP_GE); BEQ(fz_jlt)
    CMPI(A0, OP_EQ); BEQ(fz_jne)
    CMPI(A0, OP_NE); BEQ(fz_jeq)
    B(fz_super)
fz_jge: MOVI(A1, OP_JGE); B(fz_mkjump)
fz_jgt: MOVI(A1, OP_JGT); B(fz_mkjump)
fz_jle: MOVI(A1, OP_JLE); B(fz_mkjump)
fz_jlt: MOVI(A1, OP_JLT); B(fz_mkjump)
fz_jne: MOVI(A1, OP_JNE); B(fz_mkjump)
fz_jeq: MOVI(A1, OP_JEQ)
fz_mkjump:
    SPILL(2, A1)                    /* yeni islem kodu */
    FILL(A0, 1)                     /* islenen b'den (atlama hedefi) */
    FILL(A1, 2)
    CALL(mk_ins)
    LEAVE_
    RET

    /* ---- CONST k + ADD/SUB  ->  ADDK/SUBK ---- */
fz_add:
    CMPI(A0, OP_ADD); BEQ(fz_k)
    CMPI(A0, OP_SUB); BEQ(fz_k)
    B(fz_super)
fz_k:
    FILL(A0, 2)
    CMPI(A0, OP_CONST)
    BNE(fz_super)
    /* sabit tamsayi olmali: dizgi birlestirmeyi bozmayalim */
    FILL(A0, 0)
    SHRI(A0, 16)
    SHLI(A0, VAL_SHIFT)
    LEA_SYM(A1, SYM(g_consts))
    LD(A1, A1)
    ADD(A0, A1)
    LD32(A0W, A0)
    BNZ(A0, fz_no)                  /* T_INT = 0 */
    FILL(A0, 3)
    CMPI(A0, OP_ADD)
    BEQ(fz_addk)
    MOVI(A1, OP_SUBK)
    B(fz_mkk)
fz_addk:
    MOVI(A1, OP_ADDK)
fz_mkk:
    SPILL(2, A1)
    FILL(A0, 0)                     /* islenen a'dan (sabit indeksi) */
    FILL(A1, 2)
    CALL(mk_ins)
    LEAVE_
    RET

    /* ---- superkomutlar: iki 8-bit islenen tek alanda ---- */
fz_super:
#if OPT_SUPER == 0
    B(fz_no)
#endif
    FILL(A0, 2)
    FILL(A1, 3)
    /* GETGLOBAL a ; GETGLOBAL b */
    CMPI(A0, OP_GETGLOBAL)
    BNE(fz_s2)
    CMPI(A1, OP_GETGLOBAL)
    BEQ(fz_gg2)
    CMPI(A1, OP_CONST)
    BNE(fz_s_incg)
    LEA_SYM(A1, SYM(g_phase))
    LD32(A1W, A1)
    BZ(A1, fz_no)                   /* asama 0: acgozlu kurallar kapali */
    MOVI(A2, OP_GETG_CONST)
    B(fz_pack)
fz_gg2:
    MOVI(A2, OP_GETGLOBAL2)
    B(fz_pack)
fz_s2:
    /* GETLOCAL a ; GETLOCAL b */
    CMPI(A0, OP_GETLOCAL)
    BNE(fz_s3)
    CMPI(A1, OP_GETLOCAL)
    BEQ(fz_gl2)
    CMPI(A1, OP_CONST)
    BNE(fz_no)
    LEA_SYM(A1, SYM(g_phase))
    LD32(A1W, A1)
    BZ(A1, fz_no)
    MOVI(A2, OP_GETL_CONST)
    B(fz_pack)
fz_gl2:
    MOVI(A2, OP_GETLOCAL2)
    B(fz_pack)
fz_s3:
    /* GETGLOBAL2(a,b) ; ADD_SETG(c)  ->  ACCG(a,b)   (yalniz c == a ise) */
#if !defined(OPT_ACCG) || OPT_ACCG
    CMPI(A0, OP_GETGLOBAL2)
    BNE(fz_s3b)
#else
    B(fz_s3b)
#endif
    CMPI(A1, OP_ADD_SETG)
    BNE(fz_no)
    FILL(A0, 0)
    SHRI(A0, 16)
    ANDI(A0, 255)                   /* a */
    FILL(A1, 1)
    SHRI(A1, 16)
    ANDI(A1, 255)                   /* c */
    CMPR(A0, A1)
    BNE(fz_no)
    FILL(A0, 0)
    MOVI(A1, OP_ACCG)
    CALL(mk_ins)
    LEAVE_
    RET
fz_s3b:
    /* ADD ; SETGLOBAL_P n   /  ADD ; SETLOCAL_P n */
    CMPI(A0, OP_ADD)
    BNE(fz_s4)
    CMPI(A1, OP_SETGLOBAL_P)
    BEQ(fz_addsetg)
    CMPI(A1, OP_SETLOCAL_P)
    BNE(fz_no)
    MOVI(A1, OP_ADD_SETL)
    B(fz_takeb)
fz_addsetg:
    MOVI(A1, OP_ADD_SETG)
fz_takeb:
    SPILL(2, A1)
    FILL(A0, 1)                     /* islenen b'den */
    FILL(A1, 2)
    CALL(mk_ins)
    LEAVE_
    RET
fz_s4:
    /* ADDK k ; SETGLOBAL_P n */
    CMPI(A0, OP_ADDK)
    BNE(fz_no)
    CMPI(A1, OP_SETGLOBAL_P)
    BNE(fz_no)
    MOVI(A2, OP_ADDK_SETG)
    B(fz_pack)

fz_s_incg:
    /* GETGLOBAL n ; ADDK_SETG(k, n)  ->  INCGLOBAL(n, k)
     * "i = i + 1" ucusu tek komuta iner: yigina hic dokunulmaz. */
    CMPI(A1, OP_ADDK_SETG)
    BNE(fz_no)
    FILL(A0, 0)
    SHRI(A0, 16)                    /* n */
    FILL(A1, 1)
    SHRI(A1, 16)
    SHRI(A1, 8)
    ANDI(A1, 255)                   /* ADDK_SETG'in hedef yuvasi */
    CMPR(A0, A1)
    BNE(fz_no)                      /* ayni degiskene yazmali */
    FILL(A1, 1)
    SHRI(A1, 16)
    ANDI(A1, 255)                   /* k */
    SHLI(A1, 8)
    ORR(A0, A1)                     /* n | k<<8 */
    SHLI(A0, 16)
    MOVI(A1, OP_INCGLOBAL)
    ORR(A0, A1)
    MOVR(RV, A0)
    LEAVE_
    RET

/* iki islenen de 8 bite sigiyorsa paketle, sigmazsa birlestirme */
fz_pack:
    SPILL(2, A2)
    FILL(A0, 0)
    SHRI(A0, 16)
    CMPI(A0, 256)
    BHS(fz_no)
    FILL(A1, 1)
    SHRI(A1, 16)
    CMPI(A1, 256)
    BHS(fz_no)
    SHLI(A1, 8)
    ORR(A0, A1)
    SHLI(A0, 16)
    FILL(A1, 2)
    ORR(A0, A1)
    MOVR(RV, A0)
    LEAVE_
    RET

fz_no:
    MOVI(RV, 0)
    LEAVE_
    RET
ENDFUNC(fuse)

/* code_at / code_put -> src/vm/codebuf.S (yurutucuyla ortak) */

/* =====================================================================
 * peephole()
 * Slotlar: 0=n 1=i 2=j 3=a 4=b 5=gecici
 * ===================================================================== */
FUNC(peephole)
    ENTER(6)
    LEA_SYM(A0, SYM(g_ncode))
    LD32(A0W, A0)
    SPILL(0, A0)
    CMPI(A0, MAX_CODE)
    BHS(ph_end)                     /* haritalar yetmez: guvenli tarafta kal */
    MOVI(A0, 0)
    LEA_SYM(A1, SYM(g_nfuse))
    ST32_OFF(A1, 0, A0W)

    /* --- gecis 0: atlama hedeflerini isaretle --- */
    MOVI(A0, 0)
    SPILL(1, A0)
ph_t0:
    FILL(A0, 1)
    FILL(A1, 0)
    CMPR(A0, A1)
    BHS(ph_t0done)
    LEA_SYM(A1, SYM(g_tgt))
    ADD(A1, A0)
    MOVI(A2, 0)
    STB(A1, A2B)
    FILL(A0, 1); INC(A0); SPILL(1, A0)
    B(ph_t0)
ph_t0done:
    LEA_SYM(A1, SYM(g_tgt))
    FILL(A0, 0)
    ADD(A1, A0)
    MOVI(A2, 1)
    STB(A1, A2B)                    /* son (kod sonuna atlama) hedeftir */

    MOVI(A0, 0)
    SPILL(1, A0)
ph_t1:
    FILL(A0, 1)
    FILL(A1, 0)
    CMPR(A0, A1)
    BHS(ph_t1done)
    CALL(code_at)
    SPILL(3, RV)
    MOVR(A0, RV)
    ANDI(A0, 255)
    LEA_SYM(A1, SYM(op_isjump))
    LDB_IDX(A0W, A1, A0)
    BZ(A0, ph_t1adv)
    FILL(A0, 3)
    SHRI(A0, 16)                    /* atlama hedefi */
    FILL(A1, 0)
    CMPR(A0, A1)
    BHI(ph_t1adv)
    LEA_SYM(A1, SYM(g_tgt))
    ADD(A1, A0)
    MOVI(A2, 1)
    STB(A1, A2B)
ph_t1adv:
    FILL(A0, 1); INC(A0); SPILL(1, A0)
    B(ph_t1)
ph_t1done:

    /* --- gecis 1: birlestir (yerinde; j <= i her zaman) --- */
    MOVI(A0, 0)
    SPILL(1, A0)                    /* i */
    SPILL(2, A0)                    /* j */
ph_f:
    FILL(A0, 1)
    FILL(A1, 0)
    CMPR(A0, A1)
    BHS(ph_fdone)
    /* g_map[i] = j */
    FILL(A0, 1)
    SHLI(A0, 2)
    LEA_SYM(A1, SYM(g_map))
    ADD(A0, A1)
    FILL(A1, 2)
    ST32_OFF(A0, 0, A1W)
    /* son komut mu? */
    FILL(A0, 1)
    INC(A0)
    FILL(A1, 0)
    CMPR(A0, A1)
    BHS(ph_copy)
    /* i+1 atlama hedefi mi? */
    LEA_SYM(A1, SYM(g_tgt))
    ADD(A1, A0)
    LDB(A2W, A1)
    BNZ(A2, ph_copy)
    /* birlestirmeyi dene */
    FILL(A0, 1)
    CALL(code_at)
    SPILL(3, RV)
    FILL(A0, 1)
    INC(A0)
    CALL(code_at)
    SPILL(4, RV)
    FILL(A0, 3)
    FILL(A1, 4)
    CALL(fuse)
    BZ(RV, ph_copy)
    /* birlesti: code[j] = f, g_map[i+1] = j, i += 2, j += 1 */
    SPILL(5, RV)
    FILL(A0, 1)
    INC(A0)
    SHLI(A0, 2)
    LEA_SYM(A1, SYM(g_map))
    ADD(A0, A1)
    FILL(A1, 2)
    ST32_OFF(A0, 0, A1W)
    FILL(A0, 2)
    FILL(A1, 5)
    CALL(code_put)
    LEA_SYM(A0, SYM(g_nfuse))
    LD32(A1W, A0)
    INC(A1)
    ST32_OFF(A0, 0, A1W)
    FILL(A0, 1); ADDI(A0, 2); SPILL(1, A0)
    FILL(A0, 2); INC(A0);     SPILL(2, A0)
    B(ph_f)
ph_copy:
    FILL(A0, 1)
    CALL(code_at)
    MOVR(A1, RV)
    FILL(A0, 2)
    CALL(code_put)
    FILL(A0, 1); INC(A0); SPILL(1, A0)
    FILL(A0, 2); INC(A0); SPILL(2, A0)
    B(ph_f)
ph_fdone:
    /* g_map[n] = j  (kod sonuna atlamalar icin) */
    FILL(A0, 0)
    SHLI(A0, 2)
    LEA_SYM(A1, SYM(g_map))
    ADD(A0, A1)
    FILL(A1, 2)
    ST32_OFF(A0, 0, A1W)
    FILL(A0, 2)
    LEA_SYM(A1, SYM(g_ncode))
    ST32_OFF(A1, 0, A0W)
    SPILL(0, A0)                    /* n = j */

    /* --- gecis 2: atlama islenenlerini yeniden esle --- */
    MOVI(A0, 0)
    SPILL(1, A0)
ph_r:
    FILL(A0, 1)
    FILL(A1, 0)
    CMPR(A0, A1)
    BHS(ph_fns)
    CALL(code_at)
    SPILL(3, RV)
    MOVR(A0, RV)
    ANDI(A0, 255)
    SPILL(5, A0)
    LEA_SYM(A1, SYM(op_isjump))
    LDB_IDX(A0W, A1, A0)
    BZ(A0, ph_radv)
    FILL(A0, 3)
    SHRI(A0, 16)
    SHLI(A0, 2)
    LEA_SYM(A1, SYM(g_map))
    ADD(A0, A1)
    LD32(A0W, A0)                   /* yeni hedef */
    SHLI(A0, 16)
    FILL(A1, 5)
    ORR(A0, A1)
    MOVR(A1, A0)
    FILL(A0, 1)
    CALL(code_put)
ph_radv:
    FILL(A0, 1); INC(A0); SPILL(1, A0)
    B(ph_r)

    /* --- gecis 3: FONKSIYON GIRIS NOKTALARINI yeniden esle ---
     * Bunu unutmak sinsi bir hataydi: atlama islenenleri esleniyordu ama
     * g_fns[i].entry derleyicinin yazdigi ESKI indekste kaliyordu.
     * Fusion fonksiyon govdesinden ONCE olustugunda CALL cop adrese
     * sicriyor ve program cokuyordu. Kod indeksi tutan HER yer eslenmeli.
     */
ph_fns:
    MOVI(A0, 0)
    SPILL(1, A0)
pf_loop:
    LEA_SYM(A0, SYM(g_nfn))
    LD32(A0W, A0)
    FILL(A1, 1)
    CMPR(A1, A0)
    BHS(ph_end)
    FILL(A0, 1)
    SHLI(A0, 3)
    LEA_SYM(A1, SYM(g_fns))
    ADD(A0, A1)
    SPILL(4, A0)
    LD32(A0W, A0)
    SHLI(A0, 2)
    LEA_SYM(A1, SYM(g_map))
    ADD(A0, A1)
    LD32(A0W, A0)
    FILL(A1, 4)
    ST32_OFF(A1, 0, A0W)
    FILL(A0, 1)
    INC(A0)
    SPILL(1, A0)
    B(pf_loop)

ph_end:
    LEAVE_
    RET
ENDFUNC(peephole)
