#!/usr/bin/env bash
set -euo pipefail
# Package assets must remain readable and executable by the TV's app user.
umask 022
source scripts/env.sh
cc="$WEBOS_SDK/bin/arm-webos-linux-gnueabi-gcc"
pkg="$WEBOS_SDK/bin/pkg-config"
sysroot="$WEBOS_SDK/arm-webos-linux-gnueabi/sysroot"
for required in "$WEBOS_ODIN" "$cc" "$pkg" "$WEBOS_SDK/bin/wayland-scanner" "$sysroot/usr/lib/libcurl.so.4" "$sysroot/usr/lib/libssl.so.3" "$sysroot/usr/lib/libcrypto.so.3" "$WEBOS_PLATFORM/runtime/libSDL3.so.0" "$WEBOS_PLATFORM/runtime/libSDL3_ttf.so.0" "$WEBOS_PLATFORM/runtime/libSDL3_image.so.0"; do
	if [[ ! -f "$required" ]]; then
		printf 'missing toolchain input: %s\nconfigure the cache paths in .env; see .env.example\n' "$required" >&2
		exit 1
	fi
done
# Recreate package staging, but keep local credentials, requests, and captures.
if [[ -d build/app ]]; then trash -- build/app; fi
mkdir -p build/obj build/app
odin_flags=(-o:speed)
c_flags=(-O2)
if [[ ${LEANTUBE_DEBUG:-0} == 1 ]]; then
	odin_flags=(-debug -o:minimal)
	c_flags=(-Og -g)
fi
"$WEBOS_ODIN" build src -target:linux_arm32 -microarch:cortex-a9 \
	-build-mode:obj -use-single-module -out:build/obj/leantube.o "${odin_flags[@]}" -define:APP_VERSION="$app_version"
"$WEBOS_SDK/bin/wayland-scanner" client-header vendor/webos-text/text.xml build/obj/text-client-protocol.h
"$WEBOS_SDK/bin/wayland-scanner" private-code vendor/webos-text/text.xml build/obj/text-protocol.c
cpu=(-mcpu=cortex-a9 -mfpu=neon -mfloat-abi=softfp)
read -r -a cflags <<< "$("$pkg" --cflags luna-service2 glib-2.0 wayland-client)"
read -r -a libs <<< "$("$pkg" --libs luna-service2 glib-2.0 wayland-client)"
# The ELF loader expands $ORIGIN on the TV, not this shell.
# shellcheck disable=SC2016
"$cc" build/obj/leantube.o \
	src/native/bridge.c src/native/clay.c \
	src/native/webos-shell-protocol.c build/obj/text-protocol.c vendor/qrcodegen/qrcodegen.c \
	-std=c11 "${c_flags[@]}" "${cpu[@]}" "${cflags[@]}" \
	-Isrc/native -Ibuild/obj -Ivendor/clay -Ivendor/qrcodegen \
	-L"$WEBOS_PLATFORM/runtime" -L"$WEBOS_PLATFORM/device-link" \
	-Wl,-rpath-link,"$WEBOS_PLATFORM/device-link" -Wl,-rpath-link,"$sysroot/usr/lib" \
	-l:libSDL3.so.0 -l:libSDL3_ttf.so.0 -l:libSDL3_image.so.0 -lAcbAPI \
	"${libs[@]}" -Wl,--allow-shlib-undefined \
	-l:libcurl.so.4 -l:libssl.so.3 -l:libcrypto.so.3 -lz -lm -lpthread -ldl -lrt -latomic \
	-Wl,--disable-new-dtags,-rpath,'$ORIGIN/lib' -o "build/app/$app_main"
cp -a app/. build/app/
mkdir -p build/app/lib
cp -a "$WEBOS_PLATFORM/runtime/." build/app/lib/
for library in libcurl.so.4 libssl.so.3 libcrypto.so.3; do
	cp -L "$sysroot/usr/lib/$library" "build/app/lib/$library"
	"$WEBOS_SDK/bin/arm-webos-linux-gnueabi-strip" --strip-unneeded "build/app/lib/$library"
done
printf 'built %s for B9 ARM32 soft-float\n' "build/app/$app_main"
