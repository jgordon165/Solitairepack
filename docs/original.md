# What the port takes from Windows 3.1's Solitaire

Solitaire shipped with Windows 3.0 (1990) and 3.1 (1992), written by Wes
Cherry: `SOL.EXE`, the card art inside it. It's Klondike. None of
the original's code or data is in this repository; the values below are
what the port's own Lua uses (`scripts/game/rules.lua`,
`scripts/game/table.lua`).

Status: the resources below are confirmed against Windows 3.1's SOL.EXE
(from the setup disk's SOL.EX_), and the layout against a screenshot of
the original running. The items marked **(check)** are still to be
confirmed, with a disassembly (`re/README.md`) or more screenshots.

## Resources the port reads

All in SOL.EXE (or the card art in CARDS.DLL, when there is one):

| Resource | Use |
|---|---|
| BITMAP 1-52 | the faces |
| BITMAP 53 | the dotted pattern of an empty pile |
| BITMAP 54-65 | the backs (Game > Deck) |
| BITMAP 67, 68 | the X and the O on an empty stock |
| BITMAP 678-684 | the animated backs' frames (`formats.md`) |
| MENU 1 | the menu bar: Game (Deal, Undo, Deck..., Options..., Exit), Help (Contents, Search for Help on..., How to Use Help, About Solitaire...) |
| DIALOG 101 "Select Card Back" | Game > Deck: twelve owner-drawn buttons, each numbered with its back's bitmap id |
| DIALOG 103 "Options" | Game > Options, its controls matched by their text |
| STRING 100-108 | "Solitaire", "Score: ", "Time: ", "Deal Again?", "Click or press Esc to stop...", "Bonus: ", the credit |

Without SOL.EXE the port uses its own copies of the menus and dialogs
(`scripts/ui/templates.lua`) and draws plain cards.

## Table

| | |
|---|---|
| Table colour | RGB 0, 128, 0 (VGA's dark green) **(check)** |
| Backs | default 54 **(check)**; 56, 63, 64 and 65 animate now and then on the stock (timing **(check)**) |
| Card | 71 x 96 |
| Piles | the stock, the waste and four foundations along the top, seven columns below, evenly spaced: gap = (width - 7 x 71) / 8, the margins as wide as the gaps |
| Wider than 640 | (the port's own) the margins stay 18 px, the stock top left and the last foundation top right, and the gaps between the columns grow evenly |
| Top row | 6 px below the menu bar |
| Columns | 6 px below the top row |
| Column offsets | 3 px per face-down card; 15 per face-up card, squeezed to fit **(check)** |
| Empty piles | bitmap 53, its white showing the table |
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

## The port's own additions

From the later Windows card games, off the original's path (Options, below
the original's): Flip cards automatically, the Blue-green table (RGB 0,
112, 104) and Card sounds (synthesized in `src/audio.cpp`: no samples are
taken from any Windows game). The window can also be resized, with the
table growing to fill it (see Table).
