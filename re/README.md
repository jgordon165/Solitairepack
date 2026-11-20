# Reverse engineering workflow

Everything produced here (Ghidra project, decompiled C, extracted
resources) is **git-ignored**. It's reference material for writing the port,
not part of it. The port's own code in `src/` and `scripts/` is written fresh
from what we learn.

## 1. Identify the executable and list its resources

```
python3 -I tools/identify_exe.py /path/to/SOL.EXE --list
python3 -I tools/identify_exe.py /path/to/SOL.EXE --extract re/output/resources
```

Do the same for `CARDS.DLL`, which holds the card art.

`--extract` writes the BITMAP resources as `.bmp` files and the string
tables as `strings.txt`. Use them to check `scripts/game/cards.lua` (which
bitmap is which card, which are the backs and the empty-pile marks).

## 1b. A quick disassembly

`tools/ne_disasm.py` (needs `pip install capstone`) writes each code
segment of an expanded SOL.EXE as an annotated .asm file, calls to KERNEL,
GDI and USER named. The seg:offset addresses in `docs/original.md` refer
to its output.

## 2. Decompile

```
GHIDRA_HOME=~/ghidra_11.x re/ghidra_headless.sh /path/to/SOL.EXE
```

Produces `re/output/all_functions.c` and `re/output/functions.tsv`.

## 3. Map subsystems, then rewrite

Work from the resources inward:

1. **Resources**: `LoadBitmap`, `LoadString`, `DialogBox` and `LoadMenu`
   imports (USER.EXE ordinals) show which resource each screen uses.
2. **Layout**: the `WM_SIZE` handler and the pile positions it computes
   from the client size and the card size (`cdtInit`).
3. **Rules**: the shuffle (the random number routine), the deal, which moves
   are legal, Draw One / Draw Three, the Standard and Vegas scoring, the
   timer's penalty and the end-of-game bonus. Findings go in
   `docs/original.md`.
4. **Options**: what `WIN.INI`'s `[Solitaire]` section holds
   (`WriteProfileString`) and its format.

Game logic stays in Lua under `scripts/`, written from your notes on the
decompiled behaviour rather than translated line by line.

Tools worth having alongside: Windows 3.1 in DOSBox-X or 86Box with the
original running, and a hex editor.
