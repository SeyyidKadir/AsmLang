/* vm.S - bytecode sanal makinesi
 *
 * Registerlar (dort mimaride de sanal register haritasindan):
 *   VP = program sayaci (kod isaretcisi)
 *   VS = deger yigini tepesi (siradaki bos slot)
 *   VF = cerceve tabani (yerel 0'in adresi)
 *
 * Dagitim NEXT makrosuyla yapilir ve makro mimari basina ELLE yazilmistir
 * (bkz. arch/<isa>/abi.inc). NEXT her isleyicinin sonuna kopyalanir;
 * merkezi bir dongu yoktur. Projede optimizasyon emegini sakladigimiz yer
 * burasi: lexer ve parser bir kez calisir, bu dongu milyarlarca kez.
 */
#include "../abi.inc"
#include "../tables/tokens.inc"
#include "../tables/opcodes.inc"

    .bss
    .p2align 3
    .globl SYM(g_stack)
SYM(g_stack):   .space (VM_STACK_BYTES) + GUARD_PAD
    .globl SYM(g_gvals)
SYM(g_gvals):   .space (MAX_GLOBALS * VAL_SIZE) + GUARD_PAD
/* cerceve: {u32 donus komut indeksi, u32 eski VF ofseti} */
    .globl SYM(g_frames)
SYM(g_frames):  .space (MAX_FRAMES * 8) + GUARD_PAD
    .globl SYM(g_nframe)
SYM(g_nframe):  .space 4
    .globl SYM(g_rterr)
SYM(g_rterr):   .space 4
    .globl SYM(g_rem)
/* Kalan KELIME genisliginde: 4 bayt saklanirken 64-bit deger
 * kirpiliyordu ve negatif kalan isaretsiz gorunuyordu
 * ((0-17) %% 5 -> 4294967294). JIT karsilastirmasi ortaya cikardi. */
SYM(g_rem):     .space 8
/* Yurutulen bytecode komutu sayisi (OPT_COUNT ile artirilir).
 * 15->5 iddiasini disassembly'den DEGIL, gercekten calistirarak
 * dogrulamak icin. perf yoksa elimizdeki tek kesin metrik bu. */
    .p2align 3
    .globl SYM(g_ninstr)
SYM(g_ninstr):  .space 8

    SECT_RODATA
rt_shift: .ascii "calisma hatasi: kaydirma sayisi sinir disinda\n"
    .equ  rt_shift_len, . - rt_shift
rt_type:  .ascii "calisma hatasi: tur uyusmazligi\n"
    .equ  rt_type_len, . - rt_type
rt_call:  .ascii "calisma hatasi: cagrilabilir degil\n"
    .equ  rt_call_len, . - rt_call
rt_arity: .ascii "calisma hatasi: arguman sayisi uymuyor\n"
    .equ  rt_arity_len, . - rt_arity
rt_div0:  .ascii "calisma hatasi: sifira bolme\n"
    .equ  rt_div0_len, . - rt_div0
rt_range: .ascii "calisma hatasi: dizi sinirlari disinda\n"
    .equ  rt_range_len, . - rt_range
rt_depth: .ascii "calisma hatasi: cagri derinligi asildi\n"
    .equ  rt_depth_len, . - rt_depth
rt_ovf:   .ascii "calisma hatasi: deger yigini tasti\n"
    .equ  rt_ovf_len, . - rt_ovf
rt_iovf:  .ascii "calisma hatasi: tamsayi tasmasi\n"
    .equ  rt_iovf_len, . - rt_iovf
rt_badop: .ascii "calisma hatasi: gecersiz islem kodu\n"
    .equ  rt_badop_len, . - rt_badop
rt_pc:    .ascii "calisma hatasi: atlama hedefi kod disinda\n"
    .equ  rt_pc_len, . - rt_pc
v_lb:     .ascii "["
    .equ  v_lb_len, . - v_lb
v_rb:     .ascii "]"
    .equ  v_rb_len, . - v_rb
v_cm:     .ascii ", "
    .equ  v_cm_len, . - v_cm
v_nat:    .ascii "<govde>"
    .equ  v_nat_len, . - v_nat
v_buf:    .ascii "<tampon "
    .equ  v_buf_len, . - v_buf
v_nil:    .ascii "bos"
    .equ  v_nil_len, . - v_nil
v_true:   .ascii "dogru"
    .equ  v_true_len, . - v_true
v_false:  .ascii "yanlis"
    .equ  v_false_len, . - v_false
v_fn:     .ascii "<fonk>"
    .equ  v_fn_len, . - v_fn

/* ---- yigin islemleri (mevcut makrolardan kurulu) ---- */
#define PUSH(tagR, payR)   ST32_OFF(VS, VAL_TAG, tagR); \
                           ST32_OFF(VS, VAL_PAY, payR); ADDI(VS, VAL_SIZE)
/* Slottan slota kopyalama: 64-bitte tek yukleme+saklama.
 * Onceki hali etiket ve yuku ayri ayri tasiyordu = 4 bellek islemi. */
#define VPUSH(srcR, tmp)   VCOPY(VS, srcR, tmp); ADDI(VS, VAL_SIZE)
/* GC kokleri yigini tarar; ayirma yapan her isleyici once VS'yi yayinlar */
#define SYNC_VS  LEA_SYM(A2, SYM(g_vstop)); ST(A2, VS)

#define POP_(tagR, payR)   SUBI(VS, VAL_SIZE); \
                           LD32_OFF(tagR, VS, VAL_TAG); \
                           LD32_OFF(payR, VS, VAL_PAY)

/* --- taban registerleri ---
 * Kuresel erisim ile yerel erisim arasindaki TEK fark LEA_SYM idi
 * (yerel VF'yi zaten registerdan aliyor). Tabani registera koyunca
 * fark kapaniyor; INCLOCAL/ADDLOCAL gibi komut cogaltmasina gerek yok.
 * Sabit havuzu ayrica bir de LOAD gerektiriyordu (isaretci degisken).
 */
#if OPT_BASEREG && defined(HAVE_VC)
#  define GVALS(r)   MOVR(r, VC)
#else
#  define GVALS(r)   LEA_SYM(r, SYM(g_gvals))
#endif
#if OPT_BASEREG && defined(HAVE_VK)
#  define GCONSTS(r) MOVR(r, VK)
#else
#  define GCONSTS(r) LEA_SYM(r, SYM(g_consts)); LD(r, r)
#endif

    SECT_TEXT

/* =====================================================================
 * udivmod(A0 = bolunen, A1 = bolen) -> RV = bolum, kalan g_rem'de
 *
 * Bolme komutu KULLANMAZ. ARMv7'nin bir kisminda udiv yok, x86'da div'in
 * edx:eax kisiti makro katmanini kirletiyor. Kaydir-cikar uzun bolme
 * dort mimaride de aynen calisiyor: 32 tur, sabit maliyet.
 * ===================================================================== */
FUNC(udivmod)
    ENTER(5)
    SPILL(0, A0)                    /* bolunen */
    SPILL(1, A1)                    /* bolen   */
    MOVI(A0, 0)
    SPILL(2, A0)                    /* bolum   */
    SPILL(3, A0)                    /* kalan   */
    MOVI(A0, 31)
    SPILL(4, A0)                    /* bit sayaci */
    FILL(A0, 1)
    BZ(A0, ud_done)
ud_loop:
    FILL(A0, 3)
    SHLI(A0, 1)
    SPILL(3, A0)
    FILL(A0, 0)                     /* bolunen */
    FILL(A1, 4)                     /* bit indeksi */
    SHR_R(A0, A1)
    ANDI(A0, 1)
    FILL(A1, 3)
    ORR(A1, A0)
    SPILL(3, A1)
    FILL(A0, 1)                     /* bolen */
    CMPR(A1, A0)
    BLO(ud_next)
    SUB(A1, A0)
    SPILL(3, A1)
    MOVI(A0, 1)
    FILL(A1, 4)
    SHL_R(A0, A1)
    FILL(A1, 2)
    ORR(A1, A0)
    SPILL(2, A1)
ud_next:
    FILL(A0, 4)
    BZ(A0, ud_done)
    DEC(A0)
    SPILL(4, A0)
    B(ud_loop)
ud_done:
    LEA_SYM(A0, SYM(g_rem))
    FILL(A1, 3)
    ST(A0, A1)
    FILL(RV, 2)
    LEAVE_
    RET
ENDFUNC(udivmod)

/* idivmod(A0 = a, A1 = b) -> RV = bolum (isaret dogrultulmus) */
/* idivmod(A0 = bolunen, A1 = bolen) -> RV = bolum, g_rem = kalan
 *
 * IKI HATA DUZELTILDI (JIT ile yorumlayiciyi karsilastirirken cikti):
 *
 * 1. Bolen NEGATIFKEN bolunen eziliyordu. Isaret hesabi icin A0
 *    gecici olarak kullaniliyor, sonra FILL(A0,0) ile "geri
 *    yukleniyordu" - ama slot 0 o noktada HENUZ YAZILMAMISTI.
 *    Sonuc: negatif bolenli her bolme COP uretiyordu.
 *    (100 / -5 -> 860675). Asama 3'ten beri vardi; testlerim yalniz
 *    negatif BOLUNEN kullaniyordu, o yuzden gorunmedi.
 *
 * 2. Kalanin isareti yanlisti. C ve x86 idiv semantiginde kalanin
 *    isareti BOLUNENIN isaretini izler, bolum isaretini degil.
 *    17 % -5 = 2 olmali, kod -2 uretiyordu. JIT (idiv) dogru
 *    davraniyordu, yani ikisi iraksiyordu.
 *
 * Slotlar: 0=bolunen 1=bolen/kalan 2=bolum isareti 3=kalan isareti
 */
FUNC(idivmod)
    ENTER(4)
    MOVI(A2, 0)
    SPILL(2, A2)
    SPILL(3, A2)
    CMPI(A0, 0)
    BGE(id_a_ok)
    NEG(A0)
    MOVI(A2, 1)
    SPILL(2, A2)
    SPILL(3, A2)                    /* kalan isareti = bolunen negatif */
id_a_ok:
    SPILL(0, A0)                    /* bolunen GUVENDE */
    CMPI(A1, 0)
    BGE(id_b_ok)
    NEG(A1)
    FILL(A2, 2)
    MOVI(A0, 1)
    SUB(A0, A2)                     /* bolum isaretini tersle */
    SPILL(2, A0)
id_b_ok:
    FILL(A0, 0)
    SPILL(1, A1)
    CALL(udivmod)
    SPILL(0, RV)                    /* bolum */
    LEA_SYM(A0, SYM(g_rem))
    LD(A1, A0)
    SPILL(1, A1)                    /* kalan */
    FILL(A0, 2)
    BZ(A0, id_q_ok)
    FILL(A0, 0); NEG(A0); SPILL(0, A0)
id_q_ok:
    FILL(A0, 3)
    BZ(A0, id_r_ok)
    FILL(A0, 1); NEG(A0); SPILL(1, A0)
id_r_ok:
    FILL(A0, 1)
    LEA_SYM(A1, SYM(g_rem))
    ST(A1, A0)
    FILL(RV, 0)
    LEAVE_
    RET
ENDFUNC(idivmod)

/* print_i32(A0 = deger) */
FUNC(print_i32)
    ENTER(1)
    CMPI(A0, 0)
    BGE(pi_pos)
    SPILL(0, A0)
    MOVI(A0, 45)                    /* '-' */
    CALL(print_ch)
    FILL(A0, 0)
    NEG(A0)
pi_pos:
    CALL(print_u32)
    LEAVE_
    RET
ENDFUNC(print_i32)

/* print_val(A0 = slot isaretcisi) */
FUNC(print_val)
    ENTER(3)
    SPILL(0, A0)
    LD32_OFF(A1W, A0, VAL_TAG)
    CMPI(A1, T_INT);  BEQ(pv_int)
    CMPI(A1, T_NIL);  BEQ(pv_nil)
    CMPI(A1, T_BOOL); BEQ(pv_bool)
    CMPI(A1, T_OBJ);  BEQ(pv_obj)
    CMPI(A1, T_NAT);  BEQ(pv_nat)
    LEA_SYM(A0, v_fn); MOVI(A1, v_fn_len); CALL(print_str)
    LEAVE_
    RET
pv_nat:
    LEA_SYM(A0, v_nat); MOVI(A1, v_nat_len); CALL(print_str)
    LEAVE_
    RET
pv_int:
    LD_OFF(A0, A0, VAL_PAY)
    CALL(print_i32)
    LEAVE_
    RET
pv_nil:
    LEA_SYM(A0, v_nil); MOVI(A1, v_nil_len); CALL(print_str)
    LEAVE_
    RET
pv_bool:
    LD_OFF(A1, A0, VAL_PAY)
    BZ(A1, pv_false)
    LEA_SYM(A0, v_true); MOVI(A1, v_true_len); CALL(print_str)
    LEAVE_
    RET
pv_false:
    LEA_SYM(A0, v_false); MOVI(A1, v_false_len); CALL(print_str)
    LEAVE_
    RET
pv_obj:
    LD_OFF(A0, A0, VAL_PAY)
    CALL(obj_ptr)
    SPILL(1, RV)
    LD32_OFF(A0W, RV, OBJ_KIND)
    CMPI(A0, O_STR)
    BEQ(pv_ostr)
    CMPI(A0, O_BUF)
    BEQ(pv_obuf)
    /* dizi: [e, e, e] */
    LEA_SYM(A0, v_lb); MOVI(A1, v_lb_len); CALL(print_str)
    MOVI(A0, 0)
    SPILL(2, A0)
pv_arr:
    FILL(A0, 1)
    LD32_OFF(A0W, A0, OBJ_LEN)
    FILL(A1, 2)
    CMPR(A1, A0)
    BHS(pv_arrend)
    BZ(A1, pv_noc)
    LEA_SYM(A0, v_cm); MOVI(A1, v_cm_len); CALL(print_str)
pv_noc:
    FILL(A0, 2)
    SHLI(A0, VAL_SHIFT)
    FILL(A1, 1)
    ADDI(A1, OBJ_DATA)
    ADD(A0, A1)
    CALL(print_val)
    FILL(A0, 2); INC(A0); SPILL(2, A0)
    B(pv_arr)
pv_arrend:
    LEA_SYM(A0, v_rb); MOVI(A1, v_rb_len); CALL(print_str)
    LEAVE_
    RET
pv_obuf:
    /* <tampon N> */
    LEA_SYM(A0, v_buf); MOVI(A1, v_buf_len); CALL(print_str)
    FILL(A0, 1)
    LD32_OFF(A0W, A0, OBJ_LEN)
    CALL(print_u32)
    MOVI(A0, 62)                    /* '>' */
    CALL(print_ch)
    LEAVE_
    RET
pv_ostr:
    FILL(A0, 1)
    LD32_OFF(A1W, A0, OBJ_LEN)
    ADDI(A0, OBJ_DATA)
    CALL(print_str)
    LEAVE_
    RET
ENDFUNC(print_val)

/* =====================================================================
 * run(A0 = kod, A1 = sabitler) -> RV = calisma hatasi sayisi
 * ===================================================================== */
FUNC(run)
    ENTER(8)
    SAVE3(1)
    LEA_SYM(A2, SYM(g_code))
    ST(A2, A0)
    LEA_SYM(A2, SYM(g_consts))
    ST(A2, A1)
    MOVI(A2, 0)
    LEA_SYM(A1, SYM(g_nframe)); ST32_OFF(A1, 0, A2W)
    LEA_SYM(A1, SYM(g_rterr));  ST32_OFF(A1, 0, A2W)
    MOVR(VP, A0)                    /* pc = kod basi */
    LEA_SYM(VS, SYM(g_stack))
    MOVR(VF, VS)
#if OPT_BASEREG && defined(HAVE_VC)
    LEA_SYM(VC, SYM(g_gvals))
#endif
#if OPT_BASEREG && defined(HAVE_VK)
    LEA_SYM(VK, SYM(g_consts))
    LD(VK, VK)
#endif
    SYNC_VS
    NEXT

/* --- islem kodu -> ofset tablosu ---
 * .text icinde: "isleyici - optable" derleme aninda katlanir,
 * hicbir yer degistirme kaydi uretmez (PIE/ASLR icin sart).
 */
    .p2align 4
    .globl SYM(optable)
SYM(optable):
    .long op_halt      - SYM(optable)
    .long op_const     - SYM(optable)
    .long op_nil       - SYM(optable)
    .long op_true      - SYM(optable)
    .long op_false     - SYM(optable)
    .long op_pop       - SYM(optable)
    .long op_getlocal  - SYM(optable)
    .long op_setlocal  - SYM(optable)
    .long op_getglobal - SYM(optable)
    .long op_setglobal - SYM(optable)
    .long op_defglobal - SYM(optable)
    .long op_add       - SYM(optable)
    .long op_sub       - SYM(optable)
    .long op_mul       - SYM(optable)
    .long op_div       - SYM(optable)
    .long op_mod       - SYM(optable)
    .long op_neg       - SYM(optable)
    .long op_not       - SYM(optable)
    .long op_eq        - SYM(optable)
    .long op_ne        - SYM(optable)
    .long op_lt        - SYM(optable)
    .long op_le        - SYM(optable)
    .long op_gt        - SYM(optable)
    .long op_ge        - SYM(optable)
    .long op_jmp       - SYM(optable)
    .long op_jz        - SYM(optable)
    .long op_jzp       - SYM(optable)
    .long op_jnzp      - SYM(optable)
    .long op_print     - SYM(optable)
    .long op_call      - SYM(optable)
    .long op_ret       - SYM(optable)
    .long op_array     - SYM(optable)
    .long op_index     - SYM(optable)
    .long op_setidx    - SYM(optable)
    .long op_setglobal_p - SYM(optable)
    .long op_setlocal_p  - SYM(optable)
    .long op_addk        - SYM(optable)
    .long op_subk        - SYM(optable)
    .long op_jeq         - SYM(optable)
    .long op_jne         - SYM(optable)
    .long op_jlt         - SYM(optable)
    .long op_jle         - SYM(optable)
    .long op_jgt         - SYM(optable)
    .long op_jge         - SYM(optable)
    .long op_getglobal2  - SYM(optable)
    .long op_getlocal2   - SYM(optable)
    .long op_add_setg    - SYM(optable)
    .long op_add_setl    - SYM(optable)
    .long op_addk_setg   - SYM(optable)
    .long op_incglobal   - SYM(optable)
    .long op_jnz         - SYM(optable)
    .long op_getg_const  - SYM(optable)
    .long op_getl_const  - SYM(optable)
    .long op_retl        - SYM(optable)
    .long op_retk        - SYM(optable)
    .long op_accg        - SYM(optable)
    .long op_band        - SYM(optable)
    .long op_bor         - SYM(optable)
    .long op_bxor        - SYM(optable)
    .long op_shl         - SYM(optable)
    .long op_shr         - SYM(optable)
    .long op_bnot        - SYM(optable)
    /* --- 256'ya kadar doldur ---
     * NEXT opcode'u 8 bite maskeliyor (0-255) ama tabloda OP_COUNT
     * girdi vardi. 55-255 arasi bir opcode tablonun DISINI okuyup
     * cop offset aliyor ve KEYFI ADRESE SICRIYORDU. Bozuk bytecode
     * ya da bellek bozulmasi bunu tetikleyebilir.
     * Doldurma calisma zamaninda SIFIR maliyetli: ek denetim yok,
     * gecersiz opcode dogal olarak op_bad'e gidiyor. */
    .rept 256 - OP_COUNT
    .long op_bad         - SYM(optable)
    .endr

    .p2align 4
op_halt:
    REST3(1)
    LEA_SYM(A0, SYM(g_rterr))
    LD32(RVW, A0)
    LEAVE_
    RET

op_const:
    GETOPD(A0W)
    SHLI(A0, VAL_SHIFT)
    GCONSTS(A1)
    ADD(A0, A1)
    VPUSH(A0, A1)
    NEXT

op_nil:
    MOVI(A0, T_NIL)
    MOVI(A1, 0)
    PUSH(A0W, A1W)
    NEXT

op_true:
    MOVI(A0, T_BOOL)
    MOVI(A1, 1)
    PUSH(A0W, A1W)
    NEXT

op_false:
    MOVI(A0, T_BOOL)
    MOVI(A1, 0)
    PUSH(A0W, A1W)
    NEXT

op_pop:
    SUBI(VS, VAL_SIZE)
    NEXT

op_getlocal:
    GETOPD(A0W)
    SHLI(A0, VAL_SHIFT)
    ADD(A0, VF)
    VPUSH(A0, A1)
    NEXT

op_setlocal:
    GETOPD(A0W)
    SHLI(A0, VAL_SHIFT)
    ADD(A0, VF)
    MOVR(A2, VS)
    SUBI(A2, VAL_SIZE)
    VCOPY(A0, A2, A1)
    NEXT

op_getglobal:
    GETOPD(A0W)
    SHLI(A0, VAL_SHIFT)
    GVALS(A1)
    ADD(A0, A1)
    VPUSH(A0, A1)
    NEXT

op_setglobal:
    GETOPD(A0W)
    SHLI(A0, VAL_SHIFT)
    GVALS(A1)
    ADD(A0, A1)
    MOVR(A2, VS)
    SUBI(A2, VAL_SIZE)
    VCOPY(A0, A2, A1)
    NEXT

op_defglobal:
    GETOPD(A0W)
    SHLI(A0, VAL_SHIFT)
    GVALS(A1)
    ADD(A0, A1)
    SUBI(VS, VAL_SIZE)
    VCOPY(A0, VS, A1)
    NEXT

/* Tur denetimi: T_INT = 0 secildigi icin iki etiketi OR'lamak yetiyor. */
/* Tasma denetimi acikken islem 32-bit bayrak ureten bicimde yapilir.
 * Sessizce sarmak, son uc asamada avladigimiz "sessiz yanlis cevap"
 * sinifinin ta kendisi. */
#if OPT_OVFCHK
#  define IADD(d,s)   ADDOV(d,s); BOV(vm_int_ovf)
#  define ISUB(d,s)   SUBOV(d,s); BOV(vm_int_ovf)
#  define IMUL(d,s)   MULOV(d,s,vm_int_ovf)
#  define INEG(d)     NEGOV(d); BOV(vm_int_ovf)
#else
   /* Denetimsiz yol da ayni genislikte kalmali. */
#  define IADD(d,s)   ADDOV(d,s)
#  define ISUB(d,s)   SUBOV(d,s)
#  define IMUL(d,s)   MUL32(d,s)
#  define INEG(d)     NEGOV(d)
#endif

#if OPT_TYPECHK
#  define NEED_INT2 \
    LD32_OFF(A0W, VS, -2*VAL_SIZE); \
    LD32_OFF(A1W, VS, -VAL_SIZE); \
    ORR(A0, A1); \
    BNZ(A0, vm_type_err)
#  define NEED_INT1 \
    LD32_OFF(A0W, VS, -VAL_SIZE); \
    BNZ(A0, vm_type_err)
#  define OBJ_PATH(l) \
    LD32_OFF(A0W, VS, -2*VAL_SIZE); \
    LD32_OFF(A1W, VS, -VAL_SIZE); \
    ORR(A0, A1); \
    BNZ(A0, l)
#else
   /* OLCUM VARYANTI: tavan icin denetimsiz */
#  define NEED_INT2
#  define NEED_INT1
#  define OBJ_PATH(l)
#endif

op_add:
    OBJ_PATH(add_obj)                /* ikisi de T_INT (=0) degil */
    LD_OFF(A0, VS, -(2*VAL_SIZE - VAL_PAY))
    LD_OFF(A1, VS, -(VAL_SIZE - VAL_PAY))
    IADD(A0, A1)
    SUBI(VS, VAL_SIZE)
    ST_OFF(VS, -(VAL_SIZE - VAL_PAY), A0)
    NEXT
add_obj:
    LD32_OFF(A0W, VS, -2*VAL_SIZE)
    CMPI(A0, T_OBJ)
    BNE(vm_type_err)
    LD32_OFF(A0W, VS, -VAL_SIZE)
    CMPI(A0, T_OBJ)
    BNE(vm_type_err)
    SYNC_VS
    LD32_OFF(A0W, VS, -(2*VAL_SIZE - VAL_PAY))
    LD32_OFF(A1W, VS, -(VAL_SIZE - VAL_PAY))
    CALL(str_concat)
    BZ(RV, vm_type_err)
    SUBI(VS, VAL_SIZE)
    ST_OFF(VS, -(VAL_SIZE - VAL_PAY), RV)
    MOVI(A0, T_OBJ)
    ST32_OFF(VS, -VAL_SIZE, A0W)
    NEXT

op_sub:
    NEED_INT2
    LD_OFF(A0, VS, -(2*VAL_SIZE - VAL_PAY))
    LD_OFF(A1, VS, -(VAL_SIZE - VAL_PAY))
    ISUB(A0, A1)
    SUBI(VS, VAL_SIZE)
    ST_OFF(VS, -(VAL_SIZE - VAL_PAY), A0)
    NEXT

op_mul:
    NEED_INT2
    LD_OFF(A0, VS, -(2*VAL_SIZE - VAL_PAY))
    LD_OFF(A1, VS, -(VAL_SIZE - VAL_PAY))
    IMUL(A0, A1)
    SUBI(VS, VAL_SIZE)
    ST_OFF(VS, -(VAL_SIZE - VAL_PAY), A0)
    NEXT

/* ---- bit islemleri ----
 * Tasma denetimi YOK: bit islemlerinin amaci zaten bit desenini
 * oldugu gibi kullanmak. Kaydirma sayisi kelime genisliginden
 * buyukse davranis mimariye gore degisir; SINIRLIYORUZ. */
op_band:
    NEED_INT2
    LD_OFF(A0, VS, -(2*VAL_SIZE - VAL_PAY))
    LD_OFF(A1, VS, -(VAL_SIZE - VAL_PAY))
    ANDR(A0, A1)
    B(bit_store)
op_bor:
    NEED_INT2
    LD_OFF(A0, VS, -(2*VAL_SIZE - VAL_PAY))
    LD_OFF(A1, VS, -(VAL_SIZE - VAL_PAY))
    ORR(A0, A1)
    B(bit_store)
op_bxor:
    NEED_INT2
    LD_OFF(A0, VS, -(2*VAL_SIZE - VAL_PAY))
    LD_OFF(A1, VS, -(VAL_SIZE - VAL_PAY))
    XORR(A0, A1)
    B(bit_store)
op_shl:
    NEED_INT2
    LD_OFF(A1, VS, -(VAL_SIZE - VAL_PAY))
    CMPI(A1, 0)
    BLT(vm_shift_err)
    CMPI(A1, WORD_SIZE * 8)
    BHS(vm_shift_err)
    LD_OFF(A0, VS, -(2*VAL_SIZE - VAL_PAY))
    SHLR(A0, A1)
    B(bit_store)
op_shr:
    NEED_INT2
    LD_OFF(A1, VS, -(VAL_SIZE - VAL_PAY))
    CMPI(A1, 0)
    BLT(vm_shift_err)
    CMPI(A1, WORD_SIZE * 8)
    BHS(vm_shift_err)
    LD_OFF(A0, VS, -(2*VAL_SIZE - VAL_PAY))
    SARR(A0, A1)                    /* ARITMETIK: isaret korunur */
    B(bit_store)
bit_store:
    SUBI(VS, VAL_SIZE)
    ST_OFF(VS, -(VAL_SIZE - VAL_PAY), A0)
    NEXT
op_bnot:
    NEED_INT1
    LD_OFF(A0, VS, -(VAL_SIZE - VAL_PAY))
    NOTR(A0)
    ST_OFF(VS, -(VAL_SIZE - VAL_PAY), A0)
    NEXT

op_div:
    NEED_INT2
    LD_OFF(A1, VS, -(VAL_SIZE - VAL_PAY))
    BZ(A1, vm_div0)
    LD_OFF(A0, VS, -(2*VAL_SIZE - VAL_PAY))
    CALL(idivmod)
    SUBI(VS, VAL_SIZE)
    ST_OFF(VS, -(VAL_SIZE - VAL_PAY), RV)
    NEXT

op_mod:
    NEED_INT2
    LD_OFF(A1, VS, -(VAL_SIZE - VAL_PAY))
    BZ(A1, vm_div0)
    LD_OFF(A0, VS, -(2*VAL_SIZE - VAL_PAY))
    CALL(idivmod)
    LEA_SYM(A0, SYM(g_rem))
    LD(A0, A0)
    SUBI(VS, VAL_SIZE)
    ST_OFF(VS, -(VAL_SIZE - VAL_PAY), A0)
    NEXT

op_neg:
    NEED_INT1
    LD_OFF(A0, VS, -(VAL_SIZE - VAL_PAY))
    INEG(A0)
    ST_OFF(VS, -(VAL_SIZE - VAL_PAY), A0)
    NEXT

op_not:
    LD32_OFF(A0W, VS, -VAL_SIZE)
    LD32_OFF(A1W, VS, -(VAL_SIZE - VAL_PAY))
    CMPI(A0, T_NIL)
    BEQ(vn_true)
    CMPI(A0, T_BOOL)
    BNE(vn_false)
    BZ(A1, vn_true)
vn_false:
    MOVI(A0, T_BOOL); MOVI(A1, 0)
    ST32_OFF(VS, -VAL_SIZE, A0W); ST_OFF(VS, -(VAL_SIZE - VAL_PAY), A1)
    NEXT
vn_true:
    MOVI(A0, T_BOOL); MOVI(A1, 1)
    ST32_OFF(VS, -VAL_SIZE, A0W); ST_OFF(VS, -(VAL_SIZE - VAL_PAY), A1)
    NEXT

/* == ve != her turde calisir: etiket + yuk karsilastirmasi */
op_eq:
    LD32_OFF(A0W, VS, -2*VAL_SIZE)
    LD32_OFF(A1W, VS, -VAL_SIZE)
    CMPR(A0, A1)
    BNE(ve_false)
    CMPI(A0, T_OBJ)
    BEQ(veq_obj)
    LD32_OFF(A0W, VS, -(2*VAL_SIZE - VAL_PAY))
    LD32_OFF(A1W, VS, -(VAL_SIZE - VAL_PAY))
    CMPR(A0, A1)
    BNE(ve_false)
    B(ve_true)
veq_obj:
    LD32_OFF(A0W, VS, -(2*VAL_SIZE - VAL_PAY))
    LD32_OFF(A1W, VS, -(VAL_SIZE - VAL_PAY))
    CALL(obj_eq)
    BNZ(RV, ve_true)
    B(ve_false)
op_ne:
    LD32_OFF(A0W, VS, -2*VAL_SIZE)
    LD32_OFF(A1W, VS, -VAL_SIZE)
    CMPR(A0, A1)
    BNE(ve_true)
    CMPI(A0, T_OBJ)
    BEQ(vne_obj)
    LD32_OFF(A0W, VS, -(2*VAL_SIZE - VAL_PAY))
    LD32_OFF(A1W, VS, -(VAL_SIZE - VAL_PAY))
    CMPR(A0, A1)
    BNE(ve_true)
    B(ve_false)
vne_obj:
    LD32_OFF(A0W, VS, -(2*VAL_SIZE - VAL_PAY))
    LD32_OFF(A1W, VS, -(VAL_SIZE - VAL_PAY))
    CALL(obj_eq)
    BZ(RV, ve_true)
ve_false:
    SUBI(VS, VAL_SIZE)
    MOVI(A0, T_BOOL); MOVI(A1, 0)
    ST32_OFF(VS, -VAL_SIZE, A0W); ST_OFF(VS, -(VAL_SIZE - VAL_PAY), A1)
    NEXT
ve_true:
    SUBI(VS, VAL_SIZE)
    MOVI(A0, T_BOOL); MOVI(A1, 1)
    ST32_OFF(VS, -VAL_SIZE, A0W); ST_OFF(VS, -(VAL_SIZE - VAL_PAY), A1)
    NEXT

op_lt:
    NEED_INT2
    LD_OFF(A0, VS, -(2*VAL_SIZE - VAL_PAY))
    LD_OFF(A1, VS, -(VAL_SIZE - VAL_PAY))
    CMPR(A0, A1)
    BLT(ve_true)
    B(ve_false)
op_le:
    NEED_INT2
    LD_OFF(A0, VS, -(2*VAL_SIZE - VAL_PAY))
    LD_OFF(A1, VS, -(VAL_SIZE - VAL_PAY))
    CMPR(A0, A1)
    BLE(ve_true)
    B(ve_false)
op_gt:
    NEED_INT2
    LD_OFF(A0, VS, -(2*VAL_SIZE - VAL_PAY))
    LD_OFF(A1, VS, -(VAL_SIZE - VAL_PAY))
    CMPR(A0, A1)
    BGT(ve_true)
    B(ve_false)
op_ge:
    NEED_INT2
    LD_OFF(A0, VS, -(2*VAL_SIZE - VAL_PAY))
    LD_OFF(A1, VS, -(VAL_SIZE - VAL_PAY))
    CMPR(A0, A1)
    BGE(ve_true)
    B(ve_false)

/* atlama hedefi = komut indeksi; VP = kod + indeks*4 */
/* Atlama hedefi kod tamponunun DISINA cikamaz.
 * Derleme aninda verify_meta denetliyor ama bu calisma zamani
 * savunmasi: bozuk bytecode ya da bellek bozulmasi VP'yi rastgele
 * bellege gonderemesin. MAX_CODE sabit oldugu icin tek karsilastirma. */
#if OPT_CFI
#  define PC_BOUND(r)  CMPI(r, MAX_CODE); BHS(vm_pc_err);
#else
#  define PC_BOUND(r)
#endif
#define SET_PC(idxR) \
    PC_BOUND(idxR) \
    SHLI(idxR, 2); \
    LEA_SYM(VP, SYM(g_code)); \
    LD(VP, VP); \
    ADD(VP, idxR)

op_jmp:
    GETOPD(A0W)
    SET_PC(A0)
    NEXT

op_jz:
    SUBI(VS, VAL_SIZE)
    LD32_OFF(A0W, VS, VAL_TAG)
    LD_OFF(A1, VS, VAL_PAY)
    CMPI(A0, T_NIL);  BEQ(jz_take)
    CMPI(A0, T_BOOL); BNE(jz_skip)
    BZ(A1, jz_take)
jz_skip:
    NEXT
jz_take:
    GETOPD(A0W)
    SET_PC(A0)
    NEXT

/* kisa devre: degeri yiginda birakir */
op_jzp:
    LD32_OFF(A0W, VS, -VAL_SIZE)
    LD32_OFF(A1W, VS, -(VAL_SIZE - VAL_PAY))
    CMPI(A0, T_NIL);  BEQ(jz_take)
    CMPI(A0, T_BOOL); BNE(jz_skip)
    BZ(A1, jz_take)
    NEXT

op_jnzp:
    LD32_OFF(A0W, VS, -VAL_SIZE)
    LD32_OFF(A1W, VS, -(VAL_SIZE - VAL_PAY))
    CMPI(A0, T_NIL);  BEQ(jnz_skip)
    CMPI(A0, T_BOOL); BNE(jz_take)
    BZ(A1, jnz_skip)
    B(jz_take)
jnz_skip:
    NEXT

op_print:
    MOVR(A0, VS)
    SUBI(A0, VAL_SIZE)
    CALL(print_val)
    MOVI(A0, 10)
    CALL(print_ch)
    SUBI(VS, VAL_SIZE)
    NEXT

/* OP_CALL islenen = arguman sayisi
 * Yigin: [... cagrilan arg0 arg1 ... argN]  <- VS
 */
op_call:
    GETOPD(A0W)
    SPILL(4, A0)                    /* arguman sayisi */
    SHLI(A0, VAL_SHIFT)
    MOVR(A1, VS)
    SUB(A1, A0)                     /* ilk arguman adresi = yeni VF */
    /* Arguman sayisi CALISMA ANINDA sinirlanmali: dogrulayici bunu
     * denetleyemez (yigin derinligi calisma zamani ozelligi).
     * Bozuk bir .bc'de argc = 33536 olunca A1 yiginin ALTINA iniyor
     * ve orayi cagrilan sanip okuyordu -> segfault. */
    LEA_SYM(A2, SYM(g_stack))
    ADDI(A2, VAL_SIZE)
    CMPR(A1, A2)
    BLO(vm_stack_err)
    MOVR(A2, VS)
    CMPR(A1, A2)
    BHI(vm_stack_err)
    SPILL(5, A1)
    LD32_OFF(A0W, A1, -VAL_SIZE)           /* cagrilanin etiketi */
    CMPI(A0, T_NAT)
    BEQ(call_nat)
    CMPI(A0, T_FN)
    BNE(vm_call_err)
    LD_OFF(A0, A1, -(VAL_SIZE - VAL_PAY))           /* fonksiyon indeksi */
    SPILL(7, A1)
    LEA_SYM(A1, SYM(g_nfn))
    LD32(A1W, A1)
    CMPR(A0, A1)
    BHS(vm_call_err)                /* derinlemesine savunma: dogrulayici
                                       kacirsa bile g_fns disina cikilmaz */
    FILL(A1, 7)
    SHLI(A0, 3)
    LEA_SYM(A1, SYM(g_fns))
    ADD(A0, A1)
    SPILL(6, A0)                    /* &g_fns[i] */
    LD32_OFF(A1W, A0, 4)            /* arite */
    FILL(A2, 4)
    CMPR(A2, A1)
    BNE(vm_arity_err)
    /* --- TASMA DENETIMLERI (cerceve itmeden once) ---
     * Denetimsizken 65. cagri g_frames disina yaziyordu ve program
     * cokmeden yanlis sonuc uretiyordu. */
    LEA_SYM(A0, SYM(g_nframe))
    LD32(A0W, A0)
    CMPI(A0, MAX_FRAMES)
    BHS(vm_depth_err)
    MOVR(A0, VS)
    LEA_SYM(A1, SYM(g_stack))
    SUB(A0, A1)
    CMPI(A0, VM_STACK_BYTES - VM_STACK_MARGIN)
    BHS(vm_stack_err)

    /* cerceve kaydet */
    LEA_SYM(A0, SYM(g_nframe))
    LD32(A1W, A0)
    MOVR(A2, A1)
    INC(A2)
    ST32_OFF(A0, 0, A2W)
    SHLI(A1, 3)
    LEA_SYM(A0, SYM(g_frames))
    ADD(A0, A1)
    SPILL(7, A0)
    MOVR(A0, VP)                    /* donus komut indeksi */
    LEA_SYM(A1, SYM(g_code))
    LD(A1, A1)
    SUB(A0, A1)
    SHRI(A0, 2)
    FILL(A1, 7)
    ST32_OFF(A1, 0, A0W)
    MOVR(A0, VF)                    /* eski VF ofseti */
    LEA_SYM(A1, SYM(g_stack))
    SUB(A0, A1)
    FILL(A1, 7)
    ST32_OFF(A1, 4, A0W)
    FILL(VF, 5)                     /* yeni cerceve tabani */
    FILL(A0, 6)
    LD32(A0W, A0)                   /* giris komut indeksi */
    SET_PC(A0)
    NEXT

call_nat:
    SYNC_VS
    LD_OFF(A0, A1, -(VAL_SIZE - VAL_PAY))           /* govde indeksi */
    ANDI(A0, 255)                   /* tablo 256 girdi: disari cikamaz */
    LEA_SYM(A1, SYM(nat_fns))
    LD32_IDX(A2W, A1, A0)
    ADD(A1, A2)
    SPILL(6, A1)
    FILL(A0, 5)                     /* arguman adresi */
    FILL(A1, 4)                     /* arguman sayisi */
    FILL(A2, 6)
    CALLR(A2)
    FILL(A0, 4)
    SHLI(A0, VAL_SHIFT)
    ADDI(A0, VAL_SIZE)              /* argumanlar + cagrilan yuvasi */
    SUB(VS, A0)
    LEA_SYM(A0, SYM(g_natres))
    LD32_OFF(A1W, A0, VAL_TAG)
    ST32_OFF(VS, VAL_TAG, A1W)
    LD_OFF(A1, A0, VAL_PAY)
    ST_OFF(VS, VAL_PAY, A1)
    ADDI(VS, VAL_SIZE)
    NEXT

/* RETL n : yerel n'i dondur   (GETLOCAL n + RET)
 * RETK k : sabit k'yi dondur   (CONST k   + RET)
 * Profil, cagri basina 5 dagitimin darbogaz oldugunu gosterdi;
 * cerceve kurma degil. Bu ikisi donus yolundan birer dagitim siliyor. */
op_retl:
    GETOPD(A0W)
    SHLI(A0, VAL_SHIFT)
    ADD(A0, VF)
    B(ret_common)

op_retk:
    GETOPD(A0W)
    SHLI(A0, VAL_SHIFT)
    GCONSTS(A1)
    ADD(A0, A1)
    B(ret_common)

op_ret:
    MOVR(A0, VS)
    SUBI(A0, VAL_SIZE)
ret_common:
    /* A0 = sonuc slotunun adresi */
    LD32_OFF(A1W, A0, VAL_TAG)
    SPILL(4, A1)                    /* sonuc etiketi */
    LD_OFF(A1, A0, VAL_PAY)
    SPILL(5, A1)                    /* sonuc yuku   */
    LEA_SYM(A0, SYM(g_nframe))
    LD32(A1W, A0)
    BZ(A1, op_halt)                 /* en dis seviyede RET -> dur */
    DEC(A1)
    ST32_OFF(A0, 0, A1W)
    SHLI(A1, 3)                     /* g_frames 8 baytlik AYRI yapi:
                                     * {retpc, vf_ofseti}. Deger yuvasi
                                     * degil - VAL_SHIFT YANLIS olur. */
    LEA_SYM(A0, SYM(g_frames))
    ADD(A0, A1)
    SPILL(6, A0)
    MOVR(VS, VF)
    SUBI(VS, VAL_SIZE)              /* args + cagrilan yuvasi atilir */
    FILL(A0, 4)
    FILL(A1, 5)
    PUSH(A0W, A1W)
    FILL(A0, 6)
    LD32_OFF(A1W, A0, 4)
    LEA_SYM(VF, SYM(g_stack))
    ADD(VF, A1)
    FILL(A0, 6)
    LD32(A0W, A0)
    SET_PC(A0)
    NEXT

op_array:
    GETOPD(A0W)
    SPILL(4, A0)
    /* eleman sayisi da ayni sinifta: VS - n*8 yigin icinde kalmali */
    SHLI(A0, VAL_SHIFT)
    MOVR(A1, VS)
    SUB(A1, A0)
    LEA_SYM(A2, SYM(g_stack))
    CMPR(A1, A2)
    BLO(vm_stack_err)
    FILL(A0, 4)
    SYNC_VS
    CALL(arr_new)
    BZ(RV, vm_type_err)
    SPILL(5, RV)
    MOVR(A0, RV)
    CALL(obj_ptr)
    ADDI(RV, OBJ_DATA)
    SPILL(6, RV)
    FILL(A0, 6)
    FILL(A1, 4)
    SHLI(A1, VAL_SHIFT)
    MOVR(A2, VS)
    SUB(A2, A1)
    MOVR(A1, A2)
    FILL(A2, 4)
    SHLI(A2, VAL_SHIFT)
    CALL(mem_copy)
    FILL(A0, 4)
    SHLI(A0, VAL_SHIFT)
    SUB(VS, A0)
    FILL(A0, 5)
    ST_OFF(VS, VAL_PAY, A0)
    MOVI(A0, T_OBJ)
    ST32_OFF(VS, VAL_TAG, A0W)
    ADDI(VS, VAL_SIZE)
    NEXT

op_index:
    LD32_OFF(A0W, VS, -2*VAL_SIZE)
    CMPI(A0, T_OBJ)
    BNE(vm_type_err)
    LD32_OFF(A0W, VS, -VAL_SIZE)
    BNZ(A0, vm_type_err)            /* indeks tamsayi olmali */
    LD32_OFF(A0W, VS, -(2*VAL_SIZE - VAL_PAY))
    CALL(obj_ptr)
    MOVR(A2, RV)
    LD32_OFF(A0W, A2, OBJ_KIND)
    CMPI(A0, O_BUF)
    BEQ(idx_buf)
    CMPI(A0, O_ARR)
    BNE(vm_type_err)
    LD_OFF(A0, VS, -(VAL_SIZE - VAL_PAY))
    LD32_OFF(A1W, A2, OBJ_LEN)
    CMPR(A0, A1)
    BHS(vm_range_err)               /* isaretsiz: negatif de yakalanir */
    SHLI(A0, VAL_SHIFT)
    ADD(A0, A2)
    ADDI(A0, OBJ_DATA)
    SUBI(VS, VAL_SIZE)
    MOVR(A2, VS)
    SUBI(A2, VAL_SIZE)
    VCOPY(A2, A0, A1)
    NEXT

idx_buf:
    /* tampon[i] -> tamsayi (0..255) */
    LD_OFF(A0, VS, -(VAL_SIZE - VAL_PAY))
    LD32_OFF(A1W, A2, OBJ_LEN)
    CMPR(A0, A1)
    BHS(vm_range_err)
    ADDI(A2, OBJ_DATA)
    LDB_IDX(A1W, A2, A0)
    SUBI(VS, VAL_SIZE)
    MOVI(A0, T_INT)
    ST32_OFF(VS, -VAL_SIZE, A0W)
    ST_OFF(VS, -(VAL_SIZE - VAL_PAY), A1)
    NEXT

op_setidx:
    LD32_OFF(A0W, VS, -3*VAL_SIZE)
    CMPI(A0, T_OBJ)
    BNE(vm_type_err)
    LD32_OFF(A0W, VS, -2*VAL_SIZE)
    BNZ(A0, vm_type_err)
    LD_OFF(A0, VS, -(3*VAL_SIZE - VAL_PAY))
    CALL(obj_ptr)
    MOVR(A2, RV)
    LD32_OFF(A0W, A2, OBJ_KIND)
    CMPI(A0, O_BUF)
    BEQ(sidx_buf)
    CMPI(A0, O_ARR)
    BNE(vm_type_err)
    LD_OFF(A0, VS, -(2*VAL_SIZE - VAL_PAY))
    LD32_OFF(A1W, A2, OBJ_LEN)
    CMPR(A0, A1)
    BHS(vm_range_err)
    SHLI(A0, VAL_SHIFT)
    ADD(A0, A2)
    ADDI(A0, OBJ_DATA)
    LD32_OFF(A1W, VS, -VAL_SIZE)
    ST32_OFF(A0, VAL_TAG, A1W)
    LD32_OFF(A1W, VS, -(VAL_SIZE - VAL_PAY))
    ST_OFF(A0, VAL_PAY, A1)
    LD32_OFF(A0W, VS, -VAL_SIZE)
    LD32_OFF(A1W, VS, -(VAL_SIZE - VAL_PAY))
    SUBI(VS, 2*VAL_SIZE)
    ST32_OFF(VS, -VAL_SIZE, A0W)
    ST_OFF(VS, -(VAL_SIZE - VAL_PAY), A1)
    NEXT

sidx_buf:
    /* tampon[i] = tamsayi; yalniz dusuk bayt yazilir */
    LD32_OFF(A0W, VS, -VAL_SIZE)
    BNZ(A0, vm_type_err)            /* deger tamsayi olmali */
    LD_OFF(A0, VS, -(2*VAL_SIZE - VAL_PAY))
    LD32_OFF(A1W, A2, OBJ_LEN)
    CMPR(A0, A1)
    BHS(vm_range_err)
    ADDI(A2, OBJ_DATA)
    ADD(A2, A0)
    LD32_OFF(A0W, VS, -(VAL_SIZE - VAL_PAY))
    STB(A2, A0B)
    LD32_OFF(A0W, VS, -VAL_SIZE)
    LD32_OFF(A1W, VS, -(VAL_SIZE - VAL_PAY))
    SUBI(VS, 2*VAL_SIZE)
    ST32_OFF(VS, -VAL_SIZE, A0W)
    ST_OFF(VS, -(VAL_SIZE - VAL_PAY), A1)
    NEXT

/* ===== gozetleme deligi birlesik komutlari =====
 * Her biri bir DAGITIM tasarrufu. Bytecode VM'inde en pahali sey
 * dolayli dallanmadir; is yapmayan komutu silmek en ucuz kazanctir.
 */
op_setglobal_p:
    GETOPD(A0W)
    SHLI(A0, VAL_SHIFT)
    GVALS(A1)
    ADD(A0, A1)
    SUBI(VS, VAL_SIZE)
    VCOPY(A0, VS, A1)
    NEXT

op_setlocal_p:
    GETOPD(A0W)
    SHLI(A0, VAL_SHIFT)
    ADD(A0, VF)
    SUBI(VS, VAL_SIZE)
    VCOPY(A0, VS, A1)
    NEXT

op_addk:
    NEED_INT1
    GETOPD(A0W)
    SHLI(A0, VAL_SHIFT)
    GCONSTS(A1)
    ADD(A0, A1)
    LD_OFF(A0, A0, VAL_PAY)
    LD_OFF(A1, VS, -(VAL_SIZE - VAL_PAY))
    IADD(A0, A1)
    ST_OFF(VS, -(VAL_SIZE - VAL_PAY), A0)
    NEXT

op_subk:
    NEED_INT1
    GETOPD(A0W)
    SHLI(A0, VAL_SHIFT)
    GCONSTS(A1)
    ADD(A0, A1)
    LD_OFF(A1, A0, VAL_PAY)
    LD_OFF(A0, VS, -(VAL_SIZE - VAL_PAY))
    ISUB(A0, A1)
    ST_OFF(VS, -(VAL_SIZE - VAL_PAY), A0)
    NEXT

/* --- birlesik karsilastir-ve-atla: iki islenen de tuketilir --- */
#define FJ_INT(br) \
    NEED_INT2; \
    LD_OFF(A0, VS, -(2*VAL_SIZE - VAL_PAY)); \
    LD_OFF(A1, VS, -(VAL_SIZE - VAL_PAY)); \
    SUBI(VS, 2*VAL_SIZE); \
    CMPR(A0, A1); \
    br(fj_take); \
    NEXT

op_jlt: FJ_INT(BLT)
op_jle: FJ_INT(BLE)
op_jgt: FJ_INT(BGT)
op_jge: FJ_INT(BGE)

fj_take:
    GETOPD(A0W)
    SET_PC(A0)
    NEXT

op_jeq:
    LD32_OFF(A0W, VS, -2*VAL_SIZE)
    LD32_OFF(A1W, VS, -VAL_SIZE)
    CMPR(A0, A1)
    BNE(fj_drop)
    CMPI(A0, T_OBJ)
    BEQ(fjq_obj)
    LD32_OFF(A0W, VS, -(2*VAL_SIZE - VAL_PAY))
    LD32_OFF(A1W, VS, -(VAL_SIZE - VAL_PAY))
    CMPR(A0, A1)
    BNE(fj_drop)
    SUBI(VS, 2*VAL_SIZE)
    B(fj_take)
fjq_obj:
    LD32_OFF(A0W, VS, -(2*VAL_SIZE - VAL_PAY))
    LD32_OFF(A1W, VS, -(VAL_SIZE - VAL_PAY))
    CALL(obj_eq)
    BZ(RV, fj_drop)
    SUBI(VS, 2*VAL_SIZE)
    B(fj_take)
fj_drop:
    SUBI(VS, 2*VAL_SIZE)
    NEXT

op_jne:
    LD32_OFF(A0W, VS, -2*VAL_SIZE)
    LD32_OFF(A1W, VS, -VAL_SIZE)
    CMPR(A0, A1)
    BNE(fjn_yes)
    CMPI(A0, T_OBJ)
    BEQ(fjn_obj)
    LD32_OFF(A0W, VS, -(2*VAL_SIZE - VAL_PAY))
    LD32_OFF(A1W, VS, -(VAL_SIZE - VAL_PAY))
    CMPR(A0, A1)
    BNE(fjn_yes)
    B(fj_drop)
fjn_obj:
    LD32_OFF(A0W, VS, -(2*VAL_SIZE - VAL_PAY))
    LD32_OFF(A1W, VS, -(VAL_SIZE - VAL_PAY))
    CALL(obj_eq)
    BNZ(RV, fj_drop)
fjn_yes:
    SUBI(VS, 2*VAL_SIZE)
    B(fj_take)

/* ===== superkomutlar =====
 * Iki 8-bit islenen tek 16-bit alanda. Her biri 1-2 dagitim tasarrufu.
 */
#define GET2(baseSym) \
    GETOPD(A0W); \
    MOVR(A2, A0); \
    ANDI(A0, 255); \
    SHLI(A0, VAL_SHIFT)

op_getglobal2:
    GET2()
    GVALS(A1)
    ADD(A0, A1)
    VPUSH(A0, A1)
    SHRI(A2, 8)
    SHLI(A2, VAL_SHIFT)
    GVALS(A1)
    ADD(A2, A1)
    VPUSH(A2, A1)
    NEXT

op_getlocal2:
    GET2()
    ADD(A0, VF)
    VPUSH(A0, A1)
    SHRI(A2, 8)
    SHLI(A2, VAL_SHIFT)
    ADD(A2, VF)
    VPUSH(A2, A1)
    NEXT

/* DIKKAT: bu superkomut op_add'in yerini aliyor, dolayisiyla op_add'in
 * DIZGI yolunu da tasimak zorunda. Ilk surumu yalniz tamsayi
 * destekliyordu ve "s = s + s" tur hatasi veriyordu. */
op_add_setg:
    OBJ_PATH(asg_obj)
    LD_OFF(A0, VS, -(2*VAL_SIZE - VAL_PAY))
    LD_OFF(A1, VS, -(VAL_SIZE - VAL_PAY))
    IADD(A0, A1)
    SUBI(VS, 2*VAL_SIZE)
    GETOPD(A1W)
    SHLI(A1, VAL_SHIFT)
    GVALS(A2)
    ADD(A1, A2)
    MOVI(A2, T_INT)
    ST32_OFF(A1, VAL_TAG, A2W)
    ST_OFF(A1, VAL_PAY, A0)
    NEXT
asg_obj:
    LD32_OFF(A0W, VS, -2*VAL_SIZE)
    CMPI(A0, T_OBJ)
    BNE(vm_type_err)
    LD32_OFF(A0W, VS, -VAL_SIZE)
    CMPI(A0, T_OBJ)
    BNE(vm_type_err)
    SYNC_VS
    LD32_OFF(A0W, VS, -(2*VAL_SIZE - VAL_PAY))
    LD32_OFF(A1W, VS, -(VAL_SIZE - VAL_PAY))
    CALL(str_concat)
    BZ(RV, vm_type_err)
    SUBI(VS, 2*VAL_SIZE)
    GETOPD(A1W)
    SHLI(A1, VAL_SHIFT)
    GVALS(A2)
    ADD(A1, A2)
    ST_OFF(A1, VAL_PAY, RV)
    MOVI(A2, T_OBJ)
    ST32_OFF(A1, VAL_TAG, A2W)
    NEXT

op_add_setl:
    OBJ_PATH(asl_obj)
    LD_OFF(A0, VS, -(2*VAL_SIZE - VAL_PAY))
    LD_OFF(A1, VS, -(VAL_SIZE - VAL_PAY))
    IADD(A0, A1)
    SUBI(VS, 2*VAL_SIZE)
    GETOPD(A1W)
    SHLI(A1, VAL_SHIFT)
    ADD(A1, VF)
    MOVI(A2, T_INT)
    ST32_OFF(A1, VAL_TAG, A2W)
    ST_OFF(A1, VAL_PAY, A0)
    NEXT
asl_obj:
    LD32_OFF(A0W, VS, -2*VAL_SIZE)
    CMPI(A0, T_OBJ)
    BNE(vm_type_err)
    LD32_OFF(A0W, VS, -VAL_SIZE)
    CMPI(A0, T_OBJ)
    BNE(vm_type_err)
    SYNC_VS
    LD32_OFF(A0W, VS, -(2*VAL_SIZE - VAL_PAY))
    LD32_OFF(A1W, VS, -(VAL_SIZE - VAL_PAY))
    CALL(str_concat)
    BZ(RV, vm_type_err)
    SUBI(VS, 2*VAL_SIZE)
    GETOPD(A1W)
    SHLI(A1, VAL_SHIFT)
    ADD(A1, VF)
    ST_OFF(A1, VAL_PAY, RV)
    MOVI(A2, T_OBJ)
    ST32_OFF(A1, VAL_TAG, A2W)
    NEXT

op_addk_setg:
    NEED_INT1
    GETOPD(A0W)
    MOVR(A2, A0)
    ANDI(A0, 255)
    SHLI(A0, VAL_SHIFT)
    GCONSTS(A1)
    ADD(A0, A1)
    LD_OFF(A0, A0, VAL_PAY)
    LD_OFF(A1, VS, -(VAL_SIZE - VAL_PAY))
    IADD(A0, A1)
    SUBI(VS, VAL_SIZE)
    SHRI(A2, 8)
    SHLI(A2, VAL_SHIFT)
    GVALS(A1)
    ADD(A2, A1)
    MOVI(A1, T_INT)
    ST32_OFF(A2, VAL_TAG, A1W)
    ST_OFF(A2, VAL_PAY, A0)
    NEXT

/* n += k  : yigina hic dokunmadan. "i = i + 1" tek komut. */
op_incglobal:
    GETOPD(A0W)
    MOVR(A2, A0)
    ANDI(A0, 255)
    SHLI(A0, VAL_SHIFT)
    GVALS(A1)
    ADD(A0, A1)
#if OPT_TYPECHK
    LD32_OFF(A1W, A0, VAL_TAG)
    BNZ(A1, vm_type_err)
#endif
    SHRI(A2, 8)
    SHLI(A2, VAL_SHIFT)
    GCONSTS(A1)
    ADD(A2, A1)
    LD_OFF(A2, A2, VAL_PAY)
    LD_OFF(A1, A0, VAL_PAY)
    IADD(A1, A2)
    ST_OFF(A0, VAL_PAY, A1)
    NEXT

/* dogruysa atla + tuket: dongu rotasyonunun geri kenari */
op_jnz:
    SUBI(VS, VAL_SIZE)
    LD32_OFF(A0W, VS, VAL_TAG)
    LD_OFF(A1, VS, VAL_PAY)
    CMPI(A0, T_NIL);  BEQ(jnz2_skip)
    CMPI(A0, T_BOOL); BNE(jnz_take)
    BZ(A1, jnz2_skip)
jnz_take:
    GETOPD(A0W)
    SET_PC(A0)
    NEXT
jnz2_skip:
    NEXT

op_getg_const:
    GET2()
    GVALS(A1)
    ADD(A0, A1)
    VPUSH(A0, A1)
    SHRI(A2, 8)
    SHLI(A2, VAL_SHIFT)
    GCONSTS(A1)
    ADD(A2, A1)
    VPUSH(A2, A1)
    NEXT

op_getl_const:
    GET2()
    ADD(A0, VF)
    VPUSH(A0, A1)
    SHRI(A2, 8)
    SHLI(A2, VAL_SHIFT)
    GCONSTS(A1)
    ADD(A2, A1)
    VPUSH(A2, A1)
    NEXT

/* ACCG(a,b): gvals[a] += gvals[b], yigin trafigi SIFIR.
 * Dizgi yolu da tasinmali (Asama 15 dersi: superkomut, yerini aldigi
 * komutun BUTUN dallarini tasimak zorunda). */
op_accg:
    GETOPD(A0W)
    MOVR(A2, A0)
    ANDI(A0, 255)
    SHLI(A0, VAL_SHIFT)
    GVALS(A1)
    ADD(A0, A1)                     /* &gvals[a] */
    SHRI(A2, 8)
    SHLI(A2, VAL_SHIFT)
    GVALS(A1)
    ADD(A2, A1)                     /* &gvals[b] */
#if OPT_TYPECHK
    LD32_OFF(A1W, A0, VAL_TAG)
    BNZ(A1, accg_obj)
    LD32_OFF(A1W, A2, VAL_TAG)
    BNZ(A1, accg_obj)
#endif
    LD_OFF(A1, A2, VAL_PAY)
    SPILL(4, A1)
    LD_OFF(A1, A0, VAL_PAY)
    SPILL(5, A0)
    FILL(A2, 4)
    IADD(A1, A2)
    FILL(A0, 5)
    ST_OFF(A0, VAL_PAY, A1)
    NEXT
#if OPT_TYPECHK
accg_obj:
    /* en az biri nesne: dizgi birlestirme yoluna dus.
     * DIKKAT: SYNC_VS A2'yi ezer; ikinci islenenin adresi A2'de
     * oldugu icin yuk ONCE okunmali. */
    LD32_OFF(A1W, A0, VAL_TAG)
    CMPI(A1, T_OBJ)
    BNE(vm_type_err)
    LD32_OFF(A1W, A2, VAL_TAG)
    CMPI(A1, T_OBJ)
    BNE(vm_type_err)
    SPILL(5, A0)                    /* hedef adresi */
    LD_OFF(A1, A2, VAL_PAY)
    SPILL(4, A1)                    /* b tutamagi */
    LD_OFF(A0, A0, VAL_PAY)      /* a tutamagi */
    SYNC_VS
    FILL(A1, 4)
    CALL(str_concat)
    BZ(RV, vm_type_err)
    MOVR(A1, RV)                    /* i386'da RV == A0: FILL(A0,..) sonucu
                                       ezerdi. Once guvenli registera al. */
    FILL(A0, 5)
    ST_OFF(A0, VAL_PAY, A1)
    MOVI(A1, T_OBJ)
    ST32_OFF(A0, VAL_TAG, A1W)
    NEXT
#endif

/* --- calisma hatalari: bildir ve dur --- */
vm_type_err:
    LEA_SYM(A0, rt_type); MOVI(A1, rt_type_len); B(vm_fail)
vm_shift_err:
    LEA_SYM(A0, rt_shift); MOVI(A1, rt_shift_len); B(vm_fail)
vm_call_err:
    LEA_SYM(A0, rt_call); MOVI(A1, rt_call_len); B(vm_fail)
vm_arity_err:
    LEA_SYM(A0, rt_arity); MOVI(A1, rt_arity_len); B(vm_fail)
op_bad:
    LEA_SYM(A0, rt_badop); MOVI(A1, rt_badop_len); B(vm_fail)
vm_pc_err:
    LEA_SYM(A0, rt_pc); MOVI(A1, rt_pc_len); B(vm_fail)
vm_int_ovf:
    LEA_SYM(A0, rt_iovf); MOVI(A1, rt_iovf_len); B(vm_fail)
vm_depth_err:
    LEA_SYM(A0, rt_depth); MOVI(A1, rt_depth_len); B(vm_fail)
vm_stack_err:
    LEA_SYM(A0, rt_ovf); MOVI(A1, rt_ovf_len); B(vm_fail)
vm_range_err:
    LEA_SYM(A0, rt_range); MOVI(A1, rt_range_len); B(vm_fail)
vm_div0:
    LEA_SYM(A0, rt_div0); MOVI(A1, rt_div0_len)
vm_fail:
    CALL(print_str)
    LEA_SYM(A0, SYM(g_rterr))
    LD32(A1W, A0)
    INC(A1)
    ST32_OFF(A0, 0, A1W)
    B(op_halt)
ENDFUNC(run)
