#!/usr/bin/env bash
set -euo pipefail
source scripts/env.sh
video="${1:-aqz-KE-bpKQ}"
if [[ "$video" != https://* ]]; then video="https://www.youtube.com/watch?v=$video"; fi
umask 077
mkdir -p build
# Keep only the request the TV needs. Never print the signed CDN URL.
yt-dlp --quiet --no-warnings --no-playlist --dump-single-json --format 18 -- "$video" |
	jq -e --arg id "$app_id" \
		'if (.url | type) == "string" then {uri: .url, type: "media", payload: {option: {appId: $id}}} else error("no stream URL") end' \
		> build/load.json
chmod 600 build/load.json
printf 'saved private stream request to build/load.json\n'
