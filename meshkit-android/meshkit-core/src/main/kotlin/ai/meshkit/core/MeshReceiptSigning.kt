package ai.meshkit.core

import java.time.Instant
import java.time.format.DateTimeParseException
import java.util.Base64
import kotlin.math.abs

data class MeshReceiptTrust(
    val targetAppId: String,
    val targetBundleId: String,
    val receiptSigningAlgorithm: String,
    val receiptSigningKeyId: String,
    val publicKeyBase64: String
)

class MeshReceiptSigner(
    val algorithm: String,
    val keyId: String,
    private val signData: (ByteArray) -> ByteArray
) {
    companion object {
        fun ed25519(keyId: String, seed: ByteArray): MeshReceiptSigner {
            val key = Ed25519Jvm.privateKeyFromSeed(seed)
            return MeshReceiptSigner("Ed25519", keyId) { data -> Ed25519Jvm.sign(data, key) }
        }
    }

    fun makeReceipt(
        receiptId: String,
        request: MeshRequest,
        targetAppId: String,
        targetBundleId: String,
        status: String,
        result: Map<String, String>,
        nonce: String,
        timestamp: String
    ): MeshReceipt {
        val unsigned = MeshReceipt(
            receiptId = receiptId,
            requestId = request.requestId,
            capabilityId = request.target.capabilityId,
            targetAppId = targetAppId,
            targetBundleId = targetBundleId,
            requestPayloadHash = request.payloadHash,
            status = status,
            result = result,
            nonce = nonce,
            timestamp = timestamp,
            signature = MeshSignature(algorithm, keyId, "")
        )
        val signatureValue = Base64.getEncoder().encodeToString(signData(unsigned.signingInputData()))
        return unsigned.copy(signature = MeshSignature(algorithm, keyId, signatureValue))
    }
}

object MeshReceiptVerifier {
    fun verify(
        receipt: MeshReceipt,
        trust: MeshReceiptTrust,
        maxAgeSeconds: Long = MeshTarget.DEFAULT_MAX_AGE_SECONDS,
        now: Instant = Instant.now(),
        verifier: MeshSignatureVerifier = Ed25519Jvm.rawKeyVerifier
    ): MeshReceipt {
        validateEnvelope(receipt)
        if (receipt.targetAppId != trust.targetAppId || receipt.targetBundleId != trust.targetBundleId) {
            throw MeshValidationException(MeshValidationCode.TARGET_IDENTITY_MISMATCH, "target identity mismatch")
        }
        if (receipt.signature.algorithm != trust.receiptSigningAlgorithm) {
            throw MeshValidationException(MeshValidationCode.SIGNATURE_MISMATCH, "receipt signing algorithm mismatch")
        }
        if (receipt.signature.keyId != trust.receiptSigningKeyId) {
            throw MeshValidationException(MeshValidationCode.SIGNATURE_MISMATCH, "receipt signing key id mismatch")
        }
        if (trust.receiptSigningAlgorithm != "Ed25519") {
            throw MeshValidationException(
                MeshValidationCode.SIGNATURE_MISMATCH,
                "unsupported receipt signing algorithm: ${trust.receiptSigningAlgorithm}"
            )
        }
        val timestamp = try {
            Instant.parse(receipt.timestamp)
        } catch (e: DateTimeParseException) {
            throw MeshValidationException(MeshValidationCode.STALE_TIMESTAMP, "stale request timestamp")
        }
        if (abs(timestamp.epochSecond - now.epochSecond) > maxAgeSeconds) {
            throw MeshValidationException(MeshValidationCode.STALE_TIMESTAMP, "stale request timestamp")
        }
        val publicKeyRaw = Ed25519Jvm.decodeBase64(trust.publicKeyBase64)?.takeIf { it.isNotEmpty() }
            ?: throw MeshValidationException(MeshValidationCode.SIGNATURE_REQUIRED, "request signature is required")
        val signatureBytes = Ed25519Jvm.decodeBase64(receipt.signature.value)?.takeIf { it.isNotEmpty() }
            ?: throw MeshValidationException(MeshValidationCode.SIGNATURE_MISMATCH, "receipt signature is not valid base64")
        val valid = try {
            verifier.verify(receipt.signingInputData(), signatureBytes, publicKeyRaw)
        } catch (e: Exception) {
            throw MeshValidationException(MeshValidationCode.SIGNATURE_MISMATCH, "invalid receipt signing public key")
        }
        if (!valid) {
            throw MeshValidationException(MeshValidationCode.SIGNATURE_MISMATCH, "invalid receipt signature")
        }
        return receipt
    }

    /** Caller-side correlation: the receipt must answer this exact request. */
    fun verifyCorrelated(
        receipt: MeshReceipt,
        request: MeshRequest,
        trust: MeshReceiptTrust,
        maxAgeSeconds: Long = MeshTarget.DEFAULT_MAX_AGE_SECONDS,
        now: Instant = Instant.now()
    ): MeshReceipt {
        verify(receipt, trust, maxAgeSeconds, now)
        val correlated = receipt.requestId == request.requestId &&
            receipt.capabilityId == request.target.capabilityId &&
            receipt.targetBundleId == request.target.targetBundleId &&
            receipt.requestPayloadHash.value.equals(request.payloadHash.value, ignoreCase = true)
        if (!correlated) {
            throw MeshValidationException(
                MeshValidationCode.RECEIPT_CORRELATION_MISMATCH,
                "target receipt does not match a pending request token"
            )
        }
        return receipt
    }

    private fun validateEnvelope(receipt: MeshReceipt) {
        MeshTarget.requireSecurityField("receiptId", receipt.receiptId)
        MeshTarget.requireSecurityField("requestId", receipt.requestId)
        MeshTarget.requireSecurityField("capabilityId", receipt.capabilityId)
        MeshTarget.requireSecurityField("targetAppId", receipt.targetAppId)
        MeshTarget.requireSecurityField("targetBundleId", receipt.targetBundleId)
        MeshTarget.requireSecurityField("status", receipt.status)
        MeshTarget.requireSecurityField("timestamp", receipt.timestamp)
        MeshTarget.requireSecurityField("nonce", receipt.nonce)
    }
}
