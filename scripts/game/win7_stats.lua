-- The Windows 7 mode's statistics, kept between runs as the Vista / 7 game
-- keeps them: games played and won, the win percentage, the longest
-- winning and losing streaks, the current streak and the high score. A
-- game counts once a move has been made; giving one up (a new deal, a
-- restart, not continuing a saved game) counts as a loss.

local M = {}

-- Each mode keeps its own (the Klondike mode one per number of suits, as
-- the later Windows games keep them per difficulty): key is the storage
-- name, "win7_stats" by default.
local FIELDS = { "played", "won", "streak", "best_win_streak", "worst_loss_streak", "high_score" }

function M.load(key)
    local s = {}
    for _, f in ipairs(FIELDS) do s[f] = 0 end
    local text = sp.storage_read(key or "win7_stats")
    if text then
        for k, v in text:gmatch("([%w_]+)=(%-?%d+)") do
            if s[k] ~= nil then s[k] = tonumber(v) end
        end
    end
    return s
end

function M.save(s, key)
    local out = {}
    for _, f in ipairs(FIELDS) do out[#out + 1] = f .. "=" .. tostring(s[f]) end
    sp.storage_write(key or "win7_stats", table.concat(out, "\n") .. "\n")
end

-- A finished game: won or lost, with its score.
function M.record(won, score, key)
    local s = M.load(key)
    s.played = s.played + 1
    if won then
        s.won = s.won + 1
        s.streak = s.streak > 0 and s.streak + 1 or 1
        s.best_win_streak = math.max(s.best_win_streak, s.streak)
        s.high_score = math.max(s.high_score, score or 0)
    else
        s.streak = s.streak < 0 and s.streak - 1 or -1
        s.worst_loss_streak = math.max(s.worst_loss_streak, -s.streak)
    end
    M.save(s, key)
    return s
end

function M.reset(key)
    local s = {}
    for _, f in ipairs(FIELDS) do s[f] = 0 end
    M.save(s, key)
end

-- The lines the Statistics box shows.
function M.lines(key)
    local s = M.load(key)
    local pct = s.played > 0 and math.floor(s.won * 100 / s.played + 0.5) or 0
    local streak = s.streak == 0 and "0" or (s.streak > 0 and (s.streak .. (s.streak == 1 and " win" or " wins"))
                                            or (-s.streak .. (s.streak == -1 and " loss" or " losses")))
    return {
        "Games played: " .. s.played,
        "Games won: " .. s.won,
        "Win percentage: " .. pct .. "%",
        "",
        "Longest winning streak: " .. s.best_win_streak,
        "Longest losing streak: " .. s.worst_loss_streak,
        "Current streak: " .. streak,
        "",
        "High score: " .. s.high_score,
    }
end

return M
