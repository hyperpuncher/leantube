#!/usr/bin/env bash
set -euo pipefail
mkdir -p build/native-display
# Compile the actual display code on the host. Replace only the TV C APIs.
cp src/display_linux_arm32.odin build/native-display/display.odin
cp tests/native/display_test.odin build/native-display/display_test.odin
cp tests/native/window_stub.odin build/native-display/window_stub.odin
cc -shared -fPIC tests/native/fixture.c -std=c11 -Wall -Wextra -Werror -o build/native-display/libAcbAPI.so.1
ln -sf libAcbAPI.so.1 build/native-display/libAcbAPI.so
cc -shared -fPIC tests/native/bridge_stub.c -std=c11 -Wall -Wextra -Werror -o build/native-display/libtv_bridge.so
LD_LIBRARY_PATH="$PWD/build/native-display" odin test build/native-display -vet \
	-extra-linker-flags:"-L$PWD/build/native-display -ltv_bridge -lAcbAPI -Wl,-rpath,$PWD/build/native-display" \
	-define:ODIN_TEST_THREADS=1 -define:ODIN_TEST_FANCY=false \
	-out:build/native-display/display-test
