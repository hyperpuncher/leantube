#include "StarfishMediaAPIs.h"

StarfishMediaAPIs::StarfishMediaAPIs(const char *) {}
StarfishMediaAPIs::~StarfishMediaAPIs() {}
const char *StarfishMediaAPIs::getMediaID() { return "fixture"; }
bool StarfishMediaAPIs::Load(const char *, void (*)(int, int64_t, const char *, void *), void *) { return true; }
bool StarfishMediaAPIs::notifyForeground() { return true; }
bool StarfishMediaAPIs::notifyBackground() { return true; }
bool StarfishMediaAPIs::Pause() { return true; }
bool StarfishMediaAPIs::Play() { return true; }
bool StarfishMediaAPIs::pushEOS() { return true; }
bool StarfishMediaAPIs::Unload() { return true; }

#if _GLIBCXX_USE_CXX11_ABI
#define FEED_SYMBOL "_ZN17StarfishMediaAPIs4FeedB5cxx11EPKc"
#else
#define FEED_SYMBOL "_ZN17StarfishMediaAPIs4FeedEPKc"
#endif
std::string fixture_feed(StarfishMediaAPIs *, const char *) asm(FEED_SYMBOL);
std::string fixture_feed(StarfishMediaAPIs *, const char *payload) { return payload; }

#ifndef NO_LIMITS
namespace smp { namespace util {
bool getMaxVideoResolution(std::string codec, int32_t *w, int32_t *h, int32_t *fps) {
#ifdef REJECT_LIMITS
    (void)codec; (void)w; (void)h; (void)fps;
    return false;
#else
    if (codec != "H264") return false;
    *w = 3840; *h = 2160; *fps = 60;
    return true;
#endif
}
} }
#endif
