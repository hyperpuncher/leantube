#!/usr/bin/env bash
set -euo pipefail
source scripts/env.sh
root=$WEBOS_TOOLCHAIN
mkdir -p "$WEBOS_PLATFORM/runtime"
export CCACHE_DIR="$root/ccache"
jobs=${JOBS:-4}
cpu="-march=armv7-a -mfpu=neon -mfloat-abi=softfp"
wayland_options=(-Dtests=false -Ddocumentation=false -Ddtd_validation=false --buildtype=release)
# The protocol scanner runs on the build host, not the TV.
meson setup --reconfigure "$root/build/wayland-host" "$root/src/wayland" --prefix="$root/host" --libdir=lib \
	-Dlibraries=false "${wayland_options[@]}"
meson compile -C "$root/build/wayland-host" -j "$jobs"
meson install -C "$root/build/wayland-host"
export PKG_CONFIG_PATH_FOR_BUILD="$root/host/lib/pkgconfig"
sysroot="$WEBOS_SDK/arm-webos-linux-gnueabi/sysroot"
meson setup --reconfigure "$root/build/wayland" "$root/src/wayland" --prefix=/usr --libdir=lib \
	--cross-file "$WEBOS_SDK/etc/meson/cross-compilation.conf" \
	-Dscanner=false "${wayland_options[@]}" -Dc_args="$cpu" -Dc_link_args="$cpu"
meson compile -C "$root/build/wayland" -j "$jobs"
# Replace the SDK's link-only EGL stub with Wayland's development symlink.
if [[ -f "$sysroot/usr/lib/libwayland-egl.so" && ! -L "$sysroot/usr/lib/libwayland-egl.so" ]]; then
	trash -- "$sysroot/usr/lib/libwayland-egl.so"
fi
# Upgrade only the private SDK sysroot. No TV system library is changed.
DESTDIR="$sysroot" meson install -C "$root/build/wayland"
unset PKG_CONFIG_PATH_FOR_BUILD
# Later xkbcommon releases reject the extended keycodes in LG remote keymaps.
meson setup --reconfigure "$root/build/xkbcommon" "$root/src/xkbcommon" --prefix=/usr --libdir=lib \
	--cross-file "$WEBOS_SDK/etc/meson/cross-compilation.conf" --buildtype=release \
	-Denable-x11=false -Denable-wayland=false -Denable-tools=false \
	-Denable-docs=false -Denable-xkbregistry=false -Denable-bash-completion=false \
	-Dxkb-config-root=/usr/share/X11/xkb -Dx-locale-root=/usr/share/X11/locale \
	-Dc_args="$cpu" -Dc_link_args="$cpu"
# Version 1.7 always defines test targets. Build only the runtime library.
meson compile -C "$root/build/xkbcommon" xkbcommon -j "$jobs"
DESTDIR="$sysroot" meson install -C "$root/build/xkbcommon" --no-rebuild
cmake -S scripts/platform -B "$root/build/platform" -G Ninja \
	-DSOURCE_ROOT="$root/src" -DCMAKE_SYSTEM_NAME=Linux \
	-DCMAKE_TOOLCHAIN_FILE="$WEBOS_SDK/share/buildroot/toolchainfile.cmake" \
	-DCMAKE_BUILD_TYPE=Release -DCMAKE_C_COMPILER_LAUNCHER=ccache \
	-DCMAKE_C_FLAGS="$cpu"
cmake --build "$root/build/platform" --parallel "$jobs"
for library in SDL:SDL3 SDL_ttf:SDL3_ttf SDL_image:SDL3_image; do
	component=${library%%:*}
	name=${library#*:}
	cp -L "$root/build/platform/$component/lib$name.so.0" "$WEBOS_PLATFORM/runtime/"
done
for library in libwayland-client.so.0 libwayland-cursor.so.0 libffi.so.8 libxkbcommon.so.0; do
	cp -L "$sysroot/usr/lib/$library" "$WEBOS_PLATFORM/runtime/"
done
for library in libgcc_s.so.1 libatomic.so.1; do
	cp -L "$("$WEBOS_SDK/bin/arm-webos-linux-gnueabi-gcc" -print-file-name="$library")" "$WEBOS_PLATFORM/runtime/"
done
"$WEBOS_SDK/bin/arm-webos-linux-gnueabi-strip" --strip-unneeded "$WEBOS_PLATFORM"/runtime/*.so.*
printf 'webOS native libraries built\n'
