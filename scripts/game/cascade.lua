-- The win: the foundations' cards thrown off one at a time, kings first,
-- each bouncing along the bottom of the window and leaving a trail of
-- itself, as Windows 3.1's Solitaire does. The table isn't redrawn while it
-- runs, so the trails stay; it ends when every card has left the window.

local cards = require("game.cards")

local M = {}
M.__index = M

M.GRAVITY = 0.6          -- pixels per step per step
M.BOUNCE = 0.75          -- how much of its speed a card keeps off the floor
M.STEPS_PER_SECOND = 60

-- L: the table layout; g: the won game (its foundations full).
function M.new(L, g, seed)
    local c = setmetatable({}, M)
    c.area = L.area
    c.queue = {}
    -- Kings first, foundation by foundation, then queens, ...
    for rank = 13, 1, -1 do
        for f = 1, 4 do
            local card = g.found[f][rank]
            if card then
                c.queue[#c.queue + 1] = { card = card, below = g.found[f][rank - 1], x = L.found[f].x, y = L.found[f].y }
            end
        end
    end
    local s = (seed or 1) & 0x7FFFFFFF
    c.rand = function(n)
        s = (s * 1103515245 + 12345) & 0x7FFFFFFF
        return (s >> 16) % n
    end
    c.cur = nil
    c.acc = 0
    c.done = false
    c.first = true
    return c
end

function M:launch()
    local nxt = table.remove(self.queue, 1)
    if not nxt then self.done = true; return end
    local vx = self.rand(5) + 2
    if self.rand(2) == 0 then vx = -vx end
    -- Mostly towards the side with room, like the original.
    -- The foundation now shows the card underneath (or its empty place).
    if nxt.below then cards.draw_face(nxt.below, nxt.x, nxt.y) else
        sp.fill(nxt.x, nxt.y, cards.W, cards.H, cards.TABLE[1], cards.TABLE[2], cards.TABLE[3])
        require("game.decor").draw_satin(nxt.x, nxt.y, cards.W, cards.H)
        cards.draw_empty(nxt.x, nxt.y)
    end
    self.cur = { card = nxt.card, x = nxt.x, y = nxt.y, vx = vx, vy = -(self.rand(4) * 2) }
end

-- Moves the flying card one step; true when it has left the window.
function M:step()
    local p = self.cur
    p.vy = p.vy + M.GRAVITY
    p.x = p.x + p.vx
    p.y = p.y + p.vy
    local floor = self.area.y + self.area.h - cards.H
    if p.y > floor then
        p.y = floor
        p.vy = -p.vy * M.BOUNCE
        if math.abs(p.vy) < 1 then p.vy = 0 end
    end
    return p.x + cards.W < self.area.x or p.x > self.area.x + self.area.w
end

-- Advances by dt seconds and draws onto what's already on the canvas.
function M:update_draw(dt)
    if self.done then return end
    sp.clip(self.area.x, self.area.y, self.area.w, self.area.h)
    self.acc = self.acc + dt * M.STEPS_PER_SECOND
    while self.acc >= 1 and not self.done do
        self.acc = self.acc - 1
        if not self.cur then
            self:launch()
            sp.clip(self.area.x, self.area.y, self.area.w, self.area.h)   -- (the satin lifts it)
        end
        if self.cur then
            local gone = self:step()
            cards.draw_face(self.cur.card, math.floor(self.cur.x), math.floor(self.cur.y))
            if gone then self.cur = nil end
        end
    end
    sp.clip()
end

return M
