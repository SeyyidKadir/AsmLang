/* asmlang'den cagrilan C ornegi.
 *
 * Bare-metal'de de derlenebilmesi icin FREESTANDING: libc yok,
 * printf/malloc yok, yalniz saf hesap.
 *
 * C++ kullanacaksaniz extern "C" ile sarin:
 *     extern "C" int topla(int a, int b) { return a + b; }
 * yoksa ad bozulur (name mangling) ve cbul() bulamaz.
 */

long topla(long a, long b) {
    return a + b;
}

long kare(long x) {
    return x * x;
}

/* Agir is ornegi: asmlang'de yazmak uzun surerdi.
 * CPUID ile uretici imzasini tek tamsayiya paketler. */
long cpu_adi(void) {
#if defined(__x86_64__) || defined(__i386__)
    unsigned int b = 0;
    __asm__ volatile("cpuid" : "=b"(b) : "a"(0) : "ecx", "edx");
    return (long)b;
#else
    return 0;
#endif
}
