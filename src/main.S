/* main.S - Asama 3: sozcuk -> token -> AST -> bytecode -> yurutme */
#include "abi.inc"
#include "tables/tokens.inc"
#include "tables/opcodes.inc"

SECT_RODATA
    .p2align 2
banner:  .ascii "== asmlang ==\n"
    .equ banner_len, . - banner
pl_path: .ascii "/tmp/asmlang.bc"
    .byte 0
pl_ban:  .ascii "== asmlang yurutucu (.bc) ==\n"
    .equ pl_ban_len, . - pl_ban
pl_bad:  .ascii "bc yuklenemedi\n"
    .equ pl_bad_len, . - pl_bad
#if defined(BC_EMBED) && BC_EMBED
/* Bytecode ikiliye GOMULU: dosya sistemi gerekmiyor.
 * ISO/cekirdek/tek-dosya dagitim icin dogru kip. */
    .p2align 3
bc_blob:
    .incbin "embed.bc"
    .equ bc_blob_len, . - bc_blob
#endif
h_out:   .ascii "\n--- cikti ---\n"
    .equ h_out_len, . - h_out
h_sum:   .ascii "\n--- ozet ---\n"
    .equ h_sum_len, . - h_sum
m_oom:   .ascii "bellek ayrilamadi\n"
    .equ m_oom_len, . - m_oom
m_tok:   .ascii "token   : "
    .equ m_tok_len, . - m_tok
m_nd:    .ascii "dugum   : "
    .equ m_nd_len, . - m_nd
m_code:  .ascii "komut   : "
    .equ m_code_len, . - m_code
m_err:   .ascii "hata    : "
    .equ m_err_len, . - m_err
m_gc:    .ascii "gc turu : "
    .equ m_gc_len, . - m_gc
m_obj:   .ascii "nesne   : "
    .equ m_obj_len, . - m_obj
m_dis:   .ascii "dagitim : "
    .equ m_dis_len, . - m_dis
m_vf:    .ascii "dogrula : "
    .equ m_vf_len, . - m_vf
m_cst:   .ascii "sabit   : "
    .equ m_cst_len, . - m_cst
m_int:   .ascii "  dedup : "
    .equ m_int_len, . - m_int
m_sup:   .ascii "superk  : "
    .equ m_sup_len, . - m_sup
m_gc2:   .ascii "  getgc : "
    .equ m_gc2_len, . - m_gc2
m_ak:    .ascii "  addk  : "
    .equ m_ak_len, . - m_ak
m_halt:  .ascii "bytecode dogrulamasi basarisiz - yurutme iptal\n"
    .equ m_halt_len, . - m_halt
m_cerr:  .ascii "derleme hatasi var - yurutme iptal\n"
    .equ m_cerr_len, . - m_cerr
m_gd:    .ascii "guard   : "
    .equ m_gd_len, . - m_gd
m_jit:   .ascii "jit     : "
    .equ m_jit_len, . - m_jit
tj_msg:  .ascii "jit testi: uretilen kod dondurdu -> "
    .equ tj_msg_len, . - tj_msg
tj_bad:  .ascii "jit: calistirilabilir bellek alinamadi (W^X?)\n"
    .equ tj_bad_len, . - tj_bad
jd_path: .ascii "/tmp/jitdump.bin"
    .byte 0
tc_line: .ascii "prog.exe  bir \"iki uc\" dort  \"\" bes"
    .byte 0
tc_pre:  .ascii "cmdline argc="
    .equ tc_pre_len, . - tc_pre

    .p2align 2
src_text:
/* Kaynak program disaridan gelir.
 * Varsayilan: src/demo.inc (gosterim programi)
 * Benchmark:  -DBENCH_SRC=1 ile src/bench_embed.inc
 * (Makroya dosya adi gecirmek kabuk tirnaklarinda kiriliyordu;
 *  sabit dosya + boolean anahtar hem basit hem saglam.) */
#if defined(BENCH_SRC) && BENCH_SRC
#  include "bench_embed.inc"
#else
#  include "demo.inc"
#endif
    .equ   src_len, . - src_text

SECT_TEXT

FUNC(lang_main)
    ENTER(8)

    CALL(guard_init)
#if defined(TEST_JITASM) && TEST_JITASM
    CALL(jitasm_selftest)
    CALL(jitlbl_selftest)
#endif
#if defined(TEST_CMDLINE) && TEST_CMDLINE
    /* Komut satiri ayristiricisinin BIRIM TESTI: Windows'ta
     * calistiramadigim mantigi burada dogruluyorum. */
    LEA_SYM(A0, tc_line)
    CALL(win_args)
    LEA_SYM(A0, tc_pre); MOVI(A1, tc_pre_len); CALL(print_str)
    LEA_SYM(A0, SYM(g_argc)); LD32(A0W, A0); CALL(print_u32)
    MOVI(A0, 10); CALL(print_ch)
    MOVI(A0, 0)
    SPILL(7, A0)
tc_loop:
    LEA_SYM(A0, SYM(g_argc)); LD32(A0W, A0)
    FILL(A1, 7)
    CMPR(A1, A0)
    BHS(tc_end)
    MOVI(A0, 91); CALL(print_ch)
    FILL(A0, 7); CALL(arg_ptr); MOVR(A0, RV); CALL(print_cstr)
    MOVI(A0, 93); CALL(print_ch)
    MOVI(A0, 10); CALL(print_ch)
    FILL(A0, 7); INC(A0); SPILL(7, A0)
    B(tc_loop)
tc_end:
#endif
#if defined(TEST_JIT) && TEST_JIT
    /* JIT MEKANIZMA TESTI: calistirilabilir bellek ayir, elle makine
     * kodu yaz, cagir. Uretilen fonksiyon 1234 dondurur.
     *   x86_64/i386: b8 d2 04 00 00   mov eax, 1234
     *                c3               ret
     * Bu, "sablon JIT yazilabilir mi" sorusunun on kosulunu kanitlar. */
    CALL(jit_init)
    BZ(RV, tj_no)
    MOVI(A0, 0xb8); CALL(emit8)
    MOVI(A0, 1234); CALL(emit32)
    MOVI(A0, 0xc3); CALL(emit8)
    CALL(jit_entry)
    MOVR(A0, RV)
    CALL(jit_call)
    MOVR(A0, RV)
    SPILL(7, A0)
    LEA_SYM(A0, tj_msg); MOVI(A1, tj_msg_len); CALL(print_str)
    FILL(A0, 7); CALL(print_u32)
    MOVI(A0, 10); CALL(print_ch)
    B(tj_done)
tj_no:
    LEA_SYM(A0, tj_bad); MOVI(A1, tj_bad_len); CALL(print_str)
tj_done:
#endif
#if defined(TEST_HIJACK) && TEST_HIJACK
    /* Derleme sonrasi bytecode'u kasitli boz: gecersiz opcode ve
     * kod disi atlama hedefi. Saldirgan bunlari tasma ile elde eder. */
#endif
#if defined(TEST_GUARD) && TEST_GUARD
    LEA_SYM(A0, SYM(g_strbuf))
    ADDI(A0, 4096)
    MOVI(A1, 0)
    ST32_OFF(A0, 0, A1W)
#if TEST_HIJACK == 3
    /* sabit 0'i "tutamak 999999 olan nesne" yap: gecersiz tutamak */
    FILL(A0, 3)
    MOVI(A1, T_OBJ)
    ST32_OFF(A0, VAL_TAG, A1W)
    MOVI(A1, 999999)
    ST_OFF(A0, VAL_PAY, A1)
#endif
#endif

#if defined(MODE_PLAYER) && MODE_PLAYER
    LEA_SYM(A0, pl_ban)
    MOVI(A1, pl_ban_len)
    CALL(print_str)
#else
    MOVI(A0, FD_STDOUT)
    LEA_SYM(A1, banner)
    MOVI(A2, banner_len)
    CALL(os_write)
#endif

    MOVI(A0, 65536);  CALL(os_alloc); SPILL(0, RV); BZ(RV, lm_oom)  /* token */
    MOVI(A0, 262144); CALL(os_alloc); SPILL(1, RV); BZ(RV, lm_oom)  /* dugum */
    MOVI(A0, 65536);  CALL(os_alloc); SPILL(2, RV); BZ(RV, lm_oom)  /* kod   */
    MOVI(A0, MAX_CONSTS * VAL_SIZE); CALL(os_alloc); SPILL(3, RV); BZ(RV, lm_oom)  /* sabit */
    /* Nesne yigini. FILE_BUF_SIZE (64 KB) tek parca dizgi olarak
     * yigina sigmali; 64 KB yigin bunu karsilamiyordu. */
    MOVI(A0, 1048576); CALL(os_alloc); BZ(RV, lm_oom)
    MOVR(A0, RV)
    MOVI(A1, 1048576)
    CALL(heap_init)

#if defined(MODE_PLAYER) && MODE_PLAYER
    /* --- YURUTUCU KIPI: sozcuk/ayristirma/derleme YOK ---
     * .bc GUVENILMEYEN girdidir; bc_load yalnizca bicimsel denetim
     * yapar, anlamsal denetimi verify_meta yapar ve calistirmadan
     * ONCE kosulur. */
    FILL(A0, 2)
    LEA_SYM(A1, SYM(g_code)); ST(A1, A0)
    FILL(A0, 3)
    LEA_SYM(A1, SYM(g_consts)); ST(A1, A0)
#if defined(BC_EMBED) && BC_EMBED
    LEA_SYM(A0, bc_blob)
    MOVI(A1, bc_blob_len)
    CALL(bc_parse)
#else
    /* .bc yolu: argv[1] varsa oradan, yoksa varsayilan.
     * Sabit yol bir eksiklikti; argv geldi, duzeldi. */
    /* Sirayla: argv[1] verildiyse o dosya; yoksa KENDI SONUNA
     * eklenmis bytecode; o da yoksa varsayilan yol. */
    MOVI(A0, 1)
    CALL(arg_ptr)
    BNZ(RV, pl_havepath)
    CALL(bc_load_self)
    BNZ(RV, pl_loaded)
    LEA_SYM(RV, pl_path)
pl_havepath:
    MOVR(A0, RV)
    CALL(bc_load)
pl_loaded:
#endif
    BNZ(RV, pl_ok)
    LEA_SYM(A0, pl_bad)
    MOVI(A1, pl_bad_len)
    CALL(print_str)
    MOVI(RV, 1)
    LEAVE_
    RET
pl_ok:
    CALL(verify_meta)
    MOVI(A0, 0)
    SPILL(4, A0)
    SPILL(5, A0)
#else
    LEA_SYM(A0, src_text)
    MOVI(A1, src_len)
    FILL(A2, 0)
    CALL(lex_all)
    SPILL(4, RV)

    MOVI(A0, 1)                     /* kontrol noktasi 1: sozcuk sonrasi */
    CALL(guard_check)
    FILL(A0, 0)
    FILL(A1, 1)
    CALL(parse_program)
    SPILL(5, RV)

    MOVI(A0, 2)                     /* kontrol noktasi 2: ayristirma sonrasi */
    CALL(guard_check)
    FILL(A0, 5)
    FILL(A1, 2)
    FILL(A2, 3)
    CALL(compile)
    MOVI(A0, 3)                     /* kontrol noktasi 3: derleme sonrasi */
    CALL(guard_check)
#endif
#if defined(TEST_HIJACK) && TEST_HIJACK
    /* Saldirganin tasma ile elde edecegi seyi taklit et:
     * TEST_HIJACK=1 -> gecersiz opcode, 2 -> kod disi atlama hedefi */
    FILL(A0, 2)
#if TEST_HIJACK == 1
    MOVI(A1, 200)                   /* optable disinda bir opcode */
#elif TEST_HIJACK == 2
    MOVI(A1, OP_JMP + (60000 << 16))
#else
    MOVI(A1, OP_CONST)              /* sabit 0'i bozacagiz */
#endif
    ST32_OFF(A0, 0, A1W)
#if TEST_HIJACK == 3
    /* sabit 0'i "tutamak 999999 olan nesne" yap: gecersiz tutamak */
    FILL(A0, 3)
    MOVI(A1, T_OBJ)
    ST32_OFF(A0, VAL_TAG, A1W)
    MOVI(A1, 999999)
    ST_OFF(A0, VAL_PAY, A1)
#endif
#endif

    /* Sozcuk/ayristirma/derleme hatasi varsa da YURUTME.
     * Bozuk kaynaktan uretilen bytecode'u calistirmak, hatanin
     * uzerine bir de anlamsiz calisma hatasi yigiyor. */
#if defined(MODE_PLAYER) && MODE_PLAYER
    LEA_SYM(A0, SYM(g_verr)); LD32(A0W, A0); SPILL(6, A0)
    LEA_SYM(A0, SYM(g_gderr)); LD32(A0W, A0); FILL(A1, 6); ADD(A0, A1)
#else
    LEA_SYM(A0, SYM(g_nerr)); LD32(A0W, A0); SPILL(6, A0)
    LEA_SYM(A0, SYM(g_perr)); LD32(A0W, A0); FILL(A1, 6); ADD(A0, A1); SPILL(6, A0)
    LEA_SYM(A0, SYM(g_cerr)); LD32(A0W, A0); FILL(A1, 6); ADD(A0, A1); SPILL(6, A0)
    LEA_SYM(A0, SYM(g_gderr)); LD32(A0W, A0); FILL(A1, 6); ADD(A0, A1)
#endif
    BZ(A0, lm_noerr)
    LEA_SYM(A0, m_cerr)
    MOVI(A1, m_cerr_len)
    CALL(print_str)
    B(lm_summary)
lm_noerr:
    /* Dogrulama hatasi varsa YURUTME. Kanitlanmis bozuk bytecode'u
     * calistirmak coku uretir; temiz tani daha degerli. */
    LEA_SYM(A0, SYM(g_verr))
    LD32(A0W, A0)
    BZ(A0, lm_run)
    LEA_SYM(A0, m_halt)
    MOVI(A1, m_halt_len)
    CALL(print_str)
    B(lm_summary)
lm_run:
    LEA_SYM(A0, h_out)
    MOVI(A1, h_out_len)
    CALL(print_str)
#if defined(OPT_JIT) && OPT_JIT
    /* JIT dene; desteklenmeyen komut ya da calisma aninda tur/tasma
     * gorurse 0 doner ve YORUMLAYICI calisir. Iki yol da ayni deger
     * yigini duzenini kullaniyor. */
    CALL(jc_compile)
    BZ(RV, lm_interp)
#if defined(JIT_DUMP) && JIT_DUMP
    LEA_SYM(A0, jd_path)
    CALL(jit_dump)
#endif
    CALL(jit_run)
    BNZ(RV, lm_ran)
lm_interp:
#endif
    FILL(A0, 2)
    FILL(A1, 3)
    CALL(run)
lm_ran:
    MOVI(A0, 4)                     /* kontrol noktasi 4: yurutme sonrasi */
    CALL(guard_check)
lm_summary:

    LEA_SYM(A0, h_sum); MOVI(A1, h_sum_len); CALL(print_str)
    LEA_SYM(A0, m_tok);  MOVI(A1, m_tok_len);  CALL(print_str)
    FILL(A0, 4); CALL(print_u32); MOVI(A0, 10); CALL(print_ch)
#if !defined(MODE_PLAYER) || !MODE_PLAYER
    LEA_SYM(A0, m_nd);   MOVI(A1, m_nd_len);   CALL(print_str)
    LEA_SYM(A0, SYM(g_nnodes)); LD32(A0W, A0)
    CALL(print_u32); MOVI(A0, 10); CALL(print_ch)
#endif
    LEA_SYM(A0, m_code); MOVI(A1, m_code_len); CALL(print_str)
    LEA_SYM(A0, SYM(g_ncode)); LD32(A0W, A0)
    CALL(print_u32); MOVI(A0, 10); CALL(print_ch)

    LEA_SYM(A0, m_gc);  MOVI(A1, m_gc_len);  CALL(print_str)
    LEA_SYM(A0, SYM(g_ngc)); LD32(A0W, A0)
    CALL(print_u32); MOVI(A0, 10); CALL(print_ch)
    LEA_SYM(A0, m_obj); MOVI(A1, m_obj_len); CALL(print_str)
    LEA_SYM(A0, SYM(g_nobj)); LD32(A0W, A0)
    CALL(print_u32); MOVI(A0, 10); CALL(print_ch)
#if OPT_COUNT
    LEA_SYM(A0, m_dis); MOVI(A1, m_dis_len); CALL(print_str)
    LEA_SYM(A0, SYM(g_ninstr)); LD(A0, A0)
    CALL(print_u32); MOVI(A0, 10); CALL(print_ch)
#endif
#if !defined(MODE_PLAYER) || !MODE_PLAYER
    CALL(code_stats)
    LEA_SYM(A0, m_cst); MOVI(A1, m_cst_len); CALL(print_str)
    LEA_SYM(A0, SYM(g_nconst)); LD32(A0W, A0)
    CALL(print_u32); MOVI(A0, 10); CALL(print_ch)
    LEA_SYM(A0, m_int); MOVI(A1, m_int_len); CALL(print_str)
    LEA_SYM(A0, SYM(g_nintern)); LD32(A0W, A0)
    CALL(print_u32); MOVI(A0, 10); CALL(print_ch)
    LEA_SYM(A0, m_sup); MOVI(A1, m_sup_len); CALL(print_str)
    LEA_SYM(A0, SYM(g_st_super)); LD32(A0W, A0)
    CALL(print_u32); MOVI(A0, 10); CALL(print_ch)
    LEA_SYM(A0, m_gc2); MOVI(A1, m_gc2_len); CALL(print_str)
    LEA_SYM(A0, SYM(g_st_gc)); LD32(A0W, A0)
    CALL(print_u32); MOVI(A0, 10); CALL(print_ch)
    LEA_SYM(A0, m_ak);  MOVI(A1, m_ak_len);  CALL(print_str)
    LEA_SYM(A0, SYM(g_st_addk)); LD32(A0W, A0)
    CALL(print_u32); MOVI(A0, 10); CALL(print_ch)
#endif
#if defined(OPT_JIT) && OPT_JIT
    /* JIT gercekten calisti mi: kapsam iddialarini olcebilmek icin */
    LEA_SYM(A0, m_jit); MOVI(A1, m_jit_len); CALL(print_str)
    LEA_SYM(A0, SYM(g_jc_ok)); LD32(A0W, A0)
    CALL(print_u32); MOVI(A0, 10); CALL(print_ch)
#endif
    LEA_SYM(A0, m_gd);  MOVI(A1, m_gd_len);  CALL(print_str)
    LEA_SYM(A0, SYM(g_gderr)); LD32(A0W, A0)
    CALL(print_u32); MOVI(A0, 10); CALL(print_ch)
    LEA_SYM(A0, m_vf);  MOVI(A1, m_vf_len);  CALL(print_str)
    LEA_SYM(A0, SYM(g_verr)); LD32(A0W, A0)
    CALL(print_u32); MOVI(A0, 10); CALL(print_ch)
    LEA_SYM(A0, m_err); MOVI(A1, m_err_len); CALL(print_str)
#if defined(MODE_PLAYER) && MODE_PLAYER
    MOVI(A0, 0); SPILL(0, A0)
#else
    LEA_SYM(A0, SYM(g_nerr));  LD32(A0W, A0); SPILL(0, A0)
    LEA_SYM(A0, SYM(g_perr));  LD32(A0W, A0); FILL(A1, 0); ADD(A0, A1); SPILL(0, A0)
    LEA_SYM(A0, SYM(g_cerr));  LD32(A0W, A0); FILL(A1, 0); ADD(A0, A1); SPILL(0, A0)
#endif
    LEA_SYM(A0, SYM(g_rterr)); LD32(A0W, A0); FILL(A1, 0); ADD(A0, A1); SPILL(0, A0)
    LEA_SYM(A0, SYM(g_verr));  LD32(A0W, A0); FILL(A1, 0); ADD(A0, A1); SPILL(0, A0)
    LEA_SYM(A0, SYM(g_gderr)); LD32(A0W, A0); FILL(A1, 0); ADD(A0, A1); SPILL(0, A0)
    FILL(A0, 0); CALL(print_u32); MOVI(A0, 10); CALL(print_ch)

    /* Cikis kodu 0 veya 1. Hata SAYISINI dondurmek 136 gibi degerler
     * uretiyordu ve 128+sinyal ile karisiyordu. */
    FILL(A0, 0)
    BZ(A0, lm_ok)
    MOVI(RV, 1)
    LEAVE_
    RET
lm_ok:
    MOVI(RV, 0)
    LEAVE_
    RET

lm_oom:
    MOVI(A0, FD_STDERR)
    LEA_SYM(A1, m_oom)
    MOVI(A2, m_oom_len)
    CALL(os_write)
    MOVI(RV, 1)
    LEAVE_
    RET
ENDFUNC(lang_main)
