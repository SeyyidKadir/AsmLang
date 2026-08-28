#!/usr/bin/env python3
"""Sabit havuzu indeksinin superkomut kapsamini nasil tikadigini gosteren
determinist program uretir.

  - 300 satir "t = t + K", K yalnizca 5 farkli deger alir
      interning YOK : 300+ havuz girdisi  -> sicak dongunun sabitleri
                      256'yi asar, GETG_CONST/ADDK ateslenmez
      interning VAR : ~8 girdi            -> dusuk indeks, fusion calisir
  - sonda sicak dongu (2M tur)
"""
import sys
L = ["tanim t = 0"]
for i in range(300):
    L.append("t = t + %d" % (1 + i % 5))
L += ["tanim i = 0",
      "iken i < 2000000 { t = t + 7  i = i + 1 }",
      "yazdir t"]
print("\n".join(L))
