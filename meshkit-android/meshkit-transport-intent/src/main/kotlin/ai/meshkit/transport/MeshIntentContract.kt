package ai.meshkit.transport

/**
 * App-to-App MCP over an explicit Activity round-trip. The envelope extras
 * carry the same base64 sorted-keys JSON the iOS URL-scheme transport uses.
 */
object MeshIntentContract {
    /** Matches the `capabilities[].android.action` OCG manifest binding. */
    const val ACTION_INVOKE_CAPABILITY = "ai.meshkit.action.INVOKE_CAPABILITY"

    /** Request envelope extra (same payload as the iOS `mesh_request` query item). */
    const val EXTRA_MESH_REQUEST = "mesh_request"

    /** Receipt envelope extra on the activity result (same as iOS `mesh_receipt`). */
    const val EXTRA_MESH_RECEIPT = "mesh_receipt"
}
