#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DESTINATION="${1:-platform=iOS Simulator,name=iPhone 16,OS=18.6}"
ARTIFACTS="${ROOT}/artifacts/mobile-e2e/ios-$(date +%Y%m%d-%H%M%S)"
mkdir -p "$ARTIFACTS"
make_keypair() {
  swift -e 'import CryptoKit; import Foundation; let k = Curve25519.Signing.PrivateKey(); print(k.rawRepresentation.base64EncodedString()); print(k.publicKey.rawRepresentation.base64EncodedString())'
}
if [[ -z "${MESHKIT_IOS_DEMO_PRIVATE_KEY_BASE64:-}" || -z "${MESHKIT_IOS_DEMO_PUBLIC_KEY_BASE64:-}" ]]; then
  mapfile -t HERMES_KEYS < <(make_keypair)
  export MESHKIT_IOS_DEMO_PRIVATE_KEY_BASE64="${HERMES_KEYS[0]}"
  export MESHKIT_IOS_DEMO_PUBLIC_KEY_BASE64="${HERMES_KEYS[1]}"
fi
if [[ -z "${MESHKIT_IOS_DAILYMART_RECEIPT_PRIVATE_KEY_BASE64:-}" || -z "${MESHKIT_IOS_DAILYMART_RECEIPT_PUBLIC_KEY_BASE64:-}" ]]; then
  mapfile -t DAILYMART_KEYS < <(make_keypair)
  export MESHKIT_IOS_DAILYMART_RECEIPT_PRIVATE_KEY_BASE64="${DAILYMART_KEYS[0]}"
  export MESHKIT_IOS_DAILYMART_RECEIPT_PUBLIC_KEY_BASE64="${DAILYMART_KEYS[1]}"
fi
xcrun simctl bootstatus booted -b || true
xcrun simctl io booted recordVideo "$ARTIFACTS/ios-e2e.mp4" &
REC_PID=$!
finish() { kill -INT "$REC_PID" 2>/dev/null || true; wait "$REC_PID" 2>/dev/null || true; }
trap finish EXIT
# Historical smoke selector retained for release-triage visibility:
# -only-testing:MeshKitiOSDemoUITests/MeshKitiOSDemoUITests/testHermesChatToMintNotesToCallback
# Release proof records the high-risk production path: first foreground approval,
# second saved-consent background MCP call, and final DailyMart paid-order proof.
xcodebuild test \
  -project "$ROOT/meshkit-ios/Samples/iOSDemo/MeshKitiOSDemo.xcodeproj" \
  -scheme MeshKitiOSDemoUITests \
  -destination "$DESTINATION" \
  -resultBundlePath "$ARTIFACTS/MeshKitiOSDemoUITests.xcresult" \
  -only-testing:MeshKitiOSDemoUITests/MeshKitiOSDemoUITests/testDailyMartSecondPurchaseUsesSavedConsentBackgroundMCPCall
file "$ARTIFACTS/ios-e2e.mp4"
echo "iOS mobile E2E runtime proof passed: $ARTIFACTS"
