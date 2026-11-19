# Solitaire (Windows 3.1) file formats

The game is one 16-bit Windows program from Windows 3.1 (1992), `SOL.EXE`
(180,688 bytes), holding the card art, menus, dialogs and strings as
resources. On the setup disks it's compressed as `SOL.EX_`. Later Windows
versions moved the cards into `CARDS.DLL`; the port falls back on a 16-bit
one for the faces when there's no SOL.EXE. All values little-endian.

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

## The card art (SOL.EXE, or CARDS.DLL)

BITMAP resources:

| Ids | |
|---|---|
| 1-13 | Clubs, Ace to King (71 x 96) |
| 14-26 | Diamonds |
| 27-39 | Hearts |
| 40-52 | Spades |
| 53 | The dotted pattern of an empty pile (monochrome) |
| 54-65 | The twelve backs |
| 67 | The X on an empty stock (no more passes) |
| 68 | The O on an empty stock (click to turn the waste over) |
| 678, 679 | Back 65 (the hand): the card up the sleeve, 32 x 22 at (32, 32) |
| 680 | Back 63 (the castle): bats, 26 x 12 at (42, 12) |
| 681, 682 | Back 64 (the beach): the sun in sunglasses, then with its tongue out, 14 x 12 at (47, 1) |
| 683, 684 | Back 56 (the robot): its lights, 24 x 7 at (24, 40) |

Card `n` (0-51 as suit * 13 + rank - 1) is bitmap `n + 1`. Spot cards are
monochrome: black (clubs, spades) or red (diamonds, hearts) on white; the
original draws a red card's edge black, and so does the port. The courts
are 16-colour. The port rounds every card's corners by clearing three
pixels at each. The empty-pile pattern is monochrome with its white drawn
as the table. Where the animation frames sit was found by matching them
against their backs.

## Install-disk compression (SOL.EX_)

`src/formats/expand.cpp`, checked byte for byte against libmspack on the
Windows 3.1 disks.

**SZDD** (COMPRESS.EXE): `SZDD 88 F0 27 33`, `A`, the file name's missing
last letter, the expanded size (u32), then LZSS: a flag byte whose bits, low
first, say literal (1) or match (0); a match is two bytes, window position
`b0 | (b1 & 0xF0) << 4`, length `(b1 & 0x0F) + 3`, over a 4 KB window
filled with spaces, writing from 4096 - 16.

**KWAJ** (Windows 3.1's setup): `KWAJ 88 F0 27 D1`, the method (u16), the
data's offset (u16), flags (u16), then per the flags: the expanded size
(u32, 0x01), 2 unknown bytes (0x02), a length-prefixed block (0x04), the
name (0x08) and extension (0x10), NUL-terminated. Methods: 0 stored, 1 XOR
0xFF, 2 SZDD's LZSS, 3 LZH, 4 MS-ZIP (not supported; not on these disks).

**LZH** (method 3), bits most significant first: six 4-bit table types
(five used), then the code lengths of five canonical Huffman tables: match
length (16 symbols), match length after a literal run (16), literal run
length (32), offset high bits (64) and literal (256). Each table's lengths
are type 0 (all the same: 4, 5, 6 or 8 bits), 1 (first in 4 bits; then 0 =
same, 10 = one more, 11 + 4 bits = new), 2 (first in 4 bits; then 2 bits:
0-2 = change by -1, 0, +1; 3 + 4 bits = new) or 3 (each in 4 bits). Then: a
match length; non-zero means a match of length + 2, its offset the offset
symbol << 6 plus 6 more bits, back from the current window position;
zero means a run of literal-run-length + 1 literals, and a run shorter
than 32 means the next match length uses the second table. The window is
4 KB of spaces.

## The game itself

What the port takes from SOL.EXE (layout, rules, scoring, the options) is
in `original.md`.
