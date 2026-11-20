-- The win: the foundations' cards thrown off one at a time, kings first,
-- each bouncing along the bottom of the window and leaving a trail of
-- itself. The table isn't redrawn while it runs, so the trails stay; it
-- ends when every card has left the window, or on a click or a key.
--
-- The motion is SOL.EXE's own (docs/original.md), in whole pixels and
-- tenths of a pixel per step:
--   dx = rand() % 110 - 65, made -20 when |dx| < 15 (mostly to the left)
--   dy = rand() % 110 - 75
--   each step: draw the card; x += dx / 10; y += dy / 10; dy += 3;
--   below the floor (the window's height less a card) while falling:
--   dy = dy * 8 / -10 (bounce, keeping 80%); divisions truncate.
-- A card is done when it's off the left or right edge. The original ran as
-- fast as the PC could draw; the port runs STEPS_PER_SECOND steps.

local cards = require("game.cards")

local M = {}
M.__index = M

M.STEPS_PER_SECOND = 90

-- C's integer division, which truncates towards zero.
local function tdiv(a, b)
    local q = a // b
    if q < 0 and q * b ~= a then q = q + 1 end
    return q
end
M.tdiv = tdiv

-- The Microsoft C library's rand(): the generator SOL.EXE uses.
function M.ms_rand(seed)
    local s = seed & 0xFFFFFFFF
    return function()
        s = (s * 214013 + 2531011) & 0xFFFFFFFF
        return (s >> 16) & 0x7FFF
    end
end

-- L: the table layout; g: the won game (its foundations full).
function M.new(L, g, seed)
    local c = setmetatable({}, M)
    c.area = L.area
    c.queue = {}
    -- Kings first, foundation by foundation, then queens, ...
    for rank = 13, 1, -1 do
        for f = 1, 4 do
            local card = g.found[f][rank]
            if card then c.queue[#c.queue + 1] = { card = card, x = L.found[f].x, y = L.found[f].y } end
        end
    end
    c.rand = M.ms_rand(seed or 1)
    c.cur = nil
    c.acc = 0
    c.done = false
    return c
end

function M:launch()
    local nxt = table.remove(self.queue, 1)
    if not nxt then self.done = true; return end
    local dx = self.rand() % 110 - 65
    if math.abs(dx) < 15 then dx = -20 end
    local dy = self.rand() % 110 - 75
    self.cur = { card = nxt.card, x = nxt.x, y = nxt.y, dx = dx, dy = dy }
end

-- Draws the flying card and moves it one step; true when it has left the
-- window.
function M:step()
    local p = self.cur
    local a = self.area
    if not (p.x > a.x - cards.W and p.x < a.x + a.w) then return true end
    cards.draw_face(p.card, p.x, p.y)
    p.x = p.x + tdiv(p.dx, 10)
    p.y = p.y + tdiv(p.dy, 10)
    p.dy = p.dy + 3
    if p.y > a.y + a.h - cards.H and p.dy > 0 then p.dy = tdiv(p.dy * 8, -10) end
    return false
end

-- Advances by dt seconds and draws onto what's already on the canvas.
function M:update_draw(dt)
    if self.done then return end
    sp.clip(self.area.x, self.area.y, self.area.w, self.area.h)
    self.acc = self.acc + dt * M.STEPS_PER_SECOND
    local guard = 0
    while self.acc >= 1 and not self.done and guard < 1000 do
        guard = guard + 1
        if not self.cur then self:launch() end
        if self.cur then
            if self:step() then self.cur = nil else self.acc = self.acc - 1 end
        end
    end
    sp.clip()
end

return M
