#!/usr/bin/env bash
set -euo pipefail
mkdir -p build/player-test
# Test the actual Odin player. Replace only the native decoder boundary.
bun -e 'for (const [file, name] of [["src/player_linux_arm32.odin", "player"], ["src/seeking.odin", "seeking"]]) await Bun.write("build/player-test/" + name + ".odin", (await Bun.file(file).text()).replaceAll("\"./", "\"../../src/"));'
cp tests/player/player_test.odin build/player-test/player_test.odin
odin test build/player-test -vet -out:build/player-test/check \
	-define:PLAYBACK_BENCH=false -define:ODIN_TEST_THREADS=1 -define:ODIN_TEST_FANCY=false
