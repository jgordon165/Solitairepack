-- The menu bar along the top of the window, as Windows 3.1 draws it: white,
-- black text, the open menu's title and the chosen item in the highlight
-- colour. The menus are SOL.EXE's own (MENU resource 1) when the player has
-- it, or the port's copy of them; each item is matched to a command by its
-- text ("&Deal" -> "deal"). Works with the mouse, the keyboard (Alt or F10,
-- the arrows, Enter, Esc, the underlined letters) and a controller.

local w31 = require("ui.win31")

local Bar = {}
Bar.__index = Bar

Bar.H = 19   -- the bar, its bottom line included

local FALLBACK = {
    { text = "&Game", items = {
        { text = "&Deal" }, { separator = true }, { text = "&Undo" }, { text = "De&ck..." },
        { text = "&Options..." }, { separator = true }, { text = "E&xit" } } },
    { text = "&Help", items = {
        { text = "&Contents" }, { text = "&Search for Help On..." }, { text = "&How to Use Help" },
        { separator = true }, { text = "&About Solitaire..." } } },
}

local function command(text)
    return (text or ""):gsub("\t.*$", ""):gsub("&", ""):gsub("%.%.%.$", ""):lower()
end
Bar.command = command

-- opts: { width, on_command = fn(name), enabled = fn(name) -> bool,
--         shortcut = fn(name) -> text shown at the right, e.g. "F2" }
function Bar.new(opts)
    local b = setmetatable({}, Bar)
    b.width = opts.width
    b.on_command = opts.on_command
    b.enabled_fn = opts.enabled
    b.shortcut = opts.shortcut
    local menus = sp.menu and sp.menu(1, "sol")
    b.from_sol = type(menus) == "table" and #menus > 0
    b.menus = b.from_sol and menus or FALLBACK
    b.open = nil      -- index of the open menu
    b.sel = nil       -- its highlighted item
    b.active = false  -- the bar has the keyboard (Alt pressed) without a menu open
    -- Titles' positions.
    local x = 0
    b.title_x = {}
    for i, m in ipairs(b.menus) do
        local w = w31.width(m.text) + 16
        b.title_x[i] = { x = x, w = w }
        x = x + w
    end
    return b
end

function Bar:enabled(item)
    if item.separator then return false end
    if item.flags and (item.flags & 0x3) ~= 0 then return false end
    if self.enabled_fn then return self.enabled_fn(command(item.text)) ~= false end
    return true
end

function Bar:is_open() return self.open ~= nil or self.active end

function Bar:close()
    self.open, self.sel, self.active = nil, nil, false
end

function Bar:open_menu(i)
    self.open = i
    self.active = false
    self.sel = nil
    local items = self.menus[i].items or {}
    for k, it in ipairs(items) do
        if self:enabled(it) then self.sel = k; break end
    end
end

-- The open menu's box and each item's row.
local ITEM_H, SEP_H = 16, 8
function Bar:dropdown()
    local m = self.menus[self.open]
    local items = m.items or {}
    local w = 0
    for _, it in ipairs(items) do
        local label = it.text or ""
        local sc = self.shortcut and self.shortcut(command(label))
        local tw = w31.width((label:gsub("\t.*$", ""))) + (sc and (sp.text_width(sc, 1, "system") + 24) or 0)
        if label:find("\t") then tw = tw + 24 + sp.text_width(label:match("\t(.*)$"), 1, "system") end
        w = math.max(w, tw)
    end
    w = w + 34
    local x = self.title_x[self.open].x
    local y = Bar.H - 1
    local rows, ry = {}, y + 1
    for k, it in ipairs(items) do
        local h = it.separator and SEP_H or ITEM_H
        rows[k] = { y = ry, h = h }
        ry = ry + h
    end
    return x, y, w, ry - y + 1, rows
end

function Bar:run(item)
    self:close()
    if self.on_command then self.on_command(command(item.text)) end
end

function Bar:keypressed(k)
    if not self.open then
        if k == "left alt" or k == "right alt" or k == "f10" then
            if self.active then self:close() else self.active = true; self.hot = 1 end
            return true
        end
        if self.active then
            if k == "left" then self.hot = (self.hot - 2) % #self.menus + 1
            elseif k == "right" then self.hot = self.hot % #self.menus + 1
            elseif k == "return" or k == "down" or k == "space" then self:open_menu(self.hot)
            elseif k == "escape" then self:close()
            else
                for i, m in ipairs(self.menus) do
                    local plain, at = w31.mnemonic(m.text)
                    if at and plain:sub(at, at):lower() == k then self:open_menu(i); return true end
                end
                self:close()
            end
            return true
        end
        return false
    end
    local items = self.menus[self.open].items or {}
    local function step(d)
        local k2 = self.sel or 0
        for _ = 1, #items do
            k2 = (k2 - 1 + d) % #items + 1
            if self:enabled(items[k2]) then self.sel = k2; return end
        end
    end
    if k == "up" or k == "pad dpup" then step(-1)
    elseif k == "down" or k == "pad dpdown" then step(1)
    elseif k == "left" or k == "pad dpleft" then self:open_menu((self.open - 2) % #self.menus + 1)
    elseif k == "right" or k == "pad dpright" then self:open_menu(self.open % #self.menus + 1)
    elseif k == "return" or k == "keypad enter" or k == "space" or k == "pad a" then
        if self.sel and self:enabled(items[self.sel]) then self:run(items[self.sel]) end
    elseif k == "escape" or k == "pad b" or k == "pad start" or k == "left alt" or k == "right alt" or k == "f10" then
        self:close()
    else
        for _, it in ipairs(items) do
            local plain, at = w31.mnemonic((it.text or ""):gsub("\t.*$", ""))
            if at and plain:sub(at, at):lower() == k and self:enabled(it) then self:run(it); return true end
        end
    end
    return true
end

-- Returns true when the press belonged to the menus.
function Bar:mousepressed(x, y, button)
    if y < Bar.H then
        for i, t in ipairs(self.title_x) do
            if x >= t.x and x < t.x + t.w then
                if self.open == i then self:close() else self:open_menu(i) end
                self.dragging = true
                return true
            end
        end
        self:close()
        return true
    end
    if self.open then
        local mx, my, mw, mh, rows = self:dropdown()
        if x >= mx and x < mx + mw and y >= my and y < my + mh then
            self.dragging = true
            return true
        end
        self:close()
        return true   -- a click outside an open menu only closes it, as in Windows
    end
    return false
end

function Bar:item_at(x, y)
    if not self.open then return nil end
    local mx, my, mw, mh, rows = self:dropdown()
    if x < mx or x >= mx + mw then return nil end
    for k, r in ipairs(rows) do
        if y >= r.y and y < r.y + r.h then return k end
    end
end

function Bar:mousemoved(x, y)
    if not self.open then return false end
    if y < Bar.H and self.dragging then
        for i, t in ipairs(self.title_x) do
            if x >= t.x and x < t.x + t.w and self.open ~= i then self:open_menu(i) end
        end
    end
    local k = self:item_at(x, y)
    local items = self.menus[self.open].items or {}
    if k and self:enabled(items[k]) then self.sel = k elseif self.dragging then self.sel = nil end
    return true
end

function Bar:mousereleased(x, y, button)
    if not self.dragging then return false end
    self.dragging = false
    if not self.open then return true end
    local k = self:item_at(x, y)
    local items = self.menus[self.open].items or {}
    if k and self:enabled(items[k]) then self:run(items[k]) end
    return true
end

function Bar:draw()
    w31.rect(0, 0, self.width, Bar.H - 1, w31.WHITE)
    sp.fill(0, Bar.H - 1, self.width, 1, 0, 0, 0)
    for i, m in ipairs(self.menus) do
        local t = self.title_x[i]
        local hot = self.open == i or (self.active and self.hot == i)
        if hot then w31.rect(t.x, 0, t.w, Bar.H - 1, w31.HILITE) end
        w31.text(t.x + 8, 3, m.text, hot and w31.WHITE or w31.BLACK)
    end
    if not self.open then return end
    local x, y, w, h, rows = self:dropdown()
    w31.rect(x, y, w, h, w31.WHITE)
    w31.box(x, y, w, h, w31.BLACK)
    sp.fill(x + w, y + 2, 2, h, 0, 0, 0, 255)
    sp.fill(x + 2, y + h, w, 2, 0, 0, 0, 255)
    local items = self.menus[self.open].items or {}
    for k, it in ipairs(items) do
        local r = rows[k]
        if it.separator then
            sp.fill(x + 1, r.y + r.h // 2, w - 2, 1, 0, 0, 0)
        else
            local on = self:enabled(it)
            local hot = self.sel == k
            if hot then w31.rect(x + 1, r.y, w - 2, r.h, w31.HILITE) end
            local c = hot and w31.WHITE or (on and w31.BLACK or w31.DISABLED)
            local label = it.text or ""
            if not label:find("\t") and self.shortcut then
                local sc = self.shortcut(command(label))
                if sc then label = label .. "\t" .. sc end
            end
            w31.text(x + 16, r.y + 2, label, c, w - 32)
            if it.flags and (it.flags & 0x8) ~= 0 then w31.text(x + 4, r.y + 2, "*", c) end
        end
    end
end

return Bar
