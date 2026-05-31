#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PROJECT="$ROOT/meshkit-ios/Samples/iOSDemo/MeshKitiOSDemo.xcodeproj"
DEVICE_SELECTOR="${DEVICE_SELECTOR:-}"
DEVICE_UDID="${DEVICE_UDID:-00008132-000910421185001C}"
CONFIGURATION="${CONFIGURATION:-Debug}"
BUILD_ROOT="${BUILD_ROOT:-$ROOT/build/ios-device-products}"
ARTIFACTS="$ROOT/artifacts/ios-device/$(date +%Y%m%d-%H%M%S)"
ALLOW_PROVISIONING_UPDATES="${ALLOW_PROVISIONING_UPDATES:-1}"
APP_TARGETS=(HermesChat MintNotes DailyMart)

mkdir -p "$ARTIFACTS"

log() { printf '\n==> %s\n' "$*"; }
fail() { printf '\nERROR: %s\n' "$*" >&2; exit 1; }

explain_build_blocker() {
  local log_file="$1"
  if grep -Eq "No Accounts|No profiles for|requires a development team|requires a provisioning profile" "$log_file"; then
    cat >&2 <<MSG

The physical iPad build reached Xcode signing/provisioning, but local Apple
Developer setup blocked installation. This is external to MeshKit runtime code.

Fix in Xcode Settings > Accounts, then download/create development profiles for
the demo bundle ids, or rerun with a valid team:
  DEVELOPMENT_TEAM=<APPLE_TEAM_ID> scripts/install_ios_device.sh

BlockedByExternalChain/DeviceSigning evidence log: $log_file
MSG
  fi
}

DEFAULT_HERMES_PRIVATE_KEY_BASE64="ciDtnehd8FlWERtZE2lzacQc3/LLIJY0CavAcv0THko="
DEFAULT_HERMES_PUBLIC_KEY_BASE64="SYRITem/8/4woLf6P3Iec58z4jBtxzEB+g+UXeS8mcU="
DEFAULT_DAILYMART_RECEIPT_PRIVATE_KEY_BASE64="LaXmm9S12JqU7R/y9sufJiShgajyWCkyFeGazh4qhb0="
DEFAULT_DAILYMART_RECEIPT_PUBLIC_KEY_BASE64="Bauj33zFJH8pAyxeCxrkn9NNjC/dRfPVXn9avxPskyg="

if [[ -z "$DEVICE_SELECTOR" ]]; then
  DEVICE_SELECTOR="$DEVICE_UDID"
fi

log "Checking Xcode and connected iOS device"
command -v xcodebuild >/dev/null || fail "xcodebuild not found"
command -v xcrun >/dev/null || fail "xcrun not found"
xcodebuild -version | tee "$ARTIFACTS/xcode-version.txt"
xcrun devicectl list devices | tee "$ARTIFACTS/devices.txt"
xcrun devicectl device info details --device "$DEVICE_SELECTOR" \
  > "$ARTIFACTS/device-details.txt" 2>&1 || true

PRECHECK_BLOCKED=0
if grep -q "developerModeStatus: disabled" "$ARTIFACTS/device-details.txt"; then
  PRECHECK_BLOCKED=1
  cat >&2 <<'MSG'

Developer Mode is disabled on the iPad.
On the iPad, enable Settings > Privacy & Security > Developer Mode, then restart/confirm when prompted.
MSG
fi
if grep -q "connected (no DDI)" "$ARTIFACTS/devices.txt"; then
  PRECHECK_BLOCKED=1
  cat >&2 <<'MSG'

The iPad is connected, but Xcode reports `connected (no DDI)`.
That means Xcode cannot start device developer services for this iPad OS right now.
Enable Developer Mode first; if it still says `no DDI`, open Xcode with the iPad attached and let it finish device preparation, or install an Xcode version/beta that supports this iPad OS.
MSG
fi

log "Checking local code signing identity"
security find-identity -v -p codesigning | tee "$ARTIFACTS/codesigning-identities.txt" || true
if grep -q "0 valid identities found" "$ARTIFACTS/codesigning-identities.txt"; then
  PRECHECK_BLOCKED=1
  cat >&2 <<'MSG'

No valid Apple Development signing identity is installed.
For physical iPad install, sign into Xcode Settings > Accounts and create/download an Apple Development certificate.
Then rerun, usually with:
  DEVELOPMENT_TEAM=<APPLE_TEAM_ID> scripts/install_ios_device.sh
MSG
fi

if [[ "$PRECHECK_BLOCKED" == "1" ]]; then
  fail "Physical iPad install precheck failed. Fix the DDI/device-support and signing blockers above, then rerun. Logs: $ARTIFACTS"
fi

if [[ -z "${MESHKIT_IOS_DEMO_PRIVATE_KEY_BASE64:-}" || -z "${MESHKIT_IOS_DEMO_PUBLIC_KEY_BASE64:-}" ]]; then
  log "Using stable sample Hermes signing keypair for direct iPad launches"
  export MESHKIT_IOS_DEMO_PRIVATE_KEY_BASE64="$DEFAULT_HERMES_PRIVATE_KEY_BASE64"
  export MESHKIT_IOS_DEMO_PUBLIC_KEY_BASE64="$DEFAULT_HERMES_PUBLIC_KEY_BASE64"
fi
if [[ -z "${MESHKIT_IOS_DAILYMART_RECEIPT_PRIVATE_KEY_BASE64:-}" || -z "${MESHKIT_IOS_DAILYMART_RECEIPT_PUBLIC_KEY_BASE64:-}" ]]; then
  log "Using stable sample DailyMart receipt keypair for direct iPad launches"
  export MESHKIT_IOS_DAILYMART_RECEIPT_PRIVATE_KEY_BASE64="$DEFAULT_DAILYMART_RECEIPT_PRIVATE_KEY_BASE64"
  export MESHKIT_IOS_DAILYMART_RECEIPT_PUBLIC_KEY_BASE64="$DEFAULT_DAILYMART_RECEIPT_PUBLIC_KEY_BASE64"
fi

DESTINATION="id=$DEVICE_SELECTOR"
COMMON_XCODE_ARGS=(
  -project "$PROJECT"
  -configuration "$CONFIGURATION"
  -destination "$DESTINATION"
)
if [[ "$ALLOW_PROVISIONING_UPDATES" == "1" ]]; then
  COMMON_XCODE_ARGS=(-allowProvisioningUpdates "${COMMON_XCODE_ARGS[@]}")
fi
if [[ -n "${DEVELOPMENT_TEAM:-}" ]]; then
  COMMON_XCODE_ARGS+=(DEVELOPMENT_TEAM="$DEVELOPMENT_TEAM" CODE_SIGN_STYLE=Automatic)
fi

log "Showing eligible destinations"
xcodebuild -project "$PROJECT" -scheme HermesChat -showdestinations | tee "$ARTIFACTS/destinations.txt"

for target in "${APP_TARGETS[@]}"; do
  target_build_dir="$BUILD_ROOT/$target"
  rm -rf "$target_build_dir"
  mkdir -p "$target_build_dir"

  log "Building $target for physical iPad"
  build_log="$ARTIFACTS/$target-build.log"
  if ! xcodebuild "${COMMON_XCODE_ARGS[@]}" -scheme "$target" CONFIGURATION_BUILD_DIR="$target_build_dir" build 2>&1 | tee "$build_log"; then
    explain_build_blocker "$build_log"
    fail "$target physical iPad build failed; inspect $build_log"
  fi

  app_path="$target_build_dir/$target.app"
  [[ -d "$app_path" ]] || fail "Built app not found for $target at $app_path"

  log "Installing $target on device $DEVICE_SELECTOR"
  xcrun devicectl device install app --device "$DEVICE_SELECTOR" "$app_path" \
    --json-output "$ARTIFACTS/$target-install.json" \
    --log-output "$ARTIFACTS/$target-install.log" \
    --timeout 120

done

for target in HermesChat DailyMart; do
  case "$target" in
    HermesChat) bundle_id="ai.meshkit.sample.hermeschat" ;;
    DailyMart) bundle_id="ai.meshkit.sample.dailymart" ;;
    *) fail "No launch bundle id configured for $target" ;;
  esac
  log "Launching $target on the iPad"
  xcrun devicectl device process launch --device "$DEVICE_SELECTOR" "$bundle_id" \
    --json-output "$ARTIFACTS/$target-launch.json" \
    --log-output "$ARTIFACTS/$target-launch.log" \
    --timeout 60 || fail "$target install succeeded but launch failed; inspect $ARTIFACTS/$target-launch.log"
done

log "Physical iPad install proof complete"
echo "$ARTIFACTS"
