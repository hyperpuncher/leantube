#include "StarfishMediaAPIs_C.h"

#include <StarfishMediaAPIs.h>

#include <dlfcn.h>
#include <mutex>
#include <new>

extern "C" bool starfish_feed_modern(StarfishMediaAPIs *, const char *, char *, size_t);
extern "C" bool starfish_feed_legacy(StarfishMediaAPIs *, const char *, char *, size_t);
extern "C" bool starfish_limits(const char *, int32_t *, int32_t *, int32_t *);

static bool modern_strings() {
    return dlsym(RTLD_DEFAULT, "_ZN17StarfishMediaAPIs4FeedB5cxx11EPKc") != nullptr;
}

using LoadWithData = bool (*)(StarfishMediaAPIs *, const char *, StarfishMediaAPIs_callbackWithData *, void *);
static LoadWithData load_with_data() {
    static auto load = reinterpret_cast<LoadWithData>(
        dlsym(RTLD_DEFAULT, "_ZN17StarfishMediaAPIs4LoadEPKcPFvixS1_PvES2_"));
    return load;
}

// Early firmware supplies no callback context. LeanTube opens one decoder at a time.
static std::mutex legacy_callback_mutex;
static StarfishMediaAPIs_callbackWithData *legacy_callback = nullptr;
static void *legacy_data = nullptr;

static void legacy_trampoline(int type, int64_t numValue, const char *strValue) {
    const std::lock_guard<std::mutex> lock(legacy_callback_mutex);
    if (legacy_callback != nullptr) {
        legacy_callback(type, numValue, strValue, legacy_data);
    }
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
    // Keep the pinned SDK's opaque size and alignment for either constructor.
    alignas(StarfishMediaAPIs) unsigned char storage[sizeof(StarfishMediaAPIs)];
    StarfishMediaAPIs *inner() { return reinterpret_cast<StarfishMediaAPIs *>(storage); }
};

StarfishMediaAPIs_C *StarfishMediaAPIs_create(const char *uid) {
    using CtorUid = void (*)(StarfishMediaAPIs *, const char *);
    using CtorVoid = void (*)(StarfishMediaAPIs *);
    auto *api = new (std::nothrow) StarfishMediaAPIs_C{};
    if (!api) return nullptr;
    if (auto ctor_uid = reinterpret_cast<CtorUid>(dlsym(RTLD_DEFAULT, "_ZN17StarfishMediaAPIsC1EPKc"))) {
        ctor_uid(api->inner(), uid);
        return api;
    }
    if (auto ctor_void = reinterpret_cast<CtorVoid>(dlsym(RTLD_DEFAULT, "_ZN17StarfishMediaAPIsC1Ev"))) {
        ctor_void(api->inner());
        return api;
    }
    delete api;
    return nullptr;
}
const char *StarfishMediaAPIs_getMediaID(StarfishMediaAPIs_C *api) {
    return api->inner()->getMediaID();
}

bool StarfishMediaAPIs_feed(StarfishMediaAPIs_C *api, const char *payload, char *result, size_t resultLen) {
    if (!api || !result || resultLen == 0) return false;
    result[0] = '\0';
    auto feed = modern_strings() ? starfish_feed_modern : starfish_feed_legacy;
    return feed(api->inner(), payload, result, resultLen);
}

bool StarfishMediaAPIs_load(StarfishMediaAPIs_C *api, const char *payload, StarfishMediaAPIs_callbackWithData *callback,
                            void *data) {
    using LegacyLoad = bool (*)(StarfishMediaAPIs *, const char *, void (*)(int, int64_t, const char *));
    if (auto load = load_with_data()) {
        return load(api->inner(), payload, callback, data);
    }
    if (auto load = reinterpret_cast<LegacyLoad>(dlsym(RTLD_DEFAULT, "_ZN17StarfishMediaAPIs4LoadEPKcPFvixS1_E"))) {
        {
            const std::lock_guard<std::mutex> lock(legacy_callback_mutex);
            legacy_callback = callback;
            legacy_data = data;
        }
        return load(api->inner(), payload, legacy_trampoline);
    }
    return false;
}

bool StarfishMediaAPIs_hasLoadWithData(void) {
    return load_with_data() != nullptr;
}

bool StarfishMediaAPIs_notifyForeground(StarfishMediaAPIs_C *api) {
    return api->inner()->notifyForeground();
}

bool StarfishMediaAPIs_notifyBackground(StarfishMediaAPIs_C *api) {
    return api->inner()->notifyBackground();
}

bool StarfishMediaAPIs_pause(StarfishMediaAPIs_C *api) {
    return api->inner()->Pause();
}

bool StarfishMediaAPIs_play(StarfishMediaAPIs_C *api) {
    return api->inner()->Play();
}

bool StarfishMediaAPIs_setPlayRate(StarfishMediaAPIs_C *api, const char *message) {
    if (_ZN17StarfishMediaAPIs11SetPlayRateEPKc == nullptr) return false;
    return _ZN17StarfishMediaAPIs11SetPlayRateEPKc(api->inner(), message);
}

bool StarfishMediaAPIs_seek(StarfishMediaAPIs_C *api, const char *message) {
    return _ZN17StarfishMediaAPIs4SeekEPKc != nullptr &&
           _ZN17StarfishMediaAPIs4SeekEPKc(api->inner(), message);
}

bool StarfishMediaAPIs_videoLimits(const char *codec, int32_t *width, int32_t *height, int32_t *fps) {
    return starfish_limits(codec, width, height, fps);
}

bool StarfishMediaAPIs_pushEOS(StarfishMediaAPIs_C *api) {
    return api->inner()->pushEOS();
}

bool StarfishMediaAPIs_setHdrInfo(StarfishMediaAPIs_C *api, const char *message) {
    if (_ZN17StarfishMediaAPIs10setHdrInfoEPKc == nullptr) {
        return false;
    }
    return _ZN17StarfishMediaAPIs10setHdrInfoEPKc(api->inner(), message);
}

bool StarfishMediaAPIs_getAudioBufferSize(StarfishMediaAPIs_C *api, int *total, int *used) {
    if (_ZN17StarfishMediaAPIs18getAudioBufferSizeERiS0_ == nullptr) {
        return false;
    }
    return _ZN17StarfishMediaAPIs18getAudioBufferSizeERiS0_(api->inner(), total, used);
}

bool StarfishMediaAPIs_unload(StarfishMediaAPIs_C *api) {
    return api->inner()->Unload();
}

void StarfishMediaAPIs_destroy(StarfishMediaAPIs_C *api) {
    if (!api) return;
    using Dtor = void (*)(StarfishMediaAPIs *);
    if (auto dtor = reinterpret_cast<Dtor>(dlsym(RTLD_DEFAULT, "_ZN17StarfishMediaAPIsD1Ev"))) {
        dtor(api->inner());
    }
    if (!load_with_data()) {
        const std::lock_guard<std::mutex> lock(legacy_callback_mutex);
        legacy_callback = nullptr;
        legacy_data = nullptr;
    }
    delete api;
}

}