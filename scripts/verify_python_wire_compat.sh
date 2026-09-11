#!/usr/bin/env bash
# Mutual wire-compat verification between the Swift and Python SDKs.
# 1. Python verifies Swift golden vectors and exports Python-signed envelopes.
# 2. Swift verifies the Python-signed envelopes.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PY_SIGNED="$REPO_ROOT/meshkit-py/build/python-signed.v1.json"

echo "[1/2] running Python tests (Python verifies Swift, exports Python-signed envelopes)"
(cd "$REPO_ROOT/meshkit-py" && MESHKIT_CROSSSIGN_OUT="$PY_SIGNED" python3 -m pytest tests/ -q)

echo "[2/2] Swift verifying Python-signed envelopes"
swift run --package-path "$REPO_ROOT/scripts/wire_vectors_gen" wire-vectors-gen cross-verify "$PY_SIGNED"

echo "python wire-compat OK in both directions"
