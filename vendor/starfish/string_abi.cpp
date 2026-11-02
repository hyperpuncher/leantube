#include "StarfishMediaAPIs_C.h"

#include <StarfishMediaAPIs.h>
#include <dlfcn.h>
#include <string>

#if _GLIBCXX_USE_CXX11_ABI
#define ABI_FUNCTION(name) name##_modern
#define FEED_SYMBOL "_ZN17StarfishMediaAPIs4FeedB5cxx11EPKc"
#else
#define ABI_FUNCTION(name) name##_legacy
#define FEED_SYMBOL "_ZN17StarfishMediaAPIs4FeedEPKc"
#endif

// Compile this translation unit twice. Each compiler-generated string owns its
// return storage, copy and destructor; no C++ object crosses the C boundary.
extern "C" bool ABI_FUNCTION(starfish_feed)(StarfishMediaAPIs *api, const char *payload,
                                           char *result, size_t size) {
    using Feed = std::string (*)(StarfishMediaAPIs *, const char *);
    auto feed = reinterpret_cast<Feed>(dlsym(RTLD_DEFAULT, FEED_SYMBOL));
    if (!feed || !api || !payload || !result || size == 0) return false;
    auto reply = feed(api, payload);
    auto copied = reply.copy(result, size - 1);
    result[copied] = '\0';
    return true;
}

#if _GLIBCXX_USE_CXX11_ABI
// Only modern firmware exports the capability query.
extern "C" bool starfish_limits(const char *codec, int32_t *width, int32_t *height, int32_t *fps) {
    using Query = bool (*)(std::string, int32_t *, int32_t *, int32_t *);
    auto query = reinterpret_cast<Query>(dlsym(
        RTLD_DEFAULT,
        "_ZN3smp4util21getMaxVideoResolutionENSt7__cxx1112basic_stringIcSt11char_traitsIcESaIcEEEPiS7_S7_"));
    return query && codec && width && height && fps && query(codec, width, height, fps);
}
#endif
