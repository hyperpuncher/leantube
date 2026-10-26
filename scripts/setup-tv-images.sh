#!/usr/bin/env bash
set -euo pipefail
source scripts/env.sh
source_dir="$PWD/.cache/image-source/SDL_image-3.4.8"
build="$PWD/.cache/tv-images-3.4.8"
if [[ ! -d "$source_dir" ]]; then
	git clone --depth=1 --single-branch --no-tags --branch release-3.4.8 \
		https://github.com/libsdl-org/SDL_image.git "$source_dir"
fi
# Use SDL_image's pinned dependency instead of wiring a second checkout by hand.
git -C "$source_dir" submodule update --init --depth=1 external/libwebp
cmake -S scripts/tv-images -B "$build" -G Ninja -DCMAKE_BUILD_TYPE=Release \
	-DIMAGE_SOURCE="$source_dir" \
	-DCMAKE_TOOLCHAIN_FILE="$WEBOS_SDK/share/buildroot/toolchainfile.cmake" \
	-DCMAKE_C_FLAGS='-mcpu=cortex-a9 -mfpu=neon -mfloat-abi=softfp' \
	-DTV_RUNTIME="$WEBOS_PLATFORM/runtime" -DTV_INCLUDE="$WEBOS_PLATFORM/include"
cmake --build "$build" --parallel 4
cp -L "$build/SDL_image/libSDL3_image.so.0" "$WEBOS_PLATFORM/runtime/"
"$WEBOS_SDK/bin/arm-webos-linux-gnueabi-strip" "$WEBOS_PLATFORM/runtime/libSDL3_image.so.0"
