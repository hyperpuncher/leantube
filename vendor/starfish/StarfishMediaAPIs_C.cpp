#include "StarfishMediaAPIs_C.h"

#include <StarfishMediaAPIs.h>

#include <dlfcn.h>

extern "C" bool starfish_feed_modern(StarfishMediaAPIs *, const char *, char *, size_t);
extern "C" bool starfish_feed_legacy(StarfishMediaAPIs *, const char *, char *, size_t);
extern "C" bool starfish_limits(const char *, int32_t *, int32_t *, int32_t *);

static bool modern_strings() {
    return dlsym(RTLD_DEFAULT, "_ZN17StarfishMediaAPIs4FeedB5cxx11EPKc") != nullptr;
}

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
    if (!api || !result || resultLen == 0) return false;
    result[0] = '\0';
    auto feed = modern_strings() ? starfish_feed_modern : starfish_feed_legacy;
    return feed(&api->inner, payload, result, resultLen);
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
    return starfish_limits(codec, width, height, fps);
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