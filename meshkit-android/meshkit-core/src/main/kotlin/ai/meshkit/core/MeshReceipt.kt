package ai.meshkit.core

import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.JsonObject

data class MeshReceipt(
    val receiptId: String,
    val requestId: String,
    val capabilityId: String,
    val targetAppId: String,
    val targetBundleId: String,
    val requestPayloadHash: MeshPayloadHash,
    val status: String,
    val result: Map<String, String>,
    val nonce: String,
    val timestamp: String,
    val signature: MeshSignature
) {
    companion object {
        const val SIGNING_VERSION = "meshkit-target-receipt-signing/v1"
        const val ENVELOPE_EXTRA = "mesh_receipt"

        fun canonicalResultString(result: Map<String, String>): String =
            result.keys.sorted().joinToString("&") { key ->
                "${MeshRequestPayloadHasher.escape(key)}=${MeshRequestPayloadHasher.escape(result.getValue(key))}"
            }

        fun decodedFromEnvelope(encoded: String): MeshReceipt {
            val root = MeshJson.decodeBase64(encoded, "mesh_receipt")
            val payloadHash = MeshJson.requireObject(root, "requestPayloadHash", "mesh_receipt")
            val signature = MeshJson.requireObject(root, "signature", "mesh_receipt")
            return MeshReceipt(
                receiptId = MeshJson.requireString(root, "receiptId", "mesh_receipt"),
                requestId = MeshJson.requireString(root, "requestId", "mesh_receipt"),
                capabilityId = MeshJson.requireString(root, "capabilityId", "mesh_receipt"),
                targetAppId = MeshJson.requireString(root, "targetAppId", "mesh_receipt"),
                targetBundleId = MeshJson.requireString(root, "targetBundleId", "mesh_receipt"),
                requestPayloadHash = MeshPayloadHash(
                    algorithm = MeshJson.requireString(payloadHash, "algorithm", "mesh_receipt.requestPayloadHash"),
                    value = MeshJson.requireString(payloadHash, "value", "mesh_receipt.requestPayloadHash")
                ),
                status = MeshJson.requireString(root, "status", "mesh_receipt"),
                result = MeshJson.requireStringMap(root, "result", "mesh_receipt"),
                nonce = MeshJson.requireString(root, "nonce", "mesh_receipt"),
                timestamp = MeshJson.requireString(root, "timestamp", "mesh_receipt"),
                signature = MeshSignature(
                    algorithm = MeshJson.requireString(signature, "algorithm", "mesh_receipt.signature"),
                    keyId = MeshJson.requireString(signature, "keyId", "mesh_receipt.signature"),
                    value = MeshJson.requireString(signature, "value", "mesh_receipt.signature")
                )
            )
        }
    }

    fun signingInput(): String = listOf(
        SIGNING_VERSION,
        receiptId,
        requestId,
        capabilityId,
        targetAppId,
        targetBundleId,
        requestPayloadHash.algorithm.lowercase(),
        requestPayloadHash.value.lowercase(),
        status,
        canonicalResultString(result),
        timestamp,
        nonce
    ).joinToString("\n")

    fun signingInputData(): ByteArray = signingInput().toByteArray(Charsets.UTF_8)

    fun encodedForEnvelope(): String = MeshJson.encodeBase64(toJsonObject())

    private fun toJsonObject(): JsonObject {
        val entries = mapOf<String, JsonElement>(
            "capabilityId" to JsonPrimitive(capabilityId),
            "nonce" to JsonPrimitive(nonce),
            "receiptId" to JsonPrimitive(receiptId),
            "requestId" to JsonPrimitive(requestId),
            "requestPayloadHash" to MeshJson.sortedObject(
                mapOf(
                    "algorithm" to JsonPrimitive(requestPayloadHash.algorithm),
                    "value" to JsonPrimitive(requestPayloadHash.value)
                )
            ),
            "result" to MeshJson.stringMapObject(result),
            "signature" to MeshJson.sortedObject(
                mapOf(
                    "algorithm" to JsonPrimitive(signature.algorithm),
                    "keyId" to JsonPrimitive(signature.keyId),
                    "value" to JsonPrimitive(signature.value)
                )
            ),
            "status" to JsonPrimitive(status),
            "targetAppId" to JsonPrimitive(targetAppId),
            "targetBundleId" to JsonPrimitive(targetBundleId),
            "timestamp" to JsonPrimitive(timestamp)
        )
        return MeshJson.sortedObject(entries)
    }
}
