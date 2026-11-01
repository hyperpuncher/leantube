#!/usr/bin/env bash
set -euo pipefail
source scripts/env.sh
just stop
ares-push "build/app/$app_main" "$app_dir/$app_main"
ares-shell -r "chmod 755 '$app_dir/$app_main'"
