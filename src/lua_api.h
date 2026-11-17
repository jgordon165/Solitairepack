#pragma once

struct lua_State;
struct Engine;

// Registers the "sp" table: data access, drawing, input and timing.
void registerLuaApi(lua_State* L, Engine* eng);
