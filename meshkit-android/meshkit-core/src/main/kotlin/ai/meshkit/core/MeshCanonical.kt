package ai.meshkit.core

import java.security.MessageDigest

/**
 * Canonical byte forms shared with the Swift SDK. Wire contract:
 * `meshkit-payload-hash/v1` — sorted `key=value&...` pairs, every byte outside
 * ASCII alphanumerics percent-escaped as uppercase-hex UTF-8.
 */
object MeshRequestPayloadHasher {
    const val ALGORITHM = "sha256"
    const val NONCE_BOUND_VERSION = "meshkit-payload-hash/v1"

    fun escape(value: String): String = buildString {
        for (byte in value.toByteArray(Charsets.UTF_8)) {
            val b = byte.toInt() and 0xFF
            val alphanumeric = b in 0x30..0x39 || b in 0x41..0x5A || b in 0x61..0x7A
            if (alphanumeric) append(b.toChar()) else append('%').append("%02X".format(b))
        }
    }

    fun canonicalString(payload: Map<String, String>): String =
        payload.keys.sorted().joinToString("&") { key ->
            "${escape(key)}=${escape(payload.getValue(key))}"
        }

    fun canonicalData(payload: Map<String, String>): ByteArray =
        canonicalString(payload).toByteArray(Charsets.UTF_8)

    fun canonicalString(payload: Map<String, String>, nonce: String): String =
        listOf(
            NONCE_BOUND_VERSION,
            "nonce=${escape(nonce)}",
            "payload=${canonicalString(payload)}"
        ).joinToString("\n")

    fun canonicalData(payload: Map<String, String>, nonce: String): ByteArray =
        canonicalString(payload, nonce).toByteArray(Charsets.UTF_8)

    fun sha256Hex(payload: Map<String, String>): String = sha256Hex(canonicalData(payload))

    fun sha256Hex(payload: Map<String, String>, nonce: String): String =
        sha256Hex(canonicalData(payload, nonce))

    fun hash(payload: Map<String, String>, nonce: String): MeshPayloadHash =
        MeshPayloadHash(ALGORITHM, sha256Hex(payload, nonce))

    private fun sha256Hex(data: ByteArray): String =
        MessageDigest.getInstance("SHA-256").digest(data).joinToString("") { "%02x".format(it) }
}
