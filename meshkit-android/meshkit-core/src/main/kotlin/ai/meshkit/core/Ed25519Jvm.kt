package ai.meshkit.core

import java.security.KeyFactory
import java.security.PrivateKey
import java.security.PublicKey
import java.security.Signature
import java.security.spec.PKCS8EncodedKeySpec
import java.security.spec.X509EncodedKeySpec
import java.util.Base64

fun interface MeshRequestSigner {
    fun sign(data: ByteArray): ByteArray
}

fun interface MeshSignatureVerifier {
    fun verify(data: ByteArray, signature: ByteArray, publicKeyRaw: ByteArray): Boolean
}

/**
 * Ed25519 via `java.security` (JDK 15+ / Android 13+ Keystore for on-device
 * keys). The wire format uses raw 32-byte public keys and 64-byte signatures,
 * matching CryptoKit's `rawRepresentation`; this object wraps/unwraps the
 * DER framing the JCA requires.
 */
object Ed25519Jvm {
    // RFC 8410 SubjectPublicKeyInfo prefix for Ed25519 (OID 1.3.101.112).
    private val SPKI_PREFIX = byteArrayOf(
        0x30, 0x2a, 0x30, 0x05, 0x06, 0x03, 0x2b, 0x65, 0x70, 0x03, 0x21, 0x00
    )

    // RFC 8410 PKCS#8 prefix wrapping the 32-byte seed as CurvePrivateKey.
    private val PKCS8_PREFIX = byteArrayOf(
        0x30, 0x2e, 0x02, 0x01, 0x00, 0x30, 0x05, 0x06, 0x03, 0x2b, 0x65, 0x70,
        0x04, 0x22, 0x04, 0x20
    )

    fun publicKeyFromRaw(raw: ByteArray): PublicKey {
        require(raw.size == 32) { "Ed25519 raw public key must be 32 bytes" }
        val spec = X509EncodedKeySpec(SPKI_PREFIX + raw)
        return KeyFactory.getInstance("Ed25519").generatePublic(spec)
    }

    fun privateKeyFromSeed(seed: ByteArray): PrivateKey {
        require(seed.size == 32) { "Ed25519 seed must be 32 bytes" }
        val spec = PKCS8EncodedKeySpec(PKCS8_PREFIX + seed)
        return KeyFactory.getInstance("Ed25519").generatePrivate(spec)
    }

    fun sign(data: ByteArray, privateKey: PrivateKey): ByteArray {
        val signature = Signature.getInstance("Ed25519")
        signature.initSign(privateKey)
        signature.update(data)
        return signature.sign()
    }

    fun verify(data: ByteArray, signatureBytes: ByteArray, publicKey: PublicKey): Boolean {
        val signature = Signature.getInstance("Ed25519")
        signature.initVerify(publicKey)
        signature.update(data)
        return try {
            signature.verify(signatureBytes)
        } catch (e: java.security.SignatureException) {
            false
        }
    }

    fun signerFromSeed(seed: ByteArray): MeshRequestSigner {
        val key = privateKeyFromSeed(seed)
        return MeshRequestSigner { data -> sign(data, key) }
    }

    val rawKeyVerifier: MeshSignatureVerifier = MeshSignatureVerifier { data, signatureBytes, publicKeyRaw ->
        verify(data, signatureBytes, publicKeyFromRaw(publicKeyRaw))
    }

    fun decodeBase64(value: String): ByteArray? = try {
        Base64.getDecoder().decode(value)
    } catch (e: IllegalArgumentException) {
        null
    }
}
