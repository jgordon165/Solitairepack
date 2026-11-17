# What the port takes from Windows 3.1's Solitaire

Solitaire shipped with Windows 3.0 (1990) and 3.1 (1992), written by Wes
Cherry: `SOL.EXE`, with the card art in `CARDS.DLL`. It's Klondike. None of
the original's code or data is in this repository; the values below are
what the port's own Lua uses (`scripts/game/rules.lua`,
`scripts/game/table.lua`).

Status: written from the game's documented behaviour and its Help. The
items marked **(check)** are still to be confirmed against SOL.EXE 3.1 and
its CARDS.DLL with `tools/identify_exe.py` and a disassembly
(`re/README.md`).

## Resources the port reads

| File | Resource | Use |
|---|---|---|
| CARDS.DLL | BITMAP 1-52 | the faces |
| CARDS.DLL | BITMAP 53 on | the backs (Game > Deck) |
| CARDS.DLL | BITMAP 67, 68 | the X and the O on an empty stock |
| SOL.EXE | MENU 1 | the menu bar (Game, Help) **(check the id)** |
| SOL.EXE | DIALOG "Options" | Game > Options, matched by caption; its controls by their text |
| SOL.EXE | DIALOG "Select Card Back" | Game > Deck; its owner-drawn buttons are the backs, in order **(check)** |

Without SOL.EXE the port uses its own copies of the menus and dialogs
(`scripts/ui/templates.lua`); without CARDS.DLL it draws plain cards.

## Table

| | |
|---|---|
| Table colour | RGB 0, 128, 0 |
| Card | 71 x 96 |
| Piles | the stock, the waste and four foundations along the top, seven columns below, evenly spaced: gap = (width - 7 x 71) / 8 |
| Top row | 5 px below the menu bar **(check)** |
| Columns | 10 px below the top row **(check)** |
| Column offsets | 3 px per face-down card, 15 per face-up card, squeezed to fit **(check)** |
| Draw Three | the waste's top three fanned 12 px apart **(check)** |
| Stacks | the stock and waste get thicker every 10 cards **(check)** |

## Rules

Klondike. Build the columns down in alternating colours; only a King (or a
run from one) goes into an empty column; any face-up card in a column can
be moved with the cards on it. Foundations by suit, Ace to King. A face-down
card at the top of a column is turned over by clicking it.

Mouse: click the stock to turn cards; drag to move; double-click to send a
card to a foundation; right-click to send up every card that can go.
Game > Undo takes back one move.

## Scoring

Standard (Help > Scoring):

| Move | Points |
|---|---|
| Waste to column | 5 |
| Waste or column to foundation | 10 |
| Turn over a column card | 5 |
| Foundation to column | -15 |
| Turn the waste over, Draw One | -100 each pass after the first |
| Turn the waste over, Draw Three | -20 each pass after the third |
| Timed game | -2 every 10 seconds |
| Timed game, won | bonus 700,000 / seconds, if over 30 seconds |

The score doesn't go below 0. The clock starts with the first move.

Vegas: the game costs $52 and each card on a foundation pays $5 (taking one
back costs it). Draw One allows one pass through the stock, Draw Three
three. Keep score carries the total over from deal to deal. None: no score.

**(check)** the exact pass rules and the bonus rounding against SOL.EXE.

## Options (WIN.INI [Solitaire])

Draw One / Draw Three (default Three), Standard / Vegas / None, Timed game,
Status bar, Outline dragging, Keep score (Vegas only), and the back. The
port keeps them in its own settings file, not WIN.INI. Changing the draw,
the scoring or the timer deals a new game.

## The win

The foundations' cards leave one at a time, kings first, each thrown left
or right and bouncing along the bottom of the window, the table not
redrawn, so each card leaves a trail of itself (`scripts/game/cascade.lua`).
Then "Deal again?".

## The shuffle

**(check)** The port shuffles with its own seeded generator (Fisher-Yates
on the C library's example `rand`) so tests and `--seed` are repeatable.
SOL.EXE's own shuffle (it seeds from the clock) is still to be read.
