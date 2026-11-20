#include "formats/upscale.h"

#include <algorithm>

namespace tp {

Image scale2x(const Image& in) {
    Image out;
    out.width = in.width * 2;
    out.height = in.height * 2;
    out.rgba.assign(static_cast<size_t>(out.width) * out.height, 0);
    auto px = [&](int x, int y) {
        x = std::clamp(x, 0, in.width - 1);
        y = std::clamp(y, 0, in.height - 1);
        return in.at(x, y);
    };
    for (int y = 0; y < in.height; ++y) {
        for (int x = 0; x < in.width; ++x) {
            //   B
            // D E F    E becomes E0 E1 / E2 E3, taking a neighbour's colour
            //   H      where two neighbours agree along a diagonal edge.
            const uint32_t B = px(x, y - 1), D = px(x - 1, y), E = px(x, y), F = px(x + 1, y), H = px(x, y + 1);
            uint32_t e0 = E, e1 = E, e2 = E, e3 = E;
            if (B != H && D != F) {
                if (D == B) e0 = D;
                if (B == F) e1 = F;
                if (D == H) e2 = D;
                if (H == F) e3 = F;
            }
            const size_t o = static_cast<size_t>(2 * y) * out.width + 2 * x;
            out.rgba[o] = e0;
            out.rgba[o + 1] = e1;
            out.rgba[o + out.width] = e2;
            out.rgba[o + out.width + 1] = e3;
        }
    }
    return out;
}

Image smoothUpscale(const Image& in, int factor) {
    factor = std::clamp(factor, 1, 8);
    if (factor == 1 || in.width <= 0 || in.height <= 0) return in;
    Image big = scale2x(scale2x(scale2x(in)));   // 8x
    Image out;
    out.width = in.width * factor;
    out.height = in.height * factor;
    out.rgba.resize(static_cast<size_t>(out.width) * out.height);
    // Each output pixel covers 8 / factor big pixels each way (a fraction
    // when factor doesn't divide 8): an area-weighted average, with colour
    // weighted by alpha so transparent pixels add no colour.
    const double step = 8.0 / factor;
    for (int oy = 0; oy < out.height; ++oy) {
        const double y0 = oy * step, y1 = y0 + step;
        for (int ox = 0; ox < out.width; ++ox) {
            const double x0 = ox * step, x1 = x0 + step;
            double r = 0, g = 0, b = 0, a = 0, area = 0;
            for (int by = static_cast<int>(y0); by < y1 && by < big.height; ++by) {
                const double wy = std::min<double>(by + 1, y1) - std::max<double>(by, y0);
                for (int bx = static_cast<int>(x0); bx < x1 && bx < big.width; ++bx) {
                    const double w = wy * (std::min<double>(bx + 1, x1) - std::max<double>(bx, x0));
                    const uint32_t p = big.at(bx, by);
                    const double pa = ((p >> 24) & 0xFF) / 255.0;
                    r += w * pa * (p & 0xFF);
                    g += w * pa * ((p >> 8) & 0xFF);
                    b += w * pa * ((p >> 16) & 0xFF);
                    a += w * pa;
                    area += w;
                }
            }
            uint32_t v = 0;
            if (a > 0) {
                auto c = [&](double s) { return static_cast<uint8_t>(std::clamp(s / a + 0.5, 0.0, 255.0)); };
                v = packRGBA(c(r), c(g), c(b), static_cast<uint8_t>(std::clamp(a / area * 255.0 + 0.5, 0.0, 255.0)));
            }
            out.rgba[static_cast<size_t>(oy) * out.width + ox] = v;
        }
    }
    return out;
}

}  // namespace tp
