-- The port's own touches to the table: a grainy satin over the table
-- colour (and only the table: it's drawn before the cards, and the empty
-- piles' dots let it show through), and the soft shadows the cards cast,
-- for depth. The textures are made by the engine
-- (sp.texture, formats/procedural.cpp); nothing comes from the original.

local cards = require("game.cards")

local M = {}

M.satin = true
M.shadows = true

-- The shadows the cards cast: under a pile, lit from the top left; between
-- overlapping cards, a soft halo; under cards being dragged, lifted a
-- little higher. Each reaches at most 25 pixels past the cards (offset +
-- the blur's margin).
M.KINDS = {
    pile = { blur = 6, alpha = 0.50, dx = 6, dy = 8 },
    overlap = { blur = 1.5, alpha = 0.35, dx = 0, dy = 0 },
    lifted = { blur = 6, alpha = 0.42, dx = 8, dy = 9 },
}
M.MAX_REACH = 25

local satin_tex, satin_size
local shadow_tex = {}

function M.load()
    satin_tex, satin_size = sp.texture("satin", { size = 512, seed = 1992 })
    for name, k in pairs(M.KINDS) do
        local h, w, ht, m = sp.texture("shadow", { w = cards.W, h = cards.H, blur = k.blur, alpha = k.alpha, radius = 3 })
        shadow_tex[name] = { h = h, w = w, ht = ht, m = m }
    end
end

-- The sheen over the table's rectangle x, y, w, h (the table colour is
-- already there), tiled from the canvas origin so pieces line up.
function M.draw_satin(x, y, w, h)
    if not M.satin or not satin_tex then return end
    sp.clip(x, y, w, h)
    local s = satin_size
    for ty = (y // s) * s, y + h - 1, s do
        for tx = (x // s) * s, x + w - 1, s do
            sp.draw(satin_tex, 0, 0, s, s, tx, ty, s, s)
        end
    end
    sp.clip()
end

-- A shadow of `kind` for cards covering x, y, w, h (one card, or a whole
-- pile), stretched from the one-card texture in nine pieces so the corners
-- keep their shape.
function M.shadow(kind, x, y, w, h)
    if not M.shadows then return end
    local t, k = shadow_tex[kind], M.KINDS[kind]
    if not t then return end
    local m = t.m
    local ox, oy = x + k.dx - m, y + k.dy - m
    local dw, dh = w + 2 * m, h + 2 * m
    local c = math.min(m + 6, t.w // 2, t.ht // 2)    -- the corner pieces
    local sx = { 0, c, t.w - c, t.w }
    local sy = { 0, c, t.ht - c, t.ht }
    local dx = { 0, c, dw - c, dw }
    local dy = { 0, c, dh - c, dh }
    for j = 1, 3 do
        for i = 1, 3 do
            local sw, sh = sx[i + 1] - sx[i], sy[j + 1] - sy[j]
            local ww, hh = dx[i + 1] - dx[i], dy[j + 1] - dy[j]
            if sw > 0 and sh > 0 and ww > 0 and hh > 0 then
                sp.draw(t.h, sx[i], sy[j], sw, sh, ox + dx[i], oy + dy[j], ww, hh)
            end
        end
    end
end

return M
