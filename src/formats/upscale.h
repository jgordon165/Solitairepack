// Smoothing the original's pixel art for bigger screens: the image is
// enlarged eight times with Scale2x (three passes; it rounds off diagonal
// steps and curves without inventing colours), then averaged back down to
// the size it will be shown at, which anti-aliases the rounded edges.
// Fully transparent pixels (a card's corners) are left out of the average.
#pragma once

#include "formats/dib.h"

namespace tp {

// One Scale2x (AdvMAME2x / EPX) pass: twice the width and height.
Image scale2x(const Image& in);

// The image at `factor` times its size (1-8), smoothed as above. factor 1
// returns it unchanged.
Image smoothUpscale(const Image& in, int factor);

}  // namespace tp
