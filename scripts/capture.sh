#!/usr/bin/env bash
set -euo pipefail
source scripts/env.sh
payload='{"path":"/tmp/leantube-capture.png","method":"DISPLAY","format":"PNG"}'
if [[ -n "${1:-}${2:-}" ]]; then
	payload=$(jq -c --argjson width "$1" --argjson height "$2" '. + {width:$width,height:$height}' <<< "$payload")
fi
bash scripts/luna.sh com.webos.service.tv.capture/executeOneShot "$payload" |
	jq -e 'if .returnValue then true else error(.errorText // "capture failed") end' >/dev/null
mkdir -p build
ares-pull /tmp/leantube-capture.png build
mv build/leantube-capture.png build/capture.png
