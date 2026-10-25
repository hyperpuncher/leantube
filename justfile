set shell := ["bash", "-euo", "pipefail", "-c"]
set dotenv-load

# Show the available project tasks. No TV command runs by default.
default:
	@just --list

# Type-check with the installed host compiler.
check:
	odin check src -vet
	odin check tests/layout -vet
	bash -n scripts/*.sh tests/install.sh
	shellcheck -x scripts/*.sh tests/install.sh
	bun fmt --check scripts/catalog.ts tests/catalog.test.ts

# Test metadata and installer completion handling without a TV.
test: test-layout
	odin test src/model -define:ODIN_TEST_THREADS=1 -define:ODIN_TEST_FANCY=false
	odin test src/input.odin -file -define:ODIN_TEST_THREADS=1 -define:ODIN_TEST_FANCY=false
	bun test tests/catalog.test.ts
	bash tests/install.sh

# Check the real C/Odin Clay boundary without opening a window.
test-layout:
	mkdir -p build/host-layout
	cc -std=c11 -O2 -Ivendor/clay -c src/native/clay.c -o build/host-layout/clay.o
	ar rcs build/host-layout/libclay.a build/host-layout/clay.o
	odin run tests/layout -out:build/host-layout/layout-check -extra-linker-flags:"-Lbuild/host-layout"

fmt:
	odinfmt src -w
	odinfmt tests -w
	clang-format -i src/native/bridge.c src/native/clay.c
	bun fmt scripts/catalog.ts tests/catalog.test.ts

# Build the B9 ARM32 executable and stage its private libraries.
build:
	bash scripts/build.sh

# Run the headless ABI/layout regression on the TV, without opening an app.
test-tv-layout: build
	bash scripts/test-tv-layout.sh

# Packaging tools are local and ignored, not global dependencies.
tools:
	mkdir -p .cache/tools
	bun add --cwd .cache/tools --ignore-scripts --exact @webos-tools/cli@3.2.6

package: build tools
	.cache/tools/node_modules/.bin/ares-package build/app -o build

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

capture:
	bash scripts/tv.sh capture

clean:
	if [[ -d build ]]; then trash -- build; fi
