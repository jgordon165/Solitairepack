// Solitairepack: C++ host for a port of Solitaire from Windows 3.1 (1992).
// Owns the window and input, and runs the game logic written in Lua
// (scripts/). The original's card art and text are read at runtime from the
// player's own SOL.EXE and CARDS.DLL; nothing from them is compiled in or
// shipped.
//
// Usage: solitairepack --data <folder with SOL.EXE and CARDS.DLL>
//                      [--scale N] [--scripts <dir>] [--seed N]
//                      [--frames N [--screenshot out.bmp]]   (headless testing)

#include "engine.h"
#include "input.h"
#include "lua_api.h"

extern "C" {
#include "lauxlib.h"
#include "lua.h"
#include "lualib.h"
}

#include <SDL.h>
#include <algorithm>
#include <cctype>
#include <cstdio>
#include <cstdlib>
#include <filesystem>
#include <string>

namespace fs = std::filesystem;

// Case-insensitive: SOL.EXE, Sol.exe, ...
static fs::path findFile(const fs::path& dir, const std::string& upperName) {
    std::error_code ec;
    for (const auto& ent : fs::directory_iterator(dir, ec)) {
        std::string n = ent.path().filename().string();
        for (auto& c : n) c = static_cast<char>(std::toupper(static_cast<unsigned char>(c)));
        if (n == upperName && ent.is_regular_file(ec)) return ent.path();
    }
    return {};
}

// Looks in dir, then one level down (a WINDOWS folder holding SYSTEM\ has
// SOL.EXE in one and CARDS.DLL in the other).
static fs::path findNear(const fs::path& dir, const std::string& upperName) {
    std::error_code ec;
    fs::path found = findFile(dir, upperName);
    if (found.empty())
        for (const auto& ent : fs::directory_iterator(dir, ec))
            if (ent.is_directory(ec) && !(found = findFile(ent.path(), upperName)).empty()) break;
    return found;
}

bool Engine::loadData() {
    std::error_code ec;
    fs::path dir = dataArg;
    if (fs::is_regular_file(dir, ec)) dir = dir.parent_path().empty() ? fs::path(".") : dir.parent_path();
    if (!fs::is_directory(dir, ec)) {
        dataError = "no folder " + dataArg;
        return false;
    }
    auto load = [&](const char* name, std::optional<tp::NeFile>& out) {
        const fs::path p = findNear(dir, name);
        if (p.empty()) return false;
        try {
            out = tp::NeFile::load(p.string());
            return true;
        } catch (const std::exception& ex) {
            std::fprintf(stderr, "%s: %s\n", p.string().c_str(), ex.what());
            return false;
        }
    };
    if (!load("SOL.EXE", sol)) std::fprintf(stderr, "SOL.EXE not found in %s (using the port's own text)\n", dataArg.c_str());
    if (!load("CARDS.DLL", cards)) {
        dataError = "CARDS.DLL not found in " + dataArg;
        return false;
    }
    return true;
}

static bool callLua(lua_State* L, const char* fn, int nargs) {
    lua_getglobal(L, "game");
    if (!lua_istable(L, -1)) { lua_pop(L, 1 + nargs); return true; }
    lua_getfield(L, -1, fn);
    lua_remove(L, -2);
    if (!lua_isfunction(L, -1)) { lua_pop(L, 1 + nargs); return true; }
    lua_insert(L, -1 - nargs);
    if (lua_pcall(L, nargs, 0, 0) != LUA_OK) {
        std::fprintf(stderr, "lua error in game.%s: %s\n", fn, lua_tostring(L, -1));
        lua_pop(L, 1);
        return false;
    }
    return true;
}

static void addPackagePath(lua_State* L, const std::string& dir) {
    lua_getglobal(L, "package");
    lua_getfield(L, -1, "path");
    std::string path = lua_tostring(L, -1);
    lua_pop(L, 1);
    path = dir + "/?.lua;" + dir + "/?/init.lua;" + path;
    lua_pushstring(L, path.c_str());
    lua_setfield(L, -2, "path");
    lua_pop(L, 1);
}

static void pushButton(lua_State* L, Uint8 b) {
    lua_pushstring(L, b == SDL_BUTTON_LEFT ? "left" : b == SDL_BUTTON_RIGHT ? "right" : b == SDL_BUTTON_MIDDLE ? "middle" : "other");
}

int main(int argc, char** argv) {
    Engine eng;
    std::string scripts;
    double scale = 1.5;  // a 640x440 client (the original maximized on a 640x480 screen) at 960x660
    long maxFrames = -1;
    std::string shot;
    lua_Integer seed = -1;

    for (int i = 1; i < argc; ++i) {
        std::string a = argv[i];
        auto next = [&]() -> std::string { return i + 1 < argc ? argv[++i] : ""; };
        if      (a == "--data")    eng.dataArg = next();
        else if (a == "--scripts") scripts = next();
        else if (a == "--scale")   scale = std::max(1.0, std::atof(next().c_str()));
        else if (a == "--frames")  maxFrames = std::atol(next().c_str());
        else if (a == "--screenshot") shot = next();
        else if (a == "--seed")    seed = std::atoll(next().c_str());
        else if (a == "--help" || a == "-h") {
            std::printf("solitairepack --data <folder with your SOL.EXE and CARDS.DLL> [--scale N] [--seed N]\n");
            return 0;
        }
    }
    if (scripts.empty()) {
        char* base = SDL_GetBasePath();
        scripts = (base ? std::string(base) : std::string("./")) + "scripts";
        SDL_free(base);
    }
    if (eng.dataArg.empty()) eng.dataArg = "data";
    if (!eng.loadData()) std::fprintf(stderr, "%s (playing with plain cards)\n", eng.dataError.c_str());

    if (SDL_Init(SDL_INIT_VIDEO | SDL_INIT_EVENTS) != 0) {
        std::fprintf(stderr, "SDL_Init: %s\n", SDL_GetError());
        return 1;
    }
    if (SDL_InitSubSystem(SDL_INIT_GAMECONTROLLER) != 0)
        std::fprintf(stderr, "controllers unavailable: %s\n", SDL_GetError());
    if (!eng.video.open("Solitaire", 640, 440, scale)) { SDL_Quit(); return 1; }

    // Options and the Vegas bank persist, except in headless (test) runs.
    const bool headless = maxFrames >= 0;
    eng.storage.open(!headless);

    lua_State* L = luaL_newstate();
    luaL_openlibs(L);
    registerLuaApi(L, &eng);
    // sp.seed: --seed, or nil for a fresh shuffle each deal.
    lua_getglobal(L, "sp");
    if (seed >= 0) lua_pushinteger(L, seed); else lua_pushnil(L);
    lua_setfield(L, -2, "seed");
    lua_pushboolean(L, headless);
    lua_setfield(L, -2, "headless");
    lua_pop(L, 1);
    if (const char* extra = std::getenv("SOLITAIREPACK_SCRIPTS")) addPackagePath(L, extra);
    addPackagePath(L, scripts);
    const std::string mainLua = scripts + "/main.lua";
    if (luaL_dofile(L, mainLua.c_str()) != LUA_OK) {
        std::fprintf(stderr, "lua: %s\n", lua_tostring(L, -1));
        lua_close(L);
        SDL_Quit();
        return 1;
    }

    bool ok = true;
    Uint64 last = SDL_GetPerformanceCounter();
    for (long frame = 0; ok && !eng.quit && (!headless || frame < maxFrames); ++frame) {
        SDL_Event ev;
        while (SDL_PollEvent(&ev)) {
            if (ev.type == SDL_QUIT) eng.quit = true;
            else if (ev.type == SDL_KEYDOWN) {
                lua_pushstring(L, input::keyName(ev.key.keysym.sym).c_str());
                lua_pushboolean(L, ev.key.repeat != 0);
                ok = callLua(L, "keypressed", 2) && ok;
            } else if (ev.type == SDL_MOUSEBUTTONDOWN || ev.type == SDL_MOUSEBUTTONUP) {
                // game.mousepressed(x, y, "left" | "right" | "middle", clicks)
                // game.mousereleased(x, y, button), in canvas pixels (clamped
                // to the canvas when the pointer is in the letterbox).
                int cx = 0, cy = 0;
                eng.video.windowToCanvas(ev.button.x, ev.button.y, cx, cy);
                lua_pushinteger(L, std::clamp(cx, 0, eng.video.canvasW() - 1));
                lua_pushinteger(L, std::clamp(cy, 0, eng.video.canvasH() - 1));
                pushButton(L, ev.button.button);
                if (ev.type == SDL_MOUSEBUTTONDOWN) {
                    lua_pushinteger(L, ev.button.clicks);
                    ok = callLua(L, "mousepressed", 4) && ok;
                } else {
                    ok = callLua(L, "mousereleased", 3) && ok;
                }
            } else if (ev.type == SDL_MOUSEMOTION) {
                int cx = 0, cy = 0;
                eng.video.windowToCanvas(ev.motion.x, ev.motion.y, cx, cy);
                lua_pushinteger(L, std::clamp(cx, 0, eng.video.canvasW() - 1));
                lua_pushinteger(L, std::clamp(cy, 0, eng.video.canvasH() - 1));
                ok = callLua(L, "mousemoved", 2) && ok;
            } else if (ev.type == SDL_MOUSEWHEEL) {
                lua_pushstring(L, ev.wheel.y > 0 ? "wheelup" : "wheeldown");
                lua_pushboolean(L, 0);
                if (ev.wheel.y != 0) ok = callLua(L, "keypressed", 2) && ok;
            } else if (ev.type == SDL_CONTROLLERDEVICEADDED) {
                SDL_GameControllerOpen(ev.cdevice.which);
            } else if (ev.type == SDL_CONTROLLERBUTTONDOWN) {
                // "pad start", "pad a", "pad dpup", ... (SDL's button names)
                const char* b = SDL_GameControllerGetStringForButton(
                    static_cast<SDL_GameControllerButton>(ev.cbutton.button));
                lua_pushstring(L, (std::string("pad ") + (b ? b : "?")).c_str());
                lua_pushboolean(L, 0);
                ok = callLua(L, "keypressed", 2) && ok;
            }
        }
        // Headless runs step a fixed 1/60 s so tests are deterministic.
        const Uint64 now = SDL_GetPerformanceCounter();
        double dt = headless ? 1.0 / 60.0 : double(now - last) / double(SDL_GetPerformanceFrequency());
        last = now;
        dt = std::min(dt, 0.1);
        lua_pushnumber(L, dt);
        ok = callLua(L, "update", 1) && ok;
        ok = callLua(L, "draw", 0) && ok;
        eng.video.compose();
        if (!shot.empty() && headless && frame == maxFrames - 1 && !eng.video.screenshot(shot))
            std::fprintf(stderr, "screenshot failed: %s\n", SDL_GetError());
        eng.video.present();
    }

    lua_close(L);
    SDL_Quit();
    if (!ok) return 1;
    return eng.exitCode;
}
