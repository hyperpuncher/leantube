#!/usr/bin/env bash
set -euo pipefail
mkdir -p build/player-test
# Test the actual Odin player. Replace only the native decoder boundary.
bun -e 'const source = await Bun.file("src/player_linux_arm32.odin").text(); await Bun.write("build/player-test/player.odin", source.replaceAll("\"./model\"", "\"../../src/model\"").replaceAll("\"./playback\"", "\"../../src/playback\"").replaceAll("\"./youtube\"", "\"../../src/youtube\""));'
cp tests/player/player_test.odin build/player-test/player_test.odin
odin test build/player-test -vet -out:build/player-test/check \
	-define:PLAYBACK_BENCH=false -define:ODIN_TEST_THREADS=1 -define:ODIN_TEST_FANCY=false
