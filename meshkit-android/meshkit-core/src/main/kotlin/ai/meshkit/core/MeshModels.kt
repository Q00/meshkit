package ai.meshkit.core

import kotlinx.serialization.Serializable

@Serializable
data class MeshIdentity(
    val appId: String,
    val installId: String,
    val bundleId: String,
    val publicKeyId: String
)

@Serializable
data class MeshCapability(
    val targetBundleId: String,
    val capabilityId: String,
    val version: String
)

@Serializable
data class MeshSignature(
    val algorithm: String,
    val keyId: String,
    val value: String
)

@Serializable
data class MeshPayloadHash(
    val algorithm: String = "sha256",
    val value: String
)
