#include "audio.h"

#include <algorithm>
#include <cmath>
#include <cstdint>
#include <cstdio>

namespace {

constexpr double kPi = 3.14159265358979323846;

// Repeatable white noise.
struct Noise {
    uint32_t s;
    explicit Noise(uint32_t seed) : s(seed) {}
    float next() {
        s = s * 1664525u + 1013904223u;
        return static_cast<float>((s >> 8) & 0xFFFF) / 32768.0f - 1.0f;
    }
};

// A two-pole resonant band-pass (the RBJ biquad).
struct BandPass {
    double b0, b2, a1, a2, x1 = 0, x2 = 0, y1 = 0, y2 = 0;
    BandPass(double freq, double q, int rate) {
        const double w = 2 * kPi * freq / rate, alpha = std::sin(w) / (2 * q), a0 = 1 + alpha;
        b0 = alpha / a0;
        b2 = -alpha / a0;
        a1 = -2 * std::cos(w) / a0;
        a2 = (1 - alpha) / a0;
    }
    double operator()(double x) {
        const double y = b0 * x + b2 * x2 - a1 * y1 - a2 * y2;
        x2 = x1; x1 = x; y2 = y1; y1 = y;
        return y;
    }
};

void normalize(std::vector<float>& v, float peak) {
    float m = 0;
    for (float s : v) m = std::max(m, std::fabs(s));
    if (m > 0) for (float& s : v) s *= peak / m;
}

}  // namespace

// The sounds:
//   click: a card laid down. A sharp, bright tick (band-passed noise,
//          decaying in a couple of milliseconds) over a short low knock.
//   flip:  a card turned over. A soft swish rising and falling, then a
//          lighter tick.
//   deal:  cards turned from the stock: two quick ticks.
std::vector<float> Audio::synth(const std::string& name, int rate) {
    std::vector<float> out;
    auto tick = [&](size_t at, double freq, double decayMs, double knockHz, float knock, uint32_t seed) {
        Noise n(seed);
        BandPass bp(freq, 1.2, rate);
        const size_t len = static_cast<size_t>(rate * decayMs * 6 / 1000.0);
        if (out.size() < at + len) out.resize(at + len, 0.0f);
        for (size_t i = 0; i < len; ++i) {
            const double t = double(i) / rate;
            const double env = std::exp(-t * 1000.0 / decayMs);
            const double k = std::sin(2 * kPi * knockHz * t) * std::exp(-t * 1000.0 / (decayMs * 2.5));
            out[at + i] += static_cast<float>(bp(n.next()) * env * 3.0 + k * knock * env);
        }
    };
    if (name == "click") {
        tick(0, 3200, 2.2, 190, 0.35f, 7);
        normalize(out, 0.9f);
    } else if (name == "flip") {
        Noise n(11);
        BandPass bp(5000, 0.7, rate);
        const size_t len = static_cast<size_t>(rate * 0.06);
        out.assign(len, 0.0f);
        for (size_t i = 0; i < len; ++i) {
            const double t = double(i) / len;
            out[i] = static_cast<float>(bp(n.next()) * std::sin(kPi * t) * 0.6);
        }
        tick(len - static_cast<size_t>(rate * 0.004), 2600, 1.8, 0, 0.0f, 13);
        normalize(out, 0.55f);
    } else if (name == "deal") {
        tick(0, 3600, 1.8, 0, 0.0f, 17);
        tick(static_cast<size_t>(rate * 0.035), 3400, 1.8, 0, 0.0f, 19);
        normalize(out, 0.6f);
    }
    // A few samples of fade-out so nothing ends with a click of its own.
    const size_t fade = std::min<size_t>(out.size(), 64);
    for (size_t i = 0; i < fade; ++i) out[out.size() - 1 - i] *= float(i) / fade;
    return out;
}

Audio::~Audio() { close(); }

void Audio::close() {
    if (dev_) SDL_CloseAudioDevice(dev_);
    dev_ = 0;
}

bool Audio::open() {
    SDL_AudioSpec want{}, have{};
    want.freq = 44100;
    want.format = AUDIO_F32SYS;
    want.channels = 1;
    want.samples = 512;
    want.callback = callback;
    want.userdata = this;
    dev_ = SDL_OpenAudioDevice(nullptr, 0, &want, &have, SDL_AUDIO_ALLOW_FREQUENCY_CHANGE);
    if (!dev_) {
        std::fprintf(stderr, "no sound: %s\n", SDL_GetError());
        return false;
    }
    rate_ = have.freq;
    for (const char* n : {"click", "flip", "deal"}) sounds_[n] = synth(n, rate_);
    SDL_PauseAudioDevice(dev_, 0);
    return true;
}

void Audio::play(const std::string& name, float gain) {
    if (!dev_) return;
    const auto it = sounds_.find(name);
    if (it == sounds_.end()) return;
    SDL_LockAudioDevice(dev_);
    if (voices_.size() < 16) voices_.push_back({&it->second, 0, gain});
    SDL_UnlockAudioDevice(dev_);
}

void Audio::setVolume(float v) {
    if (!dev_) { volume_ = v; return; }
    SDL_LockAudioDevice(dev_);
    volume_ = std::clamp(v, 0.0f, 1.0f);
    SDL_UnlockAudioDevice(dev_);
}

void Audio::callback(void* user, Uint8* stream, int len) {
    auto* a = static_cast<Audio*>(user);
    auto* out = reinterpret_cast<float*>(stream);
    const int n = len / static_cast<int>(sizeof(float));
    std::fill(out, out + n, 0.0f);
    for (auto& v : a->voices_) {
        const auto& pcm = *v.pcm;
        for (int i = 0; i < n && v.pos < pcm.size(); ++i) out[i] += pcm[v.pos++] * v.gain * a->volume_;
    }
    a->voices_.erase(std::remove_if(a->voices_.begin(), a->voices_.end(),
                                    [](const Voice& v) { return v.pos >= v.pcm->size(); }),
                     a->voices_.end());
    for (int i = 0; i < n; ++i) out[i] = std::clamp(out[i], -1.0f, 1.0f);
}
