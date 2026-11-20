// Textures the port makes itself (nothing from the original): the satin
// sheen laid over the table colour and the soft shadows under the cards.
// Both are black or white with an alpha, so they shade whatever colour is
// under them. `scale` is the real pixels per canvas pixel they'll be drawn
// at (Video::renderScale), so they stay smooth on big screens.
#pragma once

#include "formats/dib.h"

#include <cstdint>

namespace tp {

// A tileable grainy satin, size x size canvas pixels (so size * scale real
// pixels): fine grain and short horizontal fibres at canvas-pixel size, a
// faint weave, and a soft sheen along diagonal folds that only lightens
// (no shaded areas). White where it lightens the table, black where the
// grain darkens it.
Image satinTexture(int size, int scale, uint32_t seed);

// The shadow of a w x h card with rounded corners (radius), blurred by
// `blur` canvas pixels, as black at up to `alpha` (0-1). The image has a
// margin of shadowMargin(blur) on every side.
int shadowMargin(double blur);
Image shadowTexture(int w, int h, double blur, double alpha, int radius, int scale);

}  // namespace tp
