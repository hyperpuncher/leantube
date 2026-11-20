#pragma once
#include <cstdint>
#include <string>

// Only the unavailable LG implementation is replaced, not the string boundary.
class StarfishMediaAPIs {
public:
    StarfishMediaAPIs();
    explicit StarfishMediaAPIs(const char *);
    ~StarfishMediaAPIs();
    const char *getMediaID();
    bool notifyForeground();
    bool notifyBackground();
    bool Pause();
    bool Play();
    bool pushEOS();
    bool Unload();
};
