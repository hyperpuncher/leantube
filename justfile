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

# Test metadata and installer completion handling without a TV.
test: test-layout
	odin test src/metadata.odin -file -define:ODIN_TEST_THREADS=1 -define:ODIN_TEST_FANCY=false
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

# Resolve a fresh public YouTube stream. Never echo its signed URL.
resolve video="aqz-KE-bpKQ":
	@bash scripts/resolve.sh {{quote(video)}}

# These commands target the separate prototype app, not either YouTube app.
install: package
	bash scripts/install.sh

run video="aqz-KE-bpKQ": (resolve video)
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
