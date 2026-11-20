#include "../../vendor/starfish/StarfishMediaAPIs_C.h"
#include <cassert>
#include <cstring>
#include <string>

int main() {
    auto api = StarfishMediaAPIs_create(nullptr);
    assert(api);
#ifdef OLD_LOAD
    const int ready = 0x15;
#else
    const int ready = 0x16;
#endif
    assert(StarfishMediaAPIs_hasLoadWithData() == (ready == 0x16));
    int event = 0;
    assert(StarfishMediaAPIs_load(api, "{}", [](int kind, int64_t value, const char *text, void *data) {
        assert(value == 123 && std::strcmp(text, "ready") == 0 && data);
        *static_cast<int *>(data) = kind;
    }, &event));
    assert(event == ready);
    char reply[128];
    const std::string large(256, 'x');
    for (int i = 0; i < 10000; ++i) {
        assert(StarfishMediaAPIs_feed(api, "Ok", reply, sizeof(reply)));
        assert(std::strcmp(reply, "Ok") == 0);
        assert(StarfishMediaAPIs_feed(api, large.c_str(), reply, sizeof(reply)));
        assert(std::strlen(reply) == sizeof(reply) - 1);
    }
    assert(!StarfishMediaAPIs_feed(api, "Ok", nullptr, 0));
    assert(!StarfishMediaAPIs_feed(api, "Ok", reply, 0));
    assert(!StarfishMediaAPIs_feed(nullptr, "Ok", reply, sizeof(reply)));
    assert(!StarfishMediaAPIs_feed(api, nullptr, reply, sizeof(reply)));
    assert(StarfishMediaAPIs_feed(api, "Ok", reply, 1));
    assert(reply[0] == '\0');
    int32_t width = 0, height = 0, fps = 0;
#ifdef NO_LIMITS
    assert(!StarfishMediaAPIs_videoLimits("H264", &width, &height, &fps));
#else
    assert(StarfishMediaAPIs_videoLimits("H264", &width, &height, &fps));
    assert(width == 3840 && height == 2160 && fps == 60);
#endif
    assert(!StarfishMediaAPIs_videoLimits("AV1", &width, &height, &fps));
    assert(!StarfishMediaAPIs_videoLimits(nullptr, &width, &height, &fps));
    assert(!StarfishMediaAPIs_setPlayRate(api, "{}"));
    assert(!StarfishMediaAPIs_setHdrInfo(api, "{}"));
    StarfishMediaAPIs_destroy(api);
}
