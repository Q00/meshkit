"""Ed25519 with raw 32-byte public keys and 64-byte signatures.

Matches CryptoKit's ``rawRepresentation`` and the JCA raw forms used by the
Kotlin SDK. Note: CryptoKit emits randomized Ed25519 signatures while this
module (via `cryptography`) is RFC 8032 deterministic — cross-implementation
equivalence is therefore proven by mutual verification over identical signing
inputs, never by comparing signature bytes.
"""

import base64

from cryptography.exceptions import InvalidSignature
from cryptography.hazmat.primitives.asymmetric.ed25519 import (
    Ed25519PrivateKey,
    Ed25519PublicKey,
)


def private_key_from_seed(seed: bytes) -> Ed25519PrivateKey:
    if len(seed) != 32:
        raise ValueError("Ed25519 seed must be 32 bytes")
    return Ed25519PrivateKey.from_private_bytes(seed)


def public_key_raw(private_key: Ed25519PrivateKey) -> bytes:
    from cryptography.hazmat.primitives.serialization import (
        Encoding,
        PublicFormat,
    )

    return private_key.public_key().public_bytes(Encoding.Raw, PublicFormat.Raw)


def sign(data: bytes, private_key: Ed25519PrivateKey) -> bytes:
    return private_key.sign(data)


def verify(data: bytes, signature: bytes, public_key_raw_bytes: bytes) -> bool:
    if len(public_key_raw_bytes) != 32:
        return False
    try:
        Ed25519PublicKey.from_public_bytes(public_key_raw_bytes).verify(signature, data)
        return True
    except InvalidSignature:
        return False


def decode_base64(value: str) -> bytes | None:
    try:
        return base64.b64decode(value, validate=True)
    except Exception:
        return None
