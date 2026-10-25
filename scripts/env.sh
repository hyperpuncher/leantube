#!/usr/bin/env bash
# Sourced by project scripts. Run them from the project root through just.
: "${WEBOS_SDK:=$PWD/.cache/webos/sdk}"
: "${WEBOS_ODIN:=$PWD/.cache/webos/odin/odin}"
: "${WEBOS_PLATFORM:=$PWD/.cache/webos/platform}"
: "${TV_HOST:=tv}"
app_id=$(jq -r .id app/appinfo.json)
app_main=$(jq -r .main app/appinfo.json)
app_version=$(jq -r .version app/appinfo.json)
app_dir="/media/developer/apps/usr/palm/applications/$app_id"
export app_id app_main app_version app_dir
