#!/usr/bin/env bash
set -euo pipefail
source scripts/env.sh
if [[ -d build/layout-obj ]]; then trash -- build/layout-obj; fi
mkdir -p build/layout-obj
"$WEBOS_ODIN" build tests/layout -target:linux_arm32 -microarch:cortex-a9 \
	-build-mode:obj -out:build/layout-obj/test.o -debug -o:minimal
cc="$WEBOS_SDK/bin/arm-webos-linux-gnueabi-gcc"
"$cc" build/layout-obj/*.o build/obj/clay.o -lm -lpthread -ldl -lrt -o build/layout-check
scp -O build/layout-check "$TV_HOST:/tmp/leantube-layout-check"
ssh "$TV_HOST" /tmp/leantube-layout-check
