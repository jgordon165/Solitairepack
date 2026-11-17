# Solitaire (Windows 3.1) file formats

The game is two 16-bit Windows files from Windows 3.1 (1992): `SOL.EXE`,
the program, with its menus, dialogs and strings as resources, and
`CARDS.DLL`, the card art (also used by Hearts and FreeCell later), which
Windows keeps in `WINDOWS\SYSTEM`. All values little-endian.

## Executable: MZ stub + NE

```
0x00  "MZ" DOS stub ("This program requires Microsoft Windows")
0x3C  u32 e_lfanew -> NE header
```

NE header (offsets from its start) fields the port reads:

| Offset | Size | Field |
|---|---|---|
| 0x00 | 2 | `"NE"` |
| 0x24 | 2 | resource table offset (relative to the NE header) |
| 0x26 | 2 | resident-name table offset (relative); also ends the resource table |
| 0x3E | 2 | expected Windows version (major high byte, minor low byte) |

The first resident name is the module name.

## Resource table

```
u16 align_shift                       offsets and lengths are << this
repeat {
    u16 type                          0 ends the table; bit 15 set: numbered type
                                      (bit 15 clear: offset of its name, from table start)
    u16 count
    u32 reserved
    count × {
        u16 offset                    << align_shift = file offset
        u16 length                    << align_shift (rounded up to the alignment)
        u16 flags                     0x10 moveable, 0x20 pure, 0x40 preload
        u16 id                        bit 15 set: numbered; clear: offset of its name
        u32 reserved
    }
}
names: u8 length + characters (not NUL-terminated)
```

Numbered types: 1 CURSOR, 2 BITMAP, 3 ICON, 4 MENU, 5 DIALOG, 6 STRING,
9 ACCELERATOR, 10 RCDATA, 12 GROUP_CURSOR, 14 GROUP_ICON.

## BITMAP

A DIB without the 14-byte file header: `BITMAPINFOHEADER` (40 bytes) or
`BITMAPCOREHEADER` (12 bytes), then the palette (4 or 3 bytes per entry,
B, G, R), then bottom-up rows padded to 4 bytes. 1/4/8/24 bpp, uncompressed
or RLE4/RLE8. Decoded by `src/formats/dib.cpp`.

## STRING

Blocks of 16 strings; block *n* holds ids `(n-1)*16 ... (n-1)*16+15`. Each
string is a length byte then the characters (an empty entry is a 0 byte).

## DIALOG

The 16-bit `DLGTEMPLATE`: style (32 bits), control count (8 bits), x, y,
width, height in dialog units, then the menu, class and caption (each a
NUL-terminated string, or `FF` and a 16-bit id). `DS_SETFONT` adds a point
size and a font name. Each control: x, y, width, height, id, style, then
its class (a byte `80`-`85` for button / edit / static / listbox /
scrollbar / combobox, else a name), its text (or `FF` and an id), and a
length byte for creation data. Decoded by `src/formats/dialog.cpp`.

## MENU

The 16-bit `MENUITEMTEMPLATE`: a header (version 0, header size 0), then
the items in order. Each: a flags word (`0x10` pop-up, `0x80` the last item
of its level, `0x01` grayed, `0x08` checked), an id (not for pop-ups), and
the text, NUL-terminated. A pop-up's items follow it. A separator is an
item with id 0 and no text. Decoded by `src/formats/menu.cpp`.

## CARDS.DLL

BITMAP resources, 71 x 96:

| Ids | |
|---|---|
| 1-13 | Clubs, Ace to King |
| 14-26 | Diamonds |
| 27-39 | Hearts |
| 40-52 | Spades |
| 53- | The backs |
| 67 | The X on an empty stock (no more passes) |
| 68 | The O on an empty stock (click to turn the waste over) |

Card `n` (0-51 as suit * 13 + rank - 1) is bitmap `n + 1`. The port rounds
the corners the way the DLL's `cdtDraw` does, by clearing three pixels at
each corner. To be checked against the player's file: the exact set of
backs, and the extra bitmaps the animated backs flip between.

## The game itself

What the port takes from SOL.EXE (layout, rules, scoring, the options) is
in `original.md`.
