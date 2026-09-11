"""Canonical byte forms shared with the Swift/Kotlin SDKs.

Wire contract `meshkit-payload-hash/v1`: sorted ``key=value&...`` pairs with
every byte outside ASCII alphanumerics percent-escaped as uppercase-hex UTF-8.
"""

import hashlib

ALGORITHM = "sha256"
NONCE_BOUND_VERSION = "meshkit-payload-hash/v1"

_ALNUM = frozenset(
    b"0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz"
)


def escape(value: str) -> str:
    out = []
    for byte in value.encode("utf-8"):
        if byte in _ALNUM:
            out.append(chr(byte))
        else:
            out.append(f"%{byte:02X}")
    return "".join(out)


def canonical_payload(payload: dict[str, str]) -> str:
    return "&".join(f"{escape(key)}={escape(payload[key])}" for key in sorted(payload))


def canonical_payload_nonce_bound(payload: dict[str, str], nonce: str) -> str:
    return "\n".join(
        [
            NONCE_BOUND_VERSION,
            f"nonce={escape(nonce)}",
            f"payload={canonical_payload(payload)}",
        ]
    )


def sha256_hex(payload: dict[str, str]) -> str:
    return hashlib.sha256(canonical_payload(payload).encode("utf-8")).hexdigest()


def sha256_hex_nonce_bound(payload: dict[str, str], nonce: str) -> str:
    return hashlib.sha256(
        canonical_payload_nonce_bound(payload, nonce).encode("utf-8")
    ).hexdigest()


def payload_hash(payload: dict[str, str], nonce: str):
    from meshkit.models import MeshPayloadHash

    return MeshPayloadHash(algorithm=ALGORITHM, value=sha256_hex_nonce_bound(payload, nonce))
