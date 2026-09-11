package ai.meshkit.transport

import android.app.Activity
import android.content.Intent
import ai.meshkit.core.MeshInvocationPolicy
import ai.meshkit.core.MeshReceipt
import ai.meshkit.core.MeshReceiptSigner
import ai.meshkit.core.MeshReplayCache
import ai.meshkit.core.MeshRequest
import ai.meshkit.core.MeshSenderTrust
import ai.meshkit.core.MeshTarget
import ai.meshkit.core.MeshTargetPolicy
import ai.meshkit.core.MeshValidationException

/**
 * Target-side transport delegate. The hosting invoke activity owns UI and
 * consent; this delegate owns the fail-closed validation order and the
 * receipt round-trip. Mirrors the iOS target flow: decode -> observe caller
 * -> verify -> consent -> execute -> target-signed receipt.
 */
class MeshTargetActivityDelegate(
    private val policy: MeshTargetPolicy,
    private val trust: MeshSenderTrust,
    private val replayCache: MeshReplayCache,
    private val receiptSigner: MeshReceiptSigner,
    private val targetAppId: String,
    private val targetBundleId: String
) {

    fun decodeRequest(intent: Intent): MeshRequest {
        val envelope = intent.getStringExtra(MeshIntentContract.EXTRA_MESH_REQUEST)
            ?: throw MeshValidationException(
                ai.meshkit.core.MeshValidationCode.INVALID_ENCODING,
                "missing ${MeshIntentContract.EXTRA_MESH_REQUEST} extra"
            )
        return MeshRequest.decodedFromEnvelope(envelope)
    }

    /**
     * Full fail-closed acceptance. Call AFTER user consent has been captured
     * into [invocationPolicy] (`userApproved`, `approvedBudget`); throws
     * [MeshValidationException] on any trust failure.
     */
    fun validateAndAccept(
        activity: Activity,
        request: MeshRequest,
        invocationPolicy: MeshInvocationPolicy
    ) = MeshTarget.validateAndAccept(
        request = request,
        policy = policy,
        invocationPolicy = invocationPolicy,
        trust = trust,
        observedCaller = CallerIdentityObserver.observe(activity),
        replayCache = replayCache
    )

    /** Mint the target-owned receipt and finish the round-trip. */
    fun finishWithReceipt(
        activity: Activity,
        request: MeshRequest,
        status: String,
        result: Map<String, String>,
        receiptId: String,
        nonce: String,
        timestamp: String
    ) {
        val receipt: MeshReceipt = receiptSigner.makeReceipt(
            receiptId = receiptId,
            request = request,
            targetAppId = targetAppId,
            targetBundleId = targetBundleId,
            status = status,
            result = result,
            nonce = nonce,
            timestamp = timestamp
        )
        val data = Intent().putExtra(MeshIntentContract.EXTRA_MESH_RECEIPT, receipt.encodedForEnvelope())
        activity.setResult(Activity.RESULT_OK, data)
        activity.finish()
    }

    /** Deny without a receipt (pre-consent dismissal or trust failure). */
    fun finishDenied(activity: Activity) {
        activity.setResult(Activity.RESULT_CANCELED)
        activity.finish()
    }
}
