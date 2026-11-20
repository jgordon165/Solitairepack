// Sound effects: short sounds synthesized at startup (no samples from
// anywhere) and mixed on SDL's audio thread. The original Solitaire is
// silent; these are the port's own, in the spirit of the card sounds of
// the later Windows card games (docs/original.md).
#pragma once

#include <SDL.h>
#include <map>
#include <string>
#include <vector>

class Audio {
public:
    ~Audio();
    bool open();                    // false: no sound device (the game still runs)
    bool isOpen() const { return dev_ != 0; }
    void close();                   // before SDL_Quit

    // Plays a sound ("click", "flip", "deal"); unknown names are ignored.
    void play(const std::string& name, float gain = 1.0f);
    void setVolume(float v);

    // The synthesized sound, for the tests (mono, 44.1 kHz).
    static std::vector<float> synth(const std::string& name, int rate);

private:
    static void callback(void* user, Uint8* stream, int len);
    struct Voice { const std::vector<float>* pcm; size_t pos; float gain; };
    SDL_AudioDeviceID dev_ = 0;
    int rate_ = 44100;
    float volume_ = 0.8f;
    std::map<std::string, std::vector<float>> sounds_;
    std::vector<Voice> voices_;
};
