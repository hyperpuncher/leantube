#!/usr/bin/env bash
set -euo pipefail
source scripts/env.sh
cc="$WEBOS_SDK/bin/arm-webos-linux-gnueabi-gcc"
pkg="$WEBOS_SDK/bin/pkg-config"
for required in "$WEBOS_ODIN" "$cc" "$pkg" "$WEBOS_PLATFORM/runtime/libSDL3.so.0"; do
	if [[ ! -f "$required" ]]; then
		printf 'missing toolchain input: %s\nsee docs/toolchain.md\n' "$required" >&2
		exit 1
	fi
done
# Odin's object filenames can change when reachable procedures change.
# Clear objects and package staging, but keep private requests and captures.
for directory in build/obj build/app; do
	if [[ -d "$directory" ]]; then trash -- "$directory"; fi
done
mkdir -p build/obj build/app
"$WEBOS_ODIN" build src -target:linux_arm32 -microarch:cortex-a9 \
	-build-mode:obj -out:build/obj/leantube.o -debug -o:minimal
cpu=(-mcpu=cortex-a9 -mfpu=neon -mfloat-abi=softfp)
read -r -a cflags <<< "$("$pkg" --cflags luna-service2 glib-2.0 wayland-client)"
read -r -a libs <<< "$("$pkg" --libs luna-service2 glib-2.0 wayland-client)"
"$cc" -c src/native/bridge.c -o build/obj/bridge.o -std=c11 -Og -g \
	"${cpu[@]}" -Isrc/native "${cflags[@]}"
"$cc" -c src/native/webos-shell-protocol.c -o build/obj/protocol.o \
	"${cpu[@]}" "${cflags[@]}"
"$cc" -c src/native/clay.c -o build/obj/clay.o -std=c11 -O2 \
	"${cpu[@]}" -Ivendor/clay
# The ELF loader expands $ORIGIN on the TV, not this shell.
# shellcheck disable=SC2016
"$cc" build/obj/*.o -L"$WEBOS_PLATFORM/runtime" -L"$WEBOS_PLATFORM/device-link" \
	-Wl,-rpath-link,"$WEBOS_PLATFORM/device-link" -l:libSDL3.so.0 -lAcbAPI \
	"${libs[@]}" -lm -lpthread -ldl -lrt -latomic \
	-Wl,--disable-new-dtags,-rpath,'$ORIGIN/lib' -o "build/app/$app_main"
cp app/appinfo.json app/icon.png build/app/
mkdir -p build/app/lib
cp -a "$WEBOS_PLATFORM/runtime/." build/app/lib/
printf 'built %s for B9 ARM32 soft-float\n' "build/app/$app_main"
