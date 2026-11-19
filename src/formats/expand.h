// Microsoft's install-disk compression, as on the Windows 3.x setup disks
// (SOL.EX_ for SOL.EXE): COMPRESS.EXE's "SZDD" files and the "KWAJ" files
// of Windows 3.1's setup, whose usual method is an LZ77 + Huffman scheme
// ("LZH"). EXPAND.EXE undoes both; so does this. See docs/formats.md.
#pragma once

#include <cstdint>
#include <span>
#include <string>
#include <vector>

namespace tp {

enum class Packing { None, Szdd, Kwaj };

Packing packingOf(std::span<const uint8_t> data);

// The original bytes of a compressed file, or the data unchanged when it
// isn't compressed. Throws FormatError on a corrupt or unsupported file.
std::vector<uint8_t> expand(std::vector<uint8_t> data);

// "SOL.EX_" -> "SOL.EXE" when the header records the missing letter (SZDD)
// or the original name (KWAJ); otherwise the name unchanged.
std::string expandedName(std::span<const uint8_t> data, const std::string& packedName);

}  // namespace tp
