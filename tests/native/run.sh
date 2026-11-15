#!/usr/bin/env bash
set -euo pipefail
mkdir -p build/native-display
# Compile the actual display code on the host. Replace only the TV C APIs.
# Drop the webOS build tag, so the host compiles the copy.
grep -v '^#+build' src/display_webos.odin >build/native-display/display.odin
cp tests/native/display_test.odin build/native-display/display_test.odin
cp tests/native/window_stub.odin build/native-display/window_stub.odin
cc -shared -fPIC tests/native/fixture.c -std=c11 -Wall -Wextra -Werror -o build/native-display/libAcbAPI.so.1
ln -sf libAcbAPI.so.1 build/native-display/libAcbAPI.so
LD_LIBRARY_PATH="$PWD/build/native-display" odin test build/native-display -vet \
	-extra-linker-flags:"-L$PWD/build/native-display -lAcbAPI -Wl,-rpath,$PWD/build/native-display" \
	-define:ODIN_TEST_THREADS=1 -define:ODIN_TEST_FANCY=false \
	-out:build/native-display/display-test
