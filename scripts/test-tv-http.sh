#!/usr/bin/env bash
set -euo pipefail
source scripts/env.sh
link="$WEBOS_PLATFORM/device-link"
mkdir -p "$link"
# Link against the B9 libraries, not the newer SDK's OpenSSL 3 curl build.
# These copies are linker inputs only; no TV library is replaced or packaged.
if [[ ! -f "$link/libcurl.so.5" ]]; then
	scp -O -o BatchMode=yes -o ConnectTimeout=5 "$TV_HOST:/usr/lib/libcurl.so.5" "$link/libcurl.so.5"
fi
ln -sf libcurl.so.5 "$link/libcurl.so"
if [[ -d build/http-obj ]]; then trash -- build/http-obj; fi
mkdir -p build/http-obj
"$WEBOS_ODIN" build tests/http -target:linux_arm32 -microarch:cortex-a9 \
	-build-mode:obj -out:build/http-obj/test.o -debug -o:minimal
# The TV loader resolves libcurl's versioned dependencies against its own
# libraries. The SDK cannot resolve every legacy GLIBC symbol version.
"$WEBOS_SDK/bin/arm-webos-linux-gnueabi-gcc" build/http-obj/*.o \
	-L"$link" -Wl,--allow-shlib-undefined \
	-lcurl -lz -lm -lpthread -ldl -lrt -o build/http-check
scp -O -o BatchMode=yes -o ConnectTimeout=5 build/http-check "$TV_HOST:/tmp/leantube-http-check"
ssh -o BatchMode=yes -o ConnectTimeout=5 "$TV_HOST" 'timeout -t 40 /tmp/leantube-http-check'
