#!/usr/bin/env bash
# RPC arguments intentionally expand here from our local app manifest.
# shellcheck disable=SC2029
set -euo pipefail
source scripts/env.sh
payload=$(jq -nc --arg id "$app_id" '{id:$id}')
case "${1:-}" in
	run)
		info=$(ssh "$TV_HOST" "luna-send -n 1 -w 5000 luna://com.webos.applicationManager/getAppInfo '$payload' </dev/null")
		jq -e --arg main "$app_main" --arg version "$app_version" '.returnValue == true and .appInfo.main == $main and .appInfo.version == $version' <<< "$info" >/dev/null || {
			printf 'install this project package first with just install\n' >&2; exit 1;
		}
		bash scripts/tv.sh stop
		ssh "$TV_HOST" "luna-send -n 1 -w 5000 luna://com.webos.applicationManager/launch '$payload' </dev/null" |
			jq -e 'if .returnValue then . else error(.errorText) end'
		;;
	stop)
		ssh "$TV_HOST" "luna-send -n 1 -w 5000 luna://com.webos.applicationManager/closeByAppId '$payload' </dev/null" |
			jq -e '.returnValue == true or .errorText == "native app is not running"' >/dev/null
		ssh "$TV_HOST" 'if [ -f /tmp/leantube.pid ]; then read -r pid < /tmp/leantube.pid; for i in 1 2 3 4 5; do if ! kill -0 "$pid" 2>/dev/null; then exit 0; fi; sleep 1; done; printf "prototype process has not stopped\n" >&2; exit 1; fi'
		ssh "$TV_HOST" 'luna-send -n 1 -w 5000 luna://com.webos.media/getActivePipelines "{}" </dev/null' |
			jq -e --arg id "$app_id" '[.[] | select(.appId == $id)] | length == 0' >/dev/null
		printf 'leantube stopped; no media pipeline\n'
		;;
	logs)
		ssh "$TV_HOST" 'tail -n 100 /tmp/leantube.log'
		;;
	status)
		ssh "$TV_HOST" 'luna-send -n 1 -w 5000 luna://com.webos.media/getActivePipelines "{}" </dev/null' |
			jq --arg id "$app_id" '[.[] | select(.appId == $id) | {id,mediaState,is_foreground,resource}]'
		;;
	capture)
		width=${2:-1920}
		height=${3:-1080}
		[[ "$width" =~ ^[1-9][0-9]*$ && "$height" =~ ^[1-9][0-9]*$ ]] || {
			printf 'capture requires positive width and height\n' >&2; exit 1;
		}
		capture_payload=$(jq -nc --argjson width "$width" --argjson height "$height" \
			'{path:"/tmp/leantube-capture.png",method:"DISPLAY",format:"PNG",width:$width,height:$height}')
		ssh "$TV_HOST" 'luna-send -n 1 -w 5000 luna://com.webos.applicationManager/getForegroundAppInfo "{}" </dev/null' |
			jq -e --arg id "$app_id" '.appId == $id' >/dev/null
		ssh "$TV_HOST" "luna-send -n 1 -w 5000 luna://com.webos.service.tv.capture/executeOneShot '$capture_payload' </dev/null" |
			jq -e 'if .returnValue then true else error(.errorText // "capture failed") end' >/dev/null
		mkdir -p build
		scp -O "$TV_HOST:/tmp/leantube-capture.png" build/capture.png
		;;
	*) printf 'usage: scripts/tv.sh run|stop|logs|status|capture [WIDTH HEIGHT]\n' >&2; exit 1 ;;
esac
