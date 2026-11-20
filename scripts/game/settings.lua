-- The options, the chosen back and the Vegas bank, kept between runs (as
-- the original keeps them in WIN.INI's [Solitaire] section). Stored as
-- "key=value" lines through sp.storage_*.

local M = {}

M.defaults = {
    draw = 3,                 -- Draw Three, the original's default
    scoring = "standard",     -- "standard", "vegas", "none"
    timed = true,
    status = true,            -- the status bar
    outline = false,          -- Outline dragging
    keep_score = false,       -- Vegas: carry the score over
    back = 54,                -- the back's bitmap id (54-65)
    auto_flip = true,         -- turn uncovered cards up by themselves (later Windows games)
    blue_green = true,        -- the blue-green table of the later games, not 3.1's green
    sound = true,             -- the card sounds
    smooth = true,            -- the cards smoothed for the screen, not the original pixels
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
    if s.scoring ~= "standard" and s.scoring ~= "vegas" and s.scoring ~= "none" then s.scoring = "standard" end
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
