#include "StarfishMediaAPIs.h"

// The host and ARM32 mangle int64_t differently. Export the firmware names.
#ifdef OLD_LOAD
StarfishMediaAPIs::StarfishMediaAPIs() {}
using Reply = void (*)(int, int64_t, const char *);
bool fixture_load(StarfishMediaAPIs *, const char *, Reply) asm("_ZN17StarfishMediaAPIs4LoadEPKcPFvixS1_E");
bool fixture_load(StarfishMediaAPIs *, const char *, Reply reply) {
    reply(0x15, 123, "ready");
    return true;
}
#else
StarfishMediaAPIs::StarfishMediaAPIs(const char *) {}
using Reply = void (*)(int, int64_t, const char *, void *);
bool fixture_load(StarfishMediaAPIs *, const char *, Reply, void *) asm("_ZN17StarfishMediaAPIs4LoadEPKcPFvixS1_PvES2_");
bool fixture_load(StarfishMediaAPIs *, const char *, Reply reply, void *data) {
    reply(0x16, 123, "ready", data);
    return true;
}
#endif
StarfishMediaAPIs::~StarfishMediaAPIs() {}
const char *StarfishMediaAPIs::getMediaID() { return "fixture"; }
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
    if (codec != "H264") return false;
    *w = 3840; *h = 2160; *fps = 60;
    return true;
}
} }
#endif
