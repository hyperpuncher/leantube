#!/usr/bin/env bash
set -euo pipefail
mkdir -p build/native-starfish
cxx=${CXX:-c++}
flags=(-std=c++11 -Wall -Wextra -Werror -Wno-unknown-pragmas -g '-fsanitize=address,undefined' -fno-omit-frame-pointer)
for abi in 0 1; do
	"$cxx" "${flags[@]}" -fPIC -Itests/native -D_GLIBCXX_USE_CXX11_ABI="$abi" \
		-c vendor/starfish/string_abi.cpp -o "build/native-starfish/string-$abi.o"
done
for variant in legacy modern legacy-no-limits modern-no-limits legacy-reject modern-reject; do
	abi=0
	extra=()
	if [[ $variant == modern* ]]; then abi=1; fi
	if [[ $variant == *-no-limits ]]; then extra=(-DNO_LIMITS); fi
	if [[ $variant == modern-no-limits ]]; then extra+=(-DMODERN_NO_LIMITS); fi
	if [[ $variant == *-reject ]]; then extra=(-DREJECT_LIMITS); fi
	"$cxx" "${flags[@]}" -shared -fPIC -Itests/native -D_GLIBCXX_USE_CXX11_ABI="$abi" \
		"${extra[@]}" tests/native/starfish_fixture.cpp -o "build/native-starfish/lib$variant.so"
	"$cxx" "${flags[@]}" -Itests/native "${extra[@]}" vendor/starfish/StarfishMediaAPIs_C.cpp \
		build/native-starfish/string-0.o build/native-starfish/string-1.o \
		tests/native/starfish_test.cpp -Lbuild/native-starfish "-l$variant" -ldl \
		-Wl,-rpath,"$PWD/build/native-starfish" -o "build/native-starfish/$variant-test"
	"build/native-starfish/$variant-test"
	printf 'Starfish %s: passed (ASan/UBSan)\n' "$variant"
done
