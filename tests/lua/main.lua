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
        check(s and s:find("back=54", 1, true) ~= nil, "the deck dialog saved the second back (" .. tostring(s) .. ")")
    end
end

sp.log(string.format("lua: %d checks, %d failed", checks, failures))
game = game or {}
local quit_code = failures > 0 and 1 or 0
-- The game script replaced `game`; quit after its first frame either way.
local draw = game.draw
game.draw = function() if draw then pcall(draw) end; sp.quit(quit_code) end
sp.quit(quit_code)
