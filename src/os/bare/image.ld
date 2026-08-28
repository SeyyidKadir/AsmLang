/* image.ld - bare-metal imaj yerlesimi
 * Kod 0 yer degistirme kaydi urettigi icin imaj istenen adrese
 * yuklenebilir; burasi yalnizca bolum siralamasini belirler. */
ENTRY(_start)
SECTIONS
{
  . = LOAD_ADDR;
  /* Multiboot basligi imajin ilk 8 KB'sinde olmali: EN BASA. */
  .multiboot : { *(.multiboot) }
  .text : { *(.text*) }
  .rodata : { *(.rodata*) *(.const*) }
  .data : { *(.data*) }
  /* Yigin ve obek .bss BOLUMUNUN ICINDE olmali.
   *
   * Once bolumun DISINDAydilar: LOAD segmenti 0x100000..0x194678
   * iken yigin 0x195000'de kaliyordu. Bare-metal'de RAM orada
   * durdugu icin calisiyor gorunur, ama:
   *   - yukleyici o bolgeyi AYIRMAZ; modul ya da bellek haritasi
   *     oraya denk gelirse sessizce ezilir
   *   - imaj kendi bellek ayak izini dogru bildirmez
   * Bolumun icine alinca LOAD segmenti hepsini kapsiyor.
   *
   * __bss_end yigindan ONCE kaliyor: sifirlama dongusu yalniz
   * gercek .bss'i geziyor, 4 MB obek bosuna sifirlanmiyor. */
  __bss_start = .;
  .bss : {
    *(.bss*) *(COMMON)
    . = ALIGN(16);
    __bss_end = .;

    . = ALIGN(4096);
    _stack_bottom = .;
    . += 65536;               /* 64 KB makine yigini */
    _stack_top = .;

    . = ALIGN(4096);
    _heap_start = .;
    . += 4194304;             /* 4 MB: os_alloc bu bolgeden dagitir */
    _heap_end = .;
  }
}
