#!/usr/bin/env bash
set -euo pipefail
llvm=${LLVM_CONFIG:-llvm-config}
for tool in curl tar patch clang++ jq sha256sum "$llvm"; do
	command -v "$tool" >/dev/null || { printf 'missing setup tool: %s\n' "$tool" >&2; exit 1; }
done
source scripts/env.sh
root=$WEBOS_TOOLCHAIN
host=$(uname -m)
case "$host" in x86_64 | aarch64) ;; *) printf 'unsupported build host: %s\n' "$host" >&2; exit 1 ;; esac
mkdir -p "$root/downloads"
while read -r destination checksum url; do
	[[ -n "$destination" && "$destination" != \#* ]] || continue
	archive="$root/downloads/${destination//\//_}.tar"
	if [[ "$destination" == sdk-* ]]; then
		[[ "$destination" == "sdk-$host" ]] || continue
		destination=sdk
	fi
	if [[ ! -f "$archive" ]]; then
		curl -fL --retry 3 "$url" -o "$archive.part"
		printf '%s  %s\n' "$checksum" "$archive.part" | sha256sum -c -
		mv "$archive.part" "$archive"
	else
		printf '%s  %s\n' "$checksum" "$archive" | sha256sum -c -
	fi
	mkdir -p "$root/$destination"
	tar -xf "$archive" --strip-components=1 -C "$root/$destination"
done < scripts/toolchain.sources
"$WEBOS_SDK/relocate-sdk.sh"
for spec in 'odin odin-arm32-softfp.patch' 'src/SDL sdl3-b9.patch'; do
	read -r destination patch <<< "$spec"
	patch -d "$root/$destination" -p1 --forward --batch < "patches/$patch"
done
(cd "$root/odin"; LLVM_CONFIG="$llvm" CPPFLAGS='-DGIT_SHA="1bc18e5"' ./build_odin.sh release)
printf 'webOS SDK and patched Odin compiler built\n'
