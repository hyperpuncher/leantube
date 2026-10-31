#!/usr/bin/env bash
set -euo pipefail
source scripts/env.sh
sysroot="$WEBOS_SDK/arm-webos-linux-gnueabi/sysroot"
libs=build/tv-http-libs
if [[ -d "$libs" ]]; then trash -- "$libs"; fi
mkdir -p "$libs"
cp -L "$WEBOS_PLATFORM/runtime/"{libcurl.so.4,libssl.so.4,libcrypto.so.4,libz.so.1,libatomic.so.1,libnghttp3.so.9,libngtcp2.so.16,libngtcp2_crypto_ossl.so.0} "$libs/"
"$WEBOS_SDK/bin/arm-webos-linux-gnueabi-strip" --strip-unneeded "$libs/"*
"$WEBOS_ODIN" build tests/http -target:linux_arm32 -microarch:cortex-a9 \
	-build-mode:obj -use-single-module -out:build/http-check.o -debug -o:minimal
"$WEBOS_SDK/bin/arm-webos-linux-gnueabi-gcc" build/http-check.o \
	-L"$sysroot/usr/lib" -Wl,-rpath-link,"$sysroot/usr/lib" \
	-Wl,--allow-shlib-undefined -l:libcurl.so.4 -l:libssl.so.4 -l:libcrypto.so.4 \
	-lz -lm -lpthread -ldl -lrt -o build/http-check
trap 'ssh -o BatchMode=yes -o ConnectTimeout=5 "$TV_HOST" '\''rm -rf /tmp/leantube-http-libs /tmp/leantube-http-check'\'' >/dev/null 2>&1 || true' EXIT
ssh -o BatchMode=yes -o ConnectTimeout=5 "$TV_HOST" 'rm -rf /tmp/leantube-http-libs && mkdir -p /tmp/leantube-http-libs'
scp -O -o BatchMode=yes -o ConnectTimeout=5 build/http-check "$TV_HOST:/tmp/leantube-http-check"
scp -O -o BatchMode=yes -o ConnectTimeout=5 "$libs"/* "$TV_HOST:/tmp/leantube-http-libs/"
ssh -o BatchMode=yes -o ConnectTimeout=5 "$TV_HOST" \
	'LD_LIBRARY_PATH=/tmp/leantube-http-libs timeout -t 40 /tmp/leantube-http-check'
