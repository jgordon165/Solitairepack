-- Solitaire (Windows 3.1), played on the port's engine: the table, the menu
-- bar, the status bar, the dialogs, dragging cards, the keyboard and
-- controller, and the win. The rules are in game/rules.lua.

local rules = require("game.rules")
local cards = require("game.cards")
local table_ = require("game.table")
local settings = require("game.settings")
local cascade = require("game.cascade")
local w31 = require("ui.win31")
local Dialog = require("ui.dialog")
local Bar = require("ui.menubar")
local templates = require("ui.templates")

game = {}

-- The canvas: it follows the window's size (game.resize), 640 x 440 to start.
local W, H = 640, 440
local STATUS_H = 19

local S            -- settings
local g            -- the game in play (rules)
local L            -- the table's layout
local bar          -- the menu bar
local modal        -- the open dialog, if any
local drag         -- the cards being dragged
local kb           -- the keyboard / controller cursor
local win          -- the cascade, once the game is won
local deal_count = 0

-- The animated backs play now and then on the stock: a pause, then the
-- frames one after another (docs/original.md: timing to check).
local anim = { wait = 6, frame = nil, t = 0 }
local ANIM_FRAME_TIME = 0.6

local function animate(dt)
    local a = cards.ANIMATIONS[S.back]
    if not a or #g.stock == 0 then anim.frame = nil; return end
    if anim.frame then
        anim.t = anim.t + dt
        if anim.t >= ANIM_FRAME_TIME then
            anim.t = 0
            anim.frame = anim.frame + 1
            if anim.frame > #a.frames then
                anim.frame = nil
                anim.wait = 5 + math.random() * 10
            end
        end
    else
        anim.wait = anim.wait - dt
        if anim.wait <= 0 then anim.frame, anim.t = 1, 0 end
    end
end

local function area()
    local y0 = Bar.H
    local h = H - y0 - (S.status and STATUS_H or 0)
    return { x = 0, y = y0, w = W, h = h }
end

local function relayout() L = table_.layout(area()) end

local function screen() return { x = 0, y = 0, w = W, h = H } end

local mouse_x, mouse_y   -- where the pointer was last seen on the canvas

local function new_seed()
    deal_count = deal_count + 1
    if sp.seed then return sp.seed + deal_count - 1 end
    return (os.time() * 31 + sp.ticks() + deal_count) & 0x7FFFFFFF
end

local function save()
    if g and g.scoring == "vegas" and S.keep_score then S.bank = g.score end
    settings.save(S)
end

-- ---- dealing ------------------------------------------------------------------

function game.deal()
    -- In Vegas with Keep score, the bank carries what this deal left.
    if g and g.scoring == "vegas" and S.keep_score then S.bank = g.score end
    g = rules.new({ draw = S.draw, scoring = S.scoring, timed = S.timed, keep_score = S.keep_score, bank = S.bank })
    g:deal(new_seed())
    drag, win = nil, nil
    if kb then kb.held = nil end
    save()
end

-- ---- dialogs ------------------------------------------------------------------

local function message(caption, lines, buttons, onclose)
    modal = Dialog.new({ template = templates.message(caption, lines, buttons), area = screen(),
                         onclose = function(d, id, key) modal = nil; if onclose then onclose(key) end end })
end

local option_keys = {
    ["draw one"] = { "draw", 1 }, ["draw three"] = { "draw", 3 },
    ["standard"] = { "scoring", "standard" }, ["vegas"] = { "scoring", "vegas" }, ["none"] = { "scoring", "none" },
    ["timed game"] = { "timed", true }, ["status bar"] = { "status", true },
    ["outline dragging"] = { "outline", true }, ["keep score"] = { "keep_score", true },
}

local function open_options()
    local t = templates.find_sol("options") or templates.options
    local values = {}
    for _, c in ipairs(t.controls) do
        local k = option_keys[Dialog.key(c.text)]
        if k then
            if type(k[2]) == "boolean" then values[c.id] = S[k[1]] and true or false
            else values[c.id] = S[k[1]] == k[2] end
        end
    end
    local function vegas_chosen(d)
        local e = d:find("vegas")
        return e and d.values[e.c.id]
    end
    modal = Dialog.new({
        template = t, area = screen(), values = values,
        enabled = function(c, key)
            if key == "keep score" then return modal == nil or vegas_chosen(modal) end
            return true
        end,
        onclose = function(d, id, key)
            modal = nil
            if key ~= "ok" then return end
            local old = { draw = S.draw, scoring = S.scoring, timed = S.timed }
            for _, e in ipairs(d.controls) do
                local k = option_keys[e.key]
                if k and d.values[e.c.id] ~= nil then
                    if type(k[2]) == "boolean" then S[k[1]] = d.values[e.c.id] and true or false
                    elseif d.values[e.c.id] then S[k[1]] = k[2] end
                end
            end
            if S.scoring ~= "vegas" then S.keep_score = false end
            relayout()
            save()
            -- Changing how it's played or scored starts a new game, as in the original.
            if S.draw ~= old.draw or S.scoring ~= old.scoring or S.timed ~= old.timed then
                if S.scoring == "vegas" and old.scoring ~= "vegas" then S.bank = 0 end
                game.deal()
            end
        end,
    })
end

local function open_deck()
    -- SOL.EXE's dialog numbers each owner-drawn button with the bitmap id
    -- of its back (in its own order); the port's stand-in does the same.
    local t = templates.find_sol("select card back") or templates.deck(cards.back_ids())
    local function back_of(c)
        if (c.class or ""):lower() == "button" and (c.style & 0xF) == 11 then return c.id end
    end
    local selected
    for _, c in ipairs(t.controls) do if back_of(c) == S.back then selected = c.id end end
    modal = Dialog.new({
        template = t, area = screen(), selected = selected,
        draw_owner = function(c, x, y, w, h, sel, focus)
            local id = back_of(c)
            if not id then return end
            -- The back, shrunk to fit, inside the button.
            local m = 4
            cards.draw_back_scaled(id, x + m, y + m, w - 2 * m, h - 2 * m)
            if sel then
                for k = 0, 2 do w31.box(x + k, y + k, w - 2 * k, h - 2 * k, w31.BLACK) end
            end
            if focus then w31.dotted(x + 1, y + 1, w - 2, h - 2) end
        end,
        onclose = function(d, id, key)
            modal = nil
            if key == "ok" and d.selected then
                S.back = d.selected
                save()
            end
        end,
    })
end

local function open_help(topic)
    local lines = templates.help[topic] or templates.help.contents
    message("Solitaire Help", lines, { "OK" })
end

local function about()
    local lines = {
        "Microsoft Solitaire",
        sp.string(108) or "Developed for Microsoft by Wes Cherry",
        "",
        "Played by Solitairepack, an open-source",
        "port. The cards are read from your own",
        "SOL.EXE; nothing of the original is",
        "included with it.",
    }
    if not cards.have_art then lines[#lines + 1] = ""; lines[#lines + 1] = "(SOL.EXE not found: plain cards.)" end
    message("About Solitaire", lines, { "OK" })
end

local function confirm_exit()
    save()
    sp.quit(0)
end

-- ---- commands (the menus and their keys) --------------------------------------

local commands = {
    deal = function() game.deal() end,
    undo = function() if g:undo() then drag = nil end end,
    deck = open_deck,
    options = open_options,
    exit = confirm_exit,
    contents = function() open_help("contents") end,
    ["search for help on"] = function() open_help("contents") end,
    ["how to play"] = function() open_help("contents") end,
    commands = function() open_help("keys") end,
    ["how to use help"] = function() open_help("keys") end,
    ["using help"] = function() open_help("keys") end,
    ["about solitaire"] = about,
}

local function run(name)
    local f = commands[name]
    if f then f() else sp.log("menu: no command for '" .. name .. "'") end
end

local function enabled(name)
    if name == "undo" then return g ~= nil and g:can_undo() end
    return true
end

local shortcuts = { deal = "F2", undo = "Ctrl+Z", contents = "F1" }

-- ---- the win --------------------------------------------------------------------

local function check_win()
    if g.over and not win then
        drag = nil
        if kb then kb.held = nil end
        win = cascade.new(L, g, new_seed())
        win.fresh = true   -- draw the whole table once more, then let it trail
        save()
    end
end

local function end_win()
    if not win then return end
    win = nil
    message(sp.string(100) or "Solitaire", { sp.string(104) or "Deal Again?" }, { "&Yes", "&No" }, function(key)
        if key == "yes" then game.deal() end
    end)
end

-- The game in play and the table's layout, for the tests.
function game.current() return g end
function game.layout() return L end

-- ---- startup ----------------------------------------------------------------------

function game.load()
    W, H = sp.canvas()
    sp.title("Solitaire")
    S = settings.load()
    cards.load()
    -- A back that isn't in this file (or the empty-pile pattern, 53, which an
    -- earlier version offered as a back) falls back to the first.
    local ok = false
    for _, id in ipairs(cards.back_ids()) do if id == S.back then ok = true end end
    if not ok then S.back = cards.back_ids()[1] end
    relayout()
    bar = Bar.new({ width = W, on_command = run, enabled = enabled,
                    shortcut = function(name) return not bar.from_sol and shortcuts[name] or nil end })
    game.deal()
    local has, err = sp.has_data()
    if not has then sp.log(err) end
end

-- Where the point (x, y) should be after the layout changes from old to
-- new: on the same spot of the same card or pile when it's over one; else
-- as far across the table, proportionally, and at the same height (the
-- piles don't move up or down); over the menu bar, unchanged.
function game.follow_point(old, new, x, y)
    if y < Bar.H then return math.min(x, W - 1), y end
    local kind, index, i = table_.hit(old, g, x, y)
    if kind then
        local ox, oy
        if i then
            local cs = table_.pile_cards(old, g, kind, index)
            ox, oy = cs[i].x, cs[i].y
        else
            ox, oy = table_.pile_base(old, kind, index)
        end
        local nx, ny
        if i then
            local cs = table_.pile_cards(new, g, kind, index)
            nx, ny = cs[i].x, cs[i].y
        else
            nx, ny = table_.pile_base(new, kind, index)
        end
        return nx + (x - ox), ny + (y - oy)
    end
    local fx = (x - old.area.x) / math.max(1, old.area.w)
    local nx = new.area.x + math.floor(fx * new.area.w + 0.5)
    local ny = math.min(y, new.area.y + new.area.h - 1)
    return math.max(0, math.min(nx, W - 1)), math.max(0, ny)
end

-- The window was resized (or went full screen): the table takes the new
-- size. The piles spread out evenly across it, the stock staying top left
-- and the foundations top right (table.lua); open dialogs re-centre; and
-- the mouse pointer, when it's free to move (pointer_free), follows what
-- it was over.
function game.resize(w, h, pointer_free)
    local old = L
    W, H = w, h
    relayout()
    if mouse_x and old then
        local nx, ny = mouse_x, mouse_y
        if modal then
            -- Over a dialog: the same spot on the dialog, wherever it moves.
            local dx, dy = modal.x, modal.y
            modal:center(screen())
            nx, ny = mouse_x + modal.x - dx, mouse_y + modal.y - dy
        elseif not bar:is_open() then
            nx, ny = game.follow_point(old, L, mouse_x, mouse_y)
        end
        nx = math.max(0, math.min(nx, W - 1))
        ny = math.max(0, math.min(ny, H - 1))
        mouse_x, mouse_y = nx, ny
        if pointer_free then sp.warp_mouse(nx, ny) end
    end
    bar.width = W
    drag = nil
    if modal then modal:center(screen()) end
    -- The canvas is new and blank, so the cascade's trails are gone: skip
    -- to its end, "Deal Again?".
    if win then end_win() end
end

-- ---- dragging -------------------------------------------------------------------------

local function overlap(ax, ay, bx, by)
    local w = math.min(ax, bx) + cards.W - math.max(ax, bx)
    local h = math.min(ay, by) + cards.H - math.max(ay, by)
    if w <= 0 or h <= 0 then return 0 end
    return w * h
end

-- The pile the dragged cards (run, its top-left at x, y) are mostly over,
-- where they'd be legal.
local function drop_target(run, x, y)
    local best, bk, bi = 0, nil, nil
    local function try(kind, index)
        local p = g:pile(kind, index)
        local tx, ty
        if #p > 0 then
            local cs = table_.pile_cards(L, g, kind, index)
            tx, ty = cs[#cs].x, cs[#cs].y
        else
            tx, ty = table_.pile_base(L, kind, index)
        end
        local a = overlap(x, y, tx, ty)
        if a > best and g:can_drop(run, kind, index) then best, bk, bi = a, kind, index end
    end
    for f = 1, 4 do try("found", f) end
    for t = 1, 7 do try("tab", t) end
    return bk, bi
end

local function start_drag(kind, index, i, px, py)
    if not g:can_pick(kind, index, i) then return end
    local cs = table_.pile_cards(L, g, kind, index)
    local run = {}
    for k = i, #cs do run[#run + 1] = cs[k].card end
    drag = { kind = kind, index = index, i = i, run = run, ox = px - cs[i].x, oy = py - cs[i].y,
             x = cs[i].x, y = cs[i].y, sx = px, sy = py, moved = false, rects = {} }
    for k = i, #cs do drag.rects[#drag.rects + 1] = { dx = cs[k].x - cs[i].x, dy = cs[k].y - cs[i].y } end
end

local function finish_drag()
    local d = drag
    drag = nil
    if not d or not d.moved then return end
    local kind, index = drop_target(d.run, d.x, d.y)
    if kind then g:move(d.kind, d.index, d.i, kind, index) end
    check_win()
end

-- ---- input --------------------------------------------------------------------------------

function game.mousepressed(x, y, button, clicks)
    mouse_x, mouse_y = x, y
    if kb then kb.show = false end
    if win then end_win(); return end
    if bar:mousepressed(x, y, button) then return end
    if modal then modal:mousepressed(x, y, button, clicks); return end
    if button == "right" then
        -- Every card that can go up to the foundations does.
        g:autoplay()
        check_win()
        return
    end
    if button ~= "left" then return end
    local kind, index, i = table_.hit(L, g, x, y)
    if not kind then return end
    if kind == "stock" then
        g:draw()
        return
    end
    local p = g:pile(kind, index)
    if clicks and clicks >= 2 and i == #p then
        if g:to_foundation(kind, index) then drag = nil; check_win(); return end
    end
    if kind == "tab" and i and i == #p and not p[i].up then
        g:flip(index)
        return
    end
    if i then start_drag(kind, index, i, x, y) end
end

function game.mousemoved(x, y)
    mouse_x, mouse_y = x, y
    if bar:mousemoved(x, y) then return end
    if drag then
        if math.abs(x - drag.sx) + math.abs(y - drag.sy) > 2 then drag.moved = true end
        drag.x, drag.y = x - drag.ox, y - drag.oy
    end
end

function game.mousereleased(x, y, button)
    if bar:mousereleased(x, y, button) then return end
    if modal then modal:mousereleased(x, y, button); return end
    if button == "left" then finish_drag() end
end

-- Keyboard / controller play: a cursor over the piles. Left / right move
-- along a row, up / down between the rows and along a column's face-up
-- cards; Space (A) turns the stock, turns a card over, picks cards up or
-- puts them down.
local TOP = { { "stock" }, { "waste" }, nil, { "found", 1 }, { "found", 2 }, { "found", 3 }, { "found", 4 } }

local function kb_init()
    kb = kb or { row = 2, col = 1, i = nil, show = true }
    kb.show = true
end

local function kb_pile()
    if kb.row == 1 then local t = TOP[kb.col]; return t[1], t[2] end
    return "tab", kb.col
end

local function kb_clamp()
    if kb.row == 1 and not TOP[kb.col] then kb.col = kb.col < 3 and 2 or 4 end
    if kb.row == 2 then
        local p = g.tab[kb.col]
        local first = #p
        for k = 1, #p do if p[k].up then first = k; break end end
        if not kb.i or kb.i > #p or kb.i < first then kb.i = math.max(#p, 1) end
        if kb.held then kb.i = math.max(#p, 1) end
    end
end

local function kb_move(dx, dy)
    if dx ~= 0 then
        kb.col = (kb.col - 1 + dx) % 7 + 1
        if kb.row == 1 and not TOP[kb.col] then kb.col = (kb.col - 1 + dx) % 7 + 1 end
        kb.i = nil
    elseif dy ~= 0 then
        if kb.row == 2 and not kb.held then
            local p = g.tab[kb.col]
            local first = #p
            for k = 1, #p do if p[k].up then first = k; break end end
            local ni = (kb.i or #p) + dy
            if dy < 0 and ni >= first and ni >= 1 then kb.i = ni; return end
            if dy > 0 and ni <= #p then kb.i = ni; return end
        end
        kb.row = kb.row == 1 and 2 or 1
        kb.i = nil
    end
    kb_clamp()
end

local function kb_select()
    local kind, index = kb_pile()
    if kb.held then
        local h = kb.held
        kb.held = nil
        if kind == h.kind and index == h.index then return end
        g:move(h.kind, h.index, h.i, kind, index)
        check_win()
        kb_clamp()
        return
    end
    local p = g:pile(kind, index)
    if kind == "stock" then g:draw(); return end
    if #p == 0 then return end
    if kind == "tab" and not p[#p].up then g:flip(index); kb.i = #p; return end
    local i = kind == "tab" and (kb.i or #p) or #p
    if g:can_pick(kind, index, i) then kb.held = { kind = kind, index = index, i = i } end
end

function game.keypressed(k, isrepeat)
    if win then if not isrepeat then end_win() end; return end
    if modal then modal:keypressed(k); return end
    if bar:keypressed(k) then return end
    local ctrl = sp.key_down("left ctrl") or sp.key_down("right ctrl")
    if k == "f2" then game.deal(); return end
    if k == "f1" then open_help("contents"); return end
    if (ctrl and k == "z") or k == "backspace" or k == "pad back" then commands.undo(); return end
    if k == "escape" or k == "pad start" or k == "f12" then
        if kb and kb.held then kb.held = nil; return end
        if k == "pad start" or k == "f12" then bar:open_menu(1) end
        return
    end
    local dirs = { left = { -1, 0 }, right = { 1, 0 }, up = { 0, -1 }, down = { 0, 1 },
                   ["pad dpleft"] = { -1, 0 }, ["pad dpright"] = { 1, 0 }, ["pad dpup"] = { 0, -1 }, ["pad dpdown"] = { 0, 1 } }
    if dirs[k] then
        local first = not (kb and kb.show)
        kb_init()
        if not first then kb_move(dirs[k][1], dirs[k][2]) else kb_clamp() end
        return
    end
    if k == "space" or k == "return" or k == "pad a" then kb_init(); kb_clamp(); kb_select(); return end
    if k == "pad b" then if kb then kb.held = nil end; return end
    if k == "pad x" then g:draw(); return end
    if k == "pad y" then g:autoplay(); check_win(); return end
    if k == "pad leftshoulder" then
        -- To the foundation: the card under the cursor's pile top.
        if kb then local kind, index = kb_pile(); g:to_foundation(kind, index); check_win(); kb_clamp() end
        return
    end
end

-- ---- every frame --------------------------------------------------------------------------

function game.update(dt)
    game.last_dt = dt   -- the cascade runs in game.draw, at this frame's pace
    if not modal and not win and not bar:is_open() then g:tick(dt) end
    if not win then animate(dt) end
end

local function draw_status()
    if not S.status then return end
    local y = H - STATUS_H
    w31.rect(0, y, W, STATUS_H, w31.WHITE)
    sp.fill(0, y, W, 1, 0, 0, 0)
    -- The labels are SOL.EXE's own strings when it's there.
    local parts = {}
    local score_label = sp.string(101) or "Score: "
    if g.scoring == "vegas" then
        parts[#parts + 1] = score_label .. (g.score < 0 and "-$" .. -g.score or "$" .. g.score)
    elseif g.scoring == "standard" then
        parts[#parts + 1] = score_label .. g.score
    end
    if g.timed then parts[#parts + 1] = (sp.string(102) or "Time: ") .. math.floor(g.time) end
    local s = table.concat(parts, "     ")
    w31.text(W - 10 - w31.width(s), y + 4, s)
    if win then
        w31.text(8, y + 4, sp.string(106) or "Click or press Esc to stop...")
    elseif g.bonus > 0 then
        w31.text(8, y + 4, (sp.string(107) or "Bonus: ") .. g.bonus)
    end
end

local function draw_dragged()
    if not drag or not drag.moved then return end
    if S.outline then
        local last = drag.rects[#drag.rects]
        cards.draw_outline(drag.x, drag.y, cards.W, last.dy + cards.H)
        return
    end
    for k, c in ipairs(drag.run) do
        local r = drag.rects[k]
        cards.draw_face(c, drag.x + r.dx, drag.y + r.dy)
    end
end

local function draw_cursor()
    if not kb or not kb.show or modal or win then return end
    local kind, index = kb_pile()
    local x, y
    local cs = table_.pile_cards(L, g, kind, index)
    if kind == "tab" and #cs > 0 then
        local i = math.min(kb.i or #cs, #cs)
        x, y = cs[i].x, cs[i].y
    elseif #cs > 0 then
        x, y = cs[#cs].x, cs[#cs].y
    else
        x, y = table_.pile_base(L, kind, index)
    end
    local c = kb.held and { 255, 255, 0 } or { 0, 0, 128 }
    for k = 0, 2 do
        sp.fill(x - 2 - k, y - 2 - k, cards.W + 4 + 2 * k, 1, c[1], c[2], c[3])
        sp.fill(x - 2 - k, y + cards.H + 1 + k, cards.W + 4 + 2 * k, 1, c[1], c[2], c[3])
        sp.fill(x - 2 - k, y - 2 - k, 1, cards.H + 4 + 2 * k, c[1], c[2], c[3])
        sp.fill(x + cards.W + 1 + k, y - 2 - k, 1, cards.H + 4 + 2 * k, c[1], c[2], c[3])
    end
end

function game.draw()
    if win and not win.fresh then
        -- The cascade draws over what's there; only the bars are redrawn.
        win:update_draw(game.last_dt or 1 / 60)
        bar:draw()
        draw_status()
        if win.done then end_win() end
        return
    end
    sp.clear(cards.TABLE[1], cards.TABLE[2], cards.TABLE[3])
    local held = drag and drag.moved and not S.outline and drag or nil
    if kb and kb.held and not drag then held = nil end
    table_.draw(L, g, S.back, held, anim.frame)
    draw_dragged()
    draw_cursor()
    if win then win.fresh = false end
    draw_status()
    bar:draw()
    if modal then modal:draw() end
end


game.load()
