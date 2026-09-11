package ai.meshkit.transport

import android.content.Context
import android.content.Intent
import androidx.activity.result.contract.ActivityResultContract
import ai.meshkit.core.MeshReceipt
import ai.meshkit.core.MeshRequest
import ai.meshkit.core.OcgAndroidBinding

/** Explicit-intent invocation of one OCG capability on a target package. */
data class MeshInvocation(
    val request: MeshRequest,
    val targetPackage: String,
    val binding: OcgAndroidBinding
)

sealed interface MeshInvocationResult {
    /** Target returned a receipt envelope; verify it before trusting it. */
    data class ReceiptReturned(val receipt: MeshReceipt) : MeshInvocationResult

    /** User dismissed the target before consent — never completion proof. */
    data object Dismissed : MeshInvocationResult

    /** Result intent existed but carried no decodable receipt. */
    data class Invalid(val reason: String) : MeshInvocationResult
}

/**
 * Caller-side transport. Launch with a signed [MeshInvocation]; the result is
 * the raw transport outcome only — callers MUST run
 * `MeshReceiptVerifier.verifyCorrelated` against the original request before
 * accepting completion (same rule as HermesChat on iOS).
 */
class MeshCaller : ActivityResultContract<MeshInvocation, MeshInvocationResult>() {

    override fun createIntent(context: Context, input: MeshInvocation): Intent =
        Intent(input.binding.action).apply {
            setClassName(input.targetPackage, input.binding.targetActivity)
            putExtra(MeshIntentContract.EXTRA_MESH_REQUEST, input.request.encodedForEnvelope())
        }

    override fun parseResult(resultCode: Int, intent: Intent?): MeshInvocationResult {
        if (resultCode != android.app.Activity.RESULT_OK) return MeshInvocationResult.Dismissed
        val envelope = intent?.getStringExtra(MeshIntentContract.EXTRA_MESH_RECEIPT)
            ?: return MeshInvocationResult.Invalid("missing ${MeshIntentContract.EXTRA_MESH_RECEIPT} extra")
        return try {
            MeshInvocationResult.ReceiptReturned(MeshReceipt.decodedFromEnvelope(envelope))
        } catch (e: Exception) {
            MeshInvocationResult.Invalid(e.message ?: "undecodable mesh_receipt")
        }
    }
}
