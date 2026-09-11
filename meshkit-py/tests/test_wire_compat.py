"""Golden-vector wire compatibility against the Swift SDK output.

Canonical strings, hashes, and signing inputs must match byte for byte;
signatures are proven by mutual verification (CryptoKit signatures are
randomized, python-cryptography is RFC 8032 deterministic).
"""

import base64
import json
import os
from datetime import datetime
from pathlib import Path

import pytest

from meshkit import canonical, ed25519
from meshkit.receipt import (
    MeshReceipt,
    MeshReceiptSigner,
    MeshReceiptTrust,
    canonical_result,
    verify_receipt,
)
from meshkit.request import MeshRequest
from meshkit.trust import MeshSenderTrust, verify_signature

VECTORS_PATH = Path(
    os.environ.get(
        "MESHKIT_VECTORS",
        Path(__file__).resolve().parents[2] / "meshkit-android" / "vectors" / "wire-compat.v1.json",
    )
)


@pytest.fixture(scope="module")
def vectors():
    return json.loads(VECTORS_PATH.read_text())


def test_key_equivalence(vectors):
    probe = b"meshkit-key-equivalence-probe"
    for seed_key, public_key in (
        ("requestSignerSeedHex", "requestSignerPublicKeyBase64"),
        ("receiptSignerSeedHex", "receiptSignerPublicKeyBase64"),
    ):
        seed = bytes.fromhex(vectors[seed_key])
        signature = ed25519.sign(probe, ed25519.private_key_from_seed(seed))
        assert ed25519.verify(probe, signature, base64.b64decode(vectors[public_key]))


def test_request_vectors(vectors):
    for case in vectors["cases"]:
        request = MeshRequest.decoded(case["requestEnvelopeBase64"])

        assert canonical.canonical_payload(request.payload) == case["canonicalPayload"]
        assert (
            canonical.canonical_payload_nonce_bound(request.payload, request.nonce)
            == case["canonicalPayloadNonceBound"]
        )
        assert canonical.sha256_hex(request.payload) == case["payloadHashPlain"]
        assert (
            canonical.sha256_hex_nonce_bound(request.payload, request.nonce)
            == case["payloadHashNonceBound"]
        )
        assert request.payload_hash.value == case["payloadHashNonceBound"]
        assert request.signing_input() == case["requestSigningInput"]

        # Swift signature verifies under the Python verifier.
        verify_signature(
            request,
            MeshSenderTrust(
                caller_app_id=request.caller.app_id,
                caller_bundle_id=request.caller.bundle_id,
                request_signing_algorithm="Ed25519",
                request_signing_key_id=request.signature.key_id,
                public_key_base64=vectors["requestSignerPublicKeyBase64"],
            ),
        )

        # Python signature over the same signing input verifies under the
        # Swift-exported raw public key.
        seed = bytes.fromhex(vectors["requestSignerSeedHex"])
        resigned = request.signed(ed25519.private_key_from_seed(seed), request.signature.key_id)
        assert resigned.signing_input() == case["requestSigningInput"]
        assert ed25519.verify(
            resigned.signing_input().encode("utf-8"),
            base64.b64decode(resigned.signature.value),
            base64.b64decode(vectors["requestSignerPublicKeyBase64"]),
        )

        # Envelope round trip is lossless.
        assert MeshRequest.decoded(request.encoded()) == request


def test_receipt_vectors(vectors):
    for case in vectors["cases"]:
        request = MeshRequest.decoded(case["requestEnvelopeBase64"])
        receipt = MeshReceipt.decoded(case["receiptEnvelopeBase64"])

        assert canonical_result(receipt.result) == case["receiptCanonicalResult"]
        assert receipt.signing_input() == case["receiptSigningInput"]

        seed = bytes.fromhex(vectors["receiptSignerSeedHex"])
        resigned = MeshReceiptSigner.from_seed(vectors["receiptSignerKeyId"], seed).make_receipt(
            receipt_id=receipt.receipt_id,
            request=request,
            target_app_id=receipt.target_app_id,
            target_bundle_id=receipt.target_bundle_id,
            status=receipt.status,
            result=receipt.result,
            nonce=receipt.nonce,
            timestamp=receipt.timestamp,
        )
        assert resigned.signing_input() == case["receiptSigningInput"]
        assert ed25519.verify(
            resigned.signing_input().encode("utf-8"),
            base64.b64decode(resigned.signature.value),
            base64.b64decode(vectors["receiptSignerPublicKeyBase64"]),
        )

        verify_receipt(
            receipt,
            MeshReceiptTrust(
                target_app_id=receipt.target_app_id,
                target_bundle_id=receipt.target_bundle_id,
                receipt_signing_algorithm="Ed25519",
                receipt_signing_key_id=vectors["receiptSignerKeyId"],
                public_key_base64=vectors["receiptSignerPublicKeyBase64"],
            ),
            request=request,
            now=datetime.fromisoformat(receipt.timestamp.replace("Z", "+00:00")),
        )

        assert MeshReceipt.decoded(receipt.encoded()) == receipt


def test_export_python_signed_for_swift_cross_verify(vectors, tmp_path):
    """Export Python-signed envelopes; scripts/verify_python_wire_compat.sh
    feeds them to `wire-vectors-gen cross-verify` so the Swift SDK verifies
    Python signatures."""
    out_path = os.environ.get("MESHKIT_CROSSSIGN_OUT")
    if not out_path:
        pytest.skip("MESHKIT_CROSSSIGN_OUT not set")
    request_seed = bytes.fromhex(vectors["requestSignerSeedHex"])
    receipt_seed = bytes.fromhex(vectors["receiptSignerSeedHex"])
    cases = []
    for case in vectors["cases"]:
        request = MeshRequest.decoded(case["requestEnvelopeBase64"])
        receipt = MeshReceipt.decoded(case["receiptEnvelopeBase64"])
        signed_request = request.signed(
            ed25519.private_key_from_seed(request_seed), request.signature.key_id
        )
        signed_receipt = MeshReceiptSigner.from_seed(
            vectors["receiptSignerKeyId"], receipt_seed
        ).make_receipt(
            receipt_id=receipt.receipt_id,
            request=signed_request,
            target_app_id=receipt.target_app_id,
            target_bundle_id=receipt.target_bundle_id,
            status=receipt.status,
            result=receipt.result,
            nonce=receipt.nonce,
            timestamp=receipt.timestamp,
        )
        cases.append(
            {
                "name": case["name"],
                "requestEnvelopeBase64": signed_request.encoded(),
                "receiptEnvelopeBase64": signed_receipt.encoded(),
            }
        )
    Path(out_path).parent.mkdir(parents=True, exist_ok=True)
    Path(out_path).write_text(json.dumps({"cases": cases}))
