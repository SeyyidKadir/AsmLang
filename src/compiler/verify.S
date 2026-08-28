/* verify.S - bytecode metadata tutarlilik denetimi
 *
 * Neden var: gozetleme deligi kodu sikistirdiginda atlama islenenleri
 * yeniden eslenmisti ama FONKSIYON GIRIS NOKTALARI eski indekste
 * kalmisti. CALL cop adrese sicradi, program coktu. Kucuk testlerde
 * gorunmedi cunku orada birlesme hep govdeden SONRA oluyordu.
 *
 * Bu pass, kod indeksi ya da tablo indeksi tutan HER alani optimizer
 * sonrasi dogrular. Yeni metadata (kapanis girisi, istisna isleyicisi,
 * switch tablosu) eklendiginde buraya bir satir eklenmeli.
 *
 * Sabit 4-baytlik komut kodlamasi sayesinde "instruction boundary"
 * kontrolu GEREKSIZ: indeksler zaten komut numarasi, bayt ofseti degil.
 * Bu hata sinifi kodlama secimiyle bastan imkansiz kilindi.
 */
#include "../abi.inc"
#include "../tables/opcodes.inc"
#include "../tables/opkind.inc"
#define NAT_COUNT_ONLY 1
#include "../tables/natives.inc"

    .bss
    .p2align 2
    .globl SYM(g_verr)
SYM(g_verr):  .space 4

    SECT_RODATA
vf_pre:   .ascii "dogrulama HATASI: "
    .equ  vf_pre_len, . - vf_pre
vf_at:    .ascii " @ komut "
    .equ  vf_at_len, . - vf_at
vf_atf:   .ascii " @ fonksiyon "
    .equ  vf_atf_len, . - vf_atf
e_op:     .ascii "gecersiz islem kodu"
    .equ  e_op_len, . - e_op
e_code:   .ascii "atlama hedefi kod disinda"
    .equ  e_code_len, . - e_code
e_const:  .ascii "sabit indeksi havuz disinda"
    .equ  e_const_len, . - e_const
e_glob:   .ascii "kuresel yuva tanimsiz"
    .equ  e_glob_len, . - e_glob
e_loc:    .ascii "yerel yuva sinir disinda"
    .equ  e_loc_len, . - e_loc
e_entry:  .ascii "fonksiyon girisi kod disinda"
    .equ  e_entry_len, . - e_entry
e_ctag:   .ascii "gecersiz deger etiketi"
    .equ  e_ctag_len, . - e_ctag
e_cfn:    .ascii "sabit: fonksiyon indeksi sinir disinda"
    .equ  e_cfn_len, . - e_cfn
e_cnat:   .ascii "sabit: govde indeksi sinir disinda"
    .equ  e_cnat_len, . - e_cnat
e_cobj:   .ascii "sabit: nesne tutamagi sinir disinda"
    .equ  e_cobj_len, . - e_cobj

    SECT_TEXT

/* vf_err(A0 = ileti, A1 = uzunluk, A2 = indeks) */
FUNC(vf_err)
    ENTER(3)
    SPILL(0, A0)
    SPILL(1, A1)
    SPILL(2, A2)
    LEA_SYM(A0, SYM(g_verr))
    LD32(A1W, A0)
    INC(A1)
    ST32_OFF(A0, 0, A1W)
    LEA_SYM(A0, vf_pre)
    MOVI(A1, vf_pre_len)
    CALL(print_str)
    FILL(A0, 0)
    FILL(A1, 1)
    CALL(print_str)
    LEA_SYM(A0, vf_at)
    MOVI(A1, vf_at_len)
    CALL(print_str)
    FILL(A0, 2)
    CALL(print_u32)
    MOVI(A0, 10)
    CALL(print_ch)
    LEAVE_
    RET
ENDFUNC(vf_err)

/* vf_errf(A0 = ileti, A1 = uzunluk, A2 = fonksiyon no)
 * Fonksiyon tablosu hatalari komut indeksi degil fonksiyon numarasi
 * gosterir; ayni iletiyi kullanmak yaniltici olurdu. */
FUNC(vf_errf)
    ENTER(3)
    SPILL(0, A0)
    SPILL(1, A1)
    SPILL(2, A2)
    LEA_SYM(A0, SYM(g_verr))
    LD32(A1W, A0)
    INC(A1)
    ST32_OFF(A0, 0, A1W)
    LEA_SYM(A0, vf_pre)
    MOVI(A1, vf_pre_len)
    CALL(print_str)
    FILL(A0, 0)
    FILL(A1, 1)
    CALL(print_str)
    LEA_SYM(A0, vf_atf)
    MOVI(A1, vf_atf_len)
    CALL(print_str)
    FILL(A0, 2)
    CALL(print_u32)
    MOVI(A0, 10)
    CALL(print_ch)
    LEAVE_
    RET
ENDFUNC(vf_errf)

/* vf_chk(A0 = deger, A1 = sinir, A2 = indeks, A3/slot = ileti)
 * deger >= sinir ise hata sayar. Ileti g_vfmsg/g_vfmsglen'den okunur
 * (dordunculu arguman i386'da registera sigmadigi icin).
 */
    .bss
    .p2align 3
SYM(g_vfmsg):    .space 8
SYM(g_vfmsglen): .space 4
    SECT_TEXT

FUNC(vf_chk)
    ENTER(3)
    SPILL(0, A0)
    SPILL(1, A1)
    SPILL(2, A2)
    CMPR(A0, A1)
    BLO(vc_ok)
    LEA_SYM(A0, SYM(g_vfmsg))
    LD(A0, A0)
    LEA_SYM(A1, SYM(g_vfmsglen))
    LD32(A1W, A1)
    FILL(A2, 2)
    CALL(vf_err)
vc_ok:
    LEAVE_
    RET
ENDFUNC(vf_chk)

/* vf_set(A0 = ileti, A1 = uzunluk) - siradaki vf_chk icin ileti */
FUNC(vf_set)
    ENTER(1)
    LEA_SYM(A2, SYM(g_vfmsg))
    ST(A2, A0)
    LEA_SYM(A2, SYM(g_vfmsglen))
    ST32_OFF(A2, 0, A1W)
    LEAVE_
    RET
ENDFUNC(vf_set)

/* =====================================================================
 * verify_meta() -> RV = hata sayisi
 * Slotlar: 0=i 1=n 2=ins 3=op 4=opd 5=tur 6=gecici
 * ===================================================================== */
FUNC(verify_meta)
    ENTER(7)
    MOVI(A0, 0)
    LEA_SYM(A1, SYM(g_verr))
    ST32_OFF(A1, 0, A0W)
    SPILL(0, A0)
    LEA_SYM(A0, SYM(g_ncode))
    LD32(A0W, A0)
    SPILL(1, A0)

vm_loop:
    FILL(A0, 0)
    FILL(A1, 1)
    CMPR(A0, A1)
    BHS(vm_fns)
    CALL(code_at)
    SPILL(2, RV)
    MOVR(A0, RV)
    ANDI(A0, 255)
    SPILL(3, A0)
    FILL(A0, 2)
    SHRI(A0, 16)
    SPILL(4, A0)

    /* islem kodu gecerli mi */
    FILL(A0, 3)
    CMPI(A0, OP_COUNT)
    BLO(vm_kind)
    LEA_SYM(A0, e_op)
    MOVI(A1, e_op_len)
    FILL(A2, 0)
    CALL(vf_err)
    B(vm_next)

vm_kind:
    FILL(A0, 3)
    LEA_SYM(A1, SYM(op_opkind))
    LDB_IDX(A0W, A1, A0)
    SPILL(5, A0)
    CMPI(A0, OPK_CODE);   BEQ(vm_code)
    CMPI(A0, OPK_CONST);  BEQ(vm_const)
    CMPI(A0, OPK_GLOBAL); BEQ(vm_glob)
    CMPI(A0, OPK_LOCAL);  BEQ(vm_loc)
    CMPI(A0, OPK_GG);     BEQ(vm_gg)
    CMPI(A0, OPK_LL);     BEQ(vm_ll)
    CMPI(A0, OPK_GC);     BEQ(vm_gc)
    CMPI(A0, OPK_LC);     BEQ(vm_lc)
    CMPI(A0, OPK_CG);     BEQ(vm_cg)
    B(vm_next)                      /* NONE / COUNT: denetim yok */

vm_code:
    LEA_SYM(A0, e_code); MOVI(A1, e_code_len); CALL(vf_set)
    FILL(A0, 4); FILL(A1, 1); FILL(A2, 0); CALL(vf_chk)
    B(vm_next)

vm_const:
    LEA_SYM(A0, e_const); MOVI(A1, e_const_len); CALL(vf_set)
    FILL(A0, 4)
    LEA_SYM(A1, SYM(g_nconst)); LD32(A1W, A1)
    FILL(A2, 0); CALL(vf_chk)
    B(vm_next)

vm_glob:
    LEA_SYM(A0, e_glob); MOVI(A1, e_glob_len); CALL(vf_set)
    FILL(A0, 4)
    LEA_SYM(A1, SYM(g_nglob)); LD32(A1W, A1)
    FILL(A2, 0); CALL(vf_chk)
    B(vm_next)

vm_loc:
    LEA_SYM(A0, e_loc); MOVI(A1, e_loc_len); CALL(vf_set)
    FILL(A0, 4); MOVI(A1, MAX_LOCALS); FILL(A2, 0); CALL(vf_chk)
    B(vm_next)

/* --- paketli ikili islenenler: dusuk bayt | yuksek bayt --- */
vm_gg:
    LEA_SYM(A0, e_glob); MOVI(A1, e_glob_len); CALL(vf_set)
    FILL(A0, 4); ANDI(A0, 255)
    LEA_SYM(A1, SYM(g_nglob)); LD32(A1W, A1)
    FILL(A2, 0); CALL(vf_chk)
    FILL(A0, 4); SHRI(A0, 8)
    LEA_SYM(A1, SYM(g_nglob)); LD32(A1W, A1)
    FILL(A2, 0); CALL(vf_chk)
    B(vm_next)

vm_ll:
    LEA_SYM(A0, e_loc); MOVI(A1, e_loc_len); CALL(vf_set)
    FILL(A0, 4); ANDI(A0, 255); MOVI(A1, MAX_LOCALS); FILL(A2, 0); CALL(vf_chk)
    FILL(A0, 4); SHRI(A0, 8);   MOVI(A1, MAX_LOCALS); FILL(A2, 0); CALL(vf_chk)
    B(vm_next)

vm_gc:
    LEA_SYM(A0, e_glob); MOVI(A1, e_glob_len); CALL(vf_set)
    FILL(A0, 4); ANDI(A0, 255)
    LEA_SYM(A1, SYM(g_nglob)); LD32(A1W, A1)
    FILL(A2, 0); CALL(vf_chk)
    LEA_SYM(A0, e_const); MOVI(A1, e_const_len); CALL(vf_set)
    FILL(A0, 4); SHRI(A0, 8)
    LEA_SYM(A1, SYM(g_nconst)); LD32(A1W, A1)
    FILL(A2, 0); CALL(vf_chk)
    B(vm_next)

vm_lc:
    LEA_SYM(A0, e_loc); MOVI(A1, e_loc_len); CALL(vf_set)
    FILL(A0, 4); ANDI(A0, 255); MOVI(A1, MAX_LOCALS); FILL(A2, 0); CALL(vf_chk)
    LEA_SYM(A0, e_const); MOVI(A1, e_const_len); CALL(vf_set)
    FILL(A0, 4); SHRI(A0, 8)
    LEA_SYM(A1, SYM(g_nconst)); LD32(A1W, A1)
    FILL(A2, 0); CALL(vf_chk)
    B(vm_next)

vm_cg:
    LEA_SYM(A0, e_const); MOVI(A1, e_const_len); CALL(vf_set)
    FILL(A0, 4); ANDI(A0, 255)
    LEA_SYM(A1, SYM(g_nconst)); LD32(A1W, A1)
    FILL(A2, 0); CALL(vf_chk)
    LEA_SYM(A0, e_glob); MOVI(A1, e_glob_len); CALL(vf_set)
    FILL(A0, 4); SHRI(A0, 8)
    LEA_SYM(A1, SYM(g_nglob)); LD32(A1W, A1)
    FILL(A2, 0); CALL(vf_chk)
    B(vm_next)

vm_next:
    FILL(A0, 0)
    INC(A0)
    SPILL(0, A0)
    B(vm_loop)

/* --- fonksiyon giris noktalari: cokusu yasatan alan --- */
vm_fns:
    MOVI(A0, 0)
    SPILL(0, A0)
vm_f:
    LEA_SYM(A0, SYM(g_nfn))
    LD32(A0W, A0)
    FILL(A1, 0)
    CMPR(A1, A0)
    BHS(vm_fns_done)
    FILL(A0, 0)
    SHLI(A0, 3)
    LEA_SYM(A1, SYM(g_fns))
    ADD(A0, A1)
    LD32(A0W, A0)                   /* giris komut indeksi */
    SPILL(4, A0)
    FILL(A1, 1)
    CMPR(A0, A1)
    BLO(vm_fnext)
    LEA_SYM(A0, e_entry)
    MOVI(A1, e_entry_len)
    FILL(A2, 0)
    CALL(vf_errf)
vm_fnext:
    FILL(A0, 0)
    INC(A0)
    SPILL(0, A0)
    B(vm_f)
vm_fns_done:
    B(vm_consts)

/* Buraya kapanis girisi, istisna isleyicisi, switch tablosu geldiginde
 * ayni sekilde dolasilmali. break/devam hedefleri zaten atlama
 * isleneni olarak yukarida denetleniyor. */

/* --- sabit havuzu ---
 * Bozuk bir .bc'de T_FN sabitinin yuku FONKSIYON INDEKSI olarak
 * kullaniliyor ve denetimsizken g_fns disindan okuma yapiyordu
 * (fuzzer 120 bozuk dosyada 6 cokme buldu, hepsi bu sinifta).
 * Yurutucu icin bu bir GUVENLIK siniri, hata ayiklama araci degil. */
vm_consts:
    MOVI(A0, 0)
    SPILL(0, A0)
vm_c:
    LEA_SYM(A0, SYM(g_nconst))
    LD32(A0W, A0)
    FILL(A1, 0)
    CMPR(A1, A0)
    BHS(vm_done)
    FILL(A0, 0)
    SHLI(A0, VAL_SHIFT)
    LEA_SYM(A1, SYM(g_consts))
    LD(A1, A1)
    ADD(A0, A1)
    SPILL(5, A0)
    LD32(A1W, A0)                   /* etiket */
    SPILL(4, A1)
    CMPI(A1, T_NAT)
    BLS(vm_ctag_ok)
    LEA_SYM(A0, e_ctag); MOVI(A1, e_ctag_len); FILL(A2, 0); CALL(vf_err)
    B(vm_cnext)
vm_ctag_ok:
    FILL(A0, 5)
    LD_OFF(A0, A0, VAL_PAY)
    SPILL(5, A0)
    FILL(A0, 4)
    CMPI(A0, T_FN)
    BEQ(vm_cfn)
    CMPI(A0, T_NAT)
    BEQ(vm_cnat)
    CMPI(A0, T_OBJ)
    BEQ(vm_cobj)
    B(vm_cnext)
vm_cfn:
    LEA_SYM(A0, e_cfn); MOVI(A1, e_cfn_len); CALL(vf_set)
    FILL(A0, 5)
    LEA_SYM(A1, SYM(g_nfn)); LD32(A1W, A1)
    FILL(A2, 0); CALL(vf_chk)
    B(vm_cnext)
vm_cnat:
    LEA_SYM(A0, e_cnat); MOVI(A1, e_cnat_len); CALL(vf_set)
    FILL(A0, 5); MOVI(A1, NAT_COUNT); FILL(A2, 0); CALL(vf_chk)
    B(vm_cnext)
vm_cobj:
    LEA_SYM(A0, e_cobj); MOVI(A1, e_cobj_len); CALL(vf_set)
    FILL(A0, 5)
    LEA_SYM(A1, SYM(g_nobj)); LD32(A1W, A1)
    FILL(A2, 0); CALL(vf_chk)
vm_cnext:
    FILL(A0, 0)
    INC(A0)
    SPILL(0, A0)
    B(vm_c)

vm_done:
    LEA_SYM(A0, SYM(g_verr))
    LD32(RVW, A0)
    LEAVE_
    RET
ENDFUNC(verify_meta)
