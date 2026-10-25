#!/usr/bin/env bash
set -euo pipefail
source scripts/env.sh
package="build/${app_id}_${app_version}_arm.ipk"
[[ -f "$package" ]] || { printf 'package not found: %s\n' "$package" >&2; exit 1; }
scp -O "$package" "$TV_HOST:/tmp/leantube.ipk"
payload=$(jq -nc --arg id "$app_id" '{id:$id,ipkUrl:"/tmp/leantube.ipk",subscribe:true}')
# Installation is asynchronous. Wait for SUCCESS, not just subscribed=true.
coproc INSTALL {
	exec ssh "$TV_HOST" "luna-send -i -w 60000 luna://com.webos.appInstallService/dev/install '$payload' </dev/null"
}
pid=$INSTALL_PID
fd=${INSTALL[0]}
trap 'kill "$pid" 2>/dev/null || true' EXIT
while IFS= read -r -u "$fd" reply; do
	printf '%s\n' "$reply" >> build/install.log
	if jq -e '.returnValue == false' <<< "$reply" >/dev/null; then
		printf '%s\n' "$reply" >&2
		exit 1
	fi
	state=$(jq -r '.details.state // empty' <<< "$reply")
	if [[ "$state" == *FAILED* ]]; then printf '%s\n' "$reply" >&2; exit 1; fi
	if [[ "$state" == SUCCESS* || "$state" == installed* ]]; then
		printf 'installed %s %s\n' "$app_id" "$app_version"
		exit 0
	fi
done
printf 'installer ended without a success response; see build/install.log\n' >&2
exit 1
