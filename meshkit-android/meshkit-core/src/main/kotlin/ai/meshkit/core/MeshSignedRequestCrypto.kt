package ai.meshkit.core

import java.util.Base64

/** Caller-side signing facade for App-to-App MCP requests. */
object MeshSignedRequestCrypto {
    fun sign(
        unsigned: MeshRequest,
        signer: MeshRequestSigner,
        algorithm: String = "Ed25519",
        keyId: String
    ): MeshRequest {
        val withKey = unsigned.copy(signature = MeshSignature(algorithm, keyId, ""))
        val signatureValue = Base64.getEncoder().encodeToString(signer.sign(withKey.signingInputData()))
        return withKey.copy(signature = MeshSignature(algorithm, keyId, signatureValue))
    }

    fun verify(request: MeshRequest, trust: MeshSenderTrust) {
        MeshTarget.verifyRequiredSignature(request, trust)
    }
}
