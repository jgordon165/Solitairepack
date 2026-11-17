#include "formats/menu.h"

#include "formats/binreader.h"

namespace tp {

namespace {

std::string cstring(BinReader& r) {
    std::string s;
    for (uint8_t c; (c = r.u8()) != 0;) s.push_back(static_cast<char>(c));
    return s;
}

std::vector<MenuItem> level(BinReader& r, int depth) {
    if (depth > 8) throw FormatError("menu nested too deeply");
    std::vector<MenuItem> out;
    for (;;) {
        MenuItem m;
        m.flags = r.u16();
        if (!(m.flags & MenuItem::Popup)) m.id = r.u16();
        m.text = cstring(r);
        if (m.flags & MenuItem::Popup) m.items = level(r, depth + 1);
        const bool end = m.flags & MenuItem::End;
        out.push_back(std::move(m));
        if (end) return out;
    }
}

}  // namespace

std::vector<MenuItem> decodeMenu(std::span<const uint8_t> data) {
    BinReader r(data);
    r.u16();                        // version (0)
    const uint16_t headerSize = r.u16();
    r.skip(headerSize);
    return level(r, 0);
}

}  // namespace tp
