package ai.meshkit.core

/**
 * Phase 2 exposure policy: which OCG capabilities a target may publish into
 * the Android AppFunctions registry (`androidx.appfunctions`), where the
 * caller is the platform assistant and carries NO MeshKit-signed request.
 *
 * Rules:
 * - `spend:money` is never exposed — without a signed request and budget
 *   mandate there is no trust object to anchor a payment to. Targets may
 *   instead expose a `read_only` draft variant (e.g.
 *   `grocery.prepare_essentials_cart`) whose confirmation still requires the
 *   signed intent path.
 * - Everything executed via AppFunctions still routes through the target's
 *   own consent gates and mints a target-signed receipt with caller trust
 *   class [CALLER_TRUST_CLASS_PLATFORM_ASSISTANT], so the audit layer stays
 *   uniform across transports.
 */
object MeshAppFunctionGate {
    const val CALLER_TRUST_CLASS_PLATFORM_ASSISTANT = "platform_assistant"

    private val exposableRisks = setOf("read_only", "write:user_content")

    fun isExposable(capability: OcgCapability): Boolean = capability.risk in exposableRisks

    fun exposableCapabilities(graph: OpenCapabilityGraph): List<OcgCapability> =
        graph.apps.flatMap { it.capabilities }.filter { isExposable(it) }

    fun requireExposable(capability: OcgCapability) {
        if (!isExposable(capability)) {
            throw MeshValidationException(
                MeshValidationCode.CONSENT_REQUIRED,
                "capability ${capability.id} (risk ${capability.risk}) must not be exposed via AppFunctions"
            )
        }
    }
}
