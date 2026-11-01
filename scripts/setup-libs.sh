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
meson setup --reconfigure "$root/build/xkbcommon" "$root/src/xkbcommon" --prefix=/usr --libdir=lib \
	--cross-file "$WEBOS_SDK/etc/meson/cross-compilation.conf" --buildtype=release \
	-Denable-x11=false -Denable-wayland=false -Denable-tools=false \
	-Denable-docs=false -Denable-xkbregistry=false -Denable-bash-completion=false \
	-Dxkb-config-root=/usr/share/X11/xkb -Dx-locale-root=/usr/share/X11/locale \
	-Dc_args="$cpu" -Dc_link_args="$cpu"
# Build only the runtime library, not cross-compiled test programs.
meson compile -C "$root/build/xkbcommon" xkbcommon -j "$jobs"
DESTDIR="$sysroot" meson install -C "$root/build/xkbcommon" --no-rebuild
# Build the app's network stack in the private SDK, never on the TV.
cmake -S "$root/src/zlib" -B "$root/build/zlib" -G Ninja \
	-DCMAKE_TOOLCHAIN_FILE="$WEBOS_SDK/share/buildroot/toolchainfile.cmake" \
	-DCMAKE_INSTALL_PREFIX=/usr -DCMAKE_INSTALL_LIBDIR=lib -DCMAKE_BUILD_TYPE=Release \
	-DCMAKE_C_FLAGS="$cpu" -DZLIB_BUILD_TESTING=OFF
cmake --build "$root/build/zlib" --parallel "$jobs"
DESTDIR="$sysroot" cmake --install "$root/build/zlib"
# OpenSSL 4.1 generates this header even with no-apps in an out-of-tree build.
mkdir -p "$root/build/openssl/apps/include"
(
	cd "$root/build/openssl"
	"$root/src/openssl/Configure" linux-armv4 shared no-tests no-apps no-docs no-module \
		--cross-compile-prefix="$WEBOS_SDK/bin/arm-webos-linux-gnueabi-" \
		--prefix=/usr --libdir=lib --openssldir=/etc/ssl \
		-march=armv7-a -mfpu=neon -mfloat-abi=softfp
	make -j"$jobs"
	make DESTDIR="$sysroot" install_sw
)
# Use upstream C libraries for HTTP/3, with the same private OpenSSL build.
for component in nghttp3 ngtcp2; do
	quic_options=()
	if [[ "$component" == ngtcp2 ]]; then
		quic_options=(-DENABLE_OPENSSL=ON -DOPENSSL_INCLUDE_DIR="$sysroot/usr/include"
			-DOPENSSL_SSL_LIBRARY="$sysroot/usr/lib/libssl.so.4"
			-DOPENSSL_CRYPTO_LIBRARY="$sysroot/usr/lib/libcrypto.so.4")
	fi
	cmake -S "$root/src/$component" -B "$root/build/$component" -G Ninja \
		-DCMAKE_TOOLCHAIN_FILE="$WEBOS_SDK/share/buildroot/toolchainfile.cmake" \
		-DCMAKE_INSTALL_PREFIX=/usr -DCMAKE_INSTALL_LIBDIR=lib -DCMAKE_BUILD_TYPE=Release \
		-DCMAKE_C_FLAGS="$cpu" -DCMAKE_SKIP_RPATH=ON -DENABLE_LIB_ONLY=ON \
		-DENABLE_SHARED_LIB=ON -DENABLE_STATIC_LIB=OFF -DBUILD_TESTING=OFF "${quic_options[@]}"
	cmake --build "$root/build/$component" --parallel "$jobs"
	DESTDIR="$sysroot" cmake --install "$root/build/$component"
done
cmake -S "$root/src/curl" -B "$root/build/curl" -G Ninja \
	-DCMAKE_TOOLCHAIN_FILE="$WEBOS_SDK/share/buildroot/toolchainfile.cmake" \
	-DCMAKE_INSTALL_PREFIX=/usr -DCMAKE_INSTALL_LIBDIR=lib -DCMAKE_BUILD_TYPE=Release \
	-DCMAKE_C_FLAGS="$cpu" -DCMAKE_SKIP_RPATH=ON \
	-DBUILD_SHARED_LIBS=ON -DBUILD_STATIC_LIBS=OFF -DBUILD_CURL_EXE=OFF \
	-DBUILD_TESTING=OFF -DBUILD_EXAMPLES=OFF -DBUILD_LIBCURL_DOCS=OFF -DBUILD_MISC_DOCS=OFF \
	-DCURL_USE_OPENSSL=ON -DOPENSSL_INCLUDE_DIR="$sysroot/usr/include" \
	-DOPENSSL_SSL_LIBRARY="$sysroot/usr/lib/libssl.so.4" \
	-DOPENSSL_CRYPTO_LIBRARY="$sysroot/usr/lib/libcrypto.so.4" \
	-DCURL_ZLIB=ON -DCURL_BROTLI=OFF -DCURL_ZSTD=OFF \
	-DCURL_USE_LIBPSL=OFF -DCURL_USE_LIBSSH2=OFF -DUSE_LIBIDN2=OFF -DUSE_NGHTTP2=OFF \
	-DUSE_NGTCP2=ON -DUSE_NGHTTP3=ON \
	-DCURL_DISABLE_LDAP=ON -DCURL_DISABLE_LDAPS=ON \
	-DCURL_CA_BUNDLE=/etc/ssl/certs/ca-certificates.crt -DCURL_CA_PATH=none
cmake --build "$root/build/curl" --parallel "$jobs"
DESTDIR="$sysroot" cmake --install "$root/build/curl"
cmake -S scripts/platform -B "$root/build/platform" -G Ninja \
	-DSOURCE_ROOT="$root/src" -DCMAKE_SYSTEM_NAME=Linux \
	-DCMAKE_TOOLCHAIN_FILE="$WEBOS_SDK/share/buildroot/toolchainfile.cmake" \
	-DCMAKE_BUILD_TYPE=Release -DCMAKE_C_COMPILER_LAUNCHER=ccache \
	-DCMAKE_C_FLAGS="$cpu" -DCMAKE_CXX_FLAGS="$cpu"
cmake --build "$root/build/platform" --parallel "$jobs"
for library in SDL:SDL3 SDL_ttf:SDL3_ttf SDL_image:SDL3_image; do
	component=${library%%:*}
	name=${library#*:}
	cp -L "$root/build/platform/$component/lib$name.so.0" "$WEBOS_PLATFORM/runtime/"
done
for library in libwayland-client.so.0 libwayland-cursor.so.0 libffi.so.8 libxkbcommon.so.0 libcurl.so.4 libssl.so.4 libcrypto.so.4 libz.so.1 libnghttp3.so.9 libngtcp2.so.16 libngtcp2_crypto_ossl.so.0; do
	cp -L "$sysroot/usr/lib/$library" "$WEBOS_PLATFORM/runtime/"
done
for library in libgcc_s.so.1 libatomic.so.1; do
	cp -L "$("$WEBOS_SDK/bin/arm-webos-linux-gnueabi-gcc" -print-file-name="$library")" "$WEBOS_PLATFORM/runtime/"
done
"$WEBOS_SDK/bin/arm-webos-linux-gnueabi-strip" --strip-unneeded "$WEBOS_PLATFORM"/runtime/*.so.*
mkdir -p "$WEBOS_PLATFORM/licenses"
cp "$root/src/openssl/LICENSE.txt" "$WEBOS_PLATFORM/licenses/OpenSSL.txt"
cp "$root/src/curl/COPYING" "$WEBOS_PLATFORM/licenses/curl.txt"
cp "$root/src/zlib/LICENSE" "$WEBOS_PLATFORM/licenses/zlib.txt"
cp "$root/src/nghttp3/COPYING" "$WEBOS_PLATFORM/licenses/nghttp3.txt"
cp "$root/src/nghttp3/lib/sfparse/COPYING" "$WEBOS_PLATFORM/licenses/sfparse.txt"
cp "$root/src/ngtcp2/COPYING" "$WEBOS_PLATFORM/licenses/ngtcp2.txt"
printf 'webOS native libraries built\n'
