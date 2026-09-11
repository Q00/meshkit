package ai.meshkit.core

import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import java.util.Base64

/**
 * Envelope JSON helpers. The Swift SDK encodes envelopes as sorted-keys JSON
 * then base64; signatures cover the newline-joined signing input, not the
 * envelope bytes, so cross-platform compatibility requires sorted keys and
 * lossless values — not byte-identical JSON escaping.
 */
internal object MeshJson {
    val json = Json { ignoreUnknownKeys = false }

    fun sortedObject(entries: Map<String, JsonElement>): JsonObject =
        buildJsonObject { entries.toSortedMap().forEach { (key, value) -> put(key, value) } }

    fun stringMapObject(map: Map<String, String>): JsonObject =
        sortedObject(map.mapValues { JsonPrimitive(it.value) })

    fun encodeBase64(obj: JsonObject): String =
        Base64.getEncoder().encodeToString(obj.toString().toByteArray(Charsets.UTF_8))

    fun decodeBase64(encoded: String, what: String): JsonObject {
        val data = try {
            Base64.getDecoder().decode(encoded)
        } catch (e: IllegalArgumentException) {
            throw MeshValidationException(MeshValidationCode.INVALID_ENCODING, "$what is not valid base64")
        }
        val element = try {
            json.parseToJsonElement(String(data, Charsets.UTF_8))
        } catch (e: Exception) {
            throw MeshValidationException(MeshValidationCode.INVALID_ENCODING, "$what is not valid JSON")
        }
        return element as? JsonObject
            ?: throw MeshValidationException(MeshValidationCode.INVALID_ENCODING, "$what root is not an object")
    }

    fun requireString(obj: JsonObject, key: String, what: String): String {
        val element = obj[key]
            ?: throw MeshValidationException(MeshValidationCode.INVALID_ENCODING, "$what.$key is missing")
        val primitive = element as? JsonPrimitive
        if (primitive == null || !primitive.isString) {
            throw MeshValidationException(MeshValidationCode.INVALID_ENCODING, "$what.$key is not a string")
        }
        return primitive.content
    }

    fun requireObject(obj: JsonObject, key: String, what: String): JsonObject =
        obj[key]?.jsonObject
            ?: throw MeshValidationException(MeshValidationCode.INVALID_ENCODING, "$what.$key is not an object")

    fun requireStringMap(obj: JsonObject, key: String, what: String): Map<String, String> =
        requireObject(obj, key, what).entries.associate { (k, v) ->
            val primitive = v as? JsonPrimitive
            if (primitive == null || !primitive.isString) {
                throw MeshValidationException(MeshValidationCode.INVALID_ENCODING, "$what.$key[$k] is not a string")
            }
            k to primitive.content
        }
}
