package ai.meshkit.core

import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.JsonObject

data class MeshRequest(
    val requestId: String,
    val caller: MeshIdentity,
    val target: MeshCapability,
    val payload: Map<String, String>,
    val payloadHash: MeshPayloadHash,
    val nonce: String,
    val timestamp: String,
    val signature: MeshSignature
) {
    companion object {
        const val SIGNING_VERSION = "meshkit-request-signing/v1"
        const val ENVELOPE_EXTRA = "mesh_request"

        fun create(
            requestId: String,
            caller: MeshIdentity,
            target: MeshCapability,
            payload: Map<String, String>,
            nonce: String,
            timestamp: String,
            signature: MeshSignature
        ): MeshRequest = MeshRequest(
            requestId = requestId,
            caller = caller,
            target = target,
            payload = payload,
            payloadHash = MeshRequestPayloadHasher.hash(payload, nonce),
            nonce = nonce,
            timestamp = timestamp,
            signature = signature
        )

        fun decodedFromEnvelope(encoded: String): MeshRequest {
            val root = MeshJson.decodeBase64(encoded, "mesh_request")
            val caller = MeshJson.requireObject(root, "caller", "mesh_request")
            val target = MeshJson.requireObject(root, "target", "mesh_request")
            val payloadHash = MeshJson.requireObject(root, "payloadHash", "mesh_request")
            val signature = MeshJson.requireObject(root, "signature", "mesh_request")
            return MeshRequest(
                requestId = MeshJson.requireString(root, "requestId", "mesh_request"),
                caller = MeshIdentity(
                    appId = MeshJson.requireString(caller, "appId", "mesh_request.caller"),
                    installId = MeshJson.requireString(caller, "installId", "mesh_request.caller"),
                    bundleId = MeshJson.requireString(caller, "bundleId", "mesh_request.caller"),
                    publicKeyId = MeshJson.requireString(caller, "publicKeyId", "mesh_request.caller")
                ),
                target = MeshCapability(
                    targetBundleId = MeshJson.requireString(target, "targetBundleId", "mesh_request.target"),
                    capabilityId = MeshJson.requireString(target, "capabilityId", "mesh_request.target"),
                    version = MeshJson.requireString(target, "version", "mesh_request.target")
                ),
                payload = MeshJson.requireStringMap(root, "payload", "mesh_request"),
                payloadHash = MeshPayloadHash(
                    algorithm = MeshJson.requireString(payloadHash, "algorithm", "mesh_request.payloadHash"),
                    value = MeshJson.requireString(payloadHash, "value", "mesh_request.payloadHash")
                ),
                nonce = MeshJson.requireString(root, "nonce", "mesh_request"),
                timestamp = MeshJson.requireString(root, "timestamp", "mesh_request"),
                signature = MeshSignature(
                    algorithm = MeshJson.requireString(signature, "algorithm", "mesh_request.signature"),
                    keyId = MeshJson.requireString(signature, "keyId", "mesh_request.signature"),
                    value = MeshJson.requireString(signature, "value", "mesh_request.signature")
                )
            )
        }
    }

    fun signingInput(): String = listOf(
        SIGNING_VERSION,
        requestId,
        caller.appId,
        caller.bundleId,
        caller.publicKeyId,
        target.targetBundleId,
        target.capabilityId,
        target.version,
        payloadHash.algorithm.lowercase(),
        payloadHash.value.lowercase(),
        timestamp,
        nonce
    ).joinToString("\n")

    fun signingInputData(): ByteArray = signingInput().toByteArray(Charsets.UTF_8)

    fun encodedForEnvelope(): String = MeshJson.encodeBase64(toJsonObject())

    private fun toJsonObject(): JsonObject {
        val entries = mapOf<String, JsonElement>(
            "caller" to MeshJson.sortedObject(
                mapOf(
                    "appId" to JsonPrimitive(caller.appId),
                    "bundleId" to JsonPrimitive(caller.bundleId),
                    "installId" to JsonPrimitive(caller.installId),
                    "publicKeyId" to JsonPrimitive(caller.publicKeyId)
                )
            ),
            "nonce" to JsonPrimitive(nonce),
            "payload" to MeshJson.stringMapObject(payload),
            "payloadHash" to MeshJson.sortedObject(
                mapOf(
                    "algorithm" to JsonPrimitive(payloadHash.algorithm),
                    "value" to JsonPrimitive(payloadHash.value)
                )
            ),
            "requestId" to JsonPrimitive(requestId),
            "signature" to MeshJson.sortedObject(
                mapOf(
                    "algorithm" to JsonPrimitive(signature.algorithm),
                    "keyId" to JsonPrimitive(signature.keyId),
                    "value" to JsonPrimitive(signature.value)
                )
            ),
            "target" to MeshJson.sortedObject(
                mapOf(
                    "capabilityId" to JsonPrimitive(target.capabilityId),
                    "targetBundleId" to JsonPrimitive(target.targetBundleId),
                    "version" to JsonPrimitive(target.version)
                )
            ),
            "timestamp" to JsonPrimitive(timestamp)
        )
        return MeshJson.sortedObject(entries)
    }
}
