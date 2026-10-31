#!/usr/bin/env bash
set -euo pipefail
source scripts/env.sh
version=n9.0.2
revision=946fcce07b6dcd0331c8cc609192aeff5e1924f8
source_dir="$WEBOS_TOOLCHAIN/src/reader-ffmpeg-${version#n}"
build_dir="$WEBOS_TOOLCHAIN/build/reader-ffmpeg-${version#n}"
prefix="$WEBOS_TOOLCHAIN/platform/reader-ffmpeg"
if [[ ! -d "$source_dir/.git" ]]; then
	git clone --depth=1 --single-branch --no-tags --branch "$version" https://github.com/FFmpeg/FFmpeg.git "$source_dir"
fi
[[ $(git -C "$source_dir" rev-parse HEAD) == "$revision" ]] || { printf 'unexpected FFmpeg source revision\n' >&2; exit 1; }
mkdir -p "$build_dir"
# FFmpeg uses its upstream configure and make tasks, not CMake.
(
	cd "$build_dir"
	"$source_dir/configure" --prefix="$prefix" --target-os=linux --arch=arm --cpu=cortex-a9 \
		--enable-cross-compile --cross-prefix="$WEBOS_SDK/bin/arm-webos-linux-gnueabi-" \
		--sysroot="$WEBOS_SDK/arm-webos-linux-gnueabi/sysroot" --pkg-config="$WEBOS_SDK/bin/pkg-config" \
		--extra-cflags='-march=armv7-a -mfpu=neon -mfloat-abi=softfp' \
		--enable-shared --disable-static --disable-programs --disable-doc --disable-debug \
		--disable-asm --disable-autodetect --disable-everything --disable-avdevice --disable-avfilter \
		--disable-swscale --disable-swresample --enable-network --enable-openssl --enable-zlib \
		--enable-demuxer=mov,matroska --enable-muxer=adts --enable-parser=aac,vp9 --enable-decoder=aac,vp9 \
		--enable-protocol=file,http,https,tcp,tls
	# Relink against the current private SDK after dependency ABI updates.
	make clean
	make -j"$(getconf _NPROCESSORS_ONLN)"
	make install
)
mkdir -p "$prefix/share/licenses"
cp "$source_dir/COPYING.LGPLv2.1" "$prefix/share/licenses/FFmpeg.txt"
