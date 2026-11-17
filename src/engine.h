// State shared by the C++ host and the Lua API.
#pragma once

#include "storage.h"
#include "formats/ne.h"
#include "video.h"

#include <optional>
#include <string>

struct Engine {
    Video video;
    std::string dataArg;              // --data: folder holding SOL.EXE and CARDS.DLL, or SOL.EXE itself
    std::optional<tp::NeFile> sol;    // SOL.EXE: menus, dialogs, strings, icons
    std::optional<tp::NeFile> cards;  // CARDS.DLL: the card faces and backs
    Storage storage;                  // options and the Vegas bank between runs
    std::string dataError;            // why there's no data, for the no-data screen
    bool quit = false;
    int exitCode = 0;

    // Finds and parses SOL.EXE and CARDS.DLL. Returns false (and sets
    // dataError) unless CARDS.DLL was found: without it there are no cards.
    bool loadData();

    // "sol" selects SOL.EXE, anything else (or nothing) CARDS.DLL.
    const std::optional<tp::NeFile>& module(const std::string& which) const {
        return which == "sol" ? sol : cards;
    }
};
