package ai.meshkit.core

import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFailsWith
import kotlin.test.assertTrue

class MeshAppFunctionGateTest {

    private fun capability(id: String, risk: String) = OcgCapability(
        id = id,
        displayName = id,
        risk = risk,
        consent = if (risk == "spend:money") "budgeted_per_invocation" else "per_invocation"
    )

    @Test
    fun `spend money capabilities are never exposable`() {
        val purchase = capability("grocery.purchase_essentials", "spend:money")
        assertTrue(!MeshAppFunctionGate.isExposable(purchase))
        val error = assertFailsWith<MeshValidationException> {
            MeshAppFunctionGate.requireExposable(purchase)
        }
        assertEquals(MeshValidationCode.CONSENT_REQUIRED, error.code)
    }

    @Test
    fun `read only and user content capabilities are exposable`() {
        assertTrue(MeshAppFunctionGate.isExposable(capability("grocery.prepare_essentials_cart", "read_only")))
        assertTrue(MeshAppFunctionGate.isExposable(capability("notes.append_note", "write:user_content")))
    }

    @Test
    fun `graph filtering keeps only exposable capabilities`() {
        val graph = OpenCapabilityGraph(
            schemaVersion = "0.1",
            apps = listOf(
                OcgApp(
                    appId = "app.dailymart",
                    displayName = "DailyMart",
                    bundleId = "ai.meshkit.sample.dailymart",
                    publisher = "MeshKit Samples",
                    capabilities = listOf(
                        capability("grocery.purchase_essentials", "spend:money"),
                        capability("grocery.prepare_essentials_cart", "read_only")
                    )
                )
            )
        )
        assertEquals(
            listOf("grocery.prepare_essentials_cart"),
            MeshAppFunctionGate.exposableCapabilities(graph).map { it.id }
        )
    }
}
