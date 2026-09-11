package ai.meshkit.core

import kotlinx.serialization.json.Json
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import java.io.File
import kotlin.test.Test
import kotlin.test.assertTrue

/**
 * Exports Kotlin-signed envelopes for the reverse wire-compat direction:
 * `scripts/verify_android_wire_compat.sh` feeds the output to
 * `wire-vectors-gen cross-verify`, which makes the Swift SDK verify the
 * Kotlin request and receipt signatures.
 */
class CrossSignExportTest {

    @Test
    fun `export kotlin-signed envelopes for swift cross-verification`() {
        val vectorsPath = System.getProperty("meshkit.vectors") ?: "../vectors/wire-compat.v1.json"
        val outPath = System.getProperty("meshkit.crosssign.out") ?: "build/kotlin-signed.v1.json"

        val root = Json.parseToJsonElement(File(vectorsPath).readText()).jsonObject
        val requestSeed = root.getValue("requestSignerSeedHex").jsonPrimitive.content
            .chunked(2).map { it.toInt(16).toByte() }.toByteArray()
        val receiptSeed = root.getValue("receiptSignerSeedHex").jsonPrimitive.content
            .chunked(2).map { it.toInt(16).toByte() }.toByteArray()
        val receiptKeyId = root.getValue("receiptSignerKeyId").jsonPrimitive.content

        val cases = root.getValue("cases").jsonArray.map { case ->
            val obj = case.jsonObject
            val name = obj.getValue("name").jsonPrimitive.content
            val request = MeshRequest.decodedFromEnvelope(
                obj.getValue("requestEnvelopeBase64").jsonPrimitive.content
            )
            val receipt = MeshReceipt.decodedFromEnvelope(
                obj.getValue("receiptEnvelopeBase64").jsonPrimitive.content
            )

            val kotlinSignedRequest = MeshSignedRequestCrypto.sign(
                request.copy(signature = MeshSignature("Ed25519", request.signature.keyId, "")),
                Ed25519Jvm.signerFromSeed(requestSeed),
                keyId = request.signature.keyId
            )
            val kotlinSignedReceipt = MeshReceiptSigner.ed25519(receiptKeyId, receiptSeed).makeReceipt(
                receiptId = receipt.receiptId,
                request = kotlinSignedRequest,
                targetAppId = receipt.targetAppId,
                targetBundleId = receipt.targetBundleId,
                status = receipt.status,
                result = receipt.result,
                nonce = receipt.nonce,
                timestamp = receipt.timestamp
            )
            Triple(name, kotlinSignedRequest.encodedForEnvelope(), kotlinSignedReceipt.encodedForEnvelope())
        }

        val payload = buildString {
            append("{\"cases\":[")
            cases.forEachIndexed { index, (name, requestEnvelope, receiptEnvelope) ->
                if (index > 0) append(',')
                append("{\"name\":\"").append(name).append("\",")
                append("\"requestEnvelopeBase64\":\"").append(requestEnvelope).append("\",")
                append("\"receiptEnvelopeBase64\":\"").append(receiptEnvelope).append("\"}")
            }
            append("]}")
        }
        val outFile = File(outPath)
        outFile.parentFile?.mkdirs()
        outFile.writeText(payload)
        assertTrue(outFile.length() > 0)
    }
}
