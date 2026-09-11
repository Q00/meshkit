"""Target-side fail-closed validation, consent, and budget policy.

Mirrors the Swift `MeshSignedMCPRequestVerifier` order: envelope fields ->
observed caller (when the transport provides one) -> policy -> payload hash ->
timestamp -> nonce reservation -> invocation policy (consent/budget) ->
signature. Signature verification always happens before business logic.
"""

from dataclasses import dataclass
from datetime import datetime, timezone
from decimal import Decimal, InvalidOperation
from typing import Callable, TYPE_CHECKING

if TYPE_CHECKING:
    from meshkit.request import MeshRequest

DEFAULT_MAX_AGE_SECONDS = 300

PER_INVOCATION_CONSENT_RISKS = frozenset(
    {"write:user_content", "send:external", "spend:money", "identity", "location"}
)


class MeshValidationError(Exception):
    def __init__(self, code: str, message: str):
        super().__init__(message)
        self.code = code


def require_security_field(field: str, value: str) -> None:
    stripped = value.strip()
    if not stripped or stripped != value:
        raise MeshValidationError("invalid_security_field", f"invalid security field: {field}")
    if any(ch in "\r\n" or ord(ch) < 0x20 or ord(ch) == 0x7F for ch in value):
        raise MeshValidationError("invalid_security_field", f"invalid security field: {field}")


@dataclass(frozen=True)
class MeshTargetPolicy:
    allowed_caller_app_id: str
    target_bundle_id: str
    capability_id: str


@dataclass(frozen=True)
class MeshSenderTrust:
    caller_app_id: str
    caller_bundle_id: str
    request_signing_algorithm: str | None = None
    request_signing_key_id: str | None = None
    public_key_base64: str | None = None


@dataclass(frozen=True)
class MeshObservedCaller:
    """Transport-observed caller identity.

    On-device transports (iOS/Android) provide a kernel-verified value and
    MUST pass it. The HTTP/MCP transport has no equivalent; there the Ed25519
    request signature plus TLS is the caller proof and `observed_caller`
    stays None.
    """

    package_name: str
    signing_cert_sha256: str | None = None


@dataclass(frozen=True)
class MeshInvocationPolicy:
    risk: str
    consent: str
    user_approved: bool
    registry_signature_verified: bool
    approved_budget: Decimal | None = None
    production_enabled: bool = True
    kill_switch_reason: str | None = None

    @property
    def requires_per_invocation_consent(self) -> bool:
        return self.risk in PER_INVOCATION_CONSENT_RISKS

    def validate_before_execution(self, request: "MeshRequest", trust: MeshSenderTrust) -> None:
        if not self.production_enabled:
            raise MeshValidationError(
                "production_disabled",
                self.kill_switch_reason or "production invocation disabled",
            )
        if not self.registry_signature_verified:
            raise MeshValidationError(
                "registry_trust_required", "registry signature verification is required"
            )
        if self.requires_per_invocation_consent and not self.user_approved:
            raise MeshValidationError("consent_required", f"user consent required for risk: {self.risk}")
        if self.risk == "spend:money":
            self._validate_budget(request)
        if not request.signature.key_id or not request.signature.value:
            raise MeshValidationError("signature_required", "request signature is required")
        if trust.request_signing_algorithm and trust.request_signing_algorithm != request.signature.algorithm:
            raise MeshValidationError("signature_mismatch", "request signing algorithm mismatch")
        if trust.request_signing_key_id and trust.request_signing_key_id != request.signature.key_id:
            raise MeshValidationError("signature_mismatch", "request signing key id mismatch")

    def _validate_budget(self, request: "MeshRequest") -> None:
        if self.approved_budget is None:
            raise MeshValidationError("budget_required", "approved budget required for spend:money")
        raw = request.payload.get("budget_krw")
        if raw is None:
            raise MeshValidationError("budget_required", "approved budget required for spend:money")
        try:
            requested = Decimal(raw)
        except InvalidOperation:
            raise MeshValidationError("budget_required", "approved budget required for spend:money")
        if requested < 0:
            raise MeshValidationError("budget_required", "approved budget required for spend:money")
        if requested > self.approved_budget:
            raise MeshValidationError("budget_exceeded", "requested spend exceeds approved budget")


def _verify_envelope_fields(request: "MeshRequest") -> None:
    require_security_field("requestId", request.request_id)
    require_security_field("caller.appId", request.caller.app_id)
    require_security_field("caller.installId", request.caller.install_id)
    require_security_field("caller.bundleId", request.caller.bundle_id)
    require_security_field("caller.publicKeyId", request.caller.public_key_id)
    require_security_field("target.targetBundleId", request.target.target_bundle_id)
    require_security_field("target.capabilityId", request.target.capability_id)
    require_security_field("target.version", request.target.version)
    require_security_field("payloadHash.algorithm", request.payload_hash.algorithm)
    require_security_field("payloadHash.value", request.payload_hash.value)
    require_security_field("timestamp", request.timestamp)
    require_security_field("nonce", request.nonce)
    value = request.payload_hash.value
    if len(value) != 64 or any(ch not in "0123456789abcdefABCDEF" for ch in value):
        raise MeshValidationError("invalid_security_field", "invalid security field: payloadHash.value")
    if request.signature.algorithm:
        require_security_field("signature.algorithm", request.signature.algorithm)
    if request.signature.key_id:
        require_security_field("signature.keyId", request.signature.key_id)


def verify_signature(request: "MeshRequest", trust: MeshSenderTrust) -> None:
    from meshkit import ed25519

    if not request.signature.key_id or not request.signature.value:
        raise MeshValidationError("signature_required", "request signature is required")
    if request.signature.algorithm != "Ed25519":
        raise MeshValidationError(
            "signature_mismatch",
            f"unsupported request signing algorithm: {request.signature.algorithm}",
        )
    public_key = ed25519.decode_base64(trust.public_key_base64 or "")
    if not public_key:
        raise MeshValidationError("signature_required", "request signature is required")
    signature = ed25519.decode_base64(request.signature.value)
    if not signature:
        raise MeshValidationError("signature_mismatch", "request signature is not valid base64")
    if not ed25519.verify(request.signing_input().encode("utf-8"), signature, public_key):
        raise MeshValidationError("signature_mismatch", "invalid request signature")


def validate_and_accept(
    request: "MeshRequest",
    policy: MeshTargetPolicy,
    invocation_policy: MeshInvocationPolicy,
    trust: MeshSenderTrust,
    reserve_nonce: Callable[[str], bool],
    observed_caller: MeshObservedCaller | None = None,
    require_observed_caller: bool = False,
    trusted_caller_cert_sha256: str | None = None,
    max_age_seconds: int = DEFAULT_MAX_AGE_SECONDS,
    now: datetime | None = None,
) -> dict:
    """Full fail-closed acceptance; returns an accepted audit event dict."""
    from meshkit import canonical

    _verify_envelope_fields(request)

    if require_observed_caller or observed_caller is not None:
        if observed_caller is None:
            raise MeshValidationError("observed_caller_required", "observed caller identity is required")
        if observed_caller.package_name != request.caller.bundle_id:
            raise MeshValidationError("observed_caller_mismatch", "observed caller package mismatch")
        if observed_caller.package_name != trust.caller_bundle_id:
            raise MeshValidationError("trusted_caller_mismatch", "trusted caller bundle mismatch")
        if trusted_caller_cert_sha256 and (
            (observed_caller.signing_cert_sha256 or "").lower() != trusted_caller_cert_sha256.lower()
        ):
            raise MeshValidationError(
                "observed_caller_signature_mismatch",
                "observed caller signing certificate mismatch",
            )

    if request.caller.app_id != policy.allowed_caller_app_id or request.caller.app_id != trust.caller_app_id:
        raise MeshValidationError("trusted_caller_mismatch", "trusted caller app id mismatch")
    if request.caller.bundle_id != trust.caller_bundle_id:
        raise MeshValidationError("caller_bundle_claim_mismatch", "caller bundle claim mismatch")
    if request.target.target_bundle_id != policy.target_bundle_id:
        raise MeshValidationError("target_identity_mismatch", "target identity mismatch")
    if request.target.capability_id != policy.capability_id:
        raise MeshValidationError("unsupported_capability", "unsupported capability")

    if request.payload_hash.algorithm.lower() != "sha256":
        raise MeshValidationError("unsupported_payload_hash_algorithm", "unsupported payload hash algorithm")
    actual = canonical.sha256_hex_nonce_bound(request.payload, request.nonce)
    if actual.lower() != request.payload_hash.value.lower():
        raise MeshValidationError("payload_hash_mismatch", "payload hash mismatch")

    try:
        timestamp = datetime.fromisoformat(request.timestamp.replace("Z", "+00:00"))
    except ValueError:
        raise MeshValidationError("stale_timestamp", "stale request timestamp")
    reference = now if now is not None else datetime.now(timezone.utc)
    if abs((timestamp - reference).total_seconds()) > max_age_seconds:
        raise MeshValidationError("stale_timestamp", "stale request timestamp")

    if not reserve_nonce(request.nonce):
        raise MeshValidationError("replay_detected", f"replay detected for nonce: {request.nonce}")

    invocation_policy.validate_before_execution(request, trust)
    verify_signature(request, trust)

    return {
        "requestId": request.request_id,
        "callerAppId": request.caller.app_id,
        "targetBundleId": request.target.target_bundle_id,
        "capabilityId": request.target.capability_id,
        "risk": invocation_policy.risk,
        "consent": invocation_policy.consent,
        "status": "accepted",
    }
