-- Dialog boxes drawn from Windows 3.x dialog templates: SOL.EXE's own
-- (Options, Select Card Back) when the player has it, read with sp.dialog,
-- or the port's stand-ins in the same form. Push buttons, check boxes,
-- radio buttons, group boxes, static text and owner-drawn buttons (the card
-- backs) are drawn in Windows 3.1's look and work with the mouse, the
-- keyboard (Tab, arrows, Space, Enter, Esc) and a controller.
--
-- A template: { caption, w, h, controls = { { class, style, x, y, w, h, id,
-- text }, ... } } in dialog units, as sp.dialog returns it.

local w31 = require("ui.win31")

local Dialog = {}
Dialog.__index = Dialog

-- Dialog units to pixels (the System font's base units on VGA, 8 x 16:
-- a horizontal unit is a quarter of the width, a vertical one an eighth).
Dialog.DX, Dialog.DY = 2, 2

local BS_PUSHBUTTON, BS_DEFPUSHBUTTON, BS_CHECKBOX, BS_AUTOCHECKBOX = 0, 1, 2, 3
local BS_RADIOBUTTON, BS_3STATE, BS_AUTO3STATE, BS_GROUPBOX = 4, 5, 6, 7
local BS_AUTORADIOBUTTON, BS_OWNERDRAW = 9, 11
local WS_GROUP, WS_TABSTOP, WS_DISABLED = 0x00020000, 0x00010000, 0x08000000

local function kind(c)
    local cls = (c.class or ""):lower()
    if cls == "button" then
        local s = c.style & 0xF
        if s == BS_PUSHBUTTON or s == BS_DEFPUSHBUTTON then return "push" end
        if s == BS_CHECKBOX or s == BS_AUTOCHECKBOX or s == BS_3STATE or s == BS_AUTO3STATE then return "check" end
        if s == BS_RADIOBUTTON or s == BS_AUTORADIOBUTTON then return "radio" end
        if s == BS_GROUPBOX then return "group" end
        if s == BS_OWNERDRAW then return "owner" end
        return "push"
    end
    if cls == "static" then
        if (c.style & 0xF) == 3 then return "icon" end
        return "static"
    end
    return "other"
end

-- "Draw &Three" -> "draw three": how the port matches SOL.EXE's controls to
-- its options.
function Dialog.key(text)
    return (text or ""):gsub("&", ""):gsub("%.%.%.$", ""):lower()
end

-- opts: { template, x, y (pixels; default centred in area), area,
--   values = { [control id] = bool }  check boxes and radio buttons,
--   enabled = fn(control) -> bool, draw_owner = fn(control, x, y, w, h, selected),
--   selected = id (owner-drawn: the chosen one), onclose = fn(dialog, button id) }
function Dialog.new(opts)
    local d = setmetatable({}, Dialog)
    d.t = opts.template
    d.values = opts.values or {}
    d.enabled_fn = opts.enabled
    d.draw_owner = opts.draw_owner
    d.selected = opts.selected
    d.onclose = opts.onclose
    d.onchange = opts.onchange
    d.pressed = nil
    d.w = d.t.w * Dialog.DX + 10
    d.h = d.t.h * Dialog.DY + 10 + (d.t.caption and (w31.CAPTION_H + 1) or 0)
    local area = opts.area
    d.x = opts.x or (area.x + (area.w - d.w) // 2)
    d.y = opts.y or (area.y + math.max(0, (area.h - d.h) // 2))
    d.controls = {}
    local group = 0
    for _, c in ipairs(d.t.controls) do
        local k = kind(c)
        if (c.style & WS_GROUP) ~= 0 or k ~= "radio" then group = group + 1 end
        d.controls[#d.controls + 1] = { c = c, kind = k, group = group, key = Dialog.key(c.text) }
    end
    -- Focus: the first control that takes it.
    for i, e in ipairs(d.controls) do
        if d:focusable(e) then d.focus = i; break end
    end
    if d.selected then
        for i, e in ipairs(d.controls) do
            if e.kind == "owner" and e.c.id == d.selected then d.focus = i end
        end
    end
    return d
end

function Dialog:enabled(e)
    if (e.c.style & WS_DISABLED) ~= 0 then return false end
    if self.enabled_fn then return self.enabled_fn(e.c, e.key) ~= false end
    return true
end

function Dialog:focusable(e)
    return (e.kind == "push" or e.kind == "check" or e.kind == "radio" or e.kind == "owner") and self:enabled(e)
end

function Dialog:rect(e)
    local cx, cy = self:client()
    return cx + e.c.x * Dialog.DX, cy + e.c.y * Dialog.DY, e.c.w * Dialog.DX, e.c.h * Dialog.DY
end

function Dialog:client()
    return self.x + 5, self.y + 5 + (self.t.caption and (w31.CAPTION_H + 1) or 0)
end

function Dialog:find(key)
    for _, e in ipairs(self.controls) do
        if e.key == key then return e end
    end
end

function Dialog:default_button()
    for _, e in ipairs(self.controls) do
        if e.kind == "push" and (e.c.style & 0xF) == BS_DEFPUSHBUTTON then return e end
    end
    for _, e in ipairs(self.controls) do
        if e.kind == "push" and (e.key == "ok" or e.c.id == 1) then return e end
    end
end

function Dialog:cancel_button()
    for _, e in ipairs(self.controls) do
        if e.kind == "push" and (e.key == "cancel" or e.c.id == 2) then return e end
    end
end

function Dialog:close(e)
    if self.onclose then self.onclose(self, e and e.c.id, e and e.key) end
end

-- Pressing a control: a push button closes the dialog; a check box flips;
-- a radio button is chosen and the others in its group cleared; an
-- owner-drawn button (a card back) is selected, and a second press on it
-- closes the dialog as OK.
function Dialog:activate(e, again)
    if not e or not self:enabled(e) then return end
    if e.kind == "push" then
        self:close(e)
    elseif e.kind == "check" then
        self.values[e.c.id] = not self.values[e.c.id]
        if self.onchange then self.onchange(self, e) end
    elseif e.kind == "radio" then
        for _, o in ipairs(self.controls) do
            if o.kind == "radio" and o.group == e.group then self.values[o.c.id] = false end
        end
        self.values[e.c.id] = true
        if self.onchange then self.onchange(self, e) end
    elseif e.kind == "owner" then
        if again and self.selected == e.c.id then
            self:close(self:default_button())
        else
            self.selected = e.c.id
        end
    end
end

function Dialog:move_focus(d)
    local n = #self.controls
    local i = self.focus or 1
    for _ = 1, n do
        i = (i - 1 + d) % n + 1
        if self:focusable(self.controls[i]) then break end
    end
    self.focus = i
    local e = self.controls[i]
    -- Arrowing onto a radio button chooses it, as in Windows.
    return e
end

-- Within a radio group or among the owner-drawn buttons: arrows move and choose.
function Dialog:arrow(d)
    local cur = self.controls[self.focus or 1]
    if cur and (cur.kind == "radio" or cur.kind == "owner") then
        local n = #self.controls
        local i = self.focus
        for _ = 1, n do
            i = (i - 1 + d) % n + 1
            local e = self.controls[i]
            if e.kind == cur.kind and (cur.kind == "owner" or e.group == cur.group) and self:enabled(e) then
                self.focus = i
                self:activate(e)
                return
            end
        end
    else
        self:move_focus(d)
    end
end

-- keys: SDL key names or "pad ..." buttons. Returns true if it used it.
function Dialog:keypressed(k)
    if k == "tab" or k == "pad rightshoulder" then
        self:move_focus(sp.key_down("left shift") and -1 or 1)
    elseif k == "up" or k == "left" or k == "pad dpup" or k == "pad dpleft" then
        self:arrow(-1)
    elseif k == "down" or k == "right" or k == "pad dpdown" or k == "pad dpright" then
        self:arrow(1)
    elseif k == "space" or k == "pad a" then
        local e = self.controls[self.focus or 0]
        if e and e.kind == "owner" then self:close(self:default_button()) else self:activate(e) end
    elseif k == "return" or k == "keypad enter" or k == "pad start" then
        local e = self.controls[self.focus or 0]
        if e and e.kind == "push" then self:activate(e) else self:close(self:default_button()) end
    elseif k == "escape" or k == "pad b" or k == "pad back" then
        self:close(self:cancel_button())
    else
        -- Alt-less mnemonics, as Windows allows in a dialog: the underlined letter.
        if #k == 1 then
            for i, e in ipairs(self.controls) do
                local _, at = w31.mnemonic(e.c.text or "")
                local plain = w31.mnemonic(e.c.text or "")
                if at and plain:sub(at, at):lower() == k and self:focusable(e) then
                    self.focus = i
                    self:activate(e)
                    return true
                end
            end
        end
        return false
    end
    return true
end

function Dialog:hit(px, py)
    for i = #self.controls, 1, -1 do
        local e = self.controls[i]
        if self:focusable(e) then
            local x, y, w, h = self:rect(e)
            if px >= x and py >= y and px < x + w and py < y + h then return i, e end
        end
    end
end

function Dialog:mousepressed(x, y, button, clicks)
    if button ~= "left" then return end
    local i, e = self:hit(x, y)
    if not e then return end
    self.focus = i
    if e.kind == "push" then
        self.pressed = i
    else
        self:activate(e, clicks and clicks >= 2)
    end
end

function Dialog:mousereleased(x, y, button)
    if button ~= "left" or not self.pressed then return end
    local i = self:hit(x, y)
    local p = self.pressed
    self.pressed = nil
    if i == p then self:activate(self.controls[p]) end
end

function Dialog:draw()
    w31.window(self.x, self.y, self.w, self.h, self.t.caption)
    for i, e in ipairs(self.controls) do
        local x, y, w, h = self:rect(e)
        local c = e.c
        local on = self:enabled(e)
        local focus = self.focus == i
        if e.kind == "push" then
            local def = (c.style & 0xF) == BS_DEFPUSHBUTTON
            w31.button(x, y, w, h, c.text, { default = def, pressed = self.pressed == i, focus = focus, disabled = not on })
        elseif e.kind == "check" then
            w31.checkbox(x, y + (h - w31.LINE_H) // 2, c.text, self.values[c.id], focus)
            if not on then w31.rect(x, y, w, h, w31.WHITE, 140) end
        elseif e.kind == "radio" then
            w31.radio(x, y + (h - w31.LINE_H) // 2, c.text, self.values[c.id], focus)
            if not on then w31.rect(x, y, w, h, w31.WHITE, 140) end
        elseif e.kind == "group" then
            w31.group(x, y, w, h, c.text)
        elseif e.kind == "static" then
            local s = c.style & 0xF
            local plain = c.text or ""
            for line in (plain .. "\n"):gmatch("(.-)\n") do
                if s == 1 then w31.text_center(x, y, w, line)
                elseif s == 2 then w31.text(x + w - w31.width(line), y, line)
                else w31.text(x, y, line) end
                y = y + w31.LINE_H + 2
            end
        elseif e.kind == "owner" then
            if self.draw_owner then self.draw_owner(c, x, y, w, h, self.selected == c.id, focus) end
        end
    end
end

return Dialog
