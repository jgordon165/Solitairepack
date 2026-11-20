-- Klondike as the Windows Vista / 7 Solitaire plays it: a separate mode
-- (Options > Scoring > Windows 7) with its own logic, not the 3.1 rules in
-- rules.lua. What it adds to the classic game:
--
--   * Undo as far back as the deal (the old game undoes one move).
--   * Hints: the next useful move, best first (game.hint).
--   * Cards uncovered in a column always turn up by themselves.
--   * Auto-complete: once every card is face up and the stock is used up,
--     the rest goes up to the foundations on its own (game.auto_step).
--   * Restart this game: the same deal again.
--   * Saving a game in progress and carrying on next time (save/restore).
--   * A move counter; statistics live in win7_stats.lua.
--
-- Scoring is the Windows standard: 10 to a foundation, 5 from the waste to
-- a column, 5 for a card turned over, -15 back off a foundation, -2 every
-- 10 seconds when timed, a bonus of 700,000 / seconds for a win taking
-- over 30 seconds; turning the waste over is free on the first pass with
-- Draw One (then -100 a pass) and the first three with Draw Three (then
-- -20). The score never goes below 0.
--
-- It offers the same functions and fields as rules.lua (stock, waste, found,
-- tab, move, draw, flip, ...), so the table, the input and the sounds work
-- with either. Cards: { rank = 1..13, suit = 0..3, up = bool }.

local M = {}
M.__index = M

M.SCORE = {
    waste_to_tab = 5, to_found = 10, turn_over = 5, found_to_tab = -15,
    recycle_one = -100, recycle_three = -20, time_penalty = -2, bonus = 700000,
}

local function red(c) return c.suit == 1 or c.suit == 2 end

local function copy_cards(p)
    local out = {}
    for i, c in ipairs(p) do out[i] = { rank = c.rank, suit = c.suit, up = c.up } end
    return out
end

-- The same small generator as the classic mode, so a seed is a seed.
local function rng(seed)
    local s = seed & 0xFFFFFFFF
    return function(n)
        s = (s * 1103515245 + 12345) & 0xFFFFFFFF
        return ((s >> 16) & 0x7FFF) % n
    end
end

-- opts: draw (1 or 3), timed.
function M.new(opts)
    opts = opts or {}
    local g = setmetatable({}, M)
    g.draw_count = opts.draw == 1 and 1 or 3
    g.timed = opts.timed ~= false
    g.scoring = "win7"
    g.auto_flip = true     -- always, in this mode
    g.win7 = true
    return g
end

-- The 52 cards before shuffling (a mode can deal a different deck).
function M:new_deck()
    local deck = {}
    for suit = 0, 3 do
        for rank = 1, 13 do deck[#deck + 1] = { rank = rank, suit = suit, up = false } end
    end
    return deck
end

function M:deal(seed)
    self.seed = seed or os.time()
    local deck = self:new_deck()
    local rand = rng(self.seed)
    for i = #deck, 2, -1 do
        local j = rand(i) + 1
        deck[i], deck[j] = deck[j], deck[i]
    end
    self.stock, self.waste, self.found, self.tab = {}, {}, { {}, {}, {}, {} }, {}
    for i = 1, 7 do self.tab[i] = {} end
    local n = #deck
    for row = 1, 7 do
        for col = row, 7 do
            local c = deck[n]; n = n - 1
            c.up = (col == row)
            table.insert(self.tab[col], c)
        end
    end
    for i = n, 1, -1 do table.insert(self.stock, deck[i]) end
    self.waste_shown, self.passes = 0, 1
    self.score, self.time, self.bonus, self.moves = 0, 0, 0, 0
    self.started, self.over = false, false
    self.history = {}
    self.flipped = nil
    return self
end

-- The same deal from the start (Game > Restart this game).
function M:restart() return self:deal(self.seed) end

-- ---- state, undo and saving --------------------------------------------------

function M:state()
    local s = { stock = copy_cards(self.stock), waste = copy_cards(self.waste), found = {}, tab = {},
                waste_shown = self.waste_shown, passes = self.passes, score = self.score, moves = self.moves }
    for i = 1, 4 do s.found[i] = copy_cards(self.found[i]) end
    for i = 1, 7 do s.tab[i] = copy_cards(self.tab[i]) end
    return s
end

function M:set_state(s)
    self.stock, self.waste = copy_cards(s.stock), copy_cards(s.waste)
    self.found, self.tab = {}, {}
    for i = 1, 4 do self.found[i] = copy_cards(s.found[i]) end
    for i = 1, 7 do self.tab[i] = copy_cards(s.tab[i]) end
    self.waste_shown, self.passes, self.score, self.moves = s.waste_shown, s.passes, s.score, s.moves
end

local function push(self)
    self.history[#self.history + 1] = self:state()
    if #self.history > 2000 then table.remove(self.history, 1) end
end

function M:can_undo() return #self.history > 0 and not self.over end

-- Back one move, as many times as there are moves. The score of the move
-- comes back off; the time doesn't go back, and neither do its penalties
-- (tick takes them off the saved scores too). An undo counts as a move.
function M:undo()
    if not self:can_undo() then return false end
    local moves = self.moves
    self:set_state(table.remove(self.history))
    self.moves = moves + 1
    self.flipped = nil
    return true
end

-- A game in progress as text, for saving: the seed, the clock, and the
-- piles ("ranks suits face" per card).
local function enc_pile(p)
    local t = {}
    for _, c in ipairs(p) do t[#t + 1] = string.format("%d.%d.%d", c.rank, c.suit, c.up and 1 or 0) end
    return table.concat(t, ",")
end

local function dec_pile(s)
    local p = {}
    for r, su, u in (s or ""):gmatch("(%d+)%.(%d+)%.(%d)") do
        p[#p + 1] = { rank = tonumber(r), suit = tonumber(su), up = u == "1" }
    end
    return p
end

function M:save()
    local lines = {
        "seed=" .. self.seed, "draw=" .. self.draw_count, "timed=" .. (self.timed and 1 or 0),
        "suits=" .. (self.suits or 4),
        "time=" .. string.format("%.2f", self.time), "score=" .. self.score, "moves=" .. self.moves,
        "passes=" .. self.passes, "shown=" .. self.waste_shown,
        "stock=" .. enc_pile(self.stock), "waste=" .. enc_pile(self.waste),
    }
    for i = 1, 4 do lines[#lines + 1] = "found" .. i .. "=" .. enc_pile(self.found[i]) end
    for i = 1, 7 do lines[#lines + 1] = "tab" .. i .. "=" .. enc_pile(self.tab[i]) end
    return table.concat(lines, "\n") .. "\n"
end

-- A saved game back (nil if the text isn't one, or doesn't hold 52 cards).
-- class: the mode to make it (a mode built on this one, such as
-- klondike.lua, passes itself).
function M.restore(text, class)
    class = class or M
    if not text then return nil end
    local v = {}
    for k, val in text:gmatch("([%w]+)=([^\n]*)") do v[k] = val end
    if not v.seed then return nil end
    local g = class.new({ draw = tonumber(v.draw), timed = v.timed == "1", suits = tonumber(v.suits) })
    g.seed = tonumber(v.seed)
    g.stock, g.waste, g.found, g.tab = dec_pile(v.stock), dec_pile(v.waste), {}, {}
    for i = 1, 4 do g.found[i] = dec_pile(v["found" .. i]) end
    for i = 1, 7 do g.tab[i] = dec_pile(v["tab" .. i]) end
    g.time, g.score, g.moves = tonumber(v.time) or 0, tonumber(v.score) or 0, tonumber(v.moves) or 0
    g.passes, g.waste_shown = tonumber(v.passes) or 1, tonumber(v.shown) or 0
    g.bonus, g.over, g.history, g.started = 0, false, {}, true
    if g:count() ~= 52 then return nil end
    return g
end

-- ---- the clock and the score ------------------------------------------------------

local function add(self, pts)
    self.score = math.max(0, self.score + pts)
end

function M:start() self.started = true end

function M:tick(dt)
    if not self.started or self.over then return end
    local before = math.floor(self.time / 10)
    self.time = self.time + dt
    local after = math.floor(self.time / 10)
    if self.timed and after > before then
        add(self, M.SCORE.time_penalty * (after - before))
        -- Keep the penalty through undos: every saved score pays it too.
        for _, s in ipairs(self.history) do s.score = math.max(0, s.score + M.SCORE.time_penalty * (after - before)) end
    end
end

-- ---- piles and moves -----------------------------------------------------------------

function M:pile(kind, index)
    if kind == "stock" then return self.stock end
    if kind == "waste" then return self.waste end
    if kind == "found" then return self.found[index] end
    if kind == "tab" then return self.tab[index] end
end

function M:passes_left() return nil end   -- no limit; the score pays for passes

function M:can_pick(kind, index, i)
    local p = self:pile(kind, index)
    if not p or not p[i] or not p[i].up then return false end
    if kind == "tab" then return true end
    return (kind == "waste" or kind == "found") and i == #p
end

function M:can_drop(cards, kind, index)
    local first = cards[1]
    if not first then return false end
    local p = self:pile(kind, index)
    local t = p and p[#p]
    if kind == "found" then
        if #cards ~= 1 then return false end
        if not t then return first.rank == 1 end
        return t.suit == first.suit and first.rank == t.rank + 1
    elseif kind == "tab" then
        if not t then return first.rank == 13 end
        return t.up and red(t) ~= red(first) and first.rank == t.rank - 1
    end
    return false
end

-- Turns up the top card of a column if it's face down; true if it did.
local function reveal(self, index)
    local p = self.tab[index]
    local t = p[#p]
    if t and not t.up then
        t.up = true
        add(self, M.SCORE.turn_over)
        self.flipped = index
        return true
    end
    return false
end

function M:move(from_kind, from_index, i, to_kind, to_index)
    if self.over or (from_kind == to_kind and from_index == to_index) then return false end
    if not self:can_pick(from_kind, from_index, i) then return false end
    local src = self:pile(from_kind, from_index)
    local run = {}
    for k = i, #src do run[#run + 1] = src[k] end
    if not self:can_drop(run, to_kind, to_index) then return false end
    self:start()
    push(self)
    self.flipped = nil
    for _ = i, #src do table.remove(src) end
    local dst = self:pile(to_kind, to_index)
    for _, c in ipairs(run) do dst[#dst + 1] = c end
    if from_kind == "waste" then
        self.waste_shown = math.max(1, self.waste_shown - 1)
        if #self.waste == 0 then self.waste_shown = 0 end
    end
    if to_kind == "found" then add(self, M.SCORE.to_found)
    elseif from_kind == "waste" then add(self, M.SCORE.waste_to_tab)
    elseif from_kind == "found" then add(self, M.SCORE.found_to_tab) end
    if from_kind == "tab" then reveal(self, from_index) end
    self.moves = self.moves + 1
    self:check_won()
    return true
end

-- A face-down top card only stays face down in a saved game from before;
-- clicking it turns it up.
function M:flip(index)
    if self.over then return false end
    local p = self.tab[index]
    local t = p and p[#p]
    if not t or t.up then return false end
    self:start()
    push(self)
    reveal(self, index)
    self.moves = self.moves + 1
    return true
end

function M:draw()
    if self.over then return false end
    if #self.stock == 0 then
        if #self.waste == 0 then return false end
        self:start()
        push(self)
        for k = #self.waste, 1, -1 do
            local c = self.waste[k]
            c.up = false
            self.stock[#self.stock + 1] = c
        end
        self.waste, self.waste_shown = {}, 0
        self.passes = self.passes + 1
        if self.draw_count == 1 then add(self, M.SCORE.recycle_one)
        elseif self.passes > 3 then add(self, M.SCORE.recycle_three) end
        self.moves = self.moves + 1
        return true
    end
    self:start()
    push(self)
    local n = math.min(self.draw_count, #self.stock)
    for _ = 1, n do
        local c = table.remove(self.stock)
        c.up = true
        self.waste[#self.waste + 1] = c
    end
    self.waste_shown = n
    self.moves = self.moves + 1
    return true
end

function M:to_foundation(kind, index)
    local p = self:pile(kind, index)
    if not p or #p == 0 or kind == "found" or not p[#p].up then return nil end
    for f = 1, 4 do
        if self:can_drop({ p[#p] }, "found", f) and self:move(kind, index, #p, "found", f) then return f end
    end
    return nil
end

function M:autoplay()
    local moved = 0
    repeat
        local any = false
        if self:to_foundation("waste") then any = true; moved = moved + 1 end
        for i = 1, 7 do
            if self:to_foundation("tab", i) then any = true; moved = moved + 1 end
        end
    until not any or self.over
    return moved
end

function M:solved()
    if #self.stock > 0 or #self.waste > 0 then return false end
    for i = 1, 7 do
        for _, c in ipairs(self.tab[i]) do if not c.up then return false end end
    end
    return true
end

-- Auto-complete, one card at a time (the game calls it on a timer): the
-- lowest card that can go up. Returns true while there was one.
function M:auto_step()
    if self.over or not self:solved() then return false end
    local best, bi
    for i = 1, 7 do
        local p = self.tab[i]
        local t = p[#p]
        if t then
            for f = 1, 4 do
                if self:can_drop({ t }, "found", f) and (not best or t.rank < best.rank) then best, bi = t, i end
            end
        end
    end
    if not best then return false end
    return self:to_foundation("tab", bi) ~= nil
end

function M:check_won()
    for f = 1, 4 do if #self.found[f] < 13 then return false end end
    self.over = true
    self.history = {}
    if self.timed and self.time > 30 then
        self.bonus = math.floor(M.SCORE.bonus / math.floor(self.time))
        add(self, self.bonus)
    end
    return true
end

function M:count()
    local n = #self.stock + #self.waste
    for i = 1, 4 do n = n + #self.found[i] end
    for i = 1, 7 do n = n + #self.tab[i] end
    return n
end

function M:bank_after() return 0 end

-- ---- hints ------------------------------------------------------------------------------

-- Every useful move, best first, as { from = { kind, index, i }, to = { kind,
-- index } } (to = nil: turn the stock). The order: a card up to a
-- foundation; a column move that uncovers a face-down card (or empties a
-- column for a King waiting elsewhere); the waste's card to a column; then
-- the stock. Moves that only shuffle a run between columns, or put a King
-- that's already at the bottom of a column into another empty one, aren't
-- offered.
function M:hints()
    local list = {}
    local function add_hint(fk, fi, i, tk, ti, rank)
        list[#list + 1] = { from = { kind = fk, index = fi, i = i }, to = tk and { kind = tk, index = ti }, rank = rank }
    end
    -- To a foundation.
    if #self.waste > 0 then
        for f = 1, 4 do
            if self:can_drop({ self.waste[#self.waste] }, "found", f) then add_hint("waste", nil, #self.waste, "found", f, 1); break end
        end
    end
    for t = 1, 7 do
        local p = self.tab[t]
        if #p > 0 and p[#p].up then
            for f = 1, 4 do
                if self:can_drop({ p[#p] }, "found", f) then add_hint("tab", t, #p, "found", f, 1); break end
            end
        end
    end
    -- Between columns: the whole face-up run of a column.
    local king_waiting = (#self.waste > 0 and self.waste[#self.waste].rank == 13)
    for t = 1, 7 do
        local p = self.tab[t]
        local first
        for k = 1, #p do if p[k].up then first = k; break end end
        if first then
            local run = {}
            for k = first, #p do run[#run + 1] = p[k] end
            for d = 1, 7 do
                if d ~= t and self:can_drop(run, "tab", d) then
                    local uncovers = first > 1
                    local empty_target = #self.tab[d] == 0
                    if uncovers and not (empty_target and first == 1) then
                        add_hint("tab", t, first, "tab", d, 2)
                        break
                    elseif first == 1 and not empty_target and king_waiting then
                        add_hint("tab", t, first, "tab", d, 3)   -- frees a column for the waste's King
                        break
                    end
                end
            end
        end
    end
    -- The waste to a column.
    if #self.waste > 0 then
        for d = 1, 7 do
            if self:can_drop({ self.waste[#self.waste] }, "tab", d) then add_hint("waste", nil, #self.waste, "tab", d, 4); break end
        end
    end
    -- The stock.
    if #self.stock > 0 or #self.waste > 0 then add_hint("stock", nil, nil, nil, nil, 5) end
    table.sort(list, function(a, b) return a.rank < b.rank end)
    return list
end

return M
