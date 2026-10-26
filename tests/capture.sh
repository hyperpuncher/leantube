#!/usr/bin/env bash
set -euo pipefail
fixture=$(mktemp -d /tmp/leantube-capture-test.XXXXXX)
trap 'trash -- "$fixture"' EXIT
mkdir -p "$fixture"/{scripts,app,bin}
cp scripts/{env.sh,tv.sh} "$fixture/scripts/"
cp app/appinfo.json "$fixture/app/"
export CAPTURE_CALLS="$fixture/calls"
cat > "$fixture/bin/ssh" <<'MOCK'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$CAPTURE_CALLS"
case "$*" in
	*getForegroundAppInfo*) printf '{"appId":"org.hyperpuncher.leantube"}\n' ;;
	*executeOneShot*)
		if [[ "${CAPTURE_FAIL:-}" == 1 ]]; then
			printf '{"returnValue":false,"errorText":"Specified size is out of range"}\n'
		else
			printf '{"returnValue":true}\n'
		fi ;;
esac
MOCK
cat > "$fixture/bin/scp" <<'MOCK'
#!/usr/bin/env bash
printf 'capture fixture' > "${!#}"
MOCK
chmod +x "$fixture/bin/ssh" "$fixture/bin/scp"
export PATH="$fixture/bin:$PATH" TV_HOST=capture-test
(
	cd "$fixture"
	bash scripts/tv.sh capture
	rg -q '"width":1920,"height":1080' "$CAPTURE_CALLS"
	bash scripts/tv.sh capture 2560 1440
	rg -q '"width":2560,"height":1440' "$CAPTURE_CALLS"
	: > "$CAPTURE_CALLS"
	if bash scripts/tv.sh capture 0 1080 2>/dev/null; then exit 1; fi
	[[ ! -s "$CAPTURE_CALLS" ]]
	if CAPTURE_FAIL=1 bash scripts/tv.sh capture 3840 2160 2>error; then exit 1; fi
	rg -q 'Specified size is out of range' error
)
printf 'capture defaults, overrides, validation, and service errors: passed\n'
