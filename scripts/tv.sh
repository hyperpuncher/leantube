#!/usr/bin/env bash
# RPC arguments intentionally expand here from our local app manifest.
# shellcheck disable=SC2029
set -euo pipefail
source scripts/env.sh
payload=$(jq -nc --arg id "$app_id" '{id:$id}')
case "${1:-}" in
	run)
		: "${TV_APP_UID:?set the native app UID in .env; see docs/toolchain.md}"
		[[ "$TV_APP_UID" =~ ^[0-9]+$ ]] || { printf 'invalid TV_APP_UID\n' >&2; exit 1; }
		jq -e --arg id "$app_id" '.uri != null and .payload.option.appId == $id' build/load.json >/dev/null
		info=$(ssh "$TV_HOST" "luna-send -n 1 -w 5000 luna://com.webos.applicationManager/getAppInfo '$payload' </dev/null")
		jq -e --arg main "$app_main" '.returnValue == true and .appInfo.main == $main' <<< "$info" >/dev/null || {
			printf 'install this project package first with just install\n' >&2; exit 1;
		}
		scp -O build/load.json "$TV_HOST:$app_dir/load.json"
		ssh "$TV_HOST" "chown '$TV_APP_UID:5000' '$app_dir/load.json'; chmod 600 '$app_dir/load.json'"
		ssh "$TV_HOST" "luna-send -n 1 -w 5000 luna://com.webos.applicationManager/launch '$payload' </dev/null" |
			jq -e 'if .returnValue then . else error(.errorText) end'
		;;
	stop)
		ssh "$TV_HOST" "luna-send -n 1 -w 5000 luna://com.webos.applicationManager/closeByAppId '$payload' </dev/null"
		;;
	logs)
		ssh "$TV_HOST" 'tail -n 100 /tmp/leantube.log'
		;;
	status)
		ssh "$TV_HOST" 'luna-send -n 1 -w 5000 luna://com.webos.media/getActivePipelines "{}" </dev/null' |
			jq --arg id "$app_id" '[.[] | select(.appId == $id) | {id,mediaState,is_foreground,resource}]'
		;;
	capture)
		ssh "$TV_HOST" 'luna-send -n 1 -w 5000 luna://com.webos.applicationManager/getForegroundAppInfo "{}" </dev/null' |
			jq -e --arg id "$app_id" '.appId == $id' >/dev/null
		ssh "$TV_HOST" 'luna-send -n 1 -w 5000 luna://com.webos.service.tv.capture/executeOneShot "{\"path\":\"/tmp/leantube-capture.png\",\"method\":\"DISPLAY\",\"format\":\"PNG\",\"width\":1920,\"height\":1080}" </dev/null' |
			jq -e '.returnValue == true' >/dev/null
		mkdir -p build
		scp -O "$TV_HOST:/tmp/leantube-capture.png" build/capture.png
		;;
	*) printf 'usage: scripts/tv.sh run|stop|logs|status|capture\n' >&2; exit 1 ;;
esac
