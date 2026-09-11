package ai.meshkit.core

import kotlinx.serialization.Serializable

/** Android invocation binding declared in an OCG manifest (`capabilities[].android`). */
@Serializable
data class OcgAndroidBinding(
    val action: String = "ai.meshkit.action.INVOKE_CAPABILITY",
    val targetActivity: String
)

@Serializable
data class OcgCapability(
    val id: String,
    val displayName: String,
    val risk: String,
    val consent: String,
    val urlScheme: String? = null,
    val android: OcgAndroidBinding? = null,
    val inputSchema: List<String> = emptyList(),
    val resultSchema: List<String> = emptyList()
)

@Serializable
data class OcgApp(
    val appId: String,
    val ocgAppId: String? = null,
    val displayName: String,
    val bundleId: String,
    val publisher: String,
    val capabilities: List<OcgCapability>
)

@Serializable
data class OpenCapabilityGraph(
    val schemaVersion: String,
    val apps: List<OcgApp>
) {
    fun findCapability(capabilityId: String): OcgCapability? =
        apps.flatMap { it.capabilities }.firstOrNull { it.id == capabilityId }

    fun acpRegistryDescriptors(): List<AcpAppDescriptor> = apps.map { app ->
        val slug = app.appId.replace("app.", "").lowercase()
        val hasAndroidBinding = app.capabilities.any { it.android != null }
        AcpAppDescriptor(
            schemaVersion = "meshkit-acp-superapp/v1",
            appId = app.appId,
            ocgAppId = app.ocgAppId ?: app.appId,
            displayName = app.displayName,
            publisher = app.publisher,
            acpEndpoint = "acp://$slug/apps",
            mcpTransport = if (hasAndroidBinding) "app-to-app-intent" else "app-to-app-url-scheme",
            bundleId = app.bundleId,
            platform = if (hasAndroidBinding) "android-demo" else "ios-demo",
            registrySource = "meshkit-android-sample",
            capabilities = app.capabilities.map { AcpCapabilityDescriptor.from(it) }
        )
    }
}

@Serializable
data class AcpCapabilityDescriptor(
    val id: String,
    val displayName: String,
    val risk: String,
    val consent: String,
    val requiresPayment: Boolean,
    val asset: String? = null,
    val urlScheme: String? = null,
    val androidAction: String? = null,
    val inputSchema: List<String>,
    val resultSchema: List<String>,
    val routingHint: String
) {
    companion object {
        fun from(capability: OcgCapability): AcpCapabilityDescriptor {
            val requiresPayment = capability.risk == "spend:money"
            return AcpCapabilityDescriptor(
                id = capability.id,
                displayName = capability.displayName,
                risk = capability.risk,
                consent = capability.consent,
                requiresPayment = requiresPayment,
                asset = if (requiresPayment) "OKRW" else null,
                urlScheme = capability.urlScheme,
                androidAction = capability.android?.action,
                inputSchema = capability.inputSchema,
                resultSchema = capability.resultSchema,
                routingHint = if (requiresPayment) "onchain_payment" else "offchain_app_call"
            )
        }
    }
}

@Serializable
data class AcpAppDescriptor(
    val schemaVersion: String,
    val appId: String,
    val ocgAppId: String,
    val displayName: String,
    val publisher: String,
    val acpEndpoint: String,
    val mcpTransport: String,
    val bundleId: String,
    val platform: String,
    val registrySource: String,
    val capabilities: List<AcpCapabilityDescriptor>
)
