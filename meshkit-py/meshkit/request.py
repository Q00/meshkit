import base64
from dataclasses import dataclass, replace

from cryptography.hazmat.primitives.asymmetric.ed25519 import Ed25519PrivateKey

from meshkit import canonical, ed25519, envelope
from meshkit.models import MeshCapability, MeshIdentity, MeshPayloadHash, MeshSignature

SIGNING_VERSION = "meshkit-request-signing/v1"
ENVELOPE_KEY = "mesh_request"


@dataclass(frozen=True)
class MeshRequest:
    request_id: str
    caller: MeshIdentity
    target: MeshCapability
    payload: dict[str, str]
    payload_hash: MeshPayloadHash
    nonce: str
    timestamp: str
    signature: MeshSignature

    @staticmethod
    def create(
        request_id: str,
        caller: MeshIdentity,
        target: MeshCapability,
        payload: dict[str, str],
        nonce: str,
        timestamp: str,
        signature: MeshSignature = MeshSignature("Ed25519", "", ""),
    ) -> "MeshRequest":
        return MeshRequest(
            request_id=request_id,
            caller=caller,
            target=target,
            payload=dict(payload),
            payload_hash=canonical.payload_hash(payload, nonce),
            nonce=nonce,
            timestamp=timestamp,
            signature=signature,
        )

    def signing_input(self) -> str:
        return "\n".join(
            [
                SIGNING_VERSION,
                self.request_id,
                self.caller.app_id,
                self.caller.bundle_id,
                self.caller.public_key_id,
                self.target.target_bundle_id,
                self.target.capability_id,
                self.target.version,
                self.payload_hash.algorithm.lower(),
                self.payload_hash.value.lower(),
                self.timestamp,
                self.nonce,
            ]
        )

    def signed(self, private_key: Ed25519PrivateKey, key_id: str) -> "MeshRequest":
        unsigned = replace(self, signature=MeshSignature("Ed25519", key_id, ""))
        signature_value = base64.b64encode(
            ed25519.sign(unsigned.signing_input().encode("utf-8"), private_key)
        ).decode("ascii")
        return replace(unsigned, signature=MeshSignature("Ed25519", key_id, signature_value))

    def encoded(self) -> str:
        return envelope.encode(
            {
                "caller": {
                    "appId": self.caller.app_id,
                    "bundleId": self.caller.bundle_id,
                    "installId": self.caller.install_id,
                    "publicKeyId": self.caller.public_key_id,
                },
                "nonce": self.nonce,
                "payload": dict(sorted(self.payload.items())),
                "payloadHash": {
                    "algorithm": self.payload_hash.algorithm,
                    "value": self.payload_hash.value,
                },
                "requestId": self.request_id,
                "signature": {
                    "algorithm": self.signature.algorithm,
                    "keyId": self.signature.key_id,
                    "value": self.signature.value,
                },
                "target": {
                    "capabilityId": self.target.capability_id,
                    "targetBundleId": self.target.target_bundle_id,
                    "version": self.target.version,
                },
                "timestamp": self.timestamp,
            }
        )

    @staticmethod
    def decoded(encoded: str) -> "MeshRequest":
        root = envelope.decode(encoded, ENVELOPE_KEY)
        caller = envelope.require_obj(root, "caller", ENVELOPE_KEY)
        target = envelope.require_obj(root, "target", ENVELOPE_KEY)
        payload_hash = envelope.require_obj(root, "payloadHash", ENVELOPE_KEY)
        signature = envelope.require_obj(root, "signature", ENVELOPE_KEY)
        return MeshRequest(
            request_id=envelope.require_str(root, "requestId", ENVELOPE_KEY),
            caller=MeshIdentity(
                app_id=envelope.require_str(caller, "appId", "mesh_request.caller"),
                install_id=envelope.require_str(caller, "installId", "mesh_request.caller"),
                bundle_id=envelope.require_str(caller, "bundleId", "mesh_request.caller"),
                public_key_id=envelope.require_str(caller, "publicKeyId", "mesh_request.caller"),
            ),
            target=MeshCapability(
                target_bundle_id=envelope.require_str(target, "targetBundleId", "mesh_request.target"),
                capability_id=envelope.require_str(target, "capabilityId", "mesh_request.target"),
                version=envelope.require_str(target, "version", "mesh_request.target"),
            ),
            payload=envelope.require_str_map(root, "payload", ENVELOPE_KEY),
            payload_hash=MeshPayloadHash(
                algorithm=envelope.require_str(payload_hash, "algorithm", "mesh_request.payloadHash"),
                value=envelope.require_str(payload_hash, "value", "mesh_request.payloadHash"),
            ),
            nonce=envelope.require_str(root, "nonce", ENVELOPE_KEY),
            timestamp=envelope.require_str(root, "timestamp", ENVELOPE_KEY),
            signature=MeshSignature(
                algorithm=envelope.require_str(signature, "algorithm", "mesh_request.signature"),
                key_id=envelope.require_str(signature, "keyId", "mesh_request.signature"),
                value=envelope.require_str(signature, "value", "mesh_request.signature"),
            ),
        )
