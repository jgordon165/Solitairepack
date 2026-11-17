// Windows 3.x MENU resources (the 16-bit MENUITEMTEMPLATE form): a header,
// then the items in order, each a flags word, an id (not for pop-ups) and
// its text; a pop-up's items follow it, and MF_END marks the last item of
// each level. SOL.EXE's Game and Help menus are read this way.
#pragma once

#include <cstdint>
#include <span>
#include <string>
#include <vector>

namespace tp {

struct MenuItem {
    static constexpr uint16_t Grayed = 0x0001, Disabled = 0x0002, Checked = 0x0008, Popup = 0x0010,
                              Separator = 0x0800, End = 0x0080;
    uint16_t flags = 0;
    uint16_t id = 0;                   // 0 for pop-ups and separators
    std::string text;                  // "&Deal", "&Options...", "" for a separator
    std::vector<MenuItem> items;       // a pop-up's items

    bool separator() const { return !(flags & Popup) && id == 0 && text.empty(); }
};

// The menu bar's items. Throws FormatError on a truncated or malformed menu.
std::vector<MenuItem> decodeMenu(std::span<const uint8_t> data);

}  // namespace tp
