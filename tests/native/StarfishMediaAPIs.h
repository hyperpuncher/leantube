#pragma once
#include <cstdint>
#include <string>

// Only the unavailable LG implementation is replaced, not the string boundary.
class StarfishMediaAPIs {
public:
    explicit StarfishMediaAPIs(const char *);
    ~StarfishMediaAPIs();
    const char *getMediaID();
    bool Load(const char *, void (*)(int, int64_t, const char *, void *), void *);
    bool notifyForeground();
    bool notifyBackground();
    bool Pause();
    bool Play();
    bool pushEOS();
    bool Unload();
};
