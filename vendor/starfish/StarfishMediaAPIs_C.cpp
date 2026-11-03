#include "StarfishMediaAPIs_C.h"

#include <StarfishMediaAPIs.h>

// Added for LeanTube: query the installed capabilities without exporting C++ types.
namespace smp { namespace util {
bool getMaxVideoResolution(std::string, int32_t *, int32_t *, int32_t *) __attribute__((weak));
} }

#pragma clang diagnostic push
#pragma ide diagnostic ignored "bugprone-reserved-identifier"
extern "C" bool
_ZN17StarfishMediaAPIs10setHdrInfoEPKc(StarfishMediaAPIs *api, const char *message) __attribute__((weak));
extern "C" bool
_ZN17StarfishMediaAPIs18getAudioBufferSizeERiS0_(StarfishMediaAPIs *api, int *total, int *used) __attribute__((weak));
extern "C" bool
_ZN17StarfishMediaAPIs11SetPlayRateEPKc(StarfishMediaAPIs *api, const char *message) __attribute__((weak));
extern "C" bool
_ZN17StarfishMediaAPIs4SeekEPKc(StarfishMediaAPIs *api, const char *message) __attribute__((weak));
#pragma clang diagnostic pop

extern "C" {

struct StarfishMediaAPIs_C {
    StarfishMediaAPIs inner;
};

StarfishMediaAPIs_C *StarfishMediaAPIs_create(const char *uid) {
    return new StarfishMediaAPIs_C{
            .inner = StarfishMediaAPIs(uid)
    };
}
const char *StarfishMediaAPIs_getMediaID(StarfishMediaAPIs_C *api) {
    return api->inner.getMediaID();
}

bool StarfishMediaAPIs_feed(StarfishMediaAPIs_C *api, const char *payload, char *result, size_t resultLen) {
    auto ret = api->inner.Feed(payload);
    auto nCopied = ret.copy(result, resultLen - 1, 0);
    result[nCopied] = '\0';
    return true;
}

bool StarfishMediaAPIs_load(StarfishMediaAPIs_C *api, const char *payload, StarfishMediaAPIs_callbackWithData *callback,
                            void *data) {
    return api->inner.Load(payload, callback, data);
}

bool StarfishMediaAPIs_notifyForeground(StarfishMediaAPIs_C *api) {
    return api->inner.notifyForeground();
}

bool StarfishMediaAPIs_notifyBackground(StarfishMediaAPIs_C *api) {
    return api->inner.notifyBackground();
}

bool StarfishMediaAPIs_pause(StarfishMediaAPIs_C *api) {
    return api->inner.Pause();
}

bool StarfishMediaAPIs_play(StarfishMediaAPIs_C *api) {
    return api->inner.Play();
}

bool StarfishMediaAPIs_setPlayRate(StarfishMediaAPIs_C *api, const char *message) {
    if (_ZN17StarfishMediaAPIs11SetPlayRateEPKc == nullptr) return false;
    return _ZN17StarfishMediaAPIs11SetPlayRateEPKc(&api->inner, message);
}

bool StarfishMediaAPIs_seek(StarfishMediaAPIs_C *api, const char *message) {
    return _ZN17StarfishMediaAPIs4SeekEPKc != nullptr &&
           _ZN17StarfishMediaAPIs4SeekEPKc(&api->inner, message);
}

bool StarfishMediaAPIs_videoLimits(const char *codec, int32_t *width, int32_t *height, int32_t *fps) {
    using Query = bool (*)(std::string, int32_t *, int32_t *, int32_t *);
    auto query = static_cast<Query>(smp::util::getMaxVideoResolution);
    return query != nullptr && query(codec, width, height, fps);
}

bool StarfishMediaAPIs_pushEOS(StarfishMediaAPIs_C *api) {
    return api->inner.pushEOS();
}

bool StarfishMediaAPIs_setHdrInfo(StarfishMediaAPIs_C *api, const char *message) {
    if (_ZN17StarfishMediaAPIs10setHdrInfoEPKc == nullptr) {
        return false;
    }
    return _ZN17StarfishMediaAPIs10setHdrInfoEPKc(&api->inner, message);
}

bool StarfishMediaAPIs_getAudioBufferSize(StarfishMediaAPIs_C *api, int *total, int *used) {
    if (_ZN17StarfishMediaAPIs18getAudioBufferSizeERiS0_ == nullptr) {
        return false;
    }
    return _ZN17StarfishMediaAPIs18getAudioBufferSizeERiS0_(&api->inner, total, used);
}

bool StarfishMediaAPIs_unload(StarfishMediaAPIs_C *api) {
    return api->inner.Unload();
}

void StarfishMediaAPIs_destroy(StarfishMediaAPIs_C *api) {
    delete api;
}

}