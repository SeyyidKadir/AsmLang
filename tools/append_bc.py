#!/usr/bin/env python3
"""tools/append_bc.py yurutucu program.bc cikti

Bytecode'u yurutucunun SONUNA ekler ve 8 baytlik fuye yazar:
    [ ...bytecode... ][ u32 uzunluk ][ u32 "ASMT" ]

PE ve ELF yukleyicileri dosya sonundaki fazlaligi yok sayar, bu yuzden
ayni yontem uc OS'ta da calisir.
"""
import sys, struct, pathlib, os
if len(sys.argv) != 4:
    sys.exit("kullanim: append_bc.py <yurutucu> <program.bc> <cikti>")
exe = pathlib.Path(sys.argv[1]).read_bytes()
bc  = pathlib.Path(sys.argv[2]).read_bytes()
out = pathlib.Path(sys.argv[3])
out.write_bytes(exe + bc + struct.pack('<II', len(bc), 0x544D5341))
os.chmod(out, 0o755)
print("%s: %d bayt yurutucu + %d bayt bytecode = %d" %
      (out, len(exe), len(bc), out.stat().st_size))
