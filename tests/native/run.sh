#!/usr/bin/env bash
set -euo pipefail
mkdir -p build/native-display
# Compile the actual display code on the host. Replace only the TV C API.
cp src/display_linux_arm32.odin build/native-display/display.odin
cp tests/native/display_test.odin build/native-display/display_test.odin
cc -c tests/native/fixture.c -std=c11 -Wall -Wextra -Werror -o build/native-display/fixture.o
ar rcs build/native-display/libAcbAPI.a build/native-display/fixture.o
odin test build/native-display -vet -extra-linker-flags:"-L$PWD/build/native-display" \
	-define:ODIN_TEST_THREADS=1 -define:ODIN_TEST_FANCY=false \
	-out:build/native-display/display-test
