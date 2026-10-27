#!/usr/bin/env bash
set -euo pipefail

script_directory="$(cd "$(dirname "$0")" && pwd)"
test_directory="$(mktemp -d)"
trap 'rm -rf "$test_directory"' EXIT

cat > "$test_directory/xcrun" <<'SCRIPT'
#!/usr/bin/env bash
printf '%s\n' "${TEST_ACTIVE_SDK:?}"
SCRIPT
chmod +x "$test_directory/xcrun"

for supported_version in 26.4 26.5 26.5.0 27.0 27.0.0 27.0.1 27.1 27.1.0; do
  TEST_ACTIVE_SDK="$supported_version" \
    XCRUN_COMMAND="$test_directory/xcrun" \
    "$script_directory/validate-active-app-store-sdk.sh"
done

for unsupported_version in 27.1.1 27.2 28.0; do
  if TEST_ACTIVE_SDK="$unsupported_version" \
    XCRUN_COMMAND="$test_directory/xcrun" \
    "$script_directory/validate-active-app-store-sdk.sh"; then
    echo "Expected SDK $unsupported_version validation to fail" >&2
    exit 1
  fi
done

echo "Active App Store SDK validation tests passed"
