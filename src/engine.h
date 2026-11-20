// State shared by the C++ host and the Lua API.
#pragma once

#include "audio.h"
#include "storage.h"
#include "formats/ne.h"
#include "video.h"

#include <optional>
#include <string>

struct Engine {
    Video video;
    Audio audio;
    std::string dataArg;              // --data: folder holding SOL.EXE (or SOL.EX_), or the file itself
    std::optional<tp::NeFile> sol;    // SOL.EXE: menus, dialogs, strings, and in 3.0/3.1 the cards
    std::optional<tp::NeFile> cards;  // CARDS.DLL (16-bit), used for the cards only without SOL.EXE
    Storage storage;                  // options and the Vegas bank between runs
    std::string dataError;            // why there's no data, for the no-data screen
    bool quit = false;
    int exitCode = 0;

    // Finds and parses SOL.EXE and CARDS.DLL, installed or compressed.
    // Returns false (and sets dataError) when neither was found.
    bool loadData();

    // "sol" selects SOL.EXE; "cards" (or nothing) the file holding the card
    // art: SOL.EXE, or CARDS.DLL when there's no SOL.EXE.
    const std::optional<tp::NeFile>& module(const std::string& which) const {
        if (which == "sol") return sol;
        return sol ? sol : cards;
    }
};
