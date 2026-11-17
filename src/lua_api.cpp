#include "lua_api.h"

#include "engine.h"
#include "formats/dialog.h"
#include "formats/dib.h"
#include "formats/menu.h"
#include "input.h"

extern "C" {
#include "lauxlib.h"
#include "lua.h"
}

#include <SDL.h>
#include <memory>
#include <utility>
#include <cstdio>
#include <string>

namespace {

Engine* eng(lua_State* L) {
    return static_cast<Engine*>(lua_touserdata(L, lua_upvalueindex(1)));
}

uint8_t u8arg(lua_State* L, int i, lua_Integer def = 0) {
    const lua_Integer v = luaL_optinteger(L, i, def);
    return static_cast<uint8_t>(v < 0 ? 0 : v > 255 ? 255 : v);
}

int iarg(lua_State* L, int i) { return static_cast<int>(luaL_checkinteger(L, i)); }

// Three pixels at each corner made transparent: the rounding of a card.
void roundCorners(tp::Image& img) {
    if (img.width < 4 || img.height < 4) return;
    auto clear = [&](int x, int y) { img.rgba[static_cast<size_t>(y) * img.width + x] = 0; };
    const int r = img.width - 1, b = img.height - 1;
    for (const auto& [x, y] : {std::pair{0, 0}, {1, 0}, {0, 1}}) {
        clear(x, y); clear(r - x, y); clear(x, b - y); clear(r - x, b - y);
    }
}

// sp.has_data() -> bool (CARDS.DLL loaded), error message, bool (SOL.EXE loaded)
int l_has_data(lua_State* L) {
    lua_pushboolean(L, eng(L)->cards.has_value());
    lua_pushstring(L, eng(L)->dataError.c_str());
    lua_pushboolean(L, eng(L)->sol.has_value());
    return 3;
}

const std::optional<tp::NeFile>& moduleArg(lua_State* L, int i) {
    return eng(L)->module(luaL_optstring(L, i, "cards"));
}

// sp.module(["sol"]) -> the module name and its expected Windows version
// (nil when that file isn't there)
int l_module(lua_State* L) {
    const auto& e = moduleArg(L, 1);
    if (!e) return 0;
    lua_pushstring(L, e->moduleName().c_str());
    lua_pushfstring(L, "%d.%d", e->expectedWindowsMajor(), e->expectedWindowsMinor());
    return 2;
}

// sp.resources() -> { {type=, name=, size=}, ... }
int l_resources(lua_State* L) {
    const auto& e = moduleArg(L, 1);
    lua_newtable(L);
    if (!e) return 1;
    int n = 0;
    for (const auto& r : e->resources()) {
        lua_newtable(L);
        lua_pushstring(L, r.typeName.empty() ? tp::resTypeName(r.typeId) : r.typeName.c_str());
        lua_setfield(L, -2, "type");
        lua_pushstring(L, r.key.str().c_str());
        lua_setfield(L, -2, "name");
        lua_pushinteger(L, r.length);
        lua_setfield(L, -2, "size");
        lua_rawseti(L, -2, ++n);
    }
    return 1;
}

// sp.bitmap("NAME" or "#12" or 12 [, "cards" | "sol" [, round]]) -> handle,
// width, height | nil, error. round: clear the corner pixels, as CARDS.DLL's
// cdtDraw paints a card's corners in the table colour.
int l_bitmap(lua_State* L) {
    const auto& e = moduleArg(L, 2);
    if (!e) { lua_pushnil(L); lua_pushstring(L, "no game data"); return 2; }
    const tp::NeResource* r = lua_isinteger(L, 1)
        ? e->find(static_cast<uint16_t>(tp::ResType::Bitmap), static_cast<uint16_t>(lua_tointeger(L, 1)))
        : e->find(static_cast<uint16_t>(tp::ResType::Bitmap), std::string(luaL_checkstring(L, 1)));
    if (!r) { lua_pushnil(L); lua_pushstring(L, "no such bitmap"); return 2; }
    try {
        auto img = tp::decodeDib(e->read(*r));
        if (lua_toboolean(L, 3)) roundCorners(img);
        lua_pushinteger(L, eng(L)->video.addImage(img));
        lua_pushinteger(L, img.width);
        lua_pushinteger(L, img.height);
        return 3;
    } catch (const std::exception& ex) {
        lua_pushnil(L);
        lua_pushstring(L, ex.what());
        return 2;
    }
}

// sp.string(id) -> string | nil (SOL.EXE's string table)
int l_string(lua_State* L) {
    const auto& e = eng(L)->sol;
    if (!e) return 0;
    const auto s = e->string(static_cast<uint16_t>(luaL_checkinteger(L, 1)));
    if (!s) return 0;
    lua_pushlstring(L, s->data(), s->size());
    return 1;
}

// sp.dialog(id [, "cards" | "sol"]) -> { x, y, w, h, caption, controls = { { x, y, w, h,
// id, style, class, text }, ... } } in dialog units | nil, error
int l_dialog(lua_State* L) {
    const auto& e = moduleArg(L, 2);
    if (!e) { lua_pushnil(L); lua_pushstring(L, "no such file"); return 2; }
    const uint16_t type = static_cast<uint16_t>(tp::ResType::Dialog);
    const tp::NeResource* r = lua_isinteger(L, 1) ? e->find(type, static_cast<uint16_t>(lua_tointeger(L, 1)))
                                                  : e->find(type, std::string(luaL_checkstring(L, 1)));
    if (!r) { lua_pushnil(L); lua_pushstring(L, "no such dialog"); return 2; }
    try {
        const tp::Dialog d = tp::decodeDialog(e->read(*r));
        auto setInt = [L](const char* k, lua_Integer v) { lua_pushinteger(L, v); lua_setfield(L, -2, k); };
        auto setStr = [L](const char* k, const std::string& v) { lua_pushlstring(L, v.data(), v.size()); lua_setfield(L, -2, k); };
        lua_newtable(L);
        setInt("x", d.x); setInt("y", d.y); setInt("w", d.w); setInt("h", d.h);
        setInt("style", d.style);
        setStr("caption", d.caption);
        lua_newtable(L);
        int n = 0;
        for (const auto& c : d.controls) {
            lua_newtable(L);
            setInt("x", c.x); setInt("y", c.y); setInt("w", c.w); setInt("h", c.h);
            setInt("id", c.id); setInt("style", c.style);
            setStr("class", c.cls); setStr("text", c.text);
            lua_rawseti(L, -2, ++n);
        }
        lua_setfield(L, -2, "controls");
        return 1;
    } catch (const std::exception& ex) {
        lua_pushnil(L);
        lua_pushstring(L, ex.what());
        return 2;
    }
}

void pushMenu(lua_State* L, const std::vector<tp::MenuItem>& items) {
    lua_newtable(L);
    int n = 0;
    for (const auto& m : items) {
        lua_newtable(L);
        lua_pushlstring(L, m.text.data(), m.text.size());
        lua_setfield(L, -2, "text");
        lua_pushinteger(L, m.id);
        lua_setfield(L, -2, "id");
        lua_pushinteger(L, m.flags);
        lua_setfield(L, -2, "flags");
        lua_pushboolean(L, m.separator());
        lua_setfield(L, -2, "separator");
        if (m.flags & tp::MenuItem::Popup) {
            pushMenu(L, m.items);
            lua_setfield(L, -2, "items");
        }
        lua_rawseti(L, -2, ++n);
    }
}

// sp.menu(id or "NAME" [, "cards" | "sol"]) -> { { text, id, flags, separator,
// items = { ... } }, ... } (the menu bar's pop-ups) | nil, error
int l_menu(lua_State* L) {
    const auto& e = moduleArg(L, 2);
    if (!e) { lua_pushnil(L); lua_pushstring(L, "no such file"); return 2; }
    const uint16_t type = static_cast<uint16_t>(tp::ResType::Menu);
    const tp::NeResource* r = lua_isinteger(L, 1) ? e->find(type, static_cast<uint16_t>(lua_tointeger(L, 1)))
                                                  : e->find(type, std::string(luaL_checkstring(L, 1)));
    if (!r) { lua_pushnil(L); lua_pushstring(L, "no such menu"); return 2; }
    try {
        pushMenu(L, tp::decodeMenu(e->read(*r)));
        return 1;
    } catch (const std::exception& ex) {
        lua_pushnil(L);
        lua_pushstring(L, ex.what());
        return 2;
    }
}

// sp.exe_string(prefix [, "cards" | "sol"]) -> the first NUL-terminated string in the
// file starting with prefix (text kept in the data segment), or nil
int l_exe_string(lua_State* L) {
    const auto& e = moduleArg(L, 2);
    if (!e) return 0;
    const auto s = e->cstringStartingWith(luaL_checkstring(L, 1));
    if (!s) return 0;
    lua_pushlstring(L, s->data(), s->size());
    return 1;
}

// sp.storage_read(name) -> text | nil; sp.storage_write(name, text) -> bool.
// Small files the game keeps between runs (src/storage.h); names are
// letters, digits and '_'.
int l_storage_read(lua_State* L) {
    std::string text;
    if (!eng(L)->storage.read(luaL_checkstring(L, 1), text)) return 0;
    lua_pushlstring(L, text.data(), text.size());
    return 1;
}

int l_storage_write(lua_State* L) {
    size_t n = 0;
    const char* text = luaL_checklstring(L, 2, &n);
    lua_pushboolean(L, eng(L)->storage.write(luaL_checkstring(L, 1), std::string(text, n)));
    return 1;
}

int l_canvas(lua_State* L) {
    if (lua_gettop(L) >= 2) eng(L)->video.setCanvas(iarg(L, 1), iarg(L, 2));
    lua_pushinteger(L, eng(L)->video.canvasW());
    lua_pushinteger(L, eng(L)->video.canvasH());
    return 2;
}

int l_clear(lua_State* L) {
    eng(L)->video.clear(u8arg(L, 1), u8arg(L, 2), u8arg(L, 3));
    return 0;
}

// sp.clip(x, y, w, h): draw only inside it; sp.clip() lifts it.
int l_clip(lua_State* L) {
    if (lua_gettop(L) < 4) eng(L)->video.clip(0, 0, 0, 0);
    else eng(L)->video.clip(iarg(L, 1), iarg(L, 2), iarg(L, 3), iarg(L, 4));
    return 0;
}

int l_fill(lua_State* L) {
    eng(L)->video.fill(iarg(L, 1), iarg(L, 2), iarg(L, 3), iarg(L, 4),
                       u8arg(L, 5), u8arg(L, 6), u8arg(L, 7), u8arg(L, 8, 255));
    return 0;
}

Video::Font fontArg(lua_State* L, int i) {
    const char* f = luaL_optstring(L, i, "small");
    return std::string(f) == "system" ? Video::Font::System : Video::Font::Small;
}

// sp.text(x, y, s, scale, r, g, b [, "small" | "system"])
int l_text(lua_State* L) {
    eng(L)->video.text(iarg(L, 1), iarg(L, 2), luaL_checkstring(L, 3),
                       static_cast<int>(luaL_optinteger(L, 4, 1)),
                       u8arg(L, 5, 255), u8arg(L, 6, 255), u8arg(L, 7, 255), fontArg(L, 8));
    return 0;
}

// sp.text_width(s [, scale [, font]])
int l_text_width(lua_State* L) {
    lua_pushinteger(L, Video::textWidth(luaL_checkstring(L, 1), static_cast<int>(luaL_optinteger(L, 2, 1)), fontArg(L, 3)));
    return 1;
}

// sp.draw(handle, sx, sy, sw, sh, dx, dy [, dw, dh])
int l_draw(lua_State* L) {
    const int sw = iarg(L, 4), sh = iarg(L, 5);
    eng(L)->video.draw(iarg(L, 1), iarg(L, 2), iarg(L, 3), sw, sh, iarg(L, 6), iarg(L, 7),
                       static_cast<int>(luaL_optinteger(L, 8, sw)), static_cast<int>(luaL_optinteger(L, 9, sh)));
    return 0;
}

// sp.draw_flip(handle, sx, sy, sw, sh, dx, dy, dw, dh): as draw, mirrored
// left to right (the win animation's cards bounce both ways).
int l_draw_flip(lua_State* L) {
    eng(L)->video.draw(iarg(L, 1), iarg(L, 2), iarg(L, 3), iarg(L, 4), iarg(L, 5), iarg(L, 6), iarg(L, 7),
                       iarg(L, 8), iarg(L, 9), true);
    return 0;
}

int l_key_down(lua_State* L) {
    lua_pushboolean(L, input::isDown(luaL_checkstring(L, 1)));
    return 1;
}

int l_ticks(lua_State* L) {
    lua_pushinteger(L, static_cast<lua_Integer>(SDL_GetTicks64()));
    return 1;
}

int l_title(lua_State* L) {
    eng(L)->video.setTitle(luaL_checkstring(L, 1));
    return 0;
}

int l_quit(lua_State* L) {
    eng(L)->quit = true;
    eng(L)->exitCode = static_cast<int>(luaL_optinteger(L, 1, 0));
    return 0;
}

int l_log(lua_State* L) {
    std::printf("%s\n", luaL_checkstring(L, 1));
    std::fflush(stdout);
    return 0;
}

// sp.platform() -> "Windows", "Linux", "Mac OS X", ... (SDL's names)
int l_platform(lua_State* L) { lua_pushstring(L, SDL_GetPlatform()); return 1; }

// sp.base_path() -> the folder the game runs from, with a trailing separator
int l_base_path(lua_State* L) {
    char* b = SDL_GetBasePath();
    lua_pushstring(L, b ? b : "./");
    SDL_free(b);
    return 1;
}

}  // namespace

void registerLuaApi(lua_State* L, Engine* e) {
    static const luaL_Reg fns[] = {
        {"has_data", l_has_data}, {"module", l_module}, {"resources", l_resources},
        {"bitmap", l_bitmap}, {"string", l_string}, {"dialog", l_dialog}, {"menu", l_menu}, {"exe_string", l_exe_string},
        {"storage_read", l_storage_read}, {"storage_write", l_storage_write},
        {"canvas", l_canvas}, {"clear", l_clear}, {"clip", l_clip}, {"fill", l_fill}, {"text", l_text},
        {"text_width", l_text_width}, {"draw", l_draw},
        {"key_down", l_key_down}, {"ticks", l_ticks}, {"title", l_title},
        {"quit", l_quit}, {"log", l_log},
        {"platform", l_platform}, {"base_path", l_base_path}, {"draw_flip", l_draw_flip},
        {nullptr, nullptr},
    };
    lua_newtable(L);
    lua_pushlightuserdata(L, e);
    luaL_setfuncs(L, fns, 1);
    lua_setglobal(L, "sp");
}
