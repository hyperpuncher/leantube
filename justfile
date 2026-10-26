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
	bash -n scripts/*.sh tests/install.sh
	shellcheck -x scripts/*.sh tests/install.sh
	bun fmt --check package.json tsconfig.json scripts/catalog.ts scripts/ui.ts tests/catalog.test.ts tests/http/run.ts
	bun check

# Test metadata and installer completion handling without a TV.
test: test-layout test-http test-ui
	odin test src/model -define:ODIN_TEST_THREADS=1 -define:ODIN_TEST_FANCY=false
	odin test src/input.odin -file -define:ODIN_TEST_THREADS=1 -define:ODIN_TEST_FANCY=false
	bun test tests/catalog.test.ts
	bash tests/install.sh

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
	clang-format -i src/native/bridge.c src/native/clay.c
	bun fmt package.json tsconfig.json scripts/catalog.ts scripts/ui.ts tests/catalog.test.ts tests/http/run.ts

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

# Prepare one page of results and private requests without touching the TV.
prepare query="Blender open movies":
	@bun scripts/catalog.ts {{quote(query)}}

# Prepare and open a grid. The host resolves all streams before launch.
browse query="Blender open movies": (prepare query) run

# These commands target the separate prototype app, not either YouTube app.
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

# Request an explicit capture size; no fixed 1080p limit.
capture width height:
	bash scripts/tv.sh capture {{quote(width)}} {{quote(height)}}

clean:
	if [[ -d build ]]; then trash -- build; fi
