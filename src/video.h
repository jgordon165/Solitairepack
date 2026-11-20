// The window and everything drawn to it. The Lua side draws on a logical
// canvas that follows the window's size at the chosen zoom, as the
// original's window shows more table when it's made bigger; SDL scales it
// to the window (letterboxing only the fraction of a zoomed pixel left over).
#pragma once

#include "formats/dib.h"

#include <SDL.h>
#include <string>
#include <vector>

class Video {
public:
    ~Video();
    // canvasW x canvasH at `scale` is the window's starting size; minW x
    // minH the smallest canvas it can be resized to.
    bool open(const std::string& title, int canvasW, int canvasH, double scale, int minW, int minH);
    void setTitle(const std::string& t);
    void setCanvas(int w, int h);
    // Resizes the canvas to the window's size divided by the zoom (no
    // smaller than the minimum given at open). True when it changed.
    bool fitCanvas();
    // Full screen (the desktop's resolution) or back to a window.
    void toggleFullscreen();
    void windowSize(int& w, int& h) const;
    bool hasMouseFocus() const;
    // Moves the mouse pointer to a canvas position.
    void warpMouse(int cx, int cy);
    int canvasW() const { return cw_; }
    int canvasH() const { return ch_; }

    void clear(uint8_t r, uint8_t g, uint8_t b);
    // Limits drawing to a rectangle of the canvas; w <= 0 lifts the limit.
    void clip(int x, int y, int w, int h);
    void fill(int x, int y, int w, int h, uint8_t r, uint8_t g, uint8_t b, uint8_t a = 255);
    // Built-in fonts, so the port can show text without the original's:
    // Small, 3x5 (digits, A-Z, a little punctuation); System, proportional
    // and bold in the style of the Windows 3.x System font (font_system.h).
    enum class Font { Small, System };
    void text(int x, int y, const std::string& s, int scale, uint8_t r, uint8_t g, uint8_t b, Font font = Font::Small);
    static int textWidth(const std::string& s, int scale, Font font = Font::Small);

    // Uploads a decoded bitmap; returns a handle for draw(), or -1.
    // texScale: the image is that many times bigger than it's drawn (a
    // smoothed card at renderScale()); draw() takes rectangles in canvas
    // pixels either way.
    int addImage(const tp::Image& img, int texScale = 1);
    void freeImage(int handle);

    // The canvas is drawn at this many real pixels per canvas pixel (the
    // zoom times the display's pixel density, rounded up; at most 4), so
    // smoothed cards keep their detail.
    int renderScale() const { return rs_; }
    // How the finished canvas is scaled to the window: smoothly (linear) or
    // as sharp pixels (nearest).
    void setSmooth(bool on) { smooth_ = on; }
    void draw(int handle, int sx, int sy, int sw, int sh, int dx, int dy, int dw, int dh, bool flip = false);

    void compose();   // canvas -> window, before screenshot() and present()
    // A window position (mouse events, in window coordinates) to the canvas
    // pixel under it, through compose()'s scaling and letterbox. False when
    // it falls in the letterbox.
    bool windowToCanvas(int wx, int wy, int& cx, int& cy) const;
    // The other way: the window position (in points) showing canvas pixel
    // (cx, cy)'s centre.
    void canvasToWindow(int cx, int cy, int& wx, int& wy) const;
    void present();
    // Saves what's in the window (the canvas as scaled to it) as a .bmp.
    bool screenshot(const std::string& path);

private:
    SDL_Window* win_ = nullptr;
    SDL_Renderer* ren_ = nullptr;
    std::vector<SDL_Texture*> tex_;
    std::vector<int> texScale_;
    int rs_ = 1;
    bool smooth_ = false;
    SDL_Texture* canvas_ = nullptr;  // everything is drawn here at canvas size, then scaled to the window
    int cw_ = 0, ch_ = 0;
    double scale_ = 1.0;
    int minW_ = 1, minH_ = 1;
    SDL_Rect clipSaved_{};          // the canvas clip, kept across compose()
};
