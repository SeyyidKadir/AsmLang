/* Kalan farkin kaynagini ayirmak icin: ayni is, ama degerler
 * BELLEKTE kalmaya zorlaniyor (volatile) - JIT'imizin yaptigi gibi.
 * Fark buysa, kalan bosluk register tahsisinden geliyor demektir. */
#include <stdint.h>
typedef struct { uint32_t tag; int32_t pay; } val;
static volatile val gv[8];
int main(void){
    gv[0].tag=0; gv[0].pay=0;
    gv[1].tag=0; gv[1].pay=1;
    gv[2].tag=0; gv[2].pay=0;
    for(;;){
        if (gv[2].tag) return -1;
        if (!(gv[2].pay < 20000000)) break;
        if (gv[0].tag | gv[1].tag) return -1;
        int32_t r;
        if (__builtin_add_overflow(gv[0].pay, gv[1].pay, &r)) return -1;
        gv[0].pay = r;
        if (gv[2].tag) return -1;
        if (__builtin_add_overflow(gv[2].pay, 1, &r)) return -1;
        gv[2].pay = r;
    }
    return gv[0].pay;
}
