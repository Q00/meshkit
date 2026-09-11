"""MeshKit app-to-app MCP trust layer - Python SDK.

Wire-compatible with the Swift and Kotlin SDKs: same canonical payload form
(`meshkit-payload-hash/v1`), signing inputs (`meshkit-request-signing/v1`,
`meshkit-target-receipt-signing/v1`), base64 sorted-keys JSON envelopes, and
Ed25519 with raw public keys. Golden vectors:
`meshkit-android/vectors/wire-compat.v1.json`.
"""

from meshkit.models import (
    MeshCapability,
    MeshIdentity,
    MeshPayloadHash,
    MeshSignature,
)
from meshkit.canonical import (
    canonical_payload,
    canonical_payload_nonce_bound,
    payload_hash,
    sha256_hex,
    sha256_hex_nonce_bound,
)
from meshkit.request import MeshRequest
from meshkit.receipt import MeshReceipt, MeshReceiptSigner, MeshReceiptTrust, verify_receipt
from meshkit.trust import (
    MeshInvocationPolicy,
    MeshObservedCaller,
    MeshSenderTrust,
    MeshTargetPolicy,
    MeshValidationError,
    validate_and_accept,
)
from meshkit import ed25519
from meshkit import mcpv2

__all__ = [
    "MeshCapability",
    "MeshIdentity",
    "MeshPayloadHash",
    "MeshSignature",
    "MeshRequest",
    "MeshReceipt",
    "MeshReceiptSigner",
    "MeshReceiptTrust",
    "verify_receipt",
    "MeshInvocationPolicy",
    "MeshObservedCaller",
    "MeshSenderTrust",
    "MeshTargetPolicy",
    "MeshValidationError",
    "validate_and_accept",
    "canonical_payload",
    "canonical_payload_nonce_bound",
    "payload_hash",
    "sha256_hex",
    "sha256_hex_nonce_bound",
    "ed25519",
    "mcpv2",
]
