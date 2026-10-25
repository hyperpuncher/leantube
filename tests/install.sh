#!/usr/bin/env bash
set -euo pipefail
fixture=$(mktemp -d /tmp/leantube-install.XXXXXX)
trap 'trash -- "$fixture"' EXIT
mkdir -p "$fixture"/{app,scripts,build,bin}
cp app/appinfo.json "$fixture/app/"
cp scripts/env.sh scripts/install.sh "$fixture/scripts/"
id=$(jq -r .id app/appinfo.json)
version=$(jq -r .version app/appinfo.json)
touch "$fixture/build/${id}_${version}_arm.ipk"
# Only the external SSH/SCP boundary is replaced. jq and the real installer
# script parse exactly the same stream as they do for a TV.
cat > "$fixture/bin/scp" <<'STUB'
#!/usr/bin/env bash
exit 0
STUB
cat > "$fixture/bin/ssh" <<'STUB'
#!/usr/bin/env bash
printf '{"subscribed":true,"returnValue":true}\n'
sleep 0.1
case "$INSTALL_TEST_CASE" in
	success)
		printf '{"returnValue":true,"details":{"state":"SUCCESS"}}\n'
		exec sleep 5
		;;
	rejected) printf '{"returnValue":false,"errorText":"test rejection"}\n' ;;
	acknowledgement) exit 0 ;;
esac
STUB
chmod +x "$fixture/bin/ssh" "$fixture/bin/scp"
for test_case in success rejected acknowledgement; do
	if (
		cd "$fixture"
		PATH="$fixture/bin:$PATH" INSTALL_TEST_CASE="$test_case" timeout 3 bash scripts/install.sh
	) > "$fixture/$test_case.log" 2>&1; then
		result=0
	else
		result=$?
	fi
	case "$test_case" in
		success) [[ "$result" == 0 ]] ;;
		rejected) [[ "$result" == 1 && $(< "$fixture/$test_case.log") == *"test rejection"* ]] ;;
		acknowledgement) [[ "$result" == 1 && $(< "$fixture/$test_case.log") == *"without a success response"* ]] ;;
	esac
	printf 'installer %s: passed\n' "$test_case"
done
