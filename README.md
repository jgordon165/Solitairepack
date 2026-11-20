# Solitairepack

[![CI-build](https://github.com/jgordon165/Solitairepack/actions/workflows/ci-build.yml/badge.svg)](https://github.com/jgordon165/Solitairepack/actions/workflows/ci-build.yml)
[![code-analysis](https://github.com/jgordon165/Solitairepack/actions/workflows/code-analysis.yml/badge.svg)](https://github.com/jgordon165/Solitairepack/actions/workflows/code-analysis.yml)

A modern reimplementation host for *Solitaire* from **Windows 3.1** (1992):
a C++ engine (SDL2) running game logic written in Lua. A sister project of
[Tetrispack](https://github.com/jgordon165/Tetrispack), on the same engine
and pipelines.

**No original game code or data is included.** The engine reads the cards,
menus, dialogs and text from the player's own `SOL.EXE` at runtime (it can
read it straight off a Windows 3.1 setup disk), the same way ScummVM and
OpenRCT2 work. Original
files are git-ignored as a safety net, and release packages are checked for
them.

## Build

Requires CMake 3.20+ and a C++20 compiler. SDL2 and Lua 5.4 are downloaded
and built automatically.

```
cmake -S . -B build -DCMAKE_BUILD_TYPE=Release
cmake --build build --config Release
ctest --test-dir build -C Release
```

Windows (Visual Studio 2022): the same commands work from a Developer prompt,
or open the folder in Visual Studio.

## Run

Point the engine at a folder holding your `SOL.EXE`: a Windows 3.1
`WINDOWS` folder, or the Windows 3.1 setup disk or CD itself, where it's
compressed as `SOL.EX_` (the port expands it, as Setup would):

```
build\Release\solitairepack.exe --data E:\
build\Release\solitairepack.exe --data C:\WINDOWS
```

Without `--data` it looks in a `data` folder beside the program, the
program's folder, then (on Windows) the root and `WINDOWS` folder of each
drive, so with the Windows 3.1 CD or disk image mounted it just finds it.

Windows 3.0 and 3.1 keep the cards inside `SOL.EXE`. Without it, a 16-bit
`CARDS.DLL` (Windows for Workgroups) can stand in for the cards.

It opens like the original maximized on a 640x480 screen, shown at 1.5x
(960x660; `--scale` changes the zoom, `--size 1280x720` the starting
size): the green table, the stock, the waste, the four foundations and the
seven columns.

**Resizing.** Make the window bigger, maximize it, or press **F11** for full
screen, and the table grows with it rather than stretching: the cards keep
their size, the deck stays in the top left corner and the four foundations
in the top right, and the seven columns spread out evenly between them,
with more room below for long columns. Up to 640 pixels wide the spacing is
the original's (margins as wide as the gaps).
Without `SOL.EXE` it still runs, with plain cards of its own.

**Playing.** Click the deck to turn over cards (one or three, Game >
Options). Drag a card, or a run of face-up cards, to move it; drop it where
it goes. Double-click a card to send it to its foundation; right-click to
send up every card that can go. Click a face-down card at the top of a
column to turn it over. Game > Undo takes back the last move.

| Key | |
|---|---|
| F2 | Deal |
| Ctrl+Z, Backspace | Undo |
| Arrows | Move the cursor over the piles and along a column's face-up cards |
| Space, Enter | Turn the deck, turn a card over, pick cards up, put them down |
| Esc | Let go of the picked-up cards |
| Alt, F10, F12 | The menus |
| F1 | Help |
| F11 | Full screen / window |

**Controller** (SDL game controllers): D-pad moves the cursor, A picks up
and puts down, B lets go, X turns the deck, Y sends every card it can to
the foundations, LB sends the one under the cursor, Back undoes, Start
opens the menus.

**Menus and dialogs** are drawn in Windows 3.1's look. Game: Deal, Undo,
Deck..., Options..., Exit. Help: the rules and the keys, About. With
`SOL.EXE` the menus, the Options and Select Card Back dialogs and the
status bar's text come from its own resources.

**Options.** Draw One or Draw Three; Standard, Vegas or no scoring; Timed
game; Status bar; Outline dragging; Keep score (Vegas). Changing the draw,
the scoring or the timer deals again. The status bar shows the score and
the time. **Deck** picks one of the twelve backs; the robot, the castle, the
beach and the hand come alive now and then, as in the original.

**Scoring.** Standard: 10 for each card to a foundation, 5 from the deck to
a column and for each card turned over, -15 for taking one off a
foundation, a penalty for each pass through the deck past the free ones,
and in a timed game -2 every 10 seconds and a bonus for a quick win.
Vegas: $52 a game, $5 a card on the foundations, one pass through the deck
(Draw One) or three (Draw Three). See `docs/original.md`.

**The win.** The cards leave the foundations one by one and bounce down
the window, leaving their trail, then it asks to deal again.

**Where things are saved.** The options and the Vegas bank are a small text
file in your user folder for apps: `%APPDATA%\jgordon165\Solitairepack` on
Windows, `~/.local/share/jgordon165/Solitairepack` on Linux,
`~/Library/Application Support/jgordon165/Solitairepack` on macOS.

## Layout

| Path | |
|---|---|
| `src/` | C++ host: window and drawing (`video.cpp`), input, the Lua API (`lua_api.cpp`) |
| `src/formats/` | The NE executable and its resources (`ne.cpp`), bitmaps (`dib.cpp`), dialogs (`dialog.cpp`), menus (`menu.cpp`), setup-disk compression (`expand.cpp`) |
| `scripts/game/` | The rules (`rules.lua`), the cards (`cards.lua`), the table (`table.lua`), the win (`cascade.lua`), the options (`settings.lua`) |
| `scripts/ui/` | Windows 3.1-style drawing (`win31.lua`), the menu bar, dialogs, and the port's own dialog templates |
| `tests/` | Format tests on files built in memory, and the Lua rule and interface tests |
| `re/`, `tools/` | Reverse-engineering workflow: identify, list and extract resources, decompile with Ghidra |
| `docs/formats.md` | NE and resource formats as the port reads them |
| `docs/original.md` | What the port takes from SOL.EXE: layout, rules, scoring |

To also test against your own files, configure with the folder (or setup
disk) in `SOLITAIREPACK_DATA` (the format tests then parse every bitmap,
menu and dialog in SOL.EXE):

```
SOLITAIREPACK_DATA=/path/to/WIN31 cmake -S . -B build && ctest --test-dir build
```

`--seed N` deals the same games every run; `--frames N --screenshot out.bmp`
runs headless and saves the last frame.

## CI and releases

Same pipelines as Tetrispack and Meguarace:

- **CI-build**: every push (and pull requests from forks) builds and tests
  on Linux (GCC and Clang), macOS (Intel and Apple silicon) and Windows
  (x64 and x86). Run it by hand from the Actions tab to pick platforms.
- **code-analysis**: CodeQL (security-and-quality) on `master`.
- **release-linux / release-windows / release-mac-osx**, and
  **release-all** to run them all: build, test, package (no game data) and
  upload the archives as workflow artifacts, plus Windows `.pdb` symbols.
  macOS builds are universal and are signed and notarized when the
  `PROD_MACOS_*` secrets are set on the repository.

## Legal

Windows and Solitaire are trademarks of Microsoft. This project is not
affiliated with Microsoft, and you need your own copy of Windows 3.1's
`SOL.EXE`.
