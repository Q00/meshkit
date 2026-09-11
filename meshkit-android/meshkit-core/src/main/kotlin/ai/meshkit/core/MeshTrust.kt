package ai.meshkit.core

import java.math.BigDecimal

data class MeshTargetPolicy(
    val allowedCallerAppId: String,
    val targetBundleId: String,
    val capabilityId: String
)

/**
 * Caller trust metadata from the OCG registry. On Android the observed
 * caller is kernel-verified: `callerPackageSignatureSha256` pins the caller
 * package's signing certificate, checked against
 * `PackageManager.GET_SIGNING_CERTIFICATES` by the transport layer.
 */
data class MeshSenderTrust(
    val callerAppId: String,
    val callerBundleId: String,
    val callerPackageSignatureSha256: String? = null,
    val requestSigningAlgorithm: String? = null,
    val requestSigningKeyId: String? = null,
    val publicKeyBase64: String? = null
)

data class MeshInvocationPolicy(
    val risk: String,
    val consent: String,
    val userApproved: Boolean,
    val registrySignatureVerified: Boolean,
    val approvedBudget: BigDecimal? = null,
    val productionEnabled: Boolean = true,
    val killSwitchReason: String? = null
) {
    val requiresPerInvocationConsent: Boolean
        get() = risk in setOf("write:user_content", "send:external", "spend:money", "identity", "location")

    fun validateBeforeExecution(request: MeshRequest, trust: MeshSenderTrust) {
        if (!productionEnabled) {
            throw MeshValidationException(
                MeshValidationCode.PRODUCTION_DISABLED,
                killSwitchReason ?: "production invocation disabled"
            )
        }
        if (!registrySignatureVerified) {
            throw MeshValidationException(MeshValidationCode.REGISTRY_TRUST_REQUIRED, "registry signature verification is required")
        }
        if (requiresPerInvocationConsent && !userApproved) {
            throw MeshValidationException(MeshValidationCode.CONSENT_REQUIRED, "user consent required for risk: $risk")
        }
        if (risk == "spend:money") validateBudget(request)
        if (request.signature.keyId.isEmpty() || request.signature.value.isEmpty()) {
            throw MeshValidationException(MeshValidationCode.SIGNATURE_REQUIRED, "request signature is required")
        }
        trust.requestSigningAlgorithm?.let { expected ->
            if (expected != request.signature.algorithm) {
                throw MeshValidationException(MeshValidationCode.SIGNATURE_MISMATCH, "request signing algorithm mismatch")
            }
        }
        trust.requestSigningKeyId?.let { expected ->
            if (expected != request.signature.keyId) {
                throw MeshValidationException(MeshValidationCode.SIGNATURE_MISMATCH, "request signing key id mismatch")
            }
        }
    }

    private fun validateBudget(request: MeshRequest) {
        val approved = approvedBudget
            ?: throw MeshValidationException(MeshValidationCode.BUDGET_REQUIRED, "approved budget required for spend:money")
        val raw = request.payload["budget_krw"]
            ?: throw MeshValidationException(MeshValidationCode.BUDGET_REQUIRED, "approved budget required for spend:money")
        val requested = raw.toBigDecimalOrNull()?.takeIf { it >= BigDecimal.ZERO }
            ?: throw MeshValidationException(MeshValidationCode.BUDGET_REQUIRED, "approved budget required for spend:money")
        if (requested > approved) {
            throw MeshValidationException(MeshValidationCode.BUDGET_EXCEEDED, "requested spend exceeds approved budget")
        }
    }

    private fun String.toBigDecimalOrNull(): BigDecimal? = try {
        BigDecimal(this)
    } catch (e: NumberFormatException) {
        null
    }
}

data class MeshAuditEvent(
    val requestId: String,
    val callerAppId: String,
    val targetBundleId: String,
    val capabilityId: String,
    val risk: String,
    val consent: String,
    val status: String
) {
    companion object {
        fun accepted(request: MeshRequest, policy: MeshInvocationPolicy): MeshAuditEvent = MeshAuditEvent(
            requestId = request.requestId,
            callerAppId = request.caller.appId,
            targetBundleId = request.target.targetBundleId,
            capabilityId = request.target.capabilityId,
            risk = policy.risk,
            consent = policy.consent,
            status = "accepted"
        )
    }
}

/** Reserve-once nonce store; the target keeps it per capability. */
fun interface MeshReplayCache {
    /** Returns true when the nonce was fresh and is now reserved. */
    fun reserve(nonce: String): Boolean
}
