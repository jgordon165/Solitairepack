#include "formats/expand.h"

#include "formats/binreader.h"

#include <algorithm>
#include <array>
#include <cstring>

namespace tp {

namespace {

constexpr uint8_t kSzdd[8] = {'S', 'Z', 'D', 'D', 0x88, 0xF0, 0x27, 0x33};
constexpr uint8_t kKwaj[8] = {'K', 'W', 'A', 'J', 0x88, 0xF0, 0x27, 0xD1};

// Guards against a header claiming a huge size.
constexpr uint32_t kMaxSize = 64u << 20;

// ---- SZDD: LZSS over a 4 KB window of spaces --------------------------------
//
// A flag byte, its bits low first: 1 = a literal byte, 0 = a match of two
// bytes, offset = b0 | (b1 & 0xF0) << 4 (an absolute window position),
// length = (b1 & 0x0F) + 3. Writing starts at window position 4096 - 16.
std::vector<uint8_t> unSzdd(std::span<const uint8_t> in) {
    BinReader r(in);
    r.seek(10);
    const uint32_t size = r.u32();
    if (size > kMaxSize) throw FormatError("SZDD: implausible size");
    std::vector<uint8_t> out;
    out.reserve(size);
    std::array<uint8_t, 4096> win;
    win.fill(' ');
    unsigned pos = 4096 - 16;
    size_t i = 14;
    while (i < in.size() && out.size() < size) {
        const uint8_t flags = in[i++];
        for (int b = 0; b < 8 && i < in.size() && out.size() < size; ++b) {
            if (flags & (1 << b)) {
                const uint8_t c = in[i++];
                out.push_back(c);
                win[pos] = c;
                pos = (pos + 1) & 4095;
            } else {
                if (i + 1 >= in.size()) throw FormatError("SZDD: truncated");
                const unsigned off = in[i] | ((in[i + 1] & 0xF0) << 4);
                const unsigned len = (in[i + 1] & 0x0F) + 3u;
                i += 2;
                for (unsigned k = 0; k < len && out.size() < size; ++k) {
                    const uint8_t c = win[(off + k) & 4095];
                    out.push_back(c);
                    win[pos] = c;
                    pos = (pos + 1) & 4095;
                }
            }
        }
    }
    if (out.size() != size) throw FormatError("SZDD: truncated");
    return out;
}

// ---- KWAJ -----------------------------------------------------------------------

struct KwajHeader {
    uint16_t method = 0;
    uint16_t dataOffset = 0;
    bool haveSize = false;
    uint32_t size = 0;
    std::string name, ext;
};

KwajHeader kwajHeader(std::span<const uint8_t> in) {
    BinReader r(in);
    KwajHeader h;
    r.seek(8);
    h.method = r.u16();
    h.dataOffset = r.u16();
    const uint16_t flags = r.u16();
    if (flags & 0x01) { h.haveSize = true; h.size = r.u32(); }
    if (flags & 0x02) r.skip(2);
    if (flags & 0x04) r.skip(r.u16());
    auto cstr = [&](size_t max) {
        std::string s;
        for (size_t k = 0; k < max; ++k) {
            const uint8_t c = r.u8();
            if (!c) break;
            s.push_back(static_cast<char>(c));
        }
        return s;
    };
    if (flags & 0x08) h.name = cstr(9);
    if (flags & 0x10) h.ext = cstr(4);
    if (h.haveSize && h.size > kMaxSize) throw FormatError("KWAJ: implausible size");
    if (h.dataOffset > in.size()) throw FormatError("KWAJ: truncated");
    return h;
}

// Bits, most significant first.
class MsbBits {
public:
    explicit MsbBits(std::span<const uint8_t> d) : d_(d) {}
    bool atEnd() const { return pos_ >= d_.size() * 8; }
    unsigned bits(int n) {
        unsigned v = 0;
        for (int k = 0; k < n; ++k) {
            // Past the end reads as zeros; the caller stops on atEnd().
            const size_t byte = pos_ >> 3;
            const unsigned bit = byte < d_.size() ? (d_[byte] >> (7 - (pos_ & 7))) & 1u : 0u;
            v = (v << 1) | bit;
            ++pos_;
        }
        return v;
    }

private:
    std::span<const uint8_t> d_;
    size_t pos_ = 0;
};

// A canonical Huffman code from code lengths (0 = unused): shorter codes
// first, ties in symbol order. Decoded a bit at a time; the tables are tiny.
class Huffman {
public:
    void build(const std::vector<uint8_t>& lens) {
        count_.fill(0);
        symbols_.clear();
        for (uint8_t l : lens) {
            if (l > 16) throw FormatError("KWAJ: bad code length");
            if (l) ++count_[l];
        }
        for (int len = 1; len <= 16; ++len)
            for (size_t s = 0; s < lens.size(); ++s)
                if (lens[s] == len) symbols_.push_back(static_cast<uint16_t>(s));
        if (symbols_.empty()) throw FormatError("KWAJ: empty code");
    }
    unsigned decode(MsbBits& in) const {
        int code = 0, first = 0, index = 0;
        for (int len = 1; len <= 16; ++len) {
            code |= static_cast<int>(in.bits(1));
            const int n = count_[len];
            if (code - first < n) return symbols_[static_cast<size_t>(index + code - first)];
            index += n;
            first = (first + n) << 1;
            code <<= 1;
        }
        throw FormatError("KWAJ: bad Huffman code");
    }

private:
    std::array<int, 17> count_{};
    std::vector<uint16_t> symbols_;
};

// The code lengths of a table, in one of four encodings.
std::vector<uint8_t> readLens(MsbBits& in, unsigned type, size_t n) {
    std::vector<uint8_t> lens(n);
    unsigned c = 0;
    switch (type) {
    case 0: {   // all the same: 4, 5, 6 or 8 bits for 16, 32, 64, 256 symbols
        const uint8_t l = n == 16 ? 4 : n == 32 ? 5 : n == 64 ? 6 : 8;
        std::fill(lens.begin(), lens.end(), l);
        break;
    }
    case 1:     // first in 4 bits; then 0 = same, 10 = one more, 11 + 4 bits = new
        c = in.bits(4);
        lens[0] = static_cast<uint8_t>(c);
        for (size_t i = 1; i < n; ++i) {
            if (in.bits(1) == 0) {}
            else if (in.bits(1) == 0) ++c;
            else c = in.bits(4);
            lens[i] = static_cast<uint8_t>(c);
        }
        break;
    case 2:     // first in 4 bits; then 2 bits: 0-2 = change by -1..+1, 3 + 4 bits = new
        c = in.bits(4);
        lens[0] = static_cast<uint8_t>(c);
        for (size_t i = 1; i < n; ++i) {
            const unsigned sel = in.bits(2);
            if (sel == 3) c = in.bits(4); else c = (c + sel - 1) & 0xFF;
            lens[i] = static_cast<uint8_t>(c);
        }
        break;
    case 3:     // each in 4 bits
        for (size_t i = 0; i < n; ++i) lens[i] = static_cast<uint8_t>(in.bits(4));
        break;
    default:
        throw FormatError("KWAJ: bad table type");
    }
    return lens;
}

// Method 3: five Huffman tables, then matches and runs of literals over a
// 4 KB window of spaces. A match length 0 means a run of literals follows
// (its length from LITLEN; 32 means another run may follow at once, so the
// next length is read with the second match-length table).
std::vector<uint8_t> unLzh(std::span<const uint8_t> in, const KwajHeader& h) {
    MsbBits bits(in);
    unsigned types[6];
    for (auto& t : types) t = bits.bits(4);
    Huffman matchlen1, matchlen2, litlen, offset, literal;
    matchlen1.build(readLens(bits, types[0], 16));
    matchlen2.build(readLens(bits, types[1], 16));
    litlen.build(readLens(bits, types[2], 32));
    offset.build(readLens(bits, types[3], 64));
    literal.build(readLens(bits, types[4], 256));

    std::vector<uint8_t> out;
    if (h.haveSize) out.reserve(h.size);
    std::array<uint8_t, 4096> win;
    win.fill(' ');
    unsigned pos = 0;
    bool litRun = false;
    auto put = [&](uint8_t c) {
        out.push_back(c);
        win[pos] = c;
        pos = (pos + 1) & 4095;
    };
    auto done = [&] { return (h.haveSize && out.size() >= h.size) || bits.atEnd() || out.size() > kMaxSize; };
    while (!done()) {
        unsigned len = (litRun ? matchlen2 : matchlen1).decode(bits);
        if (bits.atEnd()) break;
        if (len > 0) {
            len += 2;
            litRun = false;
            unsigned off = offset.decode(bits) << 6;
            off |= bits.bits(6);
            for (unsigned k = 0; k < len && !(h.haveSize && out.size() >= h.size); ++k)
                put(win[(pos + 4096 - off) & 4095]);
        } else {
            len = litlen.decode(bits) + 1;
            litRun = len != 32;
            for (unsigned k = 0; k < len && !done(); ++k) put(static_cast<uint8_t>(literal.decode(bits)));
        }
    }
    if (h.haveSize && out.size() != h.size) throw FormatError("KWAJ: truncated");
    return out;
}

std::vector<uint8_t> unKwaj(std::span<const uint8_t> in) {
    const KwajHeader h = kwajHeader(in);
    const auto body = in.subspan(h.dataOffset);
    std::vector<uint8_t> out;
    switch (h.method) {
    case 0: out.assign(body.begin(), body.end()); break;
    case 1: for (uint8_t c : body) out.push_back(static_cast<uint8_t>(c ^ 0xFF)); break;
    case 2: {   // SZDD's LZSS without the SZDD header
        std::vector<uint8_t> fake(14, 0);
        std::memcpy(fake.data(), kSzdd, 8);
        const uint32_t size = h.haveSize ? h.size : 0;
        if (!h.haveSize) throw FormatError("KWAJ: method 2 without a size");
        for (int k = 0; k < 4; ++k) fake[10 + k] = static_cast<uint8_t>(size >> (8 * k));
        fake.insert(fake.end(), body.begin(), body.end());
        return unSzdd(fake);
    }
    case 3: return unLzh(body, h);
    default: throw FormatError("KWAJ: compression method " + std::to_string(h.method) + " not supported");
    }
    if (h.haveSize && out.size() > h.size) out.resize(h.size);
    return out;
}

}  // namespace

Packing packingOf(std::span<const uint8_t> d) {
    if (d.size() >= 14 && std::memcmp(d.data(), kSzdd, 8) == 0) return Packing::Szdd;
    if (d.size() >= 14 && std::memcmp(d.data(), kKwaj, 8) == 0) return Packing::Kwaj;
    return Packing::None;
}

std::vector<uint8_t> expand(std::vector<uint8_t> data) {
    switch (packingOf(data)) {
    case Packing::Szdd: return unSzdd(data);
    case Packing::Kwaj: return unKwaj(data);
    default: return data;
    }
}

std::string expandedName(std::span<const uint8_t> data, const std::string& packed) {
    const Packing p = packingOf(data);
    if (p == Packing::Szdd && data[9] && !packed.empty() && packed.back() == '_') {
        std::string s = packed;
        s.back() = static_cast<char>(data[9]);
        return s;
    }
    if (p == Packing::Kwaj) {
        try {
            const KwajHeader h = kwajHeader(data);
            if (!h.name.empty()) return h.ext.empty() ? h.name : h.name + "." + h.ext;
        } catch (const FormatError&) {}
    }
    return packed;
}

}  // namespace tp
