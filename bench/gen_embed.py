#!/usr/bin/env python3
"""bench/programs/*.al  ->  GAS .ascii blogu (.inc)

Kaynagi bayt bayt gomer; kacislari GAS'in anlayacagi bicime cevirir.
UTF-8 baytlari sekizlik kacisla yazilir ki dosya kodlamasindan bagimsiz olsun.
"""
import sys, pathlib

def esc(bs):
    out = []
    for b in bs:
        if b == 0x22:   out.append('\\"')
        elif b == 0x5C: out.append('\\\\')
        elif 0x20 <= b < 0x7F: out.append(chr(b))
        else: out.append('\\%03o' % b)
    return "".join(out)

src = pathlib.Path(sys.argv[1]).read_bytes()
lines = src.split(b"\n")
out = ["/* OTOMATIK URETILDI - bench/gen_embed.py %s */" % sys.argv[1]]
for ln in lines:
    if not ln and ln is lines[-1]:
        continue
    out.append('    .ascii "%s\\n"' % esc(ln))
print("\n".join(out))
