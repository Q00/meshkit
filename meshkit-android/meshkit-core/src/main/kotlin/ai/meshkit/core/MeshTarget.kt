package ai.meshkit.core

import java.time.Instant
import java.time.format.DateTimeParseException
import kotlin.math.abs

/**
 * Observed caller identity supplied by the transport layer. On Android this
 * comes from `Activity.getCallingPackage()` (non-null only for
 * `startActivityForResult` callers) plus the caller package's signing-cert
 * SHA-256 from PackageManager — kernel-verified, unlike an envelope claim.
 */
data class MeshObservedCaller(
    val packageName: String,
    val signingCertSha256: String
)

object MeshTarget {
    const val DEFAULT_MAX_AGE_SECONDS = 300L

    fun validateAndAccept(
        request: MeshRequest,
        policy: MeshTargetPolicy,
        invocationPolicy: MeshInvocationPolicy,
        trust: MeshSenderTrust,
        observedCaller: MeshObservedCaller?,
        replayCache: MeshReplayCache,
        verifier: MeshSignatureVerifier = Ed25519Jvm.rawKeyVerifier,
        maxAgeSeconds: Long = DEFAULT_MAX_AGE_SECONDS,
        now: Instant = Instant.now()
    ): MeshAuditEvent {
        validateRequestEnvelope(request)
        verifyObservedCaller(request, trust, observedCaller)
        verifyPolicy(request, policy, trust)
        verifyPayloadHash(request)
        verifyFreshTimestamp(request, maxAgeSeconds, now)
        if (!replayCache.reserve(request.nonce)) {
            throw MeshValidationException(MeshValidationCode.REPLAY_DETECTED, "replay detected for nonce: ${request.nonce}")
        }
        invocationPolicy.validateBeforeExecution(request, trust)
        verifyRequiredSignature(request, trust, verifier)
        return MeshAuditEvent.accepted(request, invocationPolicy)
    }

    fun verifyObservedCaller(request: MeshRequest, trust: MeshSenderTrust, observedCaller: MeshObservedCaller?) {
        val observed = observedCaller
            ?: throw MeshValidationException(MeshValidationCode.OBSERVED_CALLER_REQUIRED, "observed caller identity is required")
        if (observed.packageName != request.caller.bundleId) {
            throw MeshValidationException(MeshValidationCode.OBSERVED_CALLER_MISMATCH, "observed caller package mismatch")
        }
        if (observed.packageName != trust.callerBundleId) {
            throw MeshValidationException(MeshValidationCode.TRUSTED_CALLER_MISMATCH, "trusted caller bundle mismatch")
        }
        trust.callerPackageSignatureSha256?.let { pinned ->
            if (!pinned.equals(observed.signingCertSha256, ignoreCase = true)) {
                throw MeshValidationException(
                    MeshValidationCode.OBSERVED_CALLER_SIGNATURE_MISMATCH,
                    "observed caller signing certificate mismatch"
                )
            }
        }
    }

    fun verifyPolicy(request: MeshRequest, policy: MeshTargetPolicy, trust: MeshSenderTrust) {
        if (request.caller.appId != policy.allowedCallerAppId || request.caller.appId != trust.callerAppId) {
            throw MeshValidationException(MeshValidationCode.TRUSTED_CALLER_MISMATCH, "trusted caller app id mismatch")
        }
        if (request.caller.bundleId != trust.callerBundleId) {
            throw MeshValidationException(MeshValidationCode.CALLER_BUNDLE_CLAIM_MISMATCH, "caller bundle claim mismatch")
        }
        if (request.target.targetBundleId != policy.targetBundleId) {
            throw MeshValidationException(MeshValidationCode.TARGET_IDENTITY_MISMATCH, "target identity mismatch")
        }
        if (request.target.capabilityId != policy.capabilityId) {
            throw MeshValidationException(MeshValidationCode.UNSUPPORTED_CAPABILITY, "unsupported capability")
        }
    }

    fun verifyPayloadHash(request: MeshRequest) {
        if (!request.payloadHash.algorithm.equals("sha256", ignoreCase = true)) {
            throw MeshValidationException(MeshValidationCode.UNSUPPORTED_PAYLOAD_HASH_ALGORITHM, "unsupported payload hash algorithm")
        }
        val actual = MeshRequestPayloadHasher.sha256Hex(request.payload, request.nonce)
        if (!actual.equals(request.payloadHash.value, ignoreCase = true)) {
            throw MeshValidationException(MeshValidationCode.PAYLOAD_HASH_MISMATCH, "payload hash mismatch")
        }
    }

    fun verifyFreshTimestamp(request: MeshRequest, maxAgeSeconds: Long, now: Instant = Instant.now()) {
        val timestamp = try {
            Instant.parse(request.timestamp)
        } catch (e: DateTimeParseException) {
            throw MeshValidationException(MeshValidationCode.STALE_TIMESTAMP, "stale request timestamp")
        }
        if (abs(timestamp.epochSecond - now.epochSecond) > maxAgeSeconds) {
            throw MeshValidationException(MeshValidationCode.STALE_TIMESTAMP, "stale request timestamp")
        }
    }

    fun verifyRequiredSignature(
        request: MeshRequest,
        trust: MeshSenderTrust,
        verifier: MeshSignatureVerifier = Ed25519Jvm.rawKeyVerifier
    ) {
        if (request.signature.keyId.isEmpty() || request.signature.value.isEmpty()) {
            throw MeshValidationException(MeshValidationCode.SIGNATURE_REQUIRED, "request signature is required")
        }
        if (request.signature.algorithm != "Ed25519") {
            throw MeshValidationException(
                MeshValidationCode.SIGNATURE_MISMATCH,
                "unsupported request signing algorithm: ${request.signature.algorithm}"
            )
        }
        val publicKeyRaw = trust.publicKeyBase64?.let { Ed25519Jvm.decodeBase64(it) }?.takeIf { it.isNotEmpty() }
            ?: throw MeshValidationException(MeshValidationCode.SIGNATURE_REQUIRED, "request signature is required")
        val signatureBytes = Ed25519Jvm.decodeBase64(request.signature.value)?.takeIf { it.isNotEmpty() }
            ?: throw MeshValidationException(MeshValidationCode.SIGNATURE_MISMATCH, "request signature is not valid base64")
        val valid = try {
            verifier.verify(request.signingInputData(), signatureBytes, publicKeyRaw)
        } catch (e: Exception) {
            throw MeshValidationException(MeshValidationCode.SIGNATURE_MISMATCH, "invalid request signing public key")
        }
        if (!valid) {
            throw MeshValidationException(MeshValidationCode.SIGNATURE_MISMATCH, "invalid request signature")
        }
    }

    fun validateRequestEnvelope(request: MeshRequest) {
        requireSecurityField("requestId", request.requestId)
        requireSecurityField("caller.appId", request.caller.appId)
        requireSecurityField("caller.installId", request.caller.installId)
        requireSecurityField("caller.bundleId", request.caller.bundleId)
        requireSecurityField("caller.publicKeyId", request.caller.publicKeyId)
        requireSecurityField("target.targetBundleId", request.target.targetBundleId)
        requireSecurityField("target.capabilityId", request.target.capabilityId)
        requireSecurityField("target.version", request.target.version)
        requireSecurityField("payloadHash.algorithm", request.payloadHash.algorithm)
        requireSecurityField("payloadHash.value", request.payloadHash.value)
        requireSecurityField("timestamp", request.timestamp)
        requireSecurityField("nonce", request.nonce)
        requireHexSha256(request.payloadHash.value)
        if (request.signature.algorithm.isNotEmpty()) requireSecurityField("signature.algorithm", request.signature.algorithm)
        if (request.signature.keyId.isNotEmpty()) requireSecurityField("signature.keyId", request.signature.keyId)
    }

    internal fun requireSecurityField(field: String, value: String) {
        val trimmed = value.trim()
        if (trimmed.isEmpty() || trimmed != value) {
            throw MeshValidationException(MeshValidationCode.INVALID_SECURITY_FIELD, "invalid security field: $field")
        }
        if (value.any { it == '\n' || it == '\r' || it.isISOControl() }) {
            throw MeshValidationException(MeshValidationCode.INVALID_SECURITY_FIELD, "invalid security field: $field")
        }
    }

    private fun requireHexSha256(value: String) {
        if (value.length != 64 || value.any { it !in "0123456789abcdefABCDEF" }) {
            throw MeshValidationException(MeshValidationCode.INVALID_SECURITY_FIELD, "invalid security field: payloadHash.value")
        }
    }
}
