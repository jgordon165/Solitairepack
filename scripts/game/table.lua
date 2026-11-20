-- Where everything sits on the table, drawing it, and finding what's under
-- the pointer. The stock, the waste and the four foundations along the top,
-- the seven columns below, spread evenly across the window (docs/original.md).

local cards = require("game.cards")

local M = {}

M.FACE_DOWN_DY = 3     -- how much of a face-down card shows under the next one
M.FACE_UP_DY = 15      -- and of a face-up one
M.FAN_DX = 12          -- Draw Three: the waste's top cards fanned to the right
M.STACK_EVERY = 10     -- the stock and waste get thicker by a pixel every 10 cards

-- The margin at each side, at most: what the original's even spacing gives
-- at 640 pixels wide. Up to that width the margins and the gaps between the
-- columns are equal, as in the original; wider, the stock stays this close
-- to the top left corner, the last foundation to the top right, and the
-- columns spread out evenly between them.
M.MAX_MARGIN = 18

-- area: the table's rectangle on the canvas (between the menu and status bars).
function M.layout(area)
    local L = { area = area }
    local W, H = cards.W, cards.H
    local margin = math.min((area.w - 7 * W) / 8, M.MAX_MARGIN)
    local gap = (area.w - 2 * margin - 7 * W) / 6
    L.margin, L.gap = margin, gap
    L.col_x = {}
    for i = 1, 7 do L.col_x[i] = area.x + math.floor(margin + (i - 1) * (W + gap) + 0.5) end
    L.top_y = area.y + 6
    L.tab_y = L.top_y + H + 6
    L.stock = { x = L.col_x[1], y = L.top_y }
    L.waste = { x = L.col_x[2], y = L.top_y }
    L.found = {}
    for f = 1, 4 do L.found[f] = { x = L.col_x[3 + f], y = L.top_y } end
    return L
end

-- The thickness offset of a stacked pile of n cards.
local function stack_offset(n)
    local k = math.min(math.max(n - 1, 0) // M.STACK_EVERY, 3)
    return k * 2, k
end

-- A column's per-card offsets, squeezed so the column ends above the
-- table's bottom edge.
function M.column_offsets(L, pile)
    local down, up = M.FACE_DOWN_DY, M.FACE_UP_DY
    local function height()
        local h = 0
        for i = 1, #pile - 1 do h = h + (pile[i].up and up or down) end
        return h + cards.H
    end
    local limit = L.area.y + L.area.h - L.tab_y - 2
    while height() > limit and up > 6 do up = up - 1 end
    while height() > limit and down > 1 do down = down - 1 end
    local ys, y = {}, L.tab_y
    for i = 1, #pile do
        ys[i] = y
        y = y + (pile[i].up and up or down)
    end
    return ys
end

-- Every card's rectangle in a pile, bottom to top: { {x, y, card, i}, ... }
function M.pile_cards(L, g, kind, index)
    local out = {}
    if kind == "tab" then
        local p = g.tab[index]
        local ys = M.column_offsets(L, p)
        for i, c in ipairs(p) do out[i] = { x = L.col_x[index], y = ys[i], card = c, i = i } end
    elseif kind == "stock" or kind == "found" then
        local p = kind == "stock" and g.stock or g.found[index]
        local base = kind == "stock" and L.stock or L.found[index]
        for i, c in ipairs(p) do
            local dx, dy = stack_offset(i)
            out[i] = { x = base.x + dx, y = base.y + dy, card = c, i = i }
        end
    elseif kind == "waste" then
        local p = g.waste
        local fan = g.draw_count == 3 and g.waste_shown or 1
        local first_fanned = #p - fan + 1
        for i, c in ipairs(p) do
            local dx, dy = stack_offset(math.min(i, first_fanned))
            local x = L.waste.x + dx
            if i > first_fanned then x = x + (i - first_fanned) * M.FAN_DX end
            out[i] = { x = x, y = L.waste.y + dy, card = c, i = i }
        end
    end
    return out
end

function M.pile_base(L, kind, index)
    if kind == "stock" then return L.stock.x, L.stock.y end
    if kind == "waste" then return L.waste.x, L.waste.y end
    if kind == "found" then return L.found[index].x, L.found[index].y end
    return L.col_x[index], L.tab_y
end

local function inside(px, py, x, y, w, h)
    return px >= x and py >= y and px < x + w and py < y + h
end

-- What's under (px, py): kind, index, position in the pile (nil on an empty
-- pile's place), or nothing.
function M.hit(L, g, px, py)
    local piles = { { "stock" }, { "waste" } }
    for f = 1, 4 do piles[#piles + 1] = { "found", f } end
    for t = 1, 7 do piles[#piles + 1] = { "tab", t } end
    for _, pl in ipairs(piles) do
        local kind, index = pl[1], pl[2]
        local cs = M.pile_cards(L, g, kind, index)
        for k = #cs, 1, -1 do
            local r = cs[k]
            if inside(px, py, r.x, r.y, cards.W, cards.H) then return kind, index, r.i end
        end
        local bx, by = M.pile_base(L, kind, index)
        if inside(px, py, bx, by, cards.W, cards.H) then return kind, index, nil end
    end
    return nil
end

-- Draws the table. `held` = { kind, index, i } leaves those cards out (they
-- are being dragged); back = the chosen back's bitmap id; frame = the
-- back's animation frame showing on the stock (nil: none).
function M.draw(L, g, back, held, frame)
    local function skip(kind, index, i)
        return held and held.kind == kind and held.index == index and i >= held.i
    end
    -- The stock: its cards, or the mark that says whether it turns over.
    if #g.stock == 0 then
        local left = g:passes_left()
        local can = #g.waste > 0 and (left == nil or left > 0)
        cards.draw_empty(L.stock.x, L.stock.y, can and cards.O_MARK or cards.X_MARK)
    else
        local cs = M.pile_cards(L, g, "stock")
        for k = 1, #cs, M.STACK_EVERY do cards.draw_back(back, cs[k].x, cs[k].y) end
        local t = cs[#cs]
        cards.draw_back(back, t.x, t.y, frame)
    end
    -- The waste: the top few (one, or the fanned three).
    if #g.waste == 0 then
        -- the original leaves the waste's place bare
    else
        local cs = M.pile_cards(L, g, "waste")
        local fan = g.draw_count == 3 and g.waste_shown or 1
        local from = math.max(1, #cs - math.max(fan, 1))
        for k = 1, #cs, M.STACK_EVERY do
            if k < from and not skip("waste", nil, k) then cards.draw(cs[k].card, cs[k].x, cs[k].y, back) end
        end
        for k = from, #cs do
            if not skip("waste", nil, k) then cards.draw(cs[k].card, cs[k].x, cs[k].y, back) end
        end
    end
    for f = 1, 4 do
        local cs = M.pile_cards(L, g, "found", f)
        if #cs == 0 or (skip("found", f, 1)) then cards.draw_empty(L.found[f].x, L.found[f].y) end
        -- Under a dragged top card, the one below it.
        local top = #cs
        if top > 0 and skip("found", f, top) then top = top - 1 end
        if top > 0 then cards.draw(cs[top].card, cs[top].x, cs[top].y, back) end
    end
    for t = 1, 7 do
        local cs = M.pile_cards(L, g, "tab", t)
        if #cs == 0 or skip("tab", t, 1) then cards.draw_empty(L.col_x[t], L.tab_y) end
        for k, r in ipairs(cs) do
            if not skip("tab", t, k) then cards.draw(r.card, r.x, r.y, back) end
        end
    end
end

return M
