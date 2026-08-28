/* args.S - komut satiri argumanlari
 *
 * Linux ve macOS'ta giriste yigin duzeni AYNI:
 *   [sp] = argc, [sp+word] = argv[0], ... , NULL, envp...
 * Bu yuzden alti hedef tek kod yoluyla destekleniyor.
 *
 * Windows farkli (GetCommandLineA tek bir dizgi doner ve ayristirmak
 * gerekir) ve bare-metal'de arguman kavrami yok: ikisinde de argc = 0.
 * Bu bir eksiklik, gizlenmiyor - dokumante edildi.
 */
#include "../abi.inc"
#include "../tables/opcodes.inc"

    .bss
    .p2align 3
    .globl SYM(g_argc)
SYM(g_argc):  .space 4
    .p2align 3
    .globl SYM(g_argv)
SYM(g_argv):  .space 8
/* Windows GetCommandLineA tek bir dizgi doner; kendimiz ayirmaliyiz.
 * Kopya uzerinde calisiyoruz: isletim sisteminin tamponunu
 * degistirmek dogru degil. */
#define WIN_CMD_MAX  1024
#define WIN_ARG_MAX  32
SYM(g_cmdbuf):  .space WIN_CMD_MAX
    .p2align 3
SYM(g_argvbuf): .space WIN_ARG_MAX * 8

    SECT_TEXT

/* win_args(A0 = GetCommandLineA sonucu)
 * OS koruması YOK: bu yalnizca bir dizgi ayristiricisi. Windows'ta
 * test edemedigim icin mantigini Linux'ta test edilebilir biraktim
 * (-DTEST_CMDLINE=1). Riskli olan kisim ayristirici; GetCommandLineA
 * cagrisi onemsiz.
 * Bosluklara gore ayirir, "tirnak" iceren parcalari tek arguman sayar.
 * Kopyayi yerinde NUL'lar ve isaretcileri g_argvbuf'a yazar.
 * Slotlar: 0=kaynak 1=i(kopya) 2=argc 3=parca basi 4=tirnak icinde mi
 */
FUNC(win_args)
    ENTER(6)
    SPILL(0, A0)
    MOVI(A0, 0)
    SPILL(1, A0)                    /* kopya uzunlugu */
wa_copy:
    FILL(A0, 1)
    CMPI(A0, WIN_CMD_MAX - 1)
    BHS(wa_copied)
    FILL(A1, 0)
    LDB_IDX(A2W, A1, A0)
    BZ(A2, wa_copied)
    LEA_SYM(A1, SYM(g_cmdbuf))
    ADD(A1, A0)
    STB(A1, A2B)
    FILL(A0, 1); INC(A0); SPILL(1, A0)
    B(wa_copy)
wa_copied:
    LEA_SYM(A1, SYM(g_cmdbuf))
    FILL(A0, 1)
    ADD(A1, A0)
    MOVI(A2, 0)
    STB(A1, A2B)                    /* NUL */

    MOVI(A0, 0)
    SPILL(2, A0)                    /* argc */
    SPILL(4, A0)                    /* tirnak icinde mi */
    MOVI(A0, 0)
    SPILL(3, A0)                    /* tarama konumu */
wa_scan:
    FILL(A0, 3)
    FILL(A1, 1)
    CMPR(A0, A1)
    BHS(wa_done)
    LEA_SYM(A1, SYM(g_cmdbuf))
    LDB_IDX(A2W, A1, A0)
    /* bosluklari atla */
    CMPI(A2, 32)
    BNE(wa_start)
    FILL(A0, 3); INC(A0); SPILL(3, A0)
    B(wa_scan)
wa_start:
    /* yeni parca: isaretciyi kaydet */
    FILL(A0, 2)
    CMPI(A0, WIN_ARG_MAX)
    BHS(wa_done)
    CMPI(A2, 34)                    /* '"' */
    BNE(wa_noq)
    MOVI(A1, 1); SPILL(4, A1)
    FILL(A0, 3); INC(A0); SPILL(3, A0)
wa_noq:
    LEA_SYM(A1, SYM(g_cmdbuf))
    FILL(A0, 3)
    ADD(A1, A0)
    FILL(A0, 2)
    SHLI(A0, WORD_SHIFT)
    LEA_SYM(A2, SYM(g_argvbuf))
    ADD(A0, A2)
    ST(A0, A1)
    FILL(A0, 2); INC(A0); SPILL(2, A0)
wa_body:
    FILL(A0, 3)
    FILL(A1, 1)
    CMPR(A0, A1)
    BHS(wa_done)
    LEA_SYM(A1, SYM(g_cmdbuf))
    LDB_IDX(A2W, A1, A0)
    FILL(A1, 4)
    BNZ(A1, wa_inq)
    CMPI(A2, 32)
    BEQ(wa_cut)
    B(wa_adv)
wa_inq:
    CMPI(A2, 34)
    BEQ(wa_cutq)
wa_adv:
    FILL(A0, 3); INC(A0); SPILL(3, A0)
    B(wa_body)
wa_cutq:
    MOVI(A1, 0); SPILL(4, A1)
wa_cut:
    LEA_SYM(A1, SYM(g_cmdbuf))
    FILL(A0, 3)
    ADD(A1, A0)
    MOVI(A2, 0)
    STB(A1, A2B)
    FILL(A0, 3); INC(A0); SPILL(3, A0)
    B(wa_scan)
wa_done:
    FILL(A0, 2)
    LEA_SYM(A1, SYM(g_argc))
    ST32_OFF(A1, 0, A0W)
    LEA_SYM(A0, SYM(g_argvbuf))
    LEA_SYM(A1, SYM(g_argv))
    ST(A1, A0)
    LEAVE_
    RET
ENDFUNC(win_args)

/* arg_ptr(A0 = indeks) -> RV = NUL ile biten dizgi, yoksa 0 */
FUNC(arg_ptr)
    ENTER(1)
    SPILL(0, A0)
    LEA_SYM(A1, SYM(g_argc))
    LD32(A1W, A1)
    CMPR(A0, A1)
    BHS(ap_no)
    LEA_SYM(A1, SYM(g_argv))
    LD(A1, A1)
    BZ(A1, ap_no)
    FILL(A0, 0)
    SHLI(A0, WORD_SHIFT)
    ADD(A0, A1)
    LD(RV, A0)
    LEAVE_
    RET
ap_no:
    MOVI(RV, 0)
    LEAVE_
    RET
ENDFUNC(arg_ptr)

/* cstr_len(A0 = NUL ile biten dizgi) -> RV = uzunluk */
FUNC(cstr_len)
    ENTER(2)
    SPILL(0, A0)
    MOVI(A0, 0)
    SPILL(1, A0)
cl_loop:
    FILL(A0, 0)
    FILL(A1, 1)
    LDB_IDX(A2W, A0, A1)
    BZ(A2, cl_done)
    FILL(A0, 1)
    INC(A0)
    SPILL(1, A0)
    B(cl_loop)
cl_done:
    FILL(RV, 1)
    LEAVE_
    RET
ENDFUNC(cstr_len)
