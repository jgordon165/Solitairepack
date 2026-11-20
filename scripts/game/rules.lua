-- Klondike as Windows 3.1's Solitaire plays it: the deal, the legal moves,
-- Draw One / Draw Three, Standard / Vegas / no scoring, the timer and its
-- bonus, and a one-step Undo. No drawing or input here, so the tests can
-- play it directly (tests/lua/main.lua). See docs/original.md for where the
-- numbers come from.
--
-- A card is { rank = 1..13, suit = 0..3, up = bool }; suits are in
-- SOL.EXE's bitmap order: 0 clubs, 1 diamonds, 2 hearts, 3 spades.
-- Piles are named { kind, index }: "stock", "waste", "found" 1-4, "tab" 1-7.

local M = {}
M.__index = M

M.SUITS = { [0] = "clubs", "diamonds", "hearts", "spades" }
M.RANKS = { "A", "2", "3", "4", "5", "6", "7", "8", "9", "10", "J", "Q", "K" }

-- Standard scoring (Help > Scoring).
M.SCORE = {
    waste_to_tab = 5,
    to_found = 10,
    turn_over = 5,
    found_to_tab = -15,
    recycle_one = -100,    -- each pass through the deck after the first (Draw One)
    recycle_three = -20,   -- each pass after the third (Draw Three)
    time_penalty = -2,     -- every 10 seconds of a timed game
    bonus = 700000,        -- divided by the seconds a timed game took, if over 30
}
M.VEGAS = { wager = -52, per_card = 5, found_to_tab = -5 }

function M.is_red(card) return card.suit == 1 or card.suit == 2 end

function M.name(card)
    return M.RANKS[card.rank] .. " of " .. M.SUITS[card.suit]
end

-- A small LCG (the one from the C standard's example rand), so a seed deals
-- the same game everywhere. The original's own shuffle is still to be read
-- from SOL.EXE (docs/original.md).
local function rng(seed)
    local s = seed & 0xFFFFFFFF
    return function(n)
        s = (s * 1103515245 + 12345) & 0xFFFFFFFF
        return ((s >> 16) & 0x7FFF) % n
    end
end

-- opts: draw (1 or 3), scoring ("standard", "vegas", "none"), timed,
-- keep_score (Vegas: carry the bank over from deal to deal), bank (the
-- carried-over Vegas score), auto_flip (turn a column's new top card face
-- up as soon as it's uncovered, as the later Windows card games do, rather
-- than waiting for a click).
function M.new(opts)
    opts = opts or {}
    local g = setmetatable({}, M)
    g.draw_count = opts.draw == 1 and 1 or 3
    g.scoring = opts.scoring or "standard"
    g.timed = opts.timed ~= false
    g.keep_score = opts.keep_score or false
    g.bank = opts.bank or 0
    g.auto_flip = opts.auto_flip or false
    return g
end

function M:deal(seed)
    local deck = {}
    for suit = 0, 3 do
        for rank = 1, 13 do deck[#deck + 1] = { rank = rank, suit = suit, up = false } end
    end
    local rand = rng(seed or os.time())
    for i = #deck, 2, -1 do
        local j = rand(i) + 1
        deck[i], deck[j] = deck[j], deck[i]
    end
    self.stock, self.waste = {}, {}
    self.found, self.tab = { {}, {}, {}, {} }, {}
    for i = 1, 7 do self.tab[i] = {} end
    -- Row by row, left to right, as a dealer would: column i gets i cards,
    -- the last one face up.
    local n = #deck
    for row = 1, 7 do
        for col = row, 7 do
            local c = deck[n]; n = n - 1
            c.up = (col == row)
            table.insert(self.tab[col], c)
        end
    end
    for i = n, 1, -1 do table.insert(self.stock, deck[i]) end
    self.waste_shown = 0       -- Draw Three: how many of the waste's top cards are fanned
    self.passes = 1            -- times through the stock (1 = the first)
    self.time = 0
    self.started = false       -- the timer starts with the first move
    self.over = false
    self.bonus = 0
    self.undo_state = nil
    if self.scoring == "vegas" then
        self.score = (self.keep_score and self.bank or 0) + M.VEGAS.wager
    else
        self.score = 0
    end
    return self
end

-- ---- undo -------------------------------------------------------------------

local function copy_pile(p)
    local out = {}
    for i, c in ipairs(p) do out[i] = { rank = c.rank, suit = c.suit, up = c.up } end
    return out
end

function M:snapshot()
    local s = { stock = copy_pile(self.stock), waste = copy_pile(self.waste), found = {}, tab = {},
                score = self.score, passes = self.passes, waste_shown = self.waste_shown }
    for i = 1, 4 do s.found[i] = copy_pile(self.found[i]) end
    for i = 1, 7 do s.tab[i] = copy_pile(self.tab[i]) end
    return s
end

function M:save_undo() self.undo_state = self:snapshot() end

function M:can_undo() return self.undo_state ~= nil and not self.over end

-- One step, as the original's Game > Undo. The score goes back too, except
-- the timer's penalties (time isn't undone).
function M:undo()
    local s = self.undo_state
    if not s or self.over then return false end
    self.stock, self.waste, self.found, self.tab = s.stock, s.waste, s.found, s.tab
    self.score, self.passes, self.waste_shown = s.score, s.passes, s.waste_shown
    self.undo_state = nil
    return true
end

-- ---- scoring ----------------------------------------------------------------

function M:add(points)
    if self.scoring == "none" then return end
    self.score = self.score + points
    if self.scoring == "standard" and self.score < 0 then self.score = 0 end
end

function M:start()
    self.started = true
end

-- Advances the clock; a timed Standard game loses 2 points every 10 seconds.
function M:tick(dt)
    if not self.started or self.over then return end
    local before = math.floor(self.time / 10)
    self.time = self.time + dt
    local after = math.floor(self.time / 10)
    if self.timed and self.scoring == "standard" and after > before then
        self:add(M.SCORE.time_penalty * (after - before))
    end
end

-- ---- piles ------------------------------------------------------------------

function M:pile(kind, index)
    if kind == "stock" then return self.stock end
    if kind == "waste" then return self.waste end
    if kind == "found" then return self.found[index] end
    if kind == "tab" then return self.tab[index] end
end

function M:top(kind, index)
    local p = self:pile(kind, index)
    return p and p[#p]
end

-- How many more times the waste can go back into the stock (nil: no limit).
function M:passes_left()
    if self.scoring ~= "vegas" then return nil end
    local limit = self.draw_count == 3 and 3 or 1
    return math.max(0, limit - self.passes)
end

-- Clicking the stock: turn over one or three cards, or, when it's empty,
-- put the waste back (when the rules allow another pass).
function M:draw()
    if self.over then return false end
    if #self.stock == 0 then
        if #self.waste == 0 then return false end
        local left = self:passes_left()
        if left and left <= 0 then return false end
        self:start()
        self:save_undo()
        for i = #self.waste, 1, -1 do
            local c = self.waste[i]
            c.up = false
            table.insert(self.stock, c)
        end
        self.waste = {}
        self.waste_shown = 0
        self.passes = self.passes + 1
        if self.scoring == "standard" then
            if self.draw_count == 1 then self:add(M.SCORE.recycle_one)
            elseif self.passes > 3 then self:add(M.SCORE.recycle_three) end
        end
        return true
    end
    self:start()
    self:save_undo()
    local n = math.min(self.draw_count, #self.stock)
    for _ = 1, n do
        local c = table.remove(self.stock)
        c.up = true
        table.insert(self.waste, c)
    end
    self.waste_shown = n
    return true
end

-- The face-up run that can be picked up from a pile starting at position i:
-- any face-up card of a tableau column (with everything on it), or just the
-- top card of the waste or a foundation.
function M:can_pick(kind, index, i)
    local p = self:pile(kind, index)
    if not p or i < 1 or i > #p or not p[i].up then return false end
    if kind == "tab" then return true end
    if kind == "waste" or kind == "found" then return i == #p end
    return false
end

-- Can `cards` (a run, bottom card first) go on pile (kind, index)?
function M:can_drop(cards, kind, index)
    local first = cards[1]
    if not first then return false end
    local p = self:pile(kind, index)
    if kind == "found" then
        if #cards ~= 1 then return false end
        local t = p[#p]
        if not t then return first.rank == 1 end
        return t.suit == first.suit and first.rank == t.rank + 1
    elseif kind == "tab" then
        local t = p[#p]
        if not t then return first.rank == 13 end
        return t.up and M.is_red(t) ~= M.is_red(first) and first.rank == t.rank - 1
    end
    return false
end

-- Moves the cards from position i of (from_kind, from_index) onto
-- (to_kind, to_index), scoring it. Returns true if it was legal.
function M:move(from_kind, from_index, i, to_kind, to_index)
    if self.over then return false end
    if from_kind == to_kind and from_index == to_index then return false end
    if not self:can_pick(from_kind, from_index, i) then return false end
    local src = self:pile(from_kind, from_index)
    local run = {}
    for k = i, #src do run[#run + 1] = src[k] end
    if not self:can_drop(run, to_kind, to_index) then return false end
    self:start()
    self:save_undo()
    for _ = i, #src do table.remove(src) end
    local dst = self:pile(to_kind, to_index)
    for _, c in ipairs(run) do table.insert(dst, c) end
    -- Auto flip: the card uncovered in the column turns up, scored as a
    -- turned-over card; Undo puts both back in one step.
    self.flipped = nil
    if self.auto_flip and from_kind == "tab" and #src > 0 and not src[#src].up then
        src[#src].up = true
        self.flipped = from_index
        if self.scoring == "standard" then self:add(M.SCORE.turn_over) end
    end
    if from_kind == "waste" then
        self.waste_shown = math.max(0, self.waste_shown - 1)
        if self.waste_shown == 0 and #self.waste > 0 then self.waste_shown = 1 end
    end
    if self.scoring == "vegas" then
        if to_kind == "found" then self:add(M.VEGAS.per_card) end
        if from_kind == "found" then self:add(M.VEGAS.found_to_tab) end
    else
        if to_kind == "found" then
            self:add(M.SCORE.to_found)
        elseif from_kind == "waste" and to_kind == "tab" then
            self:add(M.SCORE.waste_to_tab)
        elseif from_kind == "found" and to_kind == "tab" then
            self:add(M.SCORE.found_to_tab)
        end
    end
    self:check_won()
    return true
end

-- Turning over the face-down card at the top of a column.
function M:flip(index)
    local p = self.tab[index]
    local t = p and p[#p]
    if self.over or not t or t.up then return false end
    self:start()
    self:save_undo()
    t.up = true
    if self.scoring == "standard" then self:add(M.SCORE.turn_over) end
    return true
end

-- Double-click: the card at the top of a pile to the foundation it fits.
-- Returns the foundation's index, or nil.
function M:to_foundation(kind, index)
    local p = self:pile(kind, index)
    if not p or #p == 0 or not p[#p].up or kind == "found" then return nil end
    for f = 1, 4 do
        if self:can_drop({ p[#p] }, "found", f) then
            if self:move(kind, index, #p, "found", f) then return f end
        end
    end
    return nil
end

-- Right-click: every card that can go up to the foundations, repeatedly.
-- Returns how many moved.
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

function M:check_won()
    for f = 1, 4 do
        if #self.found[f] < 13 then return false end
    end
    self.over = true
    self.undo_state = nil
    if self.timed and self.scoring == "standard" and self.time > 30 then
        self.bonus = math.floor(M.SCORE.bonus / math.floor(self.time))
        self:add(self.bonus)
    end
    return true
end

-- Every card is face up and the stock and waste are empty: the rest is
-- mechanical, so autoplay can finish it.
function M:solved()
    if #self.stock > 0 or #self.waste > 0 then return false end
    for i = 1, 7 do
        for _, c in ipairs(self.tab[i]) do
            if not c.up then return false end
        end
    end
    return true
end

-- What the Vegas bank should hold after this deal, for Keep score.
function M:bank_after()
    if self.scoring ~= "vegas" or not self.keep_score then return 0 end
    return self.score
end

-- Counts every card in play; 52 when nothing is lost (for the tests).
function M:count()
    local n = #self.stock + #self.waste
    for i = 1, 4 do n = n + #self.found[i] end
    for i = 1, 7 do n = n + #self.tab[i] end
    return n
end

return M
