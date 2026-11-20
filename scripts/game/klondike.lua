-- The Klondike mode (Options > Scoring > Klondike): the Windows 7 mode's
-- game (unlimited undo, hints, auto-complete, Restart, statistics, saving;
-- see win7.lua) with a choice of how many suits the 52 cards come in, as
-- the later Windows Spider offers:
--
--   4 suits  the ordinary deck.
--   2 suits  spades and hearts, two of each card.
--   1 suit   four sets of spades.
--
-- Columns build down one rank at a time onto a card of the other colour,
-- as in Klondike, or onto one of the same suit, as in Spider (so with
-- 1 suit, always the same suit). But, as in Spider, cards only move
-- together when they're all one suit in order (7D 6D 5D): from a column
-- of 7D 6D 5S 4D only the 4D can be picked up. Single cards always move.
--
-- Foundations build up by suit from the Ace as always; with fewer suits,
-- several foundations hold the same suit. Its statistics are kept apart
-- for each number of suits.

local win7 = require("game.win7")

local M = setmetatable({}, { __index = win7 })
M.__index = M

M.SUIT_SETS = {
    [1] = { 3, 3, 3, 3 },   -- spades x4
    [2] = { 3, 2, 3, 2 },   -- spades, hearts, spades, hearts
    [4] = { 0, 1, 2, 3 },   -- clubs, diamonds, hearts, spades
}

local function red(c) return c.suit == 1 or c.suit == 2 end

-- opts: draw (1 or 3), timed, suits (1, 2 or 4).
function M.new(opts)
    opts = opts or {}
    local g = win7.new(opts)
    setmetatable(g, M)
    g.suits = M.SUIT_SETS[opts.suits] and opts.suits or 4
    g.scoring = "klondike"
    return g
end

function M:new_deck()
    local deck = {}
    for _, suit in ipairs(M.SUIT_SETS[self.suits]) do
        for rank = 1, 13 do deck[#deck + 1] = { rank = rank, suit = suit, up = false } end
    end
    return deck
end

-- Builds down onto the other colour or the same suit. Everything else as
-- in the Windows 7 mode.
function M:can_drop(cards, kind, index)
    if kind ~= "tab" then return win7.can_drop(self, cards, kind, index) end
    local first = cards[1]
    if not first then return false end
    local p = self.tab[index]
    local t = p[#p]
    if not t then return first.rank == 13 end
    if not t.up or first.rank ~= t.rank - 1 then return false end
    return red(t) ~= red(first) or t.suit == first.suit
end

-- What can be picked up: one card from the waste or a foundation; from a
-- column, the top card, or a run from position i that is all one suit,
-- each card one rank below the last.
function M:can_pick(kind, index, i)
    if not win7.can_pick(self, kind, index, i) then return false end
    if kind ~= "tab" then return true end
    local p = self.tab[index]
    for k = i + 1, #p do
        if p[k].suit ~= p[i].suit or p[k].rank ~= p[k - 1].rank - 1 then return false end
    end
    return true
end

function M.restore(text) return win7.restore(text, M) end

-- Where its statistics and its saved game are kept.
function M.stats_key(suits) return "klondike_stats_" .. (suits or 4) end
M.SAVE_KEY = "klondike_saved"

-- "1 suit", "2 suits", "4 suits".
function M.suits_name(n) return n .. (n == 1 and " suit" or " suits") end

-- Only for the tests: the colour rule this mode uses.
M.red = red

return M
