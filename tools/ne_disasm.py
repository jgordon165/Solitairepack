#!/usr/bin/env python3
"""Disassembles a 16-bit Windows (NE) program, such as SOL.EXE, one .asm file
per code segment, with calls to other modules (GDI.34, USER.10, ...) and to
the program's own exported entries (entry29, ...) marked. A quicker look than
the Ghidra workflow in re/README.md; docs/original.md cites addresses as
seg:offset from this.

    pip install capstone
    python3 tools/ne_disasm.py SOL.EXE re/output/sol

Compressed files (SOL.EX_) need expanding first (EXPAND.EXE, or run the
port once with --data on the disk: it reads them as they are). The output
holds the original's code: keep it out of the repository (re/output/ is
git-ignored).
"""
import os
import struct
import sys

try:
    from capstone import CS_ARCH_X86, CS_MODE_16, Cs
except ImportError:
    sys.exit("needs capstone: pip install capstone")

# A few imports worth naming (ordinals in Windows 3.1's KERNEL/GDI/USER).
NAMES = {
    "GDI.34": "BitBlt", "GDI.45": "SelectObject", "GDI.31": "SetPixel", "GDI.66": "CreateSolidBrush",
    "GDI.68": "DeleteDC", "GDI.69": "DeleteObject", "USER.10": "SetTimer", "USER.12": "KillTimer",
    "USER.33": "GetClientRect", "USER.39": "BeginPaint", "USER.40": "EndPaint", "USER.66": "GetDC",
    "USER.68": "ReleaseDC", "USER.107": "DefWindowProc", "USER.108": "GetMessage", "USER.109": "PeekMessage",
    "USER.110": "PostMessage", "USER.113": "TranslateMessage", "USER.114": "DispatchMessage",
    "USER.124": "UpdateWindow", "USER.125": "InvalidateRect", "USER.175": "LoadBitmap", "USER.1": "MessageBox",
}


def parse(data):
    ne = struct.unpack_from("<I", data, 0x3C)[0]
    if data[ne:ne + 2] != b"NE":
        sys.exit("not a 16-bit Windows (NE) program")
    h = data[ne:ne + 64]
    segcnt, modcnt = struct.unpack_from("<HH", h, 0x1C)
    segtab = ne + struct.unpack_from("<H", h, 0x22)[0]
    modref = ne + struct.unpack_from("<H", h, 0x28)[0]
    impnames = ne + struct.unpack_from("<H", h, 0x2A)[0]
    align = struct.unpack_from("<H", h, 0x32)[0]
    mods = []
    for i in range(modcnt):
        off = struct.unpack_from("<H", data, modref + 2 * i)[0]
        n = data[impnames + off]
        mods.append(data[impnames + off + 1:impnames + off + 1 + n].decode("latin-1"))
    segs = []
    for i in range(segcnt):
        so, sl, fl, _ = struct.unpack_from("<HHHH", data, segtab + 8 * i)
        off, ln = so << align, sl or 0x10000
        relocs = []
        if fl & 0x100:
            p = off + ln
            n = struct.unpack_from("<H", data, p)[0]
            relocs = [struct.unpack_from("<BBHHH", data, p + 2 + 8 * k) for k in range(n)]
        segs.append({"num": i + 1, "flags": fl, "data": data[off:off + ln], "relocs": relocs})
    # Where each relocation lands (following the chains), and what it names.
    labels = {}
    for s in segs:
        for _st, fl2, offs, a, b in s["relocs"]:
            kind, additive = fl2 & 3, fl2 & 4
            if kind == 1:
                name = "%s.%d" % (mods[a - 1], b)
                name = NAMES.get(name, name)
            elif kind == 0:
                name = "entry%d" % b if a == 0xFF else "seg%d:%04x" % (a, b)
            else:
                name = "import by name"
            o, hops = offs, 0
            while 0 <= o < len(s["data"]) - 1 and hops < 1000:
                labels[(s["num"], o)] = name
                if additive:
                    break
                nxt = struct.unpack_from("<H", s["data"], o)[0]
                if nxt == 0xFFFF:
                    break
                o, hops = nxt, hops + 1
    return segs, labels


def main():
    if len(sys.argv) != 3:
        sys.exit(__doc__)
    with open(sys.argv[1], "rb") as f:
        data = f.read()
    os.makedirs(sys.argv[2], exist_ok=True)
    segs, labels = parse(data)
    md = Cs(CS_ARCH_X86, CS_MODE_16)
    for s in segs:
        if s["flags"] & 1:   # a data segment
            continue
        lines = []
        for ins in md.disasm(bytes(s["data"]), 0):
            note = ""
            for k in range(ins.size):
                if (s["num"], ins.address + k) in labels:
                    note = "  ; -> " + labels[(s["num"], ins.address + k)]
            lines.append("%d:%04x  %-30s%s" % (s["num"], ins.address, ins.mnemonic + " " + ins.op_str, note))
        path = os.path.join(sys.argv[2], "seg%d.asm" % s["num"])
        with open(path, "w") as f:
            f.write("\n".join(lines) + "\n")
        print(path, len(lines), "instructions")


if __name__ == "__main__":
    main()
