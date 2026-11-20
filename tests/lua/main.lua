-- The rules and the interface, tested in the engine (ctest "lua"): the deal,
-- legal moves, both scorings, Draw One / Draw Three passes, the timer and
-- its bonus, Undo, autoplay to a win, then the real game script driven
-- through its input functions. Run with --scripts tests/lua and
-- SOLITAIREPACK_SCRIPTS pointing at scripts/.

local rules = require("game.rules")

local failures, checks = 0, 0
local function check(cond, what)
    checks = checks + 1
    if not cond then
        failures = failures + 1
        sp.log("FAIL: " .. what)
    end
end

local function C(rank, suit, up) return { rank = rank, suit = suit, up = up ~= false } end

-- An empty table to build positions on.
local function blank(opts)
    local g = rules.new(opts or { scoring = "standard", draw = 1 })
    g:deal(1)
    g.stock, g.waste = {}, {}
    g.found = { {}, {}, {}, {} }
    for i = 1, 7 do g.tab[i] = {} end
    g.score = opts and opts.scoring == "vegas" and -52 or 0
    return g
end

-- ---- the deal ------------------------------------------------------------------
do
    local g = rules.new({ draw = 3 }):deal(42)
    check(g:count() == 52, "52 cards dealt")
    for i = 1, 7 do
        check(#g.tab[i] == i, "column " .. i .. " has " .. i .. " cards")
        for k, c in ipairs(g.tab[i]) do check(c.up == (k == i), "only the top of column " .. i .. " is up") end
    end
    check(#g.stock == 24 and #g.waste == 0, "24 in the stock")
    local seen = {}
    local function mark(p) for _, c in ipairs(p) do seen[c.suit * 13 + c.rank] = true end end
    mark(g.stock)
    for i = 1, 7 do mark(g.tab[i]) end
    local n = 0
    for _ in pairs(seen) do n = n + 1 end
    check(n == 52, "every card once")
    local h = rules.new({}):deal(42)
    check(h.tab[7][7].rank == g.tab[7][7].rank and h.tab[7][7].suit == g.tab[7][7].suit, "same seed, same deal")
    local d = rules.new({}):deal(43)
    local same = true
    for i = 1, 24 do
        if d.stock[i].rank ~= g.stock[i].rank or d.stock[i].suit ~= g.stock[i].suit then same = false end
    end
    check(not same, "another seed, another deal")
end

-- ---- legal moves ---------------------------------------------------------------------
do
    local g = blank()
    check(g:can_drop({ C(1, 0) }, "found", 1), "an ace on an empty foundation")
    check(not g:can_drop({ C(2, 0) }, "found", 1), "not a two")
    g.found[1] = { C(1, 0) }
    check(g:can_drop({ C(2, 0) }, "found", 1), "the two of the same suit")
    check(not g:can_drop({ C(2, 3) }, "found", 1), "not another suit")
    check(not g:can_drop({ C(2, 0), C(1, 1) }, "found", 1), "one card at a time")
    check(g:can_drop({ C(13, 2) }, "tab", 1), "a king on an empty column")
    check(not g:can_drop({ C(12, 2) }, "tab", 1), "nothing else on an empty column")
    g.tab[2] = { C(10, 3) }
    check(g:can_drop({ C(9, 2) }, "tab", 2), "red 9 on black 10")
    check(g:can_drop({ C(9, 1), C(8, 0) }, "tab", 2), "a run")
    check(not g:can_drop({ C(9, 0) }, "tab", 2), "not black on black")
    check(not g:can_drop({ C(8, 2) }, "tab", 2), "not two down")
    g.tab[3] = { C(10, 3, false) }
    check(not g:can_drop({ C(9, 2) }, "tab", 3), "not on a face-down card")
    g.tab[4] = { C(5, 0, false), C(9, 2), C(8, 3) }
    check(g:can_pick("tab", 4, 2) and not g:can_pick("tab", 4, 1), "pick up face-up cards only")
end

-- ---- Standard scoring ----------------------------------------------------------------
do
    local g = blank({ scoring = "standard", draw = 1, timed = true })
    g.waste = { C(9, 2) }
    g.tab[1] = { C(10, 3) }
    check(g:move("waste", nil, 1, "tab", 1) and g.score == 5, "waste to column: 5")
    g.waste = { C(1, 0) }
    check(g:move("waste", nil, 1, "found", 1) and g.score == 15, "to a foundation: 10")
    g.tab[2] = { C(4, 1, false) }
    check(g:flip(2) and g.score == 20, "turning a card over: 5")
    check(not g:flip(2), "only face-down cards turn over")
    g.tab[3] = { C(2, 0) }
    check(g:move("tab", 3, 1, "found", 1) and g.score == 30, "column to foundation: 10")
    g.tab[4] = { C(3, 1) }
    check(g:move("found", 1, 2, "tab", 4) and g.score == 15, "foundation back to a column: -15")
    g.score = 10
    g.found[1] = { C(1, 0), C(2, 0) }
    g.tab[5] = { C(3, 2) }
    g:move("found", 1, 2, "tab", 5)
    check(g.score == 0, "never below 0")

    -- Draw One: every pass after the first costs 100.
    local d = blank({ scoring = "standard", draw = 1 })
    d.stock = { C(5, 0, false), C(6, 0, false) }
    d.score = 250
    d:draw(); d:draw()
    check(#d.waste == 2 and #d.stock == 0, "draw one at a time")
    check(d:draw() and #d.stock == 2 and d.score == 150, "turning the waste over: -100")
    -- Draw Three: free for three passes, then -20 each.
    local t = blank({ scoring = "standard", draw = 3 })
    for r = 1, 5 do t.stock[r] = C(r + 4, 3, false) end
    t.score = 100
    t:draw()
    check(#t.waste == 3 and t.waste_shown == 3 and t.waste[3].up, "three at a time, fanned")
    t:draw()
    check(#t.waste == 5 and t.waste_shown == 2, "the last two")
    t:draw(); check(t.score == 100, "2nd pass free")
    t:draw(); t:draw(); t:draw(); check(t.score == 100, "3rd pass free")
    t:draw(); t:draw(); t:draw(); check(t.score == 80, "4th pass: -20")

    -- The timer: -2 every 10 seconds, from the first move.
    local c = blank({ scoring = "standard", draw = 1, timed = true })
    c.score = 20
    c:tick(30)
    check(c.time == 0 and c.score == 20, "the clock waits for the first move")
    c:start()
    for _ = 1, 25 * 60 do c:tick(1 / 60) end
    check(math.floor(c.time + 0.5) == 25 and c.score == 16, "two 10-second penalties")
    local u = blank({ scoring = "standard", draw = 1, timed = false })
    u.score = 20; u:start(); u:tick(60)
    check(u.score == 20, "untimed: no penalty")
end

-- ---- Vegas --------------------------------------------------------------------------------
do
    local g = rules.new({ scoring = "vegas", draw = 3 }):deal(7)
    check(g.score == -52, "Vegas costs $52")
    local h = blank({ scoring = "vegas", draw = 3 })
    h.waste = { C(1, 2) }
    h:move("waste", nil, 1, "found", 1)
    check(h.score == -47, "$5 a card")
    h.tab[1] = { C(2, 3) }
    h:move("found", 1, 1, "tab", 1)
    check(h.score == -52, "taking it back costs the $5")
    -- Draw Three: three passes; Draw One: one.
    local t = blank({ scoring = "vegas", draw = 3 })
    t.stock = { C(5, 0, false) }
    t:draw()
    check(t:draw(), "2nd pass")
    t:draw(); check(t:draw(), "3rd pass")
    t:draw(); check(not t:draw() and t:passes_left() == 0, "no 4th pass")
    local o = blank({ scoring = "vegas", draw = 1 })
    o.stock = { C(5, 0, false) }
    o:draw()
    check(not o:draw(), "Draw One: one pass")
    -- Keep score: the bank carries over.
    local k = rules.new({ scoring = "vegas", keep_score = true, bank = -20 }):deal(3)
    check(k.score == -72 and k:bank_after() == -72, "keep score carries the bank")
    local n = rules.new({ scoring = "none" }):deal(3)
    n.waste = { C(1, 0) }
    n:move("waste", nil, 1, "found", 1)
    check(n.score == 0, "no scoring")
end

-- ---- Auto flip (the later Windows card games) ------------------------------------------------------
do
    local g = blank({ scoring = "standard", draw = 1, auto_flip = true })
    g.tab[1] = { C(5, 0, false), C(9, 2) }
    g.tab[2] = { C(10, 3) }
    check(g:move("tab", 1, 2, "tab", 2), "move uncovering a card")
    check(g.tab[1][1].up and g.flipped == 1, "auto flip turns it up")
    check(g.score == 5, "and scores it as turned over (" .. g.score .. ")")
    check(g:undo() and not g.tab[1][1].up and g.score == 0 and #g.tab[1] == 2, "one Undo takes back both")
    g.auto_flip = false
    g:move("tab", 1, 2, "tab", 2)
    check(not g.tab[1][1].up and g.flipped == nil, "without it, the card waits for a click")
    local f = blank({ scoring = "standard", draw = 1, auto_flip = true })
    f.tab[3] = { C(7, 1, false), C(1, 3) }
    check(f:to_foundation("tab", 3) and f.tab[3][1].up, "also when a card goes up to a foundation")
end

-- ---- the Windows 7 mode (game/win7.lua) -----------------------------------------------------------
do
    local win7 = require("game.win7")
    local function blank7(opts)
        local g = win7.new(opts or { draw = 1, timed = true })
        g:deal(1)
        g.stock, g.waste, g.found = {}, {}, { {}, {}, {}, {} }
        for i = 1, 7 do g.tab[i] = {} end
        return g
    end
    local g = win7.new({ draw = 3 }):deal(42)
    check(g:count() == 52 and #g.stock == 24 and g.win7 and g.scoring == "win7", "win7: the deal")
    local r = rules.new({ draw = 3 }):deal(42)
    check(g.tab[7][7].rank == r.tab[7][7].rank and g.tab[7][7].suit == r.tab[7][7].suit, "win7: a seed deals the same cards")

    local w = blank7()
    w.tab[1] = { C(4, 0, false), C(9, 2) }
    w.tab[2] = { C(10, 3) }
    w.waste = { C(1, 0) }
    check(w:move("tab", 1, 2, "tab", 2) and w.tab[1][1].up and w.score == 5, "win7: a move turns up the card under it, +5")
    check(w:move("waste", nil, 1, "found", 1) and w.score == 15, "win7: to a foundation +10")
    check(w.moves == 2, "win7: moves counted")
    check(w:undo() and w:undo(), "win7: undo, and undo again")
    check(#w.tab[1] == 2 and not w.tab[1][1].up and #w.waste == 1 and w.score == 0, "win7: back to the start")
    check(not w:undo(), "win7: nothing before the deal")
    check(w.moves == 4, "win7: undos count as moves")

    local d1 = blank7({ draw = 1 })
    d1.stock = { C(5, 0, false) }
    d1.score = 300
    d1:draw()
    check(d1:draw() and d1.score == 200, "win7: Draw One, a pass after the first costs 100")
    local d3 = blank7({ draw = 3 })
    d3.stock = { C(5, 0, false) }
    d3.score = 100
    for _ = 1, 2 do d3:draw(); d3:draw() end
    check(d3.score == 100 and d3.passes == 3, "win7: three free passes")
    d3:draw(); d3:draw()
    check(d3.score == 80, "win7: Draw Three, the 4th pass and on cost 20 (" .. d3.score .. ")")
    check(d3:passes_left() == nil, "win7: no limit on passes")

    local t = blank7({ draw = 1, timed = true })
    t.score = 20
    t.tab[1] = { C(9, 2) }
    t.tab[2] = { C(10, 3) }
    t:move("tab", 1, 1, "tab", 2)
    for _ = 1, 20 * 60 do t:tick(1 / 60) end
    check(t.score == 16, "win7: -2 every 10 seconds (" .. t.score .. ")")
    t:undo()
    check(t.score == 16, "win7: undo doesn't give back the time penalties (" .. t.score .. ")")

    -- Hints, best first.
    local h = blank7()
    h.waste = { C(1, 2) }
    h.tab[1] = { C(3, 0, false), C(8, 2) }
    h.tab[2] = { C(9, 3) }
    h.stock = { C(5, 1, false) }
    local list = h:hints()
    check(#list >= 3, "win7: hints found")
    check(list[1].from.kind == "waste" and list[1].to.kind == "found", "win7: first hint, the ace up")
    check(list[2].from.kind == "tab" and list[2].from.index == 1 and list[2].to.index == 2, "win7: then the move that uncovers a card")
    check(list[#list].from.kind == "stock", "win7: the stock last")
    local none = blank7()
    none.tab[1] = { C(13, 0) }
    check(#none:hints() == 0, "win7: no hints when nothing can move")

    -- Auto-complete.
    local a = blank7({ draw = 1, timed = true })
    for s = 0, 3 do for rk = 13, 1, -1 do table.insert(a.tab[s + 1], C(rk, s)) end end
    a:start(); a.time = 140
    local steps = 0
    while a:auto_step() do steps = steps + 1 end
    check(steps == 52 and a.over, "win7: auto-complete finishes it")
    check(a.bonus == 5000, "win7: bonus 700000 / 140 s (" .. a.bonus .. ")")

    -- Saving and carrying on.
    local s = win7.new({ draw = 3, timed = true }):deal(77)
    s:draw(); s:start(); s.time = 33.5
    local back = win7.restore(s:save())
    check(back and back:count() == 52 and back.seed == 77 and back.draw_count == 3, "win7: saved and restored")
    check(back and #back.waste == #s.waste and back.time == 33.5 and back.moves == s.moves, "win7: the same game")
    check(win7.restore("rubbish") == nil and win7.restore(nil) == nil, "win7: not a saved game")

    -- Statistics.
    local st = require("game.win7_stats")
    st.reset()
    st.record(true, 500); st.record(true, 900); st.record(false, 10)
    local v = st.load()
    check(v.played == 3 and v.won == 2 and v.best_win_streak == 2 and v.streak == -1 and v.high_score == 900, "win7: statistics")
    local lines = st.lines()
    check(lines[3] == "Win percentage: 67%" and lines[7] == "Current streak: 1 loss", "win7: statistics shown")
    st.reset()
end

-- ---- the Klondike mode: 1, 2 or 4 suits (game/klondike.lua) ----------------------------------------
do
    local klondike = require("game.klondike")
    local function suits_of(g)
        local n = {}
        local function count(p) for _, c in ipairs(p) do n[c.suit] = (n[c.suit] or 0) + 1 end end
        count(g.stock)
        for i = 1, 7 do count(g.tab[i]) end
        return n
    end
    for _, s in ipairs({ 1, 2, 4 }) do
        local g = klondike.new({ suits = s, draw = 1 }):deal(9)
        check(g:count() == 52 and g.suits == s and g.win7 and g.scoring == "klondike", "klondike " .. s .. ": the deal")
        local n = suits_of(g)
        if s == 1 then check(n[3] == 52, "1 suit: 52 spades") end
        if s == 2 then check(n[3] == 26 and n[2] == 26, "2 suits: 26 spades, 26 hearts") end
        if s == 4 then check(n[0] == 13 and n[1] == 13 and n[2] == 13 and n[3] == 13, "4 suits: the ordinary deck") end
    end
    local function blank_k(s)
        local g = klondike.new({ suits = s, draw = 1, timed = false })
        g:deal(1)
        g.stock, g.waste, g.found = {}, {}, { {}, {}, {}, {} }
        for i = 1, 7 do g.tab[i] = {} end
        return g
    end
    local one = blank_k(1)
    one.tab[1] = { C(10, 3) }
    check(one:can_drop({ C(9, 3) }, "tab", 1), "1 suit: by rank alone (9S on 10S)")
    check(not one:can_drop({ C(8, 3) }, "tab", 1), "1 suit: still one down")
    one.found[1] = { C(1, 3) }
    check(one:can_drop({ C(1, 3) }, "found", 2) and one:can_drop({ C(2, 3) }, "found", 1), "1 suit: aces on any empty foundation")
    one.tab[2] = { C(4, 3, false), C(9, 3) }
    local h = one:hints()
    local found_hint = false
    for _, m in ipairs(h) do
        if m.from.kind == "tab" and m.from.index == 2 and m.to and m.to.index == 1 then found_hint = true end
    end
    check(found_hint, "1 suit: the hints use its rule")
    local two = blank_k(2)
    two.tab[1] = { C(10, 3) }
    check(two:can_drop({ C(9, 2) }, "tab", 1), "2 suits: the other colour (9H on 10S)")
    check(two:can_drop({ C(9, 3) }, "tab", 1), "2 suits: the same suit (9S on 10S)")
    check(not two:can_drop({ C(8, 3) }, "tab", 1), "2 suits: still one down")
    local four = blank_k(4)
    four.tab[1] = { C(10, 3) }
    check(four:can_drop({ C(9, 3) }, "tab", 1), "4 suits: the same suit (9S on 10S)")
    check(four:can_drop({ C(9, 1) }, "tab", 1) and four:can_drop({ C(9, 2) }, "tab", 1), "4 suits: either red")
    check(not four:can_drop({ C(9, 0) }, "tab", 1), "4 suits: not the other black suit (9C on 10S)")
    four.tab[2] = { C(6, 1, false), C(9, 3), C(8, 3) }
    check(four:move("tab", 2, 2, "tab", 1) and #four.tab[1] == 3, "4 suits: a same-suit run moved")
    local hint_ok = false
    local h4 = blank_k(4)
    h4.tab[1] = { C(10, 0) }
    h4.tab[2] = { C(3, 2, false), C(9, 0) }
    for _, m in ipairs(h4:hints()) do
        if m.from.index == 2 and m.to and m.to.index == 1 then hint_ok = true end
    end
    check(hint_ok, "4 suits: hints offer same-suit moves (9C onto 10C)")
    -- Runs move together only when they're one suit (the screenshot:
    -- 7D 6D 5S 4D).
    local run = blank_k(4)
    run.tab[1] = { C(7, 1), C(6, 1), C(5, 3), C(4, 1) }
    check(run:can_pick("tab", 1, 4), "the top card alone")
    check(not run:can_pick("tab", 1, 3) and not run:can_pick("tab", 1, 1), "not 5S 4D, nor the whole mix")
    run.tab[2] = { C(8, 1), C(7, 1), C(6, 1) }
    check(run:can_pick("tab", 2, 1) and run:can_pick("tab", 2, 2), "a one-suit run moves")
    run.tab[3] = { C(9, 3) }
    check(not run:move("tab", 1, 3, "tab", 3) and #run.tab[1] == 4, "the mixed run can't be moved")
    run.tab[4] = { C(8, 0) }
    check(run:move("tab", 2, 2, "tab", 4) and #run.tab[4] == 3, "7D 6D onto 8C")
    -- Any card into an empty column (the screenshot: the 4H), not just Kings;
    -- the foundations still want an Ace.
    local em = blank_k(4)
    check(em:can_drop({ C(4, 2) }, "tab", 5), "a 4 into an empty column")
    check(em:can_drop({ C(9, 1), C(8, 1) }, "tab", 6), "a run into an empty column")
    check(em:can_drop({ C(13, 3) }, "tab", 7), "a King still")
    check(not em:can_drop({ C(4, 2) }, "found", 1), "a foundation still wants an Ace")
    em.waste = { C(5, 0) }
    check(em:move("waste", nil, 1, "tab", 1) and #em.tab[1] == 1, "the waste's 5 into an empty column")
    -- Hints don't offer runs that can't be picked up.
    local hr = blank_k(4)
    hr.tab[1] = { C(2, 0, false), C(7, 1), C(6, 3) }
    hr.tab[2] = { C(8, 0) }
    for _, m in ipairs(hr:hints()) do
        check(not (m.from.kind == "tab" and m.from.index == 1 and m.from.i == 2), "no hint for the mixed 7D 6S")
    end
    local w7r = require("game.win7").new({ draw = 1 })
    w7r:deal(1)
    w7r.tab[1] = { C(7, 1), C(6, 3) }
    check(w7r:can_pick("tab", 1, 1), "Windows 7 mode: alternating runs still move")
    w7r.tab[5] = {}
    check(not w7r:can_drop({ C(4, 2) }, "tab", 5) and w7r:can_drop({ C(13, 2) }, "tab", 5),
          "Windows 7 mode: Kings only into an empty column")
    -- The Windows 7 mode keeps the classic rule.
    local w7 = require("game.win7").new({ draw = 1 })
    w7:deal(1)
    w7.tab[1] = { C(10, 3) }
    check(not w7:can_drop({ C(9, 3) }, "tab", 1), "Windows 7 mode: alternating colours only")
    local s2 = klondike.new({ suits = 2, draw = 3, timed = true }):deal(5)
    s2:draw(); s2:start()
    local back = klondike.restore(s2:save())
    check(back and back.suits == 2 and back.scoring == "klondike" and back:count() == 52, "saved and restored with its suits")
    check(back and back.can_drop == klondike.can_drop, "restored as the Klondike mode")
    check(klondike.stats_key(1) ~= klondike.stats_key(2) and klondike.stats_key(4) ~= "win7_stats",
          "statistics kept apart per number of suits")
    -- The settings keep these modes (an earlier version reset them to Standard).
    sp.storage_write("options", "scoring=win7\nsuits=2\n")
    local st = require("game.settings").load()
    check(st.scoring == "win7" and st.suits == 2, "the Windows 7 mode is remembered")
    sp.storage_write("options", "scoring=klondike\nsuits=3\n")
    st = require("game.settings").load()
    check(st.scoring == "klondike" and st.suits == 4, "the Klondike mode is remembered; a bad suit count isn't")
    sp.storage_write("options", "")
end

-- ---- SOL.EXE's deal order and its win animation's motion -------------------------------------------
do
    local t = require("game.table")
    check(#t.DEAL_ORDER == 28, "28 cards dealt to the columns")
    check(t.DEAL_ORDER[1][1] == 1 and t.DEAL_ORDER[7][1] == 7 and t.DEAL_ORDER[8][1] == 2 and t.DEAL_ORDER[8][2] == 2,
          "row by row, each from its first column to the seventh")
    local per = t.dealt_counts(10)
    check(per[1] == 1 and per[2] == 2 and per[4] == 2 and per[5] == 1, "the first ten: row one, then three of row two")
    local c = require("game.cascade")
    check(c.tdiv(-7, 10) == 0 and c.tdiv(-17, 10) == -1 and c.tdiv(17, 10) == 1 and c.tdiv(-24, -10) == 2,
          "C's truncating division")
    local r = c.ms_rand(1)
    check(r() == 41 and r() == 18467 and r() == 6334, "the Microsoft C rand()")
    -- One card's flight: it falls, bounces off the floor losing a fifth of
    -- its speed, and leaves by a side.
    local L = { area = { x = 0, y = 19, w = 640, h = 402 }, found = { { x = 500, y = 25 } } }
    local g = { found = { { { rank = 1, suit = 0, up = true } }, {}, {}, {} } }
    local cs = c.new(L, g, 5)
    local drawn = 0
    local real = require("game.cards").draw_face
    require("game.cards").draw_face = function() drawn = drawn + 1 end
    cs:launch()
    local p = cs.cur
    check(p.dx <= -15 or p.dx >= 15 or p.dx == -20, "never too slow sideways")
    local bounced, steps = false, 0
    while not cs:step() and steps < 5000 do
        steps = steps + 1
        if p.dy < 0 and p.y > L.area.y + L.area.h - 96 - 30 then bounced = true end
    end
    require("game.cards").draw_face = real
    check(steps < 5000 and bounced and drawn == steps, "it bounces and leaves (" .. steps .. " steps)")
end

-- ---- Undo -----------------------------------------------------------------------------------
do
    local g = blank({ scoring = "standard", draw = 1 })
    g.waste = { C(9, 2) }
    g.tab[1] = { C(10, 3) }
    check(not g:can_undo(), "nothing to undo")
    g:move("waste", nil, 1, "tab", 1)
    check(g:can_undo() and g:undo(), "undo")
    check(#g.waste == 1 and #g.tab[1] == 1 and g.score == 0, "undo puts the card and the score back")
    check(not g:undo(), "one step only")
    g.tab[2] = { C(4, 1, false) }
    g:flip(2); g:undo()
    check(not g.tab[2][1].up, "undo turns a card back over")
end

-- ---- a win: everything face up, autoplay finishes it ----------------------------------------------
do
    local g = blank({ scoring = "standard", draw = 1, timed = true })
    -- Each column: K..A of a suit (four columns), face up.
    for s = 0, 3 do
        g.tab[s + 1] = {}
        for r = 13, 1, -1 do table.insert(g.tab[s + 1], C(r, s)) end
    end
    g:start()
    g.time = 100
    check(g:solved(), "solved: nothing hidden")
    local n = g:autoplay()
    check(n == 52, "autoplay moved all 52 (" .. n .. ")")
    check(g.over, "won")
    check(g.bonus == 7000, "bonus 700000 / 100 s = 7000 (" .. g.bonus .. ")")
    check(g.score == 520 + 7000, "score 520 + bonus (" .. g.score .. ")")
    check(not g:can_undo() and not g:draw(), "nothing more after the win")
end

-- ---- the real game, driven through its input ------------------------------------------------------------
do
    local dir = os.getenv("SOLITAIREPACK_SCRIPTS")
    check(dir ~= nil, "SOLITAIREPACK_SCRIPTS is set")
    if dir then
        sp.seed = 5
        dofile(dir .. "/main.lua")
        local t = require("game.table")
        local ok, err = pcall(function()
            game.update(1 / 60); game.draw()
            -- Click the stock: a card (or three) to the waste.
            game.mousepressed(30, 60, "left", 1); game.mousereleased(30, 60, "left")
            game.draw()
            -- Menus: open Game, then Options; cancel it with Esc.
            game.mousepressed(20, 5, "left", 1); game.mousereleased(20, 5, "left")
            game.draw()
            game.keypressed("o", false)        -- Options... by its letter
            game.draw()
            game.keypressed("escape", false)
            game.draw()
            -- Deck dialog, choose the second back, OK.
            game.keypressed("f10", false); game.keypressed("return", false); game.keypressed("c", false)
            game.draw()
            game.keypressed("right", false); game.keypressed("return", false)
            game.draw()
            -- Keyboard play, right-click autoplay, a new deal, undo.
            game.keypressed("down", false); game.keypressed("space", false); game.keypressed("right", false)
            game.keypressed("space", false)
            game.mousepressed(300, 300, "right", 1)
            game.keypressed("f2", false)
            game.keypressed("backspace", false)
            -- Help and About.
            game.keypressed("f1", false); game.draw(); game.keypressed("return", false)
            game.update(1 / 60); game.draw()
        end)
        check(ok, "the game script runs: " .. tostring(err))
        local s = sp.storage_read("options")
        check(s and s:find("back=55", 1, true) ~= nil, "the deck dialog saved the second back (" .. tostring(s) .. ")")
    end
end

-- ---- moving cards with the mouse, through the game's input -----------------------------------------
-- (A drop used to crash: the drag was cleared before its cards were checked.)
if game and game.current then
    local t = require("game.table")
    local cards = require("game.cards")
    local ok, err = pcall(function()
        game.keypressed("f2", false)
        local g, L = game.current(), game.layout()
        g.stock, g.waste, g.found = {}, {}, { {}, {}, {}, {} }
        for i = 1, 7 do g.tab[i] = {} end
        g.tab[1] = { C(10, 3) }
        g.tab[2] = { C(5, 0, false), C(9, 2), C(8, 3) }
        g.tab[3] = { C(1, 1) }
        g.waste = { C(7, 2) }
        local function centre(kind, index, i)
            local cs = t.pile_cards(L, g, kind, index)
            local r = cs[i or #cs]
            return r.x + cards.W // 2, r.y + 6
        end
        local function drag(fx, fy, tx, ty)
            game.mousepressed(fx, fy, "left", 1)
            game.mousemoved((fx + tx) // 2, (fy + ty) // 2)
            game.mousemoved(tx, ty)
            game.draw()
            game.mousereleased(tx, ty, "left")
            game.update(1 / 60); game.draw()
        end
        -- A run (9H 8S) onto the 10S.
        local fx, fy = centre("tab", 2, 2)
        local tx, ty = centre("tab", 1)
        drag(fx, fy, tx, ty + 15)
        check(#g.tab[1] == 3 and g.tab[1][2].rank == 9 and #g.tab[2] == 1, "drag a run onto a column")
        -- An illegal drop: the 7H back where it was.
        fx, fy = centre("waste")
        tx, ty = centre("tab", 3)
        drag(fx, fy, tx, ty)
        check(#g.waste == 1 and #g.tab[3] == 1, "an illegal drop puts the card back")
        -- Legal from the waste: 7H onto the 8S.
        tx, ty = centre("tab", 1)
        drag(fx, fy, tx, ty)
        check(#g.waste == 0 and #g.tab[1] == 4, "drag from the waste")
        -- The ace to a foundation by dragging, then back off it.
        fx, fy = centre("tab", 3)
        drag(fx, fy, L.found[2].x + 30, L.found[2].y + 30)
        check(#g.found[2] == 1 and #g.tab[3] == 0, "drag an ace to a foundation")
        -- Dropped on nothing at all.
        fx, fy = centre("tab", 1, 4)
        drag(fx, fy, 320, 400)
        check(#g.tab[1] == 4, "a drop on the bare table puts it back")
        -- Turning over and double-clicking.
        fx, fy = centre("tab", 2)
        game.mousepressed(fx, fy, "left", 1); game.mousereleased(fx, fy, "left")
        check(g.tab[2][1].up, "click turns a card over")
        -- One more: the 6C onto the 7H, then Undo.
        g.tab[5] = { C(6, 0) }
        fx, fy = centre("tab", 5)
        tx, ty = centre("tab", 1)
        game.mousepressed(fx, fy, "left", 1); game.mousemoved(tx, ty); game.draw()
        game.mousereleased(tx, ty, "left")
        check(#g.tab[1] == 5 and #g.tab[5] == 0, "drag the 6C onto the 7H")
        game.keypressed("backspace", false)
        check(#g.tab[5] == 1, "undo the drag")
    end)
    check(ok, "moving cards with the mouse: " .. tostring(err))
end

-- ---- the port's own options and the card sounds -----------------------------------------------------
if game and game.current then
    local played = {}
    local real_sfx = sp.sfx
    sp.sfx = function(name) played[#played + 1] = name end
    local ok, err = pcall(function()
        game.keypressed("f2", false)
        local g = game.current()
        g.stock, g.waste, g.found = {}, {}, { {}, {}, {}, {} }
        for i = 1, 7 do g.tab[i] = {} end
        g.tab[1] = { C(10, 3) }
        g.tab[2] = { C(4, 0, false), C(9, 2) }
        g.stock = { C(3, 3, false) }
        local t = require("game.table")
        local cards = require("game.cards")
        local L = game.layout()
        local cs = t.pile_cards(L, g, "tab", 2)
        local from = cs[2]
        local to = t.pile_cards(L, g, "tab", 1)[1]
        game.mousepressed(from.x + 30, from.y + 8, "left", 1)
        game.mousemoved(to.x + 30, to.y + 25)
        game.mousereleased(to.x + 30, to.y + 25, "left")
        check(#g.tab[1] == 2 and g.tab[2][1].up, "a drag uncovers and turns up the 4C (auto flip on by default)")
        check(played[1] == "click" and played[2] == "flip", "a click, then the flip (" .. table.concat(played, ",") .. ")")
        played = {}
        game.mousepressed(L.stock.x + 20, L.stock.y + 20, "left", 1)
        check(played[1] == "deal", "turning the stock deals with its own sound")
        -- Options: the three extra boxes are there; turn the sounds and the
        -- blue-green table off.
        game.keypressed("f10", false); game.keypressed("return", false); game.keypressed("o", false)
        game.keypressed("c", false)        -- &Card sounds
        game.keypressed("g", false)        -- Blue-&green table
        game.keypressed("return", false)   -- OK
        local s = sp.storage_read("options") or ""
        check(s:find("sound=0", 1, true) and s:find("blue_green=0", 1, true), "options saved (" .. s:gsub("\n", " ") .. ")")
        check(cards.TABLE[1] == 0 and cards.TABLE[2] == 128 and cards.TABLE[3] == 0, "the classic green again")
        played = {}
        game.mousepressed(L.stock.x + 20, L.stock.y + 20, "left", 1)
        check(#played == 0, "no sounds once they're off")
        -- And back on.
        game.keypressed("f10", false); game.keypressed("return", false); game.keypressed("o", false)
        game.keypressed("c", false); game.keypressed("g", false); game.keypressed("return", false)
        check(cards.TABLE[2] == 112, "the blue-green table back")
        -- Smooth cards off and on again (the cards are reloaded each time).
        game.keypressed("f10", false); game.keypressed("return", false); game.keypressed("o", false)
        game.keypressed("m", false); game.keypressed("return", false)
        check((sp.storage_read("options") or ""):find("smooth=0", 1, true), "smooth cards off, saved")
        check(cards.smooth == false, "the cards reloaded unsmoothed")
        game.draw()
        game.keypressed("f10", false); game.keypressed("return", false); game.keypressed("o", false)
        game.keypressed("m", false); game.keypressed("return", false)
        check(cards.smooth == true, "and smoothed again")
        game.draw()
        -- Satin and shadows off, then on.
        local decor = require("game.decor")
        check(decor.satin and decor.shadows, "satin and shadows on to start with")
        for _, k in pairs(decor.KINDS) do
            local _, _, _, m = sp.texture("shadow", { w = 71, h = 96, blur = k.blur })
            check(math.max(k.dx, k.dy) + m <= decor.MAX_REACH, "no shadow reaches more than 25 pixels")
        end
        game.keypressed("f10", false); game.keypressed("return", false); game.keypressed("o", false)
        game.keypressed("e", false); game.keypressed("h", false); game.keypressed("return", false)
        check(not decor.satin and not decor.shadows, "satin and shadows off")
        local s2 = sp.storage_read("options") or ""
        check(s2:find("satin=0", 1, true) and s2:find("shadows=0", 1, true), "and saved")
        game.draw()
        game.keypressed("f10", false); game.keypressed("return", false); game.keypressed("o", false)
        game.keypressed("e", false); game.keypressed("h", false); game.keypressed("return", false)
        check(decor.satin and decor.shadows, "and on again")
        game.draw()
    end)
    sp.sfx = real_sfx
    check(ok, "options and sounds: " .. tostring(err))
end

-- ---- the deal plays out card by card ----------------------------------------------------------------
if game and game.current then
    local ok, err = pcall(function()
        game.keypressed("f2", false)
        game.keypressed("y", false)          -- (a Windows 7 game would ask)
        game.draw()
        game.update(0.1); game.draw()        -- a few cards in
        local g = game.current()
        check(g:count() == 52, "all the cards are in play while dealing")
        game.keypressed("escape", false)     -- a key finishes the deal
        game.update(1 / 60); game.draw()
    end)
    check(ok, "the deal animation: " .. tostring(err))
end

-- ---- the Windows 7 mode through the game ------------------------------------------------------------
if game and game.current then
    local st = require("game.win7_stats")
    st.reset()
    local ok, err = pcall(function()
        -- Options > Scoring > Windows 7.
        game.keypressed("f10", false); game.keypressed("return", false); game.keypressed("o", false)
        game.keypressed("w", false); game.keypressed("return", false)
        local g = game.current()
        check(g.win7, "the Windows 7 mode chosen")
        check((sp.storage_read("options") or ""):find("scoring=win7", 1, true), "and saved")
        game.keypressed("h", false)       -- a hint
        game.update(0.5); game.draw()
        game.update(1.0); game.draw()
        -- A move, then a new deal: asked first; No keeps the game.
        game.mousepressed(game.layout().stock.x + 10, game.layout().stock.y + 10, "left", 1)
        check(g.started, "a move made")
        game.keypressed("f2", false)
        game.keypressed("n", false)
        check(game.current() == g, "No: the same game")
        game.keypressed("f2", false)
        game.keypressed("y", false)
        check(game.current() ~= g, "Yes: a new deal")
        check(st.load().played == 1 and st.load().won == 0, "the given-up game counted as a loss")
        -- Leaving saves the game in progress.
        local g2 = game.current()
        game.mousepressed(game.layout().stock.x + 10, game.layout().stock.y + 10, "left", 1)
        game.quit()
        check(#(sp.storage_read("win7_saved") or "") > 50, "leaving saves the game")
        local back = require("game.win7").restore(sp.storage_read("win7_saved"))
        check(back and back.seed == g2.seed and #back.waste == #g2.waste, "the saved game is this one")
        -- Undo all the way, Restart, Statistics.
        game.keypressed("backspace", false)
        check(#g2.waste == 0 and #g2.stock == 24, "undo back to the deal")
        game.keypressed("f10", false); game.keypressed("return", false); game.keypressed("t", false)   -- Statistics
        game.draw()
        game.keypressed("return", false)
        -- The Klondike mode with 2 suits.
        game.keypressed("f10", false); game.keypressed("return", false); game.keypressed("o", false)
        game.keypressed("d", false); game.keypressed("2", false); game.keypressed("return", false)
        local k = game.current()
        check(k.scoring == "klondike" and k.suits == 2, "the Klondike mode, 2 suits")
        game.update(1); game.draw()
        game.mousepressed(game.layout().stock.x + 10, game.layout().stock.y + 10, "left", 1)
        game.quit()
        check(#(sp.storage_read("klondike_saved") or "") > 50, "its game saved under its own name")
        -- 1 suit: a new deal (asked first, as a game is in progress).
        game.keypressed("f10", false); game.keypressed("return", false); game.keypressed("o", false)
        game.keypressed("1", false); game.keypressed("return", false)
        check(game.current().suits == 1, "1 suit")
        check(st.load(require("game.klondike").stats_key(2)).played == 1, "the 2-suit game given up counted there")
        -- Back to Standard.
        game.keypressed("f10", false); game.keypressed("return", false); game.keypressed("o", false)
        game.keypressed("a", false); game.keypressed("return", false)
        check(not game.current().win7, "back to the classic rules")
        st.reset(require("game.klondike").stats_key(1)); st.reset(require("game.klondike").stats_key(2))
        sp.storage_write("klondike_saved", "")
    end)
    check(ok, "the Windows 7 mode: " .. tostring(err))
    st.reset()
    sp.storage_write("win7_saved", "")
end

-- ---- a bigger (or smaller) window: the table spreads out evenly -------------------------------------
if game and game.resize then
    local cards = require("game.cards")
    local ok, err = pcall(function()
        local function check_spread(w, h)
            game.resize(w, h)
            game.update(1 / 60); game.draw()
            local L = game.layout()
            local margin = L.col_x[1] - 0
            local gap = L.col_x[2] - (L.col_x[1] + cards.W)
            check(L.area.w == w, "the table is as wide as the window (" .. w .. ")")
            check(L.stock.y == L.found[1].y and L.stock.y < L.tab_y, "the stock and foundations along the top")
            check(margin <= 18, "the stock stays in the top left corner (" .. margin .. ")")
            if w <= 640 then check(math.abs(gap - margin) <= 1, "up to 640 wide, margins = gaps, as the original") end
            check(L.stock.x == L.col_x[1], "the stock heads the first column")
            check(L.found[4].x == L.col_x[7], "the last foundation heads the last column")
            local right = w - (L.found[4].x + cards.W)
            check(math.abs(right - margin) <= 1, "the foundations stay in the top right corner (" ..
                  w .. ": " .. margin .. " / " .. right .. ")")
            for i = 2, 7 do
                local between = L.col_x[i] - (L.col_x[i - 1] + cards.W)
                check(math.abs(between - gap) <= 1, "even gaps at " .. w .. " (" .. between .. " vs " .. gap .. ")")
            end
            -- The columns may run down to the new bottom edge.
            check(L.area.y + L.area.h <= h, "the table fits the height")
        end
        check_spread(1280, 720)
        check_spread(1920, 1080)
        check_spread(530, 340)
        -- A dialog open across a resize stays centred.
        game.keypressed("f10", false); game.keypressed("return", false); game.keypressed("o", false)
        game.resize(1000, 700)
        game.draw()
        game.keypressed("escape", false)
        check_spread(640, 440)

        -- The mouse pointer follows what it was over.
        local warped
        local real_warp = sp.warp_mouse
        sp.warp_mouse = function(x, y) warped = { x, y } end
        local function pointer_after(x, y, w, h, free)
            warped = nil
            game.mousemoved(x, y)
            game.resize(w, h, free)
            return warped
        end
        local L = game.layout()
        local fx, fy = L.found[4].x + 20, L.found[4].y + 30            -- over the last foundation
        local p = pointer_after(fx, fy, 1280, 600, true)
        local N = game.layout()
        check(p and p[1] == N.found[4].x + 20 and p[2] == N.found[4].y + 30,
              "over the last foundation still (" .. (p and (p[1] .. "," .. p[2]) or "no warp") .. ")")
        local g = game.current()
        local cs = require("game.table").pile_cards(N, g, "tab", 1)
        local top = cs[#cs]
        p = pointer_after(top.x + 10, top.y + 40, 800, 500, true)       -- over column 1's top card
        local M2 = game.layout()
        local cs2 = require("game.table").pile_cards(M2, g, "tab", 1)
        check(p and p[1] == cs2[#cs2].x + 10 and p[2] == cs2[#cs2].y + 40, "over column 1's top card still")
        p = pointer_after(400, 420, 1600, 500, true)                    -- bare table: as far across
        check(p and p[1] == 800 and p[2] == 420, "on the bare table, as far across (" ..
              (p and (p[1] .. "," .. p[2]) or "no warp") .. ")")
        p = pointer_after(400, 420, 900, 500, false)
        check(p == nil, "not moved while a button is held or it's outside the window")
        sp.warp_mouse = real_warp
        game.resize(640, 440, false)
    end)
    check(ok, "resizing: " .. tostring(err))
end

sp.log(string.format("lua: %d checks, %d failed", checks, failures))
game = game or {}
local quit_code = failures > 0 and 1 or 0
-- The game script replaced `game`; quit after its first frame either way.
local draw = game.draw
game.draw = function() if draw then pcall(draw) end; sp.quit(quit_code) end
sp.quit(quit_code)
