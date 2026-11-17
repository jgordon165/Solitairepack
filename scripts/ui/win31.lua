-- Drawing in the look of Windows 3.1's default colour scheme: white
-- windows, the blue active caption, gray push buttons with a black rounded
-- border, the System font. Shared by the menu bar, the dialogs and the
-- status bar.

local M = {}

M.BLACK = { 0, 0, 0 }
M.WHITE = { 255, 255, 255 }
M.GRAY = { 192, 192, 192 }
M.DARK = { 128, 128, 128 }
M.CAPTION = { 0, 0, 128 }
M.HILITE = { 0, 0, 128 }        -- selected menu item
M.DISABLED = { 128, 128, 128 }

M.LINE_H = 13                   -- the System font's cell height

local function rgb(c) return c[1], c[2], c[3] end
M.rgb = rgb

function M.rect(x, y, w, h, c, a) sp.fill(x, y, w, h, c[1], c[2], c[3], a) end

function M.box(x, y, w, h, c)
    sp.fill(x, y, w, 1, rgb(c)); sp.fill(x, y + h - 1, w, 1, rgb(c))
    sp.fill(x, y, 1, h, rgb(c)); sp.fill(x + w - 1, y, 1, h, rgb(c))
end

-- "&Deal" -> "Deal", the underlined letter's index (or nil).
function M.mnemonic(s)
    local i = s:find("&", 1, true)
    if not i then return s, nil end
    return s:sub(1, i - 1) .. s:sub(i + 1), i
end

function M.width(s)
    local plain = M.mnemonic(s)
    return sp.text_width(plain, 1, "system")
end

-- Text with its mnemonic letter underlined; tab characters split it into a
-- left part and a right part ending at x + right (menu shortcuts).
function M.text(x, y, s, c, right)
    c = c or M.BLACK
    local left, rest = s, nil
    local tab = s:find("\t", 1, true)
    if tab then left, rest = s:sub(1, tab - 1), s:sub(tab + 1) end
    local plain, i = M.mnemonic(left)
    sp.text(x, y, plain, 1, c[1], c[2], c[3], "system")
    if i then
        local ux = x + (i > 1 and sp.text_width(plain:sub(1, i - 1), 1, "system") + 1 or 0)
        local uw = sp.text_width(plain:sub(i, i), 1, "system")
        sp.fill(ux, y + 11, uw, 1, c[1], c[2], c[3])
    end
    if rest and right then
        sp.text(x + right - sp.text_width(rest, 1, "system"), y, rest, 1, c[1], c[2], c[3], "system")
    end
end

function M.text_center(x, y, w, s, c)
    M.text(x + (w - M.width(s)) // 2, y, s, c)
end

-- A push button: black border with clipped corners, gray face, white
-- highlight top-left and dark shadow bottom-right (two pixels each, one
-- when pressed). Default buttons get a second black line.
function M.button(x, y, w, h, label, opts)
    opts = opts or {}
    sp.fill(x + 1, y, w - 2, 1, 0, 0, 0); sp.fill(x + 1, y + h - 1, w - 2, 1, 0, 0, 0)
    sp.fill(x, y + 1, 1, h - 2, 0, 0, 0); sp.fill(x + w - 1, y + 1, 1, h - 2, 0, 0, 0)
    local i = 1
    if opts.default then
        M.box(x + 1, y + 1, w - 2, h - 2, M.BLACK)
        i = 2
    end
    local fx, fy, fw, fh = x + i, y + i, w - 2 * i, h - 2 * i
    M.rect(fx, fy, fw, fh, M.GRAY)
    if opts.pressed then
        sp.fill(fx, fy, fw, 1, rgb(M.DARK)); sp.fill(fx, fy, 1, fh, rgb(M.DARK))
    else
        for k = 0, 1 do
            sp.fill(fx, fy + k, fw - k, 1, 255, 255, 255)
            sp.fill(fx + k, fy, 1, fh - k, 255, 255, 255)
            sp.fill(fx + k, fy + fh - 1 - k, fw - k, 1, rgb(M.DARK))
            sp.fill(fx + fw - 1 - k, fy + k, 1, fh - k, rgb(M.DARK))
        end
    end
    if label then
        local off = opts.pressed and 1 or 0
        M.text_center(fx + off, fy + (fh - M.LINE_H) // 2 + off, fw, label, opts.disabled and M.DISABLED or M.BLACK)
    end
    if opts.focus and label then
        local tw = M.width(label)
        local tx = fx + (fw - tw) // 2 - 2
        local ty = fy + (fh - M.LINE_H) // 2 - 1
        M.dotted(tx, ty, tw + 4, M.LINE_H + 2)
    end
end

-- The focus rectangle: a dotted line.
function M.dotted(x, y, w, h)
    for k = 0, w - 1, 2 do sp.fill(x + k, y, 1, 1, 0, 0, 0); sp.fill(x + k, y + h - 1, 1, 1, 0, 0, 0) end
    for k = 0, h - 1, 2 do sp.fill(x, y + k, 1, 1, 0, 0, 0); sp.fill(x + w - 1, y + k, 1, 1, 0, 0, 0) end
end

-- A check box (12 x 12, an X when checked) with its label.
function M.checkbox(x, y, label, checked, focus)
    local by = y + 1
    M.rect(x, by, 12, 12, M.WHITE)
    M.box(x, by, 12, 12, M.BLACK)
    if checked then
        for k = 1, 10 do
            sp.fill(x + k, by + k, 1, 1, 0, 0, 0)
            sp.fill(x + 11 - k, by + k, 1, 1, 0, 0, 0)
        end
    end
    M.text(x + 18, y, label)
    if focus then M.dotted(x + 16, y - 1, M.width(label) + 4, M.LINE_H + 2) end
end

-- A radio button (a 12 x 12 circle, a dot in it when chosen) with its label.
local RING = { "....####....", "..##....##..", ".#........#.", ".#........#.", "#..........#", "#..........#",
               "#..........#", "#..........#", ".#........#.", ".#........#.", "..##....##..", "....####...." }
local DOT = { "", "", "", "", "....####....", "...######...", "...######...", "....####....", "", "", "", "" }
function M.radio(x, y, label, chosen, focus)
    local by = y + 1
    for r = 1, 12 do
        local inside = false
        for c = 1, 12 do
            local ch = RING[r]:sub(c, c)
            if ch == "#" then
                sp.fill(x + c - 1, by + r - 1, 1, 1, 0, 0, 0)
                inside = not inside
            end
        end
        if chosen then
            local d = DOT[r]
            for c = 1, #d do
                if d:sub(c, c) == "#" then sp.fill(x + c - 1, by + r - 1, 1, 1, 0, 0, 0) end
            end
        end
    end
    M.text(x + 18, y, label)
    if focus then M.dotted(x + 16, y - 1, M.width(label) + 4, M.LINE_H + 2) end
end

-- A group box: a black frame with its title breaking the top line.
function M.group(x, y, w, h, label)
    local ty = y + 6
    M.box(x, ty, w, h - 6, M.BLACK)
    if label and label ~= "" then
        local tw = M.width(label)
        M.rect(x + 6, ty, tw + 6, 1, M.WHITE)
        M.text(x + 9, y, label)
    end
end

-- A dialog's frame: a black outline, the thick gray-blue dialog border,
-- the caption bar, white inside. Returns the client area's origin.
M.CAPTION_H = 19
function M.window(x, y, w, h, caption)
    M.box(x, y, w, h, M.BLACK)
    -- The dialog frame: four pixels of the window frame colour.
    for k = 1, 4 do M.box(x + k, y + k, w - 2 * k, h - 2 * k, k == 4 and M.BLACK or M.CAPTION) end
    local cx, cy, cw = x + 5, y + 5, w - 10
    if caption then
        M.rect(cx, cy, cw, M.CAPTION_H, M.CAPTION)
        M.text_center(cx, cy + 3, cw, caption, M.WHITE)
        sp.fill(cx, cy + M.CAPTION_H, cw, 1, 0, 0, 0)
        cy = cy + M.CAPTION_H + 1
    end
    M.rect(cx, cy, cw, y + h - 5 - cy, M.WHITE)
    return cx, cy
end

return M
