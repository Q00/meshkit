#!/usr/bin/env bash
# Mutual wire-compat verification between the Swift and Kotlin SDKs.
#
# 1. Regenerate golden vectors from the Swift SDK and fail on drift.
# 2. Run the Kotlin core tests (Kotlin verifies Swift signatures and byte
#    forms; exports Kotlin-signed envelopes).
# 3. Swift verifies the Kotlin-signed envelopes.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
VECTORS="$REPO_ROOT/meshkit-android/vectors/wire-compat.v1.json"
KOTLIN_SIGNED="$REPO_ROOT/meshkit-android/build/kotlin-signed.v1.json"

echo "[1/3] regenerating golden vectors from the Swift SDK"
TMP_VECTORS="$(mktemp)"
swift run --package-path "$REPO_ROOT/scripts/wire_vectors_gen" wire-vectors-gen "$TMP_VECTORS" >/dev/null

python3 - "$VECTORS" "$TMP_VECTORS" <<'PY'
import json, sys
checked, regenerated = (json.load(open(path)) for path in sys.argv[1:3])
# CryptoKit Ed25519 signatures are randomized; envelopes embed them. Compare
# every deterministic field instead of raw file bytes.
def strip(vectors):
    out = {k: v for k, v in vectors.items() if k != "cases"}
    out["cases"] = [
        {k: v for k, v in case.items()
         if k not in ("requestSignatureBase64", "receiptSignatureBase64",
                      "requestEnvelopeBase64", "receiptEnvelopeBase64")}
        for case in vectors["cases"]
    ]
    return out
if strip(checked) != strip(regenerated):
    sys.exit("checked-in vectors drift from Swift SDK output; regenerate wire-compat.v1.json")
print("vectors match the Swift SDK")
PY

echo "[2/3] running Kotlin core tests (Kotlin verifies Swift, exports Kotlin-signed envelopes)"
(cd "$REPO_ROOT/meshkit-android" && gradle --console=plain :meshkit-core:test)

echo "[3/3] Swift verifying Kotlin-signed envelopes"
swift run --package-path "$REPO_ROOT/scripts/wire_vectors_gen" wire-vectors-gen cross-verify "$KOTLIN_SIGNED"

echo "wire-compat OK in both directions"
