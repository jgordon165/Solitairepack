// The synthesized card sounds: each exists, is short, stays within full
// scale, starts at once (no delay before the click) and ends in silence.
#include "audio.h"

#include <cmath>
#include <cstdio>
#include <string>

static int failures = 0;
#define CHECK(c) do { if (!(c)) { std::fprintf(stderr, "%s:%d: CHECK(%s)\n", __FILE__, __LINE__, #c); ++failures; } } while (0)

int main(int, char**) {
    const int rate = 44100;
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
    }
    CHECK(Audio::synth("nothing", rate).empty());
    if (failures) { std::fprintf(stderr, "%d failure(s)\n", failures); return 1; }
    std::printf("audio: all passed\n");
    return 0;
}
