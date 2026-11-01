#!/usr/bin/env bash
set -euo pipefail
source scripts/env.sh
mkdir -p build
"$WEBOS_ODIN" build tests/layout -target:linux_arm32 -microarch:cortex-a9 \
	-build-mode:obj -use-single-module -out:build/layout-check.o -debug -o:minimal
cc="$WEBOS_SDK/bin/arm-webos-linux-gnueabi-gcc"
"$cc" build/layout-check.o src/native/clay.c -Ivendor/clay -O2 \
	-mcpu=cortex-a9 -mfpu=neon -mfloat-abi=softfp \
	-lm -lpthread -ldl -lrt -o build/layout-check
ares-push build/layout-check /tmp/leantube-layout-check
ares-shell -r 'chmod 755 /tmp/leantube-layout-check && /tmp/leantube-layout-check >/tmp/leantube-layout.log 2>&1'
ares-pull /tmp/leantube-layout.log build
