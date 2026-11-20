-- The options, the chosen back and the Vegas bank, kept between runs (as
-- the original keeps them in WIN.INI's [Solitaire] section). Stored as
-- "key=value" lines through sp.storage_*.

local M = {}

M.defaults = {
    draw = 3,                 -- Draw Three, the original's default
    scoring = "standard",     -- "standard", "vegas", "none", "win7", "klondike"
    suits = 4,                -- the Klondike mode's: 1, 2 or 4
    timed = true,
    status = true,            -- the status bar
    outline = false,          -- Outline dragging
    keep_score = false,       -- Vegas: carry the score over
    back = 54,                -- the back's bitmap id (54-65)
    auto_flip = true,         -- turn uncovered cards up by themselves (later Windows games)
    blue_green = true,        -- the blue-green table of the later games, not 3.1's green
    sound = true,             -- the card sounds
    smooth = true,            -- the cards smoothed for the screen, not the original pixels
    satin = true,             -- a grainy satin over the table colour
    shadows = true,           -- the cards cast soft shadows
    bank = 0,                 -- the carried-over Vegas score
}

function M.load()
    local s = {}
    for k, v in pairs(M.defaults) do s[k] = v end
    local text = sp.storage_read("options")
    if text then
        for k, v in text:gmatch("([%w_]+)=([^\n]*)") do
            local d = M.defaults[k]
            if type(d) == "boolean" then s[k] = v == "1"
            elseif type(d) == "number" then s[k] = tonumber(v) or d
            elseif d ~= nil then s[k] = v end
        end
    end
    if s.draw ~= 1 and s.draw ~= 3 then s.draw = 3 end
    local modes = { standard = true, vegas = true, none = true, win7 = true, klondike = true }
    if not modes[s.scoring] then s.scoring = "standard" end
    if s.suits ~= 1 and s.suits ~= 2 and s.suits ~= 4 then s.suits = 4 end
    return s
end

function M.save(s)
    local keys = {}
    for k in pairs(M.defaults) do keys[#keys + 1] = k end
    table.sort(keys)
    local out = {}
    for _, k in ipairs(keys) do
        local v = s[k]
        if type(v) == "boolean" then v = v and "1" or "0" end
        out[#out + 1] = k .. "=" .. tostring(v)
    end
    sp.storage_write("options", table.concat(out, "\n") .. "\n")
end

return M
