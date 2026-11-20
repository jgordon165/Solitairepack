// Solitairepack: C++ host for a port of Solitaire from Windows 3.1 (1992).
// Owns the window and input, and runs the game logic written in Lua
// (scripts/). The original's card art and text are read at runtime from the
// player's own SOL.EXE (and CARDS.DLL, when they have one); nothing from
// them is compiled in or shipped.
//
// Usage: solitairepack --data <folder with SOL.EXE, or a Windows 3.1 setup
//                              disk with SOL.EX_>
//                      [--scale N] [--size WxH] [--scripts <dir>] [--seed N]
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
#ifdef _WIN32
#define WIN32_LEAN_AND_MEAN
#define NOMINMAX
#include <windows.h>
#endif
#include <algorithm>
#include <cctype>
#include <cstdio>
#include <cstdlib>
#include <filesystem>
#include <string>
#include <vector>

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

// Looks in dir, then one level down (a folder holding WINDOWS\, or a CD
// holding DISK1\, ...).
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
    // Each file as installed, or still compressed as on the setup disks
    // (SOL.EX_), which NeFile::load expands.
    auto load = [&](std::initializer_list<const char*> names, std::optional<tp::NeFile>& out) {
        for (const char* name : names) {
            const fs::path p = findNear(dir, name);
            if (p.empty()) continue;
            try {
                out = tp::NeFile::load(p.string());
                return true;
            } catch (const std::exception& ex) {
                std::fprintf(stderr, "%s: %s\n", p.string().c_str(), ex.what());
            }
        }
        return false;
    };
    // Windows 3.0 and 3.1 keep the cards in SOL.EXE itself. A 16-bit
    // CARDS.DLL (Windows for Workgroups) is a fallback for them.
    load({"SOL.EXE", "SOL.EX_"}, sol);
    load({"CARDS.DLL", "CARDS.DL_"}, cards);
    if (!sol && !cards) {
        dataError = "SOL.EXE (or SOL.EX_) not found in " + dataArg;
        return false;
    }
    return true;
}

// In a normal run a script error is reported (once, in a message box, and
// every time on stderr) and the game carries on, rather than closing the
// window mid-game. Headless (test) runs stop on the first error instead.
static bool g_keepGoing = false;
static bool g_reported = false;

static int traceback(lua_State* L) {
    luaL_traceback(L, L, lua_tostring(L, 1), 1);
    return 1;
}

static bool callLua(lua_State* L, const char* fn, int nargs) {
    lua_getglobal(L, "game");
    if (!lua_istable(L, -1)) { lua_pop(L, 1 + nargs); return true; }
    lua_getfield(L, -1, fn);
    lua_remove(L, -2);
    if (!lua_isfunction(L, -1)) { lua_pop(L, 1 + nargs); return true; }
    lua_insert(L, -1 - nargs);
    lua_pushcfunction(L, traceback);
    lua_insert(L, -2 - nargs);
    const int handler = lua_gettop(L) - nargs - 1;
    if (lua_pcall(L, nargs, 0, handler) != LUA_OK) {
        const std::string msg = std::string("lua error in game.") + fn + ": " + lua_tostring(L, -1);
        lua_pop(L, 2);  // the message and the handler
        std::fprintf(stderr, "%s\n", msg.c_str());
        if (!g_keepGoing) return false;
        if (!g_reported) {
            g_reported = true;
            const std::string box = msg + "\n\nThe game will keep running. Please report this at "
                                          "https://github.com/jgordon165/Solitairepack/issues";
            SDL_ShowSimpleMessageBox(SDL_MESSAGEBOX_WARNING, "Solitairepack: script error", box.c_str(), nullptr);
        }
        return true;
    }
    lua_pop(L, 1);  // the handler
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
    int startW = 640, startH = 440;

    for (int i = 1; i < argc; ++i) {
        std::string a = argv[i];
        auto next = [&]() -> std::string { return i + 1 < argc ? argv[++i] : ""; };
        if      (a == "--data")    eng.dataArg = next();
        else if (a == "--scripts") scripts = next();
        else if (a == "--scale")   scale = std::max(1.0, std::atof(next().c_str()));
        else if (a == "--frames")  maxFrames = std::atol(next().c_str());
        else if (a == "--screenshot") shot = next();
        else if (a == "--seed")    seed = std::atoll(next().c_str());
        else if (a == "--size") {   // the table's starting size, e.g. 1280x720
            const std::string v = next();
            const auto x = v.find_first_of("xX");
            if (x != std::string::npos) {
                startW = std::max(530, std::atoi(v.substr(0, x).c_str()));
                startH = std::max(340, std::atoi(v.substr(x + 1).c_str()));
            }
        }
        else if (a == "--help" || a == "-h") {
            std::printf("solitairepack --data <folder with your SOL.EXE, or a Windows 3.1 setup disk> [--scale N] [--seed N]\n");
            return 0;
        }
    }
    if (scripts.empty()) {
        char* base = SDL_GetBasePath();
        scripts = (base ? std::string(base) : std::string("./")) + "scripts";
        SDL_free(base);
    }
    // Without --data: a "data" folder beside the program, the program's own
    // folder, and on Windows each drive's root and WINDOWS folder (a
    // Windows 3.1 CD or disk in the drive, an old install), in that order.
    if (eng.dataArg.empty()) {
        std::vector<std::string> tries = {"data"};
        if (char* base = SDL_GetBasePath()) {
            tries.push_back(std::string(base) + "data");
            tries.push_back(base);
            SDL_free(base);
        }
#ifdef _WIN32
        // An empty CD drive must not bring up "There is no disk in the drive".
        const UINT oldMode = SetErrorMode(SEM_FAILCRITICALERRORS | SEM_NOOPENFILEERRORBOX);
        for (char d = 'C'; d <= 'Z'; ++d) {
            const std::string root = std::string(1, d) + ":\\";
            std::error_code ec;
            if (!fs::exists(root, ec)) continue;
            tries.push_back(root);
            tries.push_back(root + "WINDOWS");
        }
        SetErrorMode(oldMode);
#endif
        bool found = false;
        for (const auto& t : tries) {
            eng.dataArg = t;
            eng.dataError.clear();
            if (eng.loadData()) { found = true; break; }
        }
        if (!found) {
            eng.dataArg = "data";
            eng.dataError = "SOL.EXE not found (use --data <folder>)";
        }
        if (found) std::fprintf(stderr, "using %s\n", eng.dataArg.c_str());
        else std::fprintf(stderr, "%s (playing with plain cards)\n", eng.dataError.c_str());
    } else if (!eng.loadData()) {
        std::fprintf(stderr, "%s (playing with plain cards)\n", eng.dataError.c_str());
    }

    if (SDL_Init(SDL_INIT_VIDEO | SDL_INIT_EVENTS) != 0) {
        std::fprintf(stderr, "SDL_Init: %s\n", SDL_GetError());
        return 1;
    }
    if (SDL_InitSubSystem(SDL_INIT_GAMECONTROLLER) != 0)
        std::fprintf(stderr, "controllers unavailable: %s\n", SDL_GetError());
    // 640 x 440 (unless --size): the original maximized on a 640 x 480 screen. The window
    // can be resized (or made full screen with F11) down to 7 columns of
    // cards; the table grows and shrinks with it.
    if (!eng.video.open("Solitaire", startW, startH, scale, 530, 340)) { SDL_Quit(); return 1; }

    // Options and the Vegas bank persist, except in headless (test) runs.
    const bool headless = maxFrames >= 0;
    g_keepGoing = !headless;
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
            else if (ev.type == SDL_WINDOWEVENT && ev.window.event == SDL_WINDOWEVENT_SIZE_CHANGED) {
                // game.resize(w, h): the canvas now has this size.
                if (eng.video.fitCanvas()) {
                    lua_pushinteger(L, eng.video.canvasW());
                    lua_pushinteger(L, eng.video.canvasH());
                    ok = callLua(L, "resize", 2) && ok;
                }
            } else if (ev.type == SDL_KEYDOWN && ev.key.keysym.sym == SDLK_F11 && !ev.key.repeat) {
                eng.video.toggleFullscreen();
            } else if (ev.type == SDL_KEYDOWN) {
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
