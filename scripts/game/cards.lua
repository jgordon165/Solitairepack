-- The card art, from the player's CARDS.DLL (Windows 3.1): 71 x 96 bitmaps,
-- faces 1-52 (clubs A-K, diamonds, hearts, spades), the backs from 53, and
-- the marks drawn on an empty stock: 67 the X (no more passes) and 68 the O
-- (click to turn the waste over). Without CARDS.DLL the port draws plain
-- cards of its own. See docs/original.md.

local M = {}

M.W, M.H = 71, 96
M.FIRST_BACK, M.LAST_BACK = 53, 65
M.X_MARK, M.O_MARK = 67, 68

local faces, backs, marks = {}, {}, {}
M.have_art = false

-- The table: Windows 3.1's Solitaire green.
M.TABLE = { 0, 128, 0 }

function M.face_id(card) return card.suit * 13 + card.rank end

function M.load()
    faces, backs, marks = {}, {}, {}
    M.have_art = false
    if not sp.has_data() then return end
    local n = 0
    for suit = 0, 3 do
        for rank = 1, 13 do
            local id = suit * 13 + rank
            local h, w, ht = sp.bitmap(id, "cards", true)
            if h then faces[id] = h; n = n + 1; M.W, M.H = w, ht end
        end
    end
    M.backs = {}
    for id = M.FIRST_BACK, M.LAST_BACK do
        local h = sp.bitmap(id, "cards", true)
        if h then backs[id] = h; M.backs[#M.backs + 1] = id end
    end
    for _, id in ipairs({ M.X_MARK, M.O_MARK }) do
        local h = sp.bitmap(id, "cards", true)
        if h then marks[id] = h end
    end
    M.have_art = n == 52
end

-- The backs on offer in Game > Deck (their CARDS.DLL ids).
M.backs = {}
function M.back_ids()
    if #M.backs > 0 then return M.backs end
    local ids = {}
    for i = 1, 12 do ids[i] = M.FIRST_BACK + i - 1 end
    return ids
end

-- ---- the port's own plain cards (no CARDS.DLL) ----------------------------

local function frame(x, y, w, h)
    sp.fill(x + 2, y, w - 4, 1, 0, 0, 0)
    sp.fill(x + 2, y + h - 1, w - 4, 1, 0, 0, 0)
    sp.fill(x, y + 2, 1, h - 4, 0, 0, 0)
    sp.fill(x + w - 1, y + 2, 1, h - 4, 0, 0, 0)
    sp.fill(x + 1, y + 1, 1, 1, 0, 0, 0); sp.fill(x + w - 2, y + 1, 1, 1, 0, 0, 0)
    sp.fill(x + 1, y + h - 2, 1, 1, 0, 0, 0); sp.fill(x + w - 2, y + h - 2, 1, 1, 0, 0, 0)
end

local function body(x, y, w, h, r, g, b)
    sp.fill(x + 2, y + 1, w - 4, h - 2, r, g, b)
    sp.fill(x + 1, y + 2, w - 2, h - 4, r, g, b)
end

local SUIT_CHAR = { [0] = "C", "D", "H", "S" }

local function plain_face(card, x, y)
    body(x, y, M.W, M.H, 255, 255, 255)
    frame(x, y, M.W, M.H)
    local red = card.suit == 1 or card.suit == 2
    local r, g, b = red and 255 or 0, 0, 0
    local label = ({ "A", "2", "3", "4", "5", "6", "7", "8", "9", "10", "J", "Q", "K" })[card.rank]
    sp.text(x + 4, y + 4, label, 1, r, g, b, "system")
    sp.text(x + 4, y + 18, SUIT_CHAR[card.suit], 1, r, g, b, "system")
    local big = label .. SUIT_CHAR[card.suit]
    sp.text(x + (M.W - sp.text_width(big, 2, "system")) // 2, y + M.H // 2 - 13, big, 2, r, g, b, "system")
end

-- Plain backs: a few colours and patterns, standing in for the twelve designs.
local BACK_COLOURS = {
    { 0, 0, 160 }, { 160, 0, 0 }, { 0, 96, 160 }, { 96, 0, 128 }, { 0, 128, 96 }, { 128, 96, 0 },
    { 0, 0, 96 }, { 128, 0, 64 }, { 64, 64, 64 }, { 0, 64, 128 }, { 160, 64, 0 }, { 32, 96, 32 }, { 96, 96, 160 },
}

local function plain_back(id, x, y)
    local c = BACK_COLOURS[(id - M.FIRST_BACK) % #BACK_COLOURS + 1]
    body(x, y, M.W, M.H, 255, 255, 255)
    frame(x, y, M.W, M.H)
    sp.fill(x + 4, y + 4, M.W - 8, M.H - 8, c[1], c[2], c[3])
    local step = 6 + (id - M.FIRST_BACK) % 3 * 2
    for k = 0, M.W - 10, step do sp.fill(x + 5 + k, y + 5, 1, M.H - 10, 255, 255, 255, 90) end
    for k = 0, M.H - 10, step do sp.fill(x + 5, y + 5 + k, M.W - 10, 1, 255, 255, 255, 90) end
end

-- ---- drawing ----------------------------------------------------------------

function M.draw_face(card, x, y, flip)
    local h = faces[M.face_id(card)]
    if h then
        if flip then sp.draw_flip(h, 0, 0, M.W, M.H, x, y, M.W, M.H)
        else sp.draw(h, 0, 0, M.W, M.H, x, y) end
    else
        plain_face(card, x, y)
    end
end

function M.draw_back(back_id, x, y)
    local h = backs[back_id] or backs[M.FIRST_BACK]
    if h then sp.draw(h, 0, 0, M.W, M.H, x, y) else plain_back(back_id, x, y) end
end

function M.draw(card, x, y, back_id)
    if card.up then M.draw_face(card, x, y) else M.draw_back(back_id, x, y) end
end

-- An empty pile's place: the outline in the table's darker green (the
-- original draws it with CARDS.DLL's empty-pile mode), or the stock's X or O.
function M.draw_empty(x, y, mark)
    local h = mark and marks[mark]
    if h then
        sp.draw(h, 0, 0, M.W, M.H, x, y)
        return
    end
    local r, g, b = 0, 80, 0
    sp.fill(x + 2, y, M.W - 4, 1, r, g, b); sp.fill(x + 2, y + M.H - 1, M.W - 4, 1, r, g, b)
    sp.fill(x, y + 2, 1, M.H - 4, r, g, b); sp.fill(x + M.W - 1, y + 2, 1, M.H - 4, r, g, b)
    if mark == M.O_MARK then
        local cx, cy = x + M.W // 2, y + M.H // 2
        for a = 0, 359, 6 do
            local t = math.rad(a)
            sp.fill(cx + math.floor(18 * math.cos(t)) - 2, cy + math.floor(18 * math.sin(t)) - 2, 4, 4, 0, 200, 0)
        end
    elseif mark == M.X_MARK then
        local cx, cy = x + M.W // 2, y + M.H // 2
        for k = -18, 18 do
            sp.fill(cx + k - 2, cy + k - 2, 4, 4, 200, 0, 0)
            sp.fill(cx - k - 2, cy + k - 2, 4, 4, 200, 0, 0)
        end
    end
end

-- The dragged-outline option: a rectangle where the cards would be.
function M.draw_outline(x, y, w, h)
    sp.fill(x, y, w, 1, 0, 0, 0); sp.fill(x, y + h - 1, w, 1, 0, 0, 0)
    sp.fill(x, y, 1, h, 0, 0, 0); sp.fill(x + w - 1, y, 1, h, 0, 0, 0)
end

return M
