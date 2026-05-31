#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TMPDIR="$(mktemp -d)"
cleanup() {
  rm -rf "$TMPDIR"
}
trap cleanup EXIT

BIN="$TMPDIR/bin"
mkdir -p "$BIN"

cat > "$BIN/xcodebuild" <<'SH'
#!/usr/bin/env bash
if [[ "$*" == *"-version"* ]]; then
  echo "Xcode 16.0"
  exit 0
fi
if [[ "$*" == *"-showdestinations"* ]]; then
  echo "eligible destination"
  exit 0
fi
build_dir=""
scheme="App"
previous=""
for arg in "$@"; do
  case "$arg" in
    CONFIGURATION_BUILD_DIR=*) build_dir="${arg#CONFIGURATION_BUILD_DIR=}" ;;
  esac
  if [[ "$previous" == "-scheme" ]]; then
    scheme="$arg"
  fi
  previous="$arg"
done
if [[ -n "$build_dir" ]]; then
  mkdir -p "$build_dir/$scheme.app"
fi
exit 0
SH

cat > "$BIN/xcrun" <<'SH'
#!/usr/bin/env bash
out=""
log=""
for ((i = 1; i <= $#; i++)); do
  arg="${!i}"
  next_index=$((i + 1))
  case "$arg" in
    --json-output) out="${!next_index}" ;;
    --log-output) log="${!next_index}" ;;
  esac
done
if [[ "$*" == *"list devices"* ]]; then
  echo "iPad connected"
  exit 0
fi
if [[ "$*" == *"device info details"* ]]; then
  echo "developerModeStatus: enabled"
  exit 0
fi
if [[ -n "$out" ]]; then
  mkdir -p "$(dirname "$out")"
  printf '{"ok":true}\n' > "$out"
fi
if [[ -n "$log" ]]; then
  mkdir -p "$(dirname "$log")"
  printf 'ok\n' > "$log"
fi
exit 0
SH

cat > "$BIN/security" <<'SH'
#!/usr/bin/env bash
echo '  1) ABC "Apple Development: MeshKit Test"'
echo '     1 valid identities found'
SH

chmod +x "$BIN/xcodebuild" "$BIN/xcrun" "$BIN/security"

OUTPUT="$TMPDIR/install-output.txt"
PATH="$BIN:$PATH" \
DEVICE_SELECTOR="meshkit-fake-ipad" \
BUILD_ROOT="$TMPDIR/build" \
MESHKIT_IOS_BRIDGE_HOST="192.0.2.10" \
MESHKIT_MAROO_PRIVATE_KEY="should-not-reach-ios-launch" \
MESHKIT_MAROO_OKRW_TRANSFER_BRIDGE_URL="http://127.0.0.1:8788/transfer" \
MESHKIT_MAROO_OKRW_TRANSFER_AUTHORIZATION="Bearer should-be-redacted" \
"$ROOT/scripts/install_ios_device.sh" > "$OUTPUT"

ARTIFACT_DIR="$(tail -n 1 "$OUTPUT")"
LAUNCH_ENV="$ARTIFACT_DIR/DailyMart-launch-environment.json"
[[ -f "$LAUNCH_ENV" ]] || {
  echo "DailyMart launch environment artifact missing: $LAUNCH_ENV" >&2
  exit 2
}

python3 - "$LAUNCH_ENV" <<'PY'
import json
import sys
from pathlib import Path

path = Path(sys.argv[1])
payload = json.loads(path.read_text())
assert payload["MESHKIT_MAROO_OKRW_TRANSFER_BRIDGE_URL"] == "http://192.0.2.10:8788/transfer"
assert payload["MESHKIT_MAROO_OKRW_TRANSFER_AUTHORIZATION"] == "<redacted>"
serialized = path.read_text()
assert "should-not-reach-ios-launch" not in serialized
assert "Bearer should-be-redacted" not in serialized
print("iOS device maroo launch environment verification passed")
PY
