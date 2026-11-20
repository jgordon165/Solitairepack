#include "formats/procedural.h"

#include <algorithm>
#include <cmath>
#include <vector>

namespace tp {

namespace {

constexpr double kTau = 6.28318530717958647692;

struct Rng {
    uint32_t s;
    explicit Rng(uint32_t seed) : s(seed ? seed : 1) {}
    uint32_t next() {   // xorshift32
        s ^= s << 13;
        s ^= s >> 17;
        s ^= s << 5;
        return s;
    }
    double uniform() { return (next() >> 8) / 16777216.0 * 2.0 - 1.0; }   // -1..1
    double normal() {   // near enough: the sum of four uniforms
        return (uniform() + uniform() + uniform() + uniform()) * 0.866;
    }
};

// Smooth value noise on a cx x cy lattice that wraps, so it tiles; sampled
// at (u, v) in [0, 1).
struct PeriodicNoise {
    int cx, cy;
    std::vector<double> g;
    PeriodicNoise(int cx_, int cy_, Rng& rng) : cx(cx_), cy(cy_), g(static_cast<size_t>(cx_) * cy_) {
        for (auto& v : g) v = rng.uniform();
    }
    double at(double u, double v) const {
        const double x = u * cx, y = v * cy;
        const int ix = static_cast<int>(x), iy = static_cast<int>(y);
        double fx = x - ix, fy = y - iy;
        fx = fx * fx * (3 - 2 * fx);
        fy = fy * fy * (3 - 2 * fy);
        auto G = [&](int i, int j) { return g[static_cast<size_t>(((j % cy) + cy) % cy) * cx + ((i % cx) + cx) % cx]; };
        const double a = G(ix, iy), b = G(ix + 1, iy), c = G(ix, iy + 1), d = G(ix + 1, iy + 1);
        return (a * (1 - fx) + b * fx) * (1 - fy) + (c * (1 - fx) + d * fx) * fy;
    }
};

}  // namespace

Image satinTexture(int size, int scale, uint32_t seed) {
    scale = std::clamp(scale, 1, 8);
    const int n = size * scale;
    Rng rng(seed);
    const PeriodicNoise warp1(3, 3, rng), warp2(6, 6, rng);
    // The weave: a random brightness per thread (row of canvas pixels).
    std::vector<double> row(static_cast<size_t>(size));
    for (auto& r : row) r = rng.normal();
    // Grain at canvas-pixel size (it stays grain, not fuzz, on big screens):
    // fine noise, smeared a few pixels along each row into short fibres.
    std::vector<double> noise(static_cast<size_t>(size) * size), fibre(noise.size());
    for (auto& v : noise) v = rng.normal();
    for (int y = 0; y < size; ++y)
        for (int x = 0; x < size; ++x) {
            double acc = 0;
            for (int k = -3; k <= 3; ++k) acc += noise[static_cast<size_t>(y) * size + ((x + k + size) % size)];
            fibre[static_cast<size_t>(y) * size + x] = acc / 7.0;
        }
    std::vector<double> grain(noise.size());
    for (auto& g : grain) g = rng.normal();

    Image img;
    img.width = img.height = n;
    img.rgba.resize(static_cast<size_t>(n) * n);
    for (int y = 0; y < n; ++y) {
        const double v = double(y) / n;
        const int cy = y / scale;
        for (int x = 0; x < n; ++x) {
            const double u = double(x) / n;
            const int cx = x / scale;
            // Soft sheen along diagonal folds, their course bent by the
            // noise (whole numbers of waves keep it tileable). It only
            // lightens: no shaded areas.
            const double w = warp1.at(u, v) * 2.2 + warp2.at(u, v) * 0.6;
            const double s = std::sin(kTau * (u + 2 * v) + w) + 0.35 * std::sin(kTau * (2 * u - v) + 0.7 * w + 1.0);
            const double sheen = s > 0 ? s * s / 1.82 : 0.0;   // 0-1
            const size_t c = static_cast<size_t>(cy) * size + cx;
            const double t = (0.25 * grain[c] + 0.18 * row[static_cast<size_t>(cy)] + 0.6 * fibre[c]) * 0.11;
            const double lighten = sheen * 0.10 + std::max(t, 0.0);
            const double darken = std::max(-t, 0.0);
            const double d = lighten - darken;
            const uint8_t a = static_cast<uint8_t>(std::clamp(std::fabs(d) * 255.0, 0.0, 255.0));
            img.rgba[static_cast<size_t>(y) * n + x] = d > 0 ? packRGBA(255, 255, 255, a) : packRGBA(0, 0, 0, a);
        }
    }
    return img;
}

int shadowMargin(double blur) { return static_cast<int>(std::ceil(blur * 2.5)) + 1; }

Image shadowTexture(int w, int h, double blur, double alpha, int radius, int scale) {
    scale = std::clamp(scale, 1, 8);
    const int m = shadowMargin(blur) * scale;
    const int W = w * scale + 2 * m, H = h * scale + 2 * m;
    const double r = radius * scale;
    // The card's shape: a rounded rectangle, coverage 0-1 (one sample per pixel centre).
    std::vector<double> a(static_cast<size_t>(W) * H, 0.0);
    for (int y = 0; y < H; ++y) {
        for (int x = 0; x < W; ++x) {
            const double px = x + 0.5 - m, py = y + 0.5 - m;
            if (px < 0 || py < 0 || px > w * scale || py > h * scale) continue;
            const double cx = std::clamp(px, r, w * scale - r), cy = std::clamp(py, r, h * scale - r);
            const double d = std::hypot(px - cx, py - cy);
            a[static_cast<size_t>(y) * W + x] = std::clamp(r - d + 0.5, 0.0, 1.0);
        }
    }
    // Blurred: three box blurs each way (close to a Gaussian).
    const int rad = std::max(1, static_cast<int>(std::lround(blur * scale * 0.9)));
    std::vector<double> tmp(a.size());
    auto boxH = [&](std::vector<double>& src, std::vector<double>& dst) {
        for (int y = 0; y < H; ++y) {
            double acc = 0;
            const size_t o = static_cast<size_t>(y) * W;
            for (int x = -rad; x <= rad; ++x) acc += (x >= 0 && x < W) ? src[o + x] : 0.0;
            for (int x = 0; x < W; ++x) {
                dst[o + x] = acc / (2 * rad + 1);
                const int out = x - rad, in = x + rad + 1;
                if (out >= 0) acc -= src[o + out];
                if (in < W) acc += src[o + in];
            }
        }
    };
    auto boxV = [&](std::vector<double>& src, std::vector<double>& dst) {
        for (int x = 0; x < W; ++x) {
            double acc = 0;
            for (int y = -rad; y <= rad; ++y) acc += (y >= 0 && y < H) ? src[static_cast<size_t>(y) * W + x] : 0.0;
            for (int y = 0; y < H; ++y) {
                dst[static_cast<size_t>(y) * W + x] = acc / (2 * rad + 1);
                const int out = y - rad, in = y + rad + 1;
                if (out >= 0) acc -= src[static_cast<size_t>(out) * W + x];
                if (in < H) acc += src[static_cast<size_t>(in) * W + x];
            }
        }
    };
    for (int k = 0; k < 3; ++k) {
        boxH(a, tmp);
        boxV(tmp, a);
    }
    Image img;
    img.width = W;
    img.height = H;
    img.rgba.resize(a.size());
    for (size_t i = 0; i < a.size(); ++i)
        img.rgba[i] = packRGBA(0, 0, 0, static_cast<uint8_t>(std::clamp(a[i] * alpha * 255.0 + 0.5, 0.0, 255.0)));
    return img;
}

}  // namespace tp
