set shell := ["bash", "-euo", "pipefail", "-c"]
set dotenv-load

# Show the available project tasks. No TV command runs by default.
default:
	@just --list

# Type-check the local preview, UI tests, and shared code.
check: host-qr
	odin check src -vet
	odin check src -vet -define:UI_TEST=true
	odin check src/playback -no-entry-point -vet
	shopt -s globstar; shellcheck -x scripts/**/*.sh tests/**/*.sh
	bun check

# Run independent suites in parallel. No TV access.
[parallel]
test: test-unit test-http test-ui test-native test-player test-reader-http

# Test the app and its imported packages in one process, then shell regressions.
test-unit: host-qr
	odin test src -all-packages -vet -out:build/unit-test -define:ODIN_TEST_THREADS=1 -define:ODIN_TEST_FANCY=false
	bash tests/install.sh
	bash tests/capture.sh

# Check TLS safety and request recovery against a real local HTTPS server.
test-http:
	bun tests/http/run.ts

# Check partial-range recovery and its retry limit against a real local server.
test-reader-http:
	bun tests/playback/http-retry.ts

# Build the shared QR encoder for local login and UI tests.
[private]
host-qr:
	mkdir -p build/host-qr
	CCACHE_DIR="$PWD/.cache/ccache" ccache cc -c vendor/qrcodegen/qrcodegen.c -std=c11 -O2 -o build/host-qr/qrcodegen.o
	ar rcs build/host-qr/qrcodegen.a build/host-qr/qrcodegen.o

# Test deferred display metadata without a TV.
test-native:
	bash tests/native/run.sh

# Test native player controls and lifecycle with only the LG boundary replaced.
test-player:
	bash tests/player/run.sh

# Test the real UI offscreen at TV sizes, without PNG export.
test-ui: host-qr
	bun scripts/ui.ts

# Run the same UI tests and save size-prefixed images in build/ui-test.
screenshots: host-qr
	bun scripts/ui.ts --screenshots

# Open a local Wayland UI preview. No TV commands or media playback.
dev *args: host-qr
	@bun scripts/ui.ts --dev {{args}}

# Check native YouTube and SponsorBlock HTTPS on the B9 without opening an app.
test-tv-http:
	bash scripts/test-tv-http.sh

fmt:
	odinfmt src -w
	odinfmt tests -w
	clang-format -i src/native/bridge.c src/native/clay.c tests/native/fixture.c
	bun fmt

# Provision the toolchain, then build native libraries. No TV access.
setup: setup-toolchain setup-libs setup-reader

# Download pinned inputs and build the patched compiler. Explicit, not a build dependency.
setup-toolchain:
	bash scripts/setup-toolchain.sh

# Build native libraries with upstream Meson, CMake, and Ninja tasks.
setup-libs:
	bash scripts/setup-libs.sh

# Build pinned FFmpeg inputs for native playback and diagnostics.
setup-reader:
	bash scripts/setup-reader.sh

# Build the same reader against host libraries to isolate device/library differences.
bench-host:
	mkdir -p build/playback-bench
	odin build tests/playback/host -o:speed -out:build/playback-bench/reader-host

# Build the app with explicit playback test entry points.
bench-build:
	bash scripts/build.sh bench

# Install benchmark code, not media fixtures or request files.
bench-install: bench-build
	bun run ares-package build/app -o build
	bash scripts/install.sh
	ssh "${TV_HOST:-tv}" 'node -e '\''require("fs").unlinkSync("/tmp/leantube.ipk")'\'''

# Serve a remux-only fixture from this computer, not from TV storage.
bench-fixture player_json:
	exec bun tests/playback/fixture.ts {{quote(player_json)}}

# Compare readers with a paced consumer. This is not a displayed-video test.
bench-reader player_json output mode="ffmpeg" seconds="90" start="0" seek_after="-1" seek_to="0":
	bun tests/playback/reader.ts {{quote(player_json)}} {{quote(output)}} {{quote(mode)}} {{quote(seconds)}} {{quote(start)}} {{quote(seek_after)}} {{quote(seek_to)}}

# Feed the LG decoder through the small C interface. Requires a free, active TV.
bench-decoder player_json output mode="curl-h3" seconds="60" start="0" seek_after="-1" seek_to="0":
	bun tests/playback/reader.ts --decode {{quote(player_json)}} {{quote(output)}} {{quote(mode)}} {{quote(seconds)}} {{quote(start)}} {{quote(seek_after)}} {{quote(seek_to)}}

# Run the same input selection and queue checks on the host, without TV access.
bench-reader-host player_json output mode="ffmpeg" seconds="90" start="0" seek_after="-1" seek_to="0": bench-host
	bun tests/playback/reader.ts --host {{quote(player_json)}} {{quote(output)}} {{quote(mode)}} {{quote(seconds)}} {{quote(start)}} {{quote(seek_after)}} {{quote(seek_to)}}

# Read bounded ranges without FFmpeg, audio, playback pacing, or media files.
bench-transport player_json output mode="curl-h3" mib="64" byte_offset="0":
	bun tests/playback/reader.ts --transport {{quote(player_json)}} {{quote(output)}} {{quote(mode)}} {{quote(mib)}} {{quote(byte_offset)}}

bench-transport-host player_json output mode="curl-h3" mib="64" byte_offset="0": bench-host
	bun tests/playback/reader.ts --host --transport {{quote(player_json)}} {{quote(output)}} {{quote(mode)}} {{quote(mib)}} {{quote(byte_offset)}}

# Build the webOS ARM32 app for development, with debug information and no optimization.
build:
	bash scripts/build.sh dev

# Build the optimized webOS ARM32 app for release.
build-release:
	bash scripts/build.sh release

# Run the headless ABI/layout regression on the TV, without opening an app.
test-tv-layout:
	bash scripts/test-tv-layout.sh

package: build-release
	bun run ares-package build/app -o build

# Check live search, cover download, resolution, and CDN access locally.
test-youtube:
	odin run tests/youtube -out:build/youtube-check

# Save private playback inputs on the host. No TV access.
bench-resolve id_file output_file:
	odin run tests/playback/resolve -out:build/playback-resolve -- {{quote(id_file)}} {{quote(output_file)}}

# Build a host reference or compare a captured picture. No TV access.
bench-reference *args:
	bun tests/playback/reference.ts {{args}}

# Check real Linus Tech Tips sponsor segments locally, without playback.
test-sponsorblock:
	odin run tests/sponsorblock -out:build/sponsorblock-check

# These commands target the separate LeanTube app, not either YouTube app.
install: package
	bash scripts/install.sh

run:
	bash scripts/tv.sh run

stop:
	bash scripts/tv.sh stop

logs:
	bash scripts/tv.sh logs

status:
	bash scripts/tv.sh status

# Use the tested B9 capture surface size; allow explicit diagnostic overrides.
capture width="1920" height="1080":
	bash scripts/tv.sh capture {{quote(width)}} {{quote(height)}}

clean:
	if [[ -d build ]]; then trash -- build; fi
