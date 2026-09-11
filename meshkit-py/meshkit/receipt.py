import base64
from dataclasses import dataclass, replace
from datetime import datetime, timezone

from cryptography.hazmat.primitives.asymmetric.ed25519 import Ed25519PrivateKey

from meshkit import canonical, ed25519, envelope
from meshkit.models import MeshPayloadHash, MeshSignature
from meshkit.request import MeshRequest
from meshkit.trust import DEFAULT_MAX_AGE_SECONDS, MeshValidationError, require_security_field

SIGNING_VERSION = "meshkit-target-receipt-signing/v1"
ENVELOPE_KEY = "mesh_receipt"


def canonical_result(result: dict[str, str]) -> str:
    return "&".join(
        f"{canonical.escape(key)}={canonical.escape(result[key])}" for key in sorted(result)
    )


@dataclass(frozen=True)
class MeshReceipt:
    receipt_id: str
    request_id: str
    capability_id: str
    target_app_id: str
    target_bundle_id: str
    request_payload_hash: MeshPayloadHash
    status: str
    result: dict[str, str]
    nonce: str
    timestamp: str
    signature: MeshSignature

    def signing_input(self) -> str:
        return "\n".join(
            [
                SIGNING_VERSION,
                self.receipt_id,
                self.request_id,
                self.capability_id,
                self.target_app_id,
                self.target_bundle_id,
                self.request_payload_hash.algorithm.lower(),
                self.request_payload_hash.value.lower(),
                self.status,
                canonical_result(self.result),
                self.timestamp,
                self.nonce,
            ]
        )

    def encoded(self) -> str:
        return envelope.encode(
            {
                "capabilityId": self.capability_id,
                "nonce": self.nonce,
                "receiptId": self.receipt_id,
                "requestId": self.request_id,
                "requestPayloadHash": {
                    "algorithm": self.request_payload_hash.algorithm,
                    "value": self.request_payload_hash.value,
                },
                "result": dict(sorted(self.result.items())),
                "signature": {
                    "algorithm": self.signature.algorithm,
                    "keyId": self.signature.key_id,
                    "value": self.signature.value,
                },
                "status": self.status,
                "targetAppId": self.target_app_id,
                "targetBundleId": self.target_bundle_id,
                "timestamp": self.timestamp,
            }
        )

    @staticmethod
    def decoded(encoded: str) -> "MeshReceipt":
        root = envelope.decode(encoded, ENVELOPE_KEY)
        payload_hash = envelope.require_obj(root, "requestPayloadHash", ENVELOPE_KEY)
        signature = envelope.require_obj(root, "signature", ENVELOPE_KEY)
        return MeshReceipt(
            receipt_id=envelope.require_str(root, "receiptId", ENVELOPE_KEY),
            request_id=envelope.require_str(root, "requestId", ENVELOPE_KEY),
            capability_id=envelope.require_str(root, "capabilityId", ENVELOPE_KEY),
            target_app_id=envelope.require_str(root, "targetAppId", ENVELOPE_KEY),
            target_bundle_id=envelope.require_str(root, "targetBundleId", ENVELOPE_KEY),
            request_payload_hash=MeshPayloadHash(
                algorithm=envelope.require_str(payload_hash, "algorithm", "mesh_receipt.requestPayloadHash"),
                value=envelope.require_str(payload_hash, "value", "mesh_receipt.requestPayloadHash"),
            ),
            status=envelope.require_str(root, "status", ENVELOPE_KEY),
            result=envelope.require_str_map(root, "result", ENVELOPE_KEY),
            nonce=envelope.require_str(root, "nonce", ENVELOPE_KEY),
            timestamp=envelope.require_str(root, "timestamp", ENVELOPE_KEY),
            signature=MeshSignature(
                algorithm=envelope.require_str(signature, "algorithm", "mesh_receipt.signature"),
                key_id=envelope.require_str(signature, "keyId", "mesh_receipt.signature"),
                value=envelope.require_str(signature, "value", "mesh_receipt.signature"),
            ),
        )


@dataclass(frozen=True)
class MeshReceiptTrust:
    target_app_id: str
    target_bundle_id: str
    receipt_signing_algorithm: str
    receipt_signing_key_id: str
    public_key_base64: str


class MeshReceiptSigner:
    def __init__(self, key_id: str, private_key: Ed25519PrivateKey):
        self.key_id = key_id
        self._private_key = private_key

    @staticmethod
    def from_seed(key_id: str, seed: bytes) -> "MeshReceiptSigner":
        return MeshReceiptSigner(key_id, ed25519.private_key_from_seed(seed))

    def make_receipt(
        self,
        receipt_id: str,
        request: MeshRequest,
        target_app_id: str,
        target_bundle_id: str,
        status: str,
        result: dict[str, str],
        nonce: str,
        timestamp: str,
    ) -> MeshReceipt:
        unsigned = MeshReceipt(
            receipt_id=receipt_id,
            request_id=request.request_id,
            capability_id=request.target.capability_id,
            target_app_id=target_app_id,
            target_bundle_id=target_bundle_id,
            request_payload_hash=request.payload_hash,
            status=status,
            result=dict(result),
            nonce=nonce,
            timestamp=timestamp,
            signature=MeshSignature("Ed25519", self.key_id, ""),
        )
        signature_value = base64.b64encode(
            ed25519.sign(unsigned.signing_input().encode("utf-8"), self._private_key)
        ).decode("ascii")
        return replace(unsigned, signature=MeshSignature("Ed25519", self.key_id, signature_value))


def verify_receipt(
    receipt: MeshReceipt,
    trust: MeshReceiptTrust,
    request: MeshRequest | None = None,
    max_age_seconds: int = DEFAULT_MAX_AGE_SECONDS,
    now: datetime | None = None,
) -> MeshReceipt:
    """Verify a target-owned receipt; with `request`, also verify correlation."""
    for field, value in (
        ("receiptId", receipt.receipt_id),
        ("requestId", receipt.request_id),
        ("capabilityId", receipt.capability_id),
        ("targetAppId", receipt.target_app_id),
        ("targetBundleId", receipt.target_bundle_id),
        ("status", receipt.status),
        ("timestamp", receipt.timestamp),
        ("nonce", receipt.nonce),
    ):
        require_security_field(field, value)
    if receipt.target_app_id != trust.target_app_id or receipt.target_bundle_id != trust.target_bundle_id:
        raise MeshValidationError("target_identity_mismatch", "target identity mismatch")
    if receipt.signature.algorithm != trust.receipt_signing_algorithm:
        raise MeshValidationError("signature_mismatch", "receipt signing algorithm mismatch")
    if receipt.signature.key_id != trust.receipt_signing_key_id:
        raise MeshValidationError("signature_mismatch", "receipt signing key id mismatch")
    if trust.receipt_signing_algorithm != "Ed25519":
        raise MeshValidationError(
            "signature_mismatch",
            f"unsupported receipt signing algorithm: {trust.receipt_signing_algorithm}",
        )
    try:
        timestamp = datetime.fromisoformat(receipt.timestamp.replace("Z", "+00:00"))
    except ValueError:
        raise MeshValidationError("stale_timestamp", "stale request timestamp")
    reference = now if now is not None else datetime.now(timezone.utc)
    if abs((timestamp - reference).total_seconds()) > max_age_seconds:
        raise MeshValidationError("stale_timestamp", "stale request timestamp")
    public_key = ed25519.decode_base64(trust.public_key_base64)
    if not public_key:
        raise MeshValidationError("signature_required", "receipt signing public key is required")
    signature = ed25519.decode_base64(receipt.signature.value)
    if not signature:
        raise MeshValidationError("signature_mismatch", "receipt signature is not valid base64")
    if not ed25519.verify(receipt.signing_input().encode("utf-8"), signature, public_key):
        raise MeshValidationError("signature_mismatch", "invalid receipt signature")
    if request is not None:
        correlated = (
            receipt.request_id == request.request_id
            and receipt.capability_id == request.target.capability_id
            and receipt.target_bundle_id == request.target.target_bundle_id
            and receipt.request_payload_hash.value.lower() == request.payload_hash.value.lower()
        )
        if not correlated:
            raise MeshValidationError(
                "receipt_correlation_mismatch",
                "target receipt does not match a pending request token",
            )
    return receipt
