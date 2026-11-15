#!/usr/bin/env bash
set -euo pipefail
source scripts/env.sh
remote=/tmp/leantube-capture.png
payload=$(jq -nc --arg path "$remote" --argjson width "$1" --argjson height "$2" \
	'{path:$path,method:"DISPLAY",format:"PNG",width:$width,height:$height}')
# Remove the old file so a failed capture cannot return it again.
ares-shell -r "rm -f $remote"
bash scripts/luna.sh com.webos.service.tv.capture/executeOneShot "$payload" |
	jq -e 'if .returnValue then true else error(.errorText // "capture failed") end' >/dev/null
mkdir -p build
previous=$(sha256sum build/capture.png 2>/dev/null | cut -d' ' -f1 || true)
ares-pull "$remote" build >/dev/null
mv build/leantube-capture.png build/capture.png
# A static screen gives the same bytes. After an app restart, the TV once
# returned the old app frame, so say when nothing changed.
if [[ "$(sha256sum build/capture.png | cut -d' ' -f1)" == "$previous" ]]; then
	printf 'warning: capture is identical to the previous one\n' >&2
fi
printf 'build/capture.png\n'
