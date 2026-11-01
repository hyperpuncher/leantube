#!/usr/bin/env bash
set -euo pipefail
# One-shot service calls through the configured SDK device.
printf -v command 'luna-send -n 1 -w 5000 %q %q' "luna://${1:?service/method required}" "${2:-'{}'}"
exec ares-shell -r "$command </dev/null"
