#!/usr/bin/env bash
set -euo pipefail
# Package assets must remain readable and executable by the TV's app user.
umask 022
mode=${1:-dev}
case "$mode" in
	dev) odin_flags=(-debug) ;;
	release) odin_flags=(-o:speed) ;;
	bench) odin_flags=(-o:speed -define:PLAYBACK_BENCH=true) ;;
	*) printf 'usage: %s [dev|release|bench]\n' "$0" >&2; exit 2 ;;
esac
profile=${WEBOS_PROFILE:-default}
case "$profile" in
	default) ;;
	legacy) odin_flags+=(-define:WEBOS_LEGACY=true) ;;
	*) printf 'unknown WEBOS_PROFILE: %s (expected default or legacy)\n' "$profile" >&2; exit 2 ;;
esac
if [[ -n ${IMAGE_CACHE_MIB:-} ]]; then
	if [[ ! $IMAGE_CACHE_MIB =~ ^(0|[1-9][0-9]{0,2})$ ]] || ((IMAGE_CACHE_MIB > 256)); then
		printf 'IMAGE_CACHE_MIB must be an integer from 0 through 256\n' >&2
		exit 2
	fi
	odin_flags+=("-define:IMAGE_CACHE_MIB=$IMAGE_CACHE_MIB")
fi
if ! command -v ccache >/dev/null; then
	printf 'ccache is required for cached native builds\n' >&2
	exit 1
fi
export CCACHE_DIR="$PWD/.cache/ccache"
source scripts/env.sh
cc="$WEBOS_SDK/bin/arm-webos-linux-gnueabi-gcc"
pkg="$WEBOS_SDK/bin/pkg-config"
sysroot="$WEBOS_SDK/arm-webos-linux-gnueabi/sysroot"
for required in "$WEBOS_ODIN" "$cc" "$pkg" "$WEBOS_SDK/bin/wayland-scanner" "$sysroot/usr/lib/libcurl.so.4" "$WEBOS_PLATFORM/runtime/libssl.so.4" "$WEBOS_PLATFORM/runtime/libcrypto.so.4" "$WEBOS_PLATFORM/runtime/libSDL3.so.0" "$WEBOS_PLATFORM/runtime/libSDL3_ttf.so.0" "$WEBOS_PLATFORM/runtime/libSDL3_image.so.0"; do
	if [[ ! -f "$required" ]]; then
		printf 'missing toolchain input: %s\nrun just setup to build the pinned toolchain\n' "$required" >&2
		exit 1
	fi
done
# Recreate package staging, but keep local credentials, requests, and captures.
if [[ -d build/app ]]; then trash -- build/app; fi
mkdir -p build/obj build/app
"$WEBOS_ODIN" build src -target:linux_arm32 -microarch:cortex-a9 \
	-build-mode:obj -use-single-module -out:build/obj/leantube.o "${odin_flags[@]}" -define:APP_VERSION="$app_version"
scanner="$WEBOS_SDK/bin/wayland-scanner"
protocol=vendor/webos-text/text.xml
for generated in build/obj/text-client-protocol.h build/obj/text-protocol.c; do
	if [[ ! -f "$generated" || "$protocol" -nt "$generated" || "$scanner" -nt "$generated" ]]; then
		"$scanner" client-header "$protocol" build/obj/text-client-protocol.h
		"$scanner" private-code "$protocol" build/obj/text-protocol.c
		break
	fi
done
cpu=(-march=armv7-a -mfpu=neon -mfloat-abi=softfp)
read -r -a cflags <<< "$("$pkg" --cflags luna-service2 glib-2.0 wayland-client)"
read -r -a libs <<< "$("$pkg" --libs luna-service2 glib-2.0 wayland-client)"
# Keep the C dependencies optimized in both modes. Ccache tracks their inputs.
objects=()
for source in src/native/bridge.c src/native/clay.c src/native/webos-shell-protocol.c \
	build/obj/text-protocol.c vendor/qrcodegen/qrcodegen.c; do
	name=${source##*/}
	object="build/obj/${name%.c}.o"
	ccache "$cc" -c "$source" -std=c11 -O2 "${cpu[@]}" "${cflags[@]}" \
		-Isrc/native -Ibuild/obj -Ivendor/clay -Ivendor/qrcodegen -o "$object"
	objects+=("$object")
done
prefix="$WEBOS_PLATFORM/reader-ffmpeg"
if [[ ! -f "$prefix/lib/libavformat.so.63" ]]; then
	printf 'run just setup to build the native playback libraries\n' >&2
	exit 1
fi
# Keep each std::string ABI in its own compiler-generated C boundary.
cxx="$WEBOS_SDK/bin/arm-webos-linux-gnueabi-g++"
for abi in 0 1; do
	ccache "$cxx" -c -fPIC -std=c++11 -O2 "${cpu[@]}" -D_GLIBCXX_USE_CXX11_ABI="$abi" \
		-I"$sysroot/usr/include/starfish-media-pipeline" vendor/starfish/string_abi.cpp \
		-o "build/obj/starfish-string-$abi.o"
done
ccache "$cxx" -shared -fPIC -std=c++11 -O2 "${cpu[@]}" \
	-I"$sysroot/usr/include/starfish-media-pipeline" vendor/starfish/StarfishMediaAPIs_C.cpp \
	build/obj/starfish-string-0.o build/obj/starfish-string-1.o \
	-lplayerAPIs -ldl -Wl,-soname,libplayerAPIs_C.so -o build/obj/libplayerAPIs_C.so
reader_libraries=(-L"$prefix/lib" -lavformat -lavcodec -lavutil -Lbuild/obj -lplayerAPIs_C)
# The ELF loader expands $ORIGIN on the TV, not this shell.
# shellcheck disable=SC2016
"$cc" build/obj/leantube.o "${objects[@]}" "${cpu[@]}" "${reader_libraries[@]}" \
	-L"$WEBOS_PLATFORM/runtime" -Wl,-rpath-link,"$sysroot/usr/lib" \
	-l:libSDL3.so.0 -l:libSDL3_ttf.so.0 -l:libSDL3_image.so.0 -lAcbAPI \
	"${libs[@]}" -Wl,--allow-shlib-undefined \
	-l:libcurl.so.4 -l:libssl.so.4 -l:libcrypto.so.4 -lz -lm -lpthread -ldl -lrt -latomic \
	-Wl,--disable-new-dtags,-rpath,'$ORIGIN/lib' -o "build/app/$app_main"
cp -a app/. build/app/
if [[ $profile == legacy ]]; then
	jq '.nativeLifeCycleInterfaceVersion = 1' app/appinfo.json > build/app/appinfo.json
fi
mkdir -p build/app/lib
cp -a "$WEBOS_PLATFORM/runtime/." build/app/lib/
cp -a "$WEBOS_PLATFORM/licenses/." build/app/licenses/
cp build/obj/libplayerAPIs_C.so build/app/lib/
# Both string ABIs need the SDK's dual-ABI runtime on old firmware. This is
# app-private and also provides the legacy ABI required by firmware libraries.
cp -L "$("$cxx" -print-file-name=libstdc++.so.6)" build/app/lib/libstdc++.so.6
for library in libavformat.so.63 libavcodec.so.63 libavutil.so.61; do
	cp -L "$prefix/lib/$library" "build/app/lib/$library"
done
cp "$prefix/share/licenses/FFmpeg.txt" build/app/licenses/FFmpeg.txt
printf 'built %s for webOS ARM32 soft-float (%s)\n' "build/app/$app_main" "$mode"
