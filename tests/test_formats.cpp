// Data-free tests of the NE, bitmap, dialog and menu readers, on files built
// here in memory. With SOLITAIREPACK_DATA set (folder with SOL.EXE and
// CARDS.DLL), also parses the real files.

#include "formats/dialog.h"
#include "formats/dib.h"
#include "formats/menu.h"
#include "formats/expand.h"
#include "formats/ne.h"

#include <cctype>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <filesystem>
#include <string>
#include <vector>

static int failures = 0;
#define CHECK(c) do { if (!(c)) { std::fprintf(stderr, "%s:%d: CHECK(%s) failed\n", __FILE__, __LINE__, #c); ++failures; } } while (0)

using Bytes = std::vector<uint8_t>;

static void put16(Bytes& b, size_t at, uint16_t v) { b[at] = v & 0xFF; b[at + 1] = v >> 8; }
static void put32(Bytes& b, size_t at, uint32_t v) { for (int i = 0; i < 4; ++i) b[at + i] = (v >> (8 * i)) & 0xFF; }
static void app16(Bytes& b, uint16_t v) { b.push_back(v & 0xFF); b.push_back(v >> 8); }
static void app32(Bytes& b, uint32_t v) { for (int i = 0; i < 4; ++i) b.push_back((v >> (8 * i)) & 0xFF); }
static void appP(Bytes& b, const std::string& s) { b.push_back(static_cast<uint8_t>(s.size())); b.insert(b.end(), s.begin(), s.end()); }

// A 4bpp 3x2 bitmap: top row palette 1,2,3; bottom row 4,5,6.
static Bytes dib4() {
    Bytes b(40, 0);
    put32(b, 0, 40); put32(b, 4, 3); put32(b, 8, 2); put16(b, 12, 1); put16(b, 14, 4);
    put32(b, 32, 7);  // 7 colours used
    for (uint8_t i = 0; i < 7; ++i) { b.push_back(i * 10); b.push_back(i * 20); b.push_back(i * 30); b.push_back(0); }  // B G R 0
    // Bottom-up rows, 4-byte stride: bottom row first.
    const uint8_t rows[2][4] = {{0x45, 0x60, 0, 0}, {0x12, 0x30, 0, 0}};
    for (auto& r : rows) b.insert(b.end(), r, r + 4);
    return b;
}

// A 1bpp 8x1 core-header bitmap, alternating.
static Bytes dib1core() {
    Bytes b(12, 0);
    put32(b, 0, 12); put16(b, 4, 8); put16(b, 6, 1); put16(b, 8, 1); put16(b, 10, 1);
    const uint8_t pal[] = {0, 0, 0, 255, 255, 255};  // black, white (B G R)
    b.insert(b.end(), pal, pal + 6);
    const uint8_t row[] = {0xAA, 0, 0, 0};
    b.insert(b.end(), row, row + 4);
    return b;
}

// An RLE8 4x2 bitmap.
static Bytes dibRle8() {
    Bytes b(40, 0);
    put32(b, 0, 40); put32(b, 4, 4); put32(b, 8, 2); put16(b, 12, 1); put16(b, 14, 8);
    put32(b, 16, 1); put32(b, 32, 3);
    const uint8_t pal[] = {0, 0, 0, 0, 0, 0, 255, 0, 0, 255, 0, 0};  // black, red, green
    b.insert(b.end(), pal, pal + sizeof pal);
    const uint8_t data[] = {4, 1, 0, 0,               // bottom row: 4x red, end of line
                            0, 4, 2, 2, 1, 1, 0, 1};  // top row: absolute 2,2,1,1; end of bitmap
    b.insert(b.end(), data, data + sizeof data);
    return b;
}

static Bytes stringBlock(const std::vector<std::string>& s) {
    Bytes b;
    for (unsigned i = 0; i < 16; ++i) appP(b, i < s.size() ? s[i] : "");
    return b;
}

// MZ stub + NE header + resource table + resident names, then the resources.
static Bytes buildNe() {
    const Bytes bmpA = dib4(), bmpB = dib1core(), bmpC = dibRle8();
    const Bytes strs = stringBlock({"", "Solitaire", "Deal Again?"});  // ids 0..15: 1 and 2 set
    const uint16_t shift = 4;

    Bytes rt;  // resource table, offsets relative to its start
    app16(rt, shift);
    app16(rt, 0x8002); app16(rt, 3); app32(rt, 0);
    const size_t bmpEntries = rt.size();
    for (int i = 0; i < 3; ++i) { for (int k = 0; k < 12; ++k) rt.push_back(0); }
    app16(rt, 0x8006); app16(rt, 1); app32(rt, 0);
    const size_t strEntry = rt.size();
    for (int k = 0; k < 12; ++k) rt.push_back(0);
    app16(rt, 0);
    const size_t nameOff = rt.size();
    appP(rt, "Blocks");
    rt.push_back(0);

    Bytes out(0x40, 0);
    out[0] = 'M'; out[1] = 'Z';
    put32(out, 0x3C, 0x40);
    Bytes ne(0x40, 0);
    ne[0] = 'N'; ne[1] = 'E';
    put16(ne, 0x24, 0x40);
    put16(ne, 0x26, static_cast<uint16_t>(0x40 + rt.size()));
    put16(ne, 0x3E, 0x0300);  // Windows 3.0
    out.insert(out.end(), ne.begin(), ne.end());
    const size_t rtAt = out.size();
    out.insert(out.end(), rt.begin(), rt.end());
    appP(out, "SOL"); app16(out, 0); out.push_back(0);

    auto place = [&](const Bytes& data, size_t entry, uint16_t id) {
        while (out.size() % (1u << shift)) out.push_back(0);
        const size_t at = out.size();
        out.insert(out.end(), data.begin(), data.end());
        const size_t e = rtAt + entry;
        put16(out, e + 0, static_cast<uint16_t>(at >> shift));
        put16(out, e + 2, static_cast<uint16_t>((data.size() + (1u << shift) - 1) >> shift));
        put16(out, e + 4, 0x30);
        put16(out, e + 6, id);
    };
    place(bmpA, bmpEntries + 0, 0x8000 | 101);
    place(bmpB, bmpEntries + 12, static_cast<uint16_t>(nameOff));
    place(bmpC, bmpEntries + 24, 0x8000 | 102);
    place(strs, strEntry, 0x8000 | 1);
    while (out.size() % 16) out.push_back(0);
    return out;
}

static void testNe() {
    tp::NeFile ne(buildNe());
    CHECK(ne.moduleName() == "SOL");
    CHECK(ne.expectedWindowsMajor() == 3 && ne.expectedWindowsMinor() == 0);
    CHECK(ne.resources().size() == 4);

    const auto* a = ne.find(2, 101);
    CHECK(a != nullptr);
    if (a) {
        const auto img = tp::decodeDib(ne.read(*a));
        CHECK(img.width == 3 && img.height == 2);
        CHECK(img.at(0, 0) == tp::packRGBA(30, 20, 10));    // palette 1, top-left
        CHECK(img.at(2, 0) == tp::packRGBA(90, 60, 30));    // palette 3
        CHECK(img.at(0, 1) == tp::packRGBA(120, 80, 40));   // palette 4, bottom-left
    }
    const auto* b = ne.find(2, std::string("blocks"));  // names are case-insensitive
    CHECK(b != nullptr && b->key.name == "BLOCKS");
    if (b) {
        const auto img = tp::decodeDib(ne.read(*b));
        CHECK(img.width == 8 && img.height == 1);
        CHECK(img.at(0, 0) == tp::packRGBA(255, 255, 255));
        CHECK(img.at(1, 0) == tp::packRGBA(0, 0, 0));
    }
    CHECK(ne.find(2, std::string("#102")) != nullptr);
    if (const auto* c = ne.find(2, 102)) {
        const auto img = tp::decodeDib(ne.read(*c));
        CHECK(img.width == 4 && img.height == 2);
        CHECK(img.at(0, 1) == tp::packRGBA(255, 0, 0));
        CHECK(img.at(3, 1) == tp::packRGBA(255, 0, 0));
        CHECK(img.at(0, 0) == tp::packRGBA(0, 255, 0));
        CHECK(img.at(3, 0) == tp::packRGBA(255, 0, 0));
    }
    CHECK(ne.find(2, 999) == nullptr);
    CHECK(ne.string(1).value_or("") == "Solitaire");
    CHECK(ne.string(2).value_or("") == "Deal Again?");
    CHECK(!ne.string(3).has_value());
    CHECK(!ne.string(40).has_value());
}

static void testRejects() {
    bool threw = false;
    try { tp::NeFile(Bytes(10, 0)); } catch (const tp::FormatError&) { threw = true; }
    CHECK(threw);

    // Truncated: cut the file inside the resource table.
    Bytes cut = buildNe();
    cut.resize(0x90);
    threw = false;
    try { tp::NeFile ne(cut); } catch (const tp::FormatError&) { threw = true; }
    CHECK(threw);

    // A PE (32-bit) executable is not NE.
    Bytes pe(0x100, 0);
    pe[0] = 'M'; pe[1] = 'Z'; pe[0x3C] = 0x80; pe[0x80] = 'P'; pe[0x81] = 'E';
    threw = false;
    try { tp::NeFile ne(pe); } catch (const tp::FormatError&) { threw = true; }
    CHECK(threw);

    Bytes badDib(40, 0);
    put32(badDib, 0, 40); put32(badDib, 4, 4); put32(badDib, 8, 4); put16(badDib, 14, 16);
    threw = false;
    try { tp::decodeDib(badDib); } catch (const tp::FormatError&) { threw = true; }
    CHECK(threw);
}

// A DLGTEMPLATE: a centred static line and a default OK button, plus a
// control whose text is a resource id.
static void testDialog() {
    Bytes b;
    app32(b, 0x80400000);   // WS_POPUP | WS_DLGFRAME
    b.push_back(3);
    app16(b, 97); app16(b, 58); app16(b, 174); app16(b, 203);
    b.push_back(0); b.push_back(0); b.push_back(0);   // no menu, class, caption
    auto control = [&](int16_t y, uint16_t id, uint32_t style, uint8_t cls, const std::string& text) {
        app16(b, 0); app16(b, static_cast<uint16_t>(y)); app16(b, 174); app16(b, 8);
        app16(b, id); app32(b, style); b.push_back(cls);
        b.insert(b.end(), text.begin(), text.end()); b.push_back(0);
        b.push_back(0);   // no creation data
    };
    control(86, 0, 0x50000001, 0x82, "All Rights Reserved.");
    control(179, 1, 0x50030001, 0x80, "&OK");
    app16(b, 16); app16(b, 60); app16(b, 0); app16(b, 0); app16(b, 102); app32(b, 0x50000003);
    b.push_back(0x82); b.push_back(0xFF); app16(b, 666); b.push_back(0);
    const tp::Dialog d = tp::decodeDialog(b);
    CHECK(d.style == 0x80400000 && d.w == 174 && d.h == 203);
    CHECK(d.controls.size() == 3);
    CHECK(d.controls[0].cls == "static" && d.controls[0].text == "All Rights Reserved." && d.controls[0].y == 86);
    CHECK(d.controls[1].cls == "button" && d.controls[1].text == "&OK" && d.controls[1].id == 1);
    CHECK(d.controls[2].text == "#666" && d.controls[2].id == 102);
    bool threw = false;
    b.resize(b.size() - 6);
    try { tp::decodeDialog(b); } catch (const tp::FormatError&) { threw = true; }
    CHECK(threw);
}

// Game, Help: Game has Deal, a separator and Exit; Help has one item.
static void testMenu() {
    Bytes b;
    app16(b, 0); app16(b, 0);
    auto item = [&](uint16_t flags, int id, const std::string& text) {
        app16(b, flags);
        if (id >= 0) app16(b, static_cast<uint16_t>(id));
        b.insert(b.end(), text.begin(), text.end()); b.push_back(0);
    };
    item(tp::MenuItem::Popup, -1, "&Game");
    item(0, 1000, "&Deal");
    item(0, 0, "");
    item(tp::MenuItem::End, 1002, "E&xit");
    item(tp::MenuItem::Popup | tp::MenuItem::End, -1, "&Help");
    item(tp::MenuItem::End, 2000, "&About Solitaire...");
    const auto m = tp::decodeMenu(b);
    CHECK(m.size() == 2);
    CHECK(m[0].text == "&Game" && m[0].items.size() == 3);
    CHECK(m[0].items[0].id == 1000 && m[0].items[0].text == "&Deal");
    CHECK(m[0].items[1].separator());
    CHECK(m[0].items[2].text == "E&xit");
    CHECK(m[1].items.size() == 1 && m[1].items[0].id == 2000);
    bool threw = false;
    b.resize(b.size() - 4);
    try { tp::decodeMenu(b); } catch (const tp::FormatError&) { threw = true; }
    CHECK(threw);
}

// Install-disk compression: SZDD (literals and a match), KWAJ stored, XOR
// and LZH (with fixed-length codes, which a test can write by hand), the
// original names, and truncated files.
static void testExpand() {
    const std::string want = "ABCABCABCX";
    auto str = [](const std::vector<uint8_t>& v) { return std::string(v.begin(), v.end()); };

    Bytes sz = {'S', 'Z', 'D', 'D', 0x88, 0xF0, 0x27, 0x33, 'A', 'E'};
    app32(sz, 10);
    // Flags 0b10111: 3 literals, a match (window 0xFF0, where the A went, 6 bytes), a literal.
    for (int b : {0x17, int('A'), int('B'), int('C'), 0xF0, 0xF3, int('X')}) sz.push_back(static_cast<uint8_t>(b));
    CHECK(tp::packingOf(sz) == tp::Packing::Szdd);
    CHECK(str(tp::expand(sz)) == want);
    CHECK(tp::expandedName(sz, "SOL.EX_") == "SOL.EXE");
    Bytes szCut(sz.begin(), sz.end() - 3);
    bool threw = false;
    try { tp::expand(szCut); } catch (const tp::FormatError&) { threw = true; }
    CHECK(threw);

    auto kwaj = [&](uint16_t method, const Bytes& body, bool names) {
        Bytes k = {'K', 'W', 'A', 'J', 0x88, 0xF0, 0x27, 0xD1};
        app16(k, method);
        const uint16_t flags = names ? 0x19 : 0x01;
        app16(k, static_cast<uint16_t>(14 + 4 + (names ? 8 : 0)));
        app16(k, flags);
        app32(k, static_cast<uint32_t>(want.size()));
        if (names) for (char c : std::string("SOL\0EXE\0", 8)) k.push_back(static_cast<uint8_t>(c));
        k.insert(k.end(), body.begin(), body.end());
        return k;
    };
    const Bytes plain(want.begin(), want.end());
    CHECK(str(tp::expand(kwaj(0, plain, false))) == want);
    Bytes x;
    for (uint8_t c : plain) x.push_back(static_cast<uint8_t>(c ^ 0xFF));
    CHECK(str(tp::expand(kwaj(1, x, true))) == want);
    CHECK(tp::expandedName(kwaj(1, x, true), "SOL.EX_") == "SOL.EXE");

    // LZH, all five tables of type 0 (fixed 4/4/5/6/8-bit codes).
    Bytes bits;
    int nbits = 0;
    auto put = [&](unsigned v, int n) {
        for (int i = n - 1; i >= 0; --i) {
            if (nbits % 8 == 0) bits.push_back(0);
            if ((v >> i) & 1) bits.back() |= static_cast<uint8_t>(0x80 >> (nbits % 8));
            ++nbits;
        }
    };
    for (int t = 0; t < 6; ++t) put(0, 4);
    put(0, 4); put(2, 5); put('A', 8); put('B', 8); put('C', 8);   // 3 literals
    put(4, 4); put(0, 6); put(3, 6);                              // match: 6 bytes, 3 back
    put(0, 4); put(0, 5); put('X', 8);                            // 1 literal
    const Bytes lzh = kwaj(3, bits, false);
    CHECK(tp::packingOf(lzh) == tp::Packing::Kwaj);
    CHECK(str(tp::expand(lzh)) == want);
    threw = false;
    try { tp::expand(Bytes(lzh.begin(), lzh.end() - 2)); } catch (const tp::FormatError&) { threw = true; }
    CHECK(threw);
    threw = false;
    try { tp::expand(kwaj(4, plain, false)); } catch (const tp::FormatError&) { threw = true; }
    CHECK(threw);   // MS-ZIP: not on the Windows 3.1 disks

    // Anything else comes back as it was.
    CHECK(str(tp::expand(plain)) == want);
}

static std::filesystem::path findUpper(const std::filesystem::path& dir, const std::string& want) {
    namespace fs = std::filesystem;
    std::error_code ec;
    for (const auto& e : fs::recursive_directory_iterator(dir, ec)) {
        std::string n = e.path().filename().string();
        for (auto& c : n) c = static_cast<char>(std::toupper(static_cast<unsigned char>(c)));
        if (n == want) return e.path();
    }
    return {};
}

static void testRealData() {
    const char* dir = std::getenv("SOLITAIREPACK_DATA");
    if (!dir) return;
    auto findAny = [&](std::initializer_list<const char*> names) {
        for (const char* n : names) {
            const auto p = findUpper(dir, n);
            if (!p.empty()) return p;
        }
        return std::filesystem::path{};
    };
    const auto solPath = findAny({"SOL.EXE", "SOL.EX_"});
    const auto cardsPath = findAny({"CARDS.DLL", "CARDS.DL_"});
    if (solPath.empty() && cardsPath.empty()) {
        std::fprintf(stderr, "[data] neither SOL.EXE nor SOL.EX_ in %s\n", dir);
        ++failures;
        return;
    }
    // The card art: CARDS.DLL when there is one, else SOL.EXE (Windows 3.0/3.1).
    const auto& artPath = cardsPath.empty() ? solPath : cardsPath;
    const auto art = tp::NeFile::load(artPath.string());
    std::printf("[data] cards from %s: module %s, %zu resources\n", artPath.string().c_str(),
                art.moduleName().c_str(), art.resources().size());
    // Faces 1-52, the empty-pile pattern 53 and the backs 54-65: 71 x 96.
    for (uint16_t id = 1; id <= 65; ++id) {
        const auto* r = art.find(static_cast<uint16_t>(tp::ResType::Bitmap), id);
        CHECK(r != nullptr);
        if (!r) continue;
        try {
            const auto img = tp::decodeDib(art.read(*r));
            CHECK(img.width == 71 && img.height == 96);
        } catch (const std::exception& ex) {
            std::fprintf(stderr, "[data] bitmap %u: %s\n", id, ex.what());
            ++failures;
        }
    }
    for (const auto& r : art.resources()) {
        if (r.typeId != 2) continue;
        try { tp::decodeDib(art.read(r)); } catch (const std::exception& ex) {
            std::fprintf(stderr, "[data] bitmap %s: %s\n", r.key.str().c_str(), ex.what());
            ++failures;
        }
    }
    if (solPath.empty()) return;
    const auto sol = tp::NeFile::load(solPath.string());
    std::printf("[data] %s: module %s, %zu resources\n", solPath.string().c_str(), sol.moduleName().c_str(),
                sol.resources().size());
    int menus = 0, dialogs = 0;
    for (const auto& r : sol.resources()) {
        try {
            if (r.typeId == 4) { CHECK(!tp::decodeMenu(sol.read(r)).empty()); ++menus; }
            if (r.typeId == 5) { tp::decodeDialog(sol.read(r)); ++dialogs; }
        } catch (const std::exception& ex) {
            std::fprintf(stderr, "[data] %s %s: %s\n", tp::resTypeName(r.typeId), r.key.str().c_str(), ex.what());
            ++failures;
        }
    }
    CHECK(menus >= 1);
    CHECK(dialogs >= 2);   // Options, Select Card Back
    CHECK(sol.string(104).value_or("") == "Deal Again?");
}

int main() {
    testNe();
    testRejects();
    testDialog();
    testMenu();
    testExpand();
    testRealData();
    if (failures) { std::fprintf(stderr, "%d failure(s)\n", failures); return 1; }
    std::printf("formats: all passed\n");
    return 0;
}
