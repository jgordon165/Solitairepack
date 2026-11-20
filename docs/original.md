# What the port takes from Windows 3.1's Solitaire

Solitaire shipped with Windows 3.0 (1990) and 3.1 (1992), written by Wes
Cherry: `SOL.EXE`, the card art inside it. It's Klondike. None of
the original's code or data is in this repository; the values below are
what the port's own Lua uses (`scripts/game/rules.lua`,
`scripts/game/table.lua`).

Status: the resources below are confirmed against Windows 3.1's SOL.EXE
(from the setup disk's SOL.EX_), the layout against a screenshot of the
original running, and the deal, the shuffle, the win animation and some
measurements against a disassembly of SOL.EXE (addresses as seg:offset in
its code segments; `re/README.md` says how to make one). The items marked **(check)** are still to be
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
| Table colour | RGB 0, 128, 0 (white on a monochrome display), seg1:01c4 |
| Backs | default 54 **(check)**; 56, 63, 64 and 65 animate now and then on the stock (timing **(check)**) |
| Card | 71 x 96 |
| Piles | the stock, the waste and four foundations along the top, seven columns below, evenly spaced: gap = (width - 7 x 71) / 8, the margins as wide as the gaps |
| Wider than 640 | (the port's own) the margins stay 18 px, the stock top left and the last foundation top right, and the gaps between the columns grow evenly |
| Top row | 6 px below the menu bar |
| Columns | 6 px below the top row |
| Column offsets | 3 px per face-down card **(check)**; face-up: card height * 4 / 25 = 15 (seg4:0124), squeezed to fit |
| Empty piles | bitmap 53, its white showing the table |
| Draw Three | the waste's top three fanned a fifth of a card apart, 71 / 5 = 14 px (seg4:00d1) |
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

## The deal

From the disassembly (seg4:0f19, the game's deal): every pile is emptied,
the deck refilled and shuffled, the foundations drawn empty, then the
columns dealt **row by row**: for row 1 to 7, for each column from that row's
own to the seventh, the top card comes off the deck (turned face up first
when it's the row's first column), goes onto the column, and the column
and the deck are redrawn at once. There's no sliding: the cards appear one
after another as fast as the PC can draw them, which on the machines of
the day was visible as a quick card-by-card deal. The port plays the same
order at 35 ms a card (`table.DEAL_ORDER`, `main.lua`); a click or a key
finishes it.

The shuffle (seg5:0e89): five passes, each swapping every card with one
picked by `rand() % count`, using the Microsoft C library's `rand()`
(seg8:01de: `seed = seed * 214013 + 2531011`, `(seed >> 16) & 0x7FFF`),
seeded once from the clock at startup (seg1:01ec). The port's own shuffle
is still its simpler seeded one (**to do**: the deck's starting order, to
reproduce the original's deals exactly).

A timer of 250 ms (seg1:0399) drives the clock and the animated backs. The
back the first time is random: `rand() % 12` (seg1:0b6a).

## The win

From the disassembly (seg4:1439): the foundations' cards leave one at a
time, kings first (rank 13 down to 1, foundations left to right). Each
gets `dx = rand() % 110 - 65` (made -20 if its size is under 15, so mostly
leftwards) and `dy = rand() % 110 - 75`, in tenths of a pixel a step. Each
step draws the card, then `x += dx / 10`, `y += dy / 10`, `dy += 3`, and
when below the floor (the window's height less a card) and falling,
`dy = dy * 8 / -10`: a bounce keeping four fifths of the speed. A card is
done when it's off the left or right edge. The table isn't redrawn, so
every card leaves a trail. A key or a click (seg4:1323 peeks for them)
stops it. Then "Deal Again?". The original ran unthrottled; the port does
90 steps a second (`scripts/game/cascade.lua`).

## The shuffle

The original's is described under The deal. The port shuffles with its own
seeded generator (Fisher-Yates on the C library's example `rand`) so tests
and `--seed` are repeatable.

## The port's own additions

The Klondike mode (Options > Scoring > Klondike) is the Windows 7 mode
with 1, 2 or 4 suits (`scripts/game/klondike.lua`): 2 suits deals spades
and hearts twice over, 1 suit four sets of spades. Columns build down onto
the other colour or the same suit, whatever the number of suits, each run
keeping to one way (by suit, or alternating). Statistics per number of
suits; its own saved game.

The Windows 7 mode (Options > Scoring > Windows 7) is Klondike as the
Vista / 7 Solitaire plays it, in its own rules module
(`scripts/game/win7.lua`, statistics in `win7_stats.lua`): unlimited undo,
hints, automatic turning up of uncovered cards, auto-complete, Restart
this game, statistics, and saving a game in progress to carry on next
time. Its scoring follows the Windows standard listed above, with no limit
on passes.

From the later Windows card games, off the original's path (Options, below
the original's): Auto-flip cards, the Blue-green table (RGB 0,
112, 104) and Card sounds (synthesized in `src/audio.cpp`: no samples are
taken from any Windows game). Smooth cards (`src/formats/upscale.cpp`):
each card bitmap is enlarged 8x with three passes of Scale2x and
area-averaged down to the real pixels per canvas pixel (the zoom times the
display's pixel density, rounded up, at most 4); the canvas is drawn at
that resolution and filtered to the window. Satin table and Card shadows
(`src/formats/procedural.cpp`, `scripts/game/decor.lua`): a tileable
512-pixel grainy satin drawn over the table colour before anything else,
and blurred rounded-rectangle shadows stretched in nine pieces under each
pile (6, 8 px down-right, blur 6: at most 25 px past the cards), between
overlapping cards and under dragged cards. The window can also be resized, with the
table growing to fill it (see Table).
