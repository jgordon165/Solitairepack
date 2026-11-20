-- Dialog templates: SOL.EXE's own when the player has it (found by their
-- caption), else the port's stand-ins, laid out like the originals, in the
-- same form sp.dialog returns (dialog units; see ui/dialog.lua). Also the
-- message boxes and the help text, which the port writes itself (the
-- original's help is a WinHelp file, SOL.HLP, which the port doesn't read).

local M = {}

local WS_CHILD_VISIBLE = 0x50000000
local WS_GROUP, WS_TABSTOP = 0x00020000, 0x00010000
local BS_DEFPUSHBUTTON, BS_AUTOCHECKBOX, BS_AUTORADIOBUTTON, BS_GROUPBOX, BS_OWNERDRAW = 1, 3, 9, 7, 11

local function button(x, y, w, h, id, text, style)
    return { class = "button", x = x, y = y, w = w, h = h, id = id, text = text, style = WS_CHILD_VISIBLE | (style or 0) }
end
local function static(x, y, w, h, text, align)
    return { class = "static", x = x, y = y, w = w, h = h, id = -1, text = text, style = WS_CHILD_VISIBLE | (align or 0) }
end

-- Options: Draw (One / Three), Scoring (Standard / Vegas / None), Timed
-- game, Status bar, Outline dragging, Keep score.
M.options = {
    caption = "Options", w = 172, h = 108,
    controls = {
        button(6, 4, 74, 40, 100, "Draw", BS_GROUPBOX),
        button(12, 16, 64, 12, 101, "Draw &One", BS_AUTORADIOBUTTON | WS_GROUP | WS_TABSTOP),
        button(12, 28, 64, 12, 102, "Draw T&hree", BS_AUTORADIOBUTTON),
        button(88, 4, 78, 52, 103, "Scoring", BS_GROUPBOX),
        button(94, 16, 66, 12, 104, "&Standard", BS_AUTORADIOBUTTON | WS_GROUP | WS_TABSTOP),
        button(94, 28, 66, 12, 105, "&Vegas", BS_AUTORADIOBUTTON),
        button(94, 40, 66, 12, 106, "&None", BS_AUTORADIOBUTTON),
        button(6, 50, 78, 12, 107, "&Timed game", BS_AUTOCHECKBOX | WS_GROUP | WS_TABSTOP),
        button(6, 62, 78, 12, 108, "Status &bar", BS_AUTOCHECKBOX | WS_TABSTOP),
        button(6, 74, 82, 12, 109, "O&utline dragging", BS_AUTOCHECKBOX | WS_TABSTOP),
        button(94, 62, 72, 12, 110, "&Keep score", BS_AUTOCHECKBOX | WS_TABSTOP),
        button(32, 90, 40, 14, 1, "OK", BS_DEFPUSHBUTTON | WS_GROUP | WS_TABSTOP),
        button(100, 90, 40, 14, 2, "Cancel", WS_TABSTOP),
    },
}

-- Select Card Back: an owner-drawn button per back, in two rows.
function M.deck(ids)
    local n = #ids
    local cols = math.max(1, math.ceil(n / 2))
    local bw, bh, gap = 40, 54, 4
    local w = cols * (bw + gap) + gap
    local t = { caption = "Select Card Back", w = w, h = 2 * (bh + gap) + gap + 20, controls = {} }
    for k, id in ipairs(ids) do
        local col, row = (k - 1) % cols, (k - 1) // cols
        t.controls[#t.controls + 1] = button(gap + col * (bw + gap), gap + row * (bh + gap), bw, bh, id, "",
                                             BS_OWNERDRAW | WS_TABSTOP)
    end
    local by = 2 * (bh + gap) + gap + 2
    t.controls[#t.controls + 1] = button(w // 2 - 50, by, 40, 14, 1, "OK", BS_DEFPUSHBUTTON | WS_TABSTOP)
    t.controls[#t.controls + 1] = button(w // 2 + 10, by, 40, 14, 2, "Cancel", WS_TABSTOP)
    return t
end

-- A message box: lines of centred text, then a row of buttons ("&Yes",
-- "&No", "OK", ...); the first is the default.
function M.message(caption, lines, buttons)
    local width = 60
    for _, l in ipairs(lines) do
        width = math.max(width, (sp.text_width(l, 1, "system") + 24) // 2)
    end
    local bw = 40
    width = math.max(width, #buttons * (bw + 8) + 8)
    local lh = 8
    local t = { caption = caption, w = width, h = #lines * lh + 32, controls = {} }
    for k, l in ipairs(lines) do
        t.controls[#t.controls + 1] = static(4, 6 + (k - 1) * lh, width - 8, lh, l, 1)
    end
    local total = #buttons * bw + (#buttons - 1) * 8
    local x = (width - total) // 2
    for k, b in ipairs(buttons) do
        t.controls[#t.controls + 1] = button(x, #lines * lh + 12, bw, 14, k, b,
                                             (k == 1 and BS_DEFPUSHBUTTON or 0) | WS_TABSTOP)
        x = x + bw + 8
    end
    -- Esc means the last button (No, or the only OK).
    t.controls[#t.controls].id = 2
    if #buttons == 1 then t.controls[#t.controls].id = 1 end
    return t
end

-- The port's own options, added below the original's in the Options
-- dialog (SOL.EXE's or the stand-in): a copy of t with three more check
-- boxes and the OK / Cancel row moved down to make room.
M.EXTRA_OPTIONS = { "&Flip cards automatically", "Blue-&green table", "&Card sounds" }
function M.with_extras(t)
    local out = { caption = t.caption, w = t.w, h = t.h, x = t.x, y = t.y, style = t.style, controls = {} }
    local push_y, left = nil, nil
    for _, c in ipairs(t.controls) do
        local copy = {}
        for k, v in pairs(c) do copy[k] = v end
        out.controls[#out.controls + 1] = copy
        local style = c.style & 0xF
        if (c.class or ""):lower() == "button" then
            if style == 0 or style == 1 then push_y = math.min(push_y or c.y, c.y)
            elseif style == 2 or style == 3 then left = math.min(left or c.x, c.x) end
        end
    end
    push_y = push_y or t.h - 18
    left = left or 6
    local row, shift = 12, #M.EXTRA_OPTIONS * 12 + 2
    for _, c in ipairs(out.controls) do
        if c.y >= push_y then c.y = c.y + shift end
    end
    for k, text in ipairs(M.EXTRA_OPTIONS) do
        out.controls[#out.controls + 1] = button(left, push_y + (k - 1) * row, t.w - 2 * left, 12, 200 + k, text,
                                                 BS_AUTOCHECKBOX | WS_TABSTOP | (k == 1 and WS_GROUP or 0))
    end
    out.h = t.h + shift
    return out
end

-- SOL.EXE's dialog whose caption matches (lower case, no "&" or "..."), or nil.
local cache = {}
function M.find_sol(caption)
    if cache[caption] ~= nil then return cache[caption] or nil end
    cache[caption] = false
    local has = select(3, sp.has_data())
    if not has then return nil end
    for _, r in ipairs(sp.resources("sol")) do
        if r.type == "DIALOG" then
            local d = sp.dialog(r.name:sub(1, 1) == "#" and tonumber(r.name:sub(2)) or r.name, "sol")
            if d and d.caption and d.caption:gsub("&", ""):lower() == caption then
                cache[caption] = d
                return d
            end
        end
    end
    return nil
end

M.help = {
    contents = {
        "The object is to move every card onto the four",
        "foundations at the top right, each suit in order",
        "from Ace to King.",
        "",
        "On the seven columns, build down in alternating",
        "colours (a red 9 on a black 10). Only a King, or a",
        "run starting with one, goes into an empty column.",
        "",
        "Click the deck to turn over cards. Drag cards to",
        "move them; double-click a card to send it to a",
        "foundation; right-click to send up every card",
        "that can go.",
        "",
        "Standard scoring: 10 to a foundation, 5 from the",
        "deck to a column or for turning a card over, -15",
        "from a foundation back to a column. Vegas: you pay",
        "$52 to play and win $5 a card on the foundations.",
    },
    keys = {
        "F2  Deal          Ctrl+Z or Backspace  Undo",
        "F1  Help          Alt or F10  The menus",
        "",
        "Arrow keys move the cursor over the piles and",
        "along a column's face-up cards. Space or Enter",
        "turns the deck, turns a card over, picks cards",
        "up and puts them down. Esc lets them go.",
        "",
        "Controller: D-pad to move, A to pick up / put",
        "down, B to let go, X to turn the deck, Y to send",
        "every card it can to the foundations, LB to send",
        "one, Back to undo, Start for the menus.",
    },
}

return M
