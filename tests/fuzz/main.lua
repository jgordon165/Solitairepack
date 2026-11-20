-- Random play through the game's input (ctest "fuzz"): clicks, drags,
-- right-clicks, double-clicks, keys, controller buttons and window
-- resizes, 40 a frame,
-- checking after each that no script error happened and no card was lost.
-- FUZZSEED picks the sequence. Exit is ignored so the run goes the distance.

sp.seed = 5
dofile(os.getenv("SOLITAIREPACK_SCRIPTS") .. "/main.lua")
local s = tonumber(os.getenv("FUZZSEED") or "12345")
local function r(n) s = (s * 1103515245 + 12345) & 0x7FFFFFFF; return (s >> 16) % n end
local keys = {"left","right","up","down","space","return","escape","backspace","pad a","pad b","pad x","pad y","pad leftshoulder","pad start","pad dpup","pad dpdown","f10","f2","o","c","tab"}
local it, upd, drw = 0, game.update, game.draw
game.update = function(dt)
  for _ = 1, 40 do
    it = it + 1
    local ok, err = pcall(function()
      if r(3) == 0 then game.keypressed(keys[r(#keys)+1], false)
      else
        local x, y = r(640), r(440)
        local b = r(10) == 0 and "right" or "left"
        game.mousepressed(x, y, b, 1 + (r(4) == 0 and 1 or 0))
        for k = 1, 3 do game.mousemoved(r(640), r(440)) end
        game.mousereleased(r(640), r(440), b)
      end
      upd(1/60)
      local g = game.current()
      assert(g:count() == 52, "lost cards: " .. g:count())
      if r(300) == 0 then game.keypressed("f2", false) end
      -- Now and then the window changes size (the canvas with it).
      if r(150) == 0 then
        local w, h = 530 + r(1400), 340 + r(800)
        sp.canvas(w, h)
        game.resize(w, h, r(2) == 0)
      end
    end)
    if not ok then sp.log("iter " .. it .. ": " .. tostring(err)); sp.quit(1); return end
  end
end
game.draw = function() drw() end
-- Game > Exit, reached by random keys, would end the run early.
local q = sp.quit
sp.quit = function(c) if c ~= 0 then q(c) end end
