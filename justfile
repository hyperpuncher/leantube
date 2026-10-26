set shell := ["bash", "-euo", "pipefail", "-c"]
set dotenv-load

# Show the available project tasks. No TV command runs by default.
default:
	@just --list

# Type-check the local preview, UI tests, and shared code.
check:
	odin check src -vet
	odin check src -vet -define:UI_TEST=true
	odin check tests/layout -vet
	odin check tests/http -vet
	odin check tests/youtube -vet
	odin check tests/sponsorblock -vet
	bash -n scripts/*.sh tests/install.sh tests/capture.sh
	shellcheck -x scripts/*.sh tests/install.sh tests/capture.sh
	bun fmt --check package.json tsconfig.json scripts/ui.ts tests/http/run.ts
	bun check

# Test metadata and installer completion handling without a TV.
test: test-layout test-http test-ui
	odin test src/model -define:ODIN_TEST_THREADS=1 -define:ODIN_TEST_FANCY=false
	odin test src/youtube -define:ODIN_TEST_THREADS=1 -define:ODIN_TEST_FANCY=false
	odin test src/sponsorblock -define:ODIN_TEST_THREADS=1 -define:ODIN_TEST_FANCY=false
	odin test src -define:ODIN_TEST_THREADS=1 -define:ODIN_TEST_FANCY=false
	bash tests/install.sh
	bash tests/capture.sh

# Test layout with the upstream host library, without opening a window.
test-layout:
	mkdir -p build/host-layout
	odin run tests/layout -out:build/host-layout/layout-check

# Check TLS safety and request recovery against a real local HTTPS server.
test-http:
	bun tests/http/run.ts

# Render the real UI offscreen and save local regression screenshots.
test-ui:
	bun scripts/ui.ts

# Open a local Wayland UI preview. No TV commands or media playback.
dev *args:
	@bun scripts/ui.ts --dev {{args}}

# Check native YouTube and SponsorBlock HTTPS on the B9 without opening an app.
test-tv-http:
	bash scripts/test-tv-http.sh

fmt:
	odinfmt src -w
	odinfmt tests -w
	clang-format -i src/native/bridge.c src/native/clay.c src/native/keyboard.c src/native/keyboard.h
	bun fmt package.json tsconfig.json scripts/ui.ts tests/http/run.ts

# Explicit TV library setup. Downloads source, but does not contact the TV.
setup-tv-images:
	bash scripts/setup-tv-images.sh

# Build the B9 ARM32 executable with the cached toolchain and libraries.
build:
	bash scripts/build.sh

# Run the headless ABI/layout regression on the TV, without opening an app.
test-tv-layout: build
	bash scripts/test-tv-layout.sh

package: build
	bun run ares-package build/app -o build

# Check live search, cover download, resolution, and CDN access locally.
test-youtube:
	odin run tests/youtube -out:build/youtube-check

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
