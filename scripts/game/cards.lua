-- The card art: 71 x 96 bitmaps in Windows 3.1's SOL.EXE (or a 16-bit
-- CARDS.DLL standing in for it): faces 1-52 (clubs A-K, diamonds, hearts,
-- spades), 53 the dotted pattern of an empty pile, the twelve backs 54-65,
-- the marks on an empty stock (67 the X: no more passes; 68 the O: click to
-- turn the waste over), and 678-684, the frames four of the backs animate
-- with. Without the files the port draws plain cards of its own. See
-- docs/original.md.

local M = {}

M.W, M.H = 71, 96
M.FIRST_BACK, M.LAST_BACK = 54, 65
M.EMPTY = 53
M.X_MARK, M.O_MARK = 67, 68

-- The animated backs: the frames (bitmap ids) drawn over the back at
-- (x, y), in turn, now and then (docs/original.md).
M.ANIMATIONS = {
    [56] = { x = 24, y = 40, frames = { 683, 684, 683, 684, 683, 684 } },   -- the robot's lights
    [63] = { x = 42, y = 12, frames = { 680 } },                          -- bats over the castle
    [64] = { x = 47, y = 1, frames = { 681, 682 } },                      -- the sun: sunglasses, then a tongue
    [65] = { x = 32, y = 32, frames = { 678, 679 } },                     -- a card up the sleeve
}

local faces, backs, marks, frames = {}, {}, {}, {}
local empty
M.have_art = false

-- The table's colour: Windows 3.1's Solitaire green, or the blue-green of
-- the later Windows card games (Spider). M.TABLE is changed in place.
M.TABLES = {
    classic = { 0, 128, 0 },
    spider = { 0, 112, 104 },
}
M.TABLE = { 0, 128, 0 }

function M.set_table(name)
    local c = M.TABLES[name] or M.TABLES.classic
    M.TABLE[1], M.TABLE[2], M.TABLE[3] = c[1], c[2], c[3]
end

function M.face_id(card) return card.suit * 13 + card.rank end

-- Smoothed for the screen (sp.bitmap's smooth: Scale2x, then averaged
-- down to the real pixels the canvas is drawn at), or the original pixels.
M.smooth = true

-- Every handle loaded, to release when the cards are loaded again.
local loaded = {}
local function bitmap(id, opts)
    opts = opts or {}
    opts.smooth = M.smooth
    local h, w, ht = sp.bitmap(id, "cards", opts)
    if h then loaded[#loaded + 1] = h end
    return h, w, ht
end

function M.load()
    for _, h in ipairs(loaded) do sp.free_bitmap(h) end
    loaded = {}
    faces, backs, marks, frames = {}, {}, {}, {}
    empty = nil
    M.have_art = false
    if not sp.has_data() then return end
    local n = 0
    for suit = 0, 3 do
        for rank = 1, 13 do
            local id = suit * 13 + rank
            -- Diamonds and hearts: red, with a black edge.
            local red = suit == 1 or suit == 2
            local h, w, ht = bitmap(id, { round = true, black_frame = red })
            if h then faces[id] = h; n = n + 1; M.W, M.H = w, ht end
        end
    end
    M.backs = {}
    for id = M.FIRST_BACK, M.LAST_BACK do
        local h = bitmap(id, { round = true })
        if h then backs[id] = h; M.backs[#M.backs + 1] = id end
    end
    for _, id in ipairs({ M.X_MARK, M.O_MARK }) do
        -- Drawn on the original's green: that green is left clear, so they
        -- sit on whichever table colour is chosen.
        local h = bitmap(id, { round = true, clear_color = { 0, 128, 0 } })
        if h then marks[id] = h end
    end
    -- A monochrome bitmap the original draws with the table green as its
    -- background: its white is left clear.
    empty = bitmap(M.EMPTY, { round = true, clear_white = true })
    for _, a in pairs(M.ANIMATIONS) do
        for _, id in ipairs(a.frames) do
            if not frames[id] then
                local h, w, ht = bitmap(id)
                if h then frames[id] = { h = h, w = w, ht = ht } end
            end
        end
    end
    M.have_art = n == 52
end

-- The backs on offer in Game > Deck (their bitmap ids).
M.backs = {}
function M.back_ids()
    if #M.backs > 0 then return M.backs end
    local ids = {}
    for i = 1, 12 do ids[i] = M.FIRST_BACK + i - 1 end
    return ids
end

-- ---- the port's own plain cards (no SOL.EXE) ------------------------------

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

-- frame: which of the back's animation frames to draw over it (nil: none).
function M.draw_back(back_id, x, y, frame)
    local h = backs[back_id] or backs[M.FIRST_BACK]
    if not h then plain_back(back_id, x, y); return end
    sp.draw(h, 0, 0, M.W, M.H, x, y)
    local a = frame and M.ANIMATIONS[back_id]
    local f = a and frames[a.frames[frame]]
    if f then sp.draw(f.h, 0, 0, f.w, f.ht, x + a.x, y + a.y) end
end

-- A back shrunk into a w x h box (the Select Card Back buttons).
function M.draw_back_scaled(back_id, x, y, w, h)
    local hd = backs[back_id]
    if hd then sp.draw(hd, 0, 0, M.W, M.H, x, y, w, h) else
        sp.fill(x, y, w, h, 0, 0, 160)
    end
end

function M.draw(card, x, y, back_id)
    if card.up then M.draw_face(card, x, y) else M.draw_back(back_id, x, y) end
end

-- An empty pile's place: the dotted outline (bitmap 53), or the stock's X
-- or O.
function M.draw_empty(x, y, mark)
    local h = mark and marks[mark]
    if h then
        sp.draw(h, 0, 0, M.W, M.H, x, y)
        return
    end
    if not mark and empty then
        sp.draw(empty, 0, 0, M.W, M.H, x, y)
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
