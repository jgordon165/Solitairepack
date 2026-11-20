// The synthesized card sounds: each exists, is short, stays within full
// scale, starts at once (no delay before the click) and ends in silence.
// With --wav <folder> it also writes each as a .wav (three times over, a
// third of a second apart) to listen to.
#include "audio.h"

#include <cmath>
#include <cstdint>
#include <vector>
#include <cstdio>
#include <string>

static int failures = 0;
#define CHECK(c) do { if (!(c)) { std::fprintf(stderr, "%s:%d: CHECK(%s)\n", __FILE__, __LINE__, #c); ++failures; } } while (0)

static void writeWav(const std::string& path, const std::vector<float>& pcm, int rate) {
    std::vector<int16_t> s;
    for (int rep = 0; rep < 3; ++rep) {
        for (float f : pcm) s.push_back(static_cast<int16_t>(f * 32767));
        s.insert(s.end(), static_cast<size_t>(rate / 3), 0);
    }
    FILE* f = std::fopen(path.c_str(), "wb");
    if (!f) return;
    auto u32 = [&](uint32_t v) { std::fwrite(&v, 4, 1, f); };
    auto u16 = [&](uint16_t v) { std::fwrite(&v, 2, 1, f); };
    const uint32_t bytes = static_cast<uint32_t>(s.size() * 2);
    std::fwrite("RIFF", 1, 4, f); u32(36 + bytes); std::fwrite("WAVEfmt ", 1, 8, f);
    u32(16); u16(1); u16(1); u32(static_cast<uint32_t>(rate)); u32(static_cast<uint32_t>(rate * 2)); u16(2); u16(16);
    std::fwrite("data", 1, 4, f); u32(bytes);
    std::fwrite(s.data(), 2, s.size(), f);
    std::fclose(f);
}

int main(int argc, char** argv) {
    const int rate = 44100;
    const std::string wavDir = argc > 2 && std::string(argv[1]) == "--wav" ? argv[2] : "";
    for (const char* name : {"click", "flip", "deal"}) {
        const auto pcm = Audio::synth(name, rate);
        CHECK(!pcm.empty());
        CHECK(pcm.size() < static_cast<size_t>(rate / 5));     // under 0.2 s
        float peak = 0, first = 0;
        bool finite = true;
        for (size_t i = 0; i < pcm.size(); ++i) {
            if (!std::isfinite(pcm[i])) finite = false;
            peak = std::fmax(peak, std::fabs(pcm[i]));
            if (i < static_cast<size_t>(rate / 200)) first = std::fmax(first, std::fabs(pcm[i]));
        }
        CHECK(finite);
        CHECK(peak > 0.3f && peak <= 1.0f);
        if (std::string(name) != "flip") CHECK(first > 0.2f);   // the click is at the start
        CHECK(std::fabs(pcm.back()) < 1e-3f);
        std::printf("%s: %zu samples, peak %.2f\n", name, pcm.size(), peak);
        if (!wavDir.empty()) writeWav(wavDir + "/solitairepack-" + name + ".wav", pcm, rate);
    }
    CHECK(Audio::synth("nothing", rate).empty());
    if (failures) { std::fprintf(stderr, "%d failure(s)\n", failures); return 1; }
    std::printf("audio: all passed\n");
    return 0;
}
