/* asmlang JIT'in urettigi kodun yaptigi isi C'de iki farkli seviyede
 * modelleyip TAVAN olcumu yapiyoruz. */
#include <stdint.h>
#include <stdio.h>
typedef struct { uint32_t tag; int32_t pay; } val;
static val gv[8];

/* A) asmlang'in deger modeliyle AYNI: etiketli, bellekte, tasma denetimli */
static int tagged(void) {
    gv[0].tag=0; gv[0].pay=0;   /* toplam */
    gv[1].tag=0; gv[1].pay=1;   /* bir    */
    gv[2].tag=0; gv[2].pay=0;   /* i      */
    for (;;) {
        if (!(gv[2].tag==0 && gv[2].pay < 20000000)) break;
        if (gv[0].tag | gv[1].tag) return -1;
        int32_t r;
        if (__builtin_add_overflow(gv[0].pay, gv[1].pay, &r)) return -1;
        gv[0].tag=0; gv[0].pay=r;
        if (gv[2].tag) return -1;
        if (__builtin_add_overflow(gv[2].pay, 1, &gv[2].pay)) return -1;
    }
    return gv[0].pay;
}

/* B) deyimsel C: duz tamsayilar, denetim yok */
static int plain(void) {
    volatile int t=0, b=1, i=0;
    while (i < 20000000) { t = t + b; i = i + 1; }
    return t;
}

int main(int c, char**v){ return (v[1][0]=='a') ? tagged() : plain(); }
