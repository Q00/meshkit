from dataclasses import dataclass


@dataclass(frozen=True)
class MeshIdentity:
    app_id: str
    install_id: str
    bundle_id: str
    public_key_id: str


@dataclass(frozen=True)
class MeshCapability:
    target_bundle_id: str
    capability_id: str
    version: str


@dataclass(frozen=True)
class MeshSignature:
    algorithm: str
    key_id: str
    value: str


@dataclass(frozen=True)
class MeshPayloadHash:
    algorithm: str
    value: str
