package ai.meshkit.transport

import android.app.Activity
import android.content.pm.PackageManager
import android.os.Build
import ai.meshkit.core.MeshObservedCaller
import java.security.MessageDigest

/**
 * Kernel-verified caller identity for a target activity launched with
 * `startActivityForResult`. `getCallingPackage()` is populated by the system
 * (not attacker-controlled data in the envelope), and the signing certificate
 * comes from PackageManager — together they upgrade the iOS "observed caller
 * bundle" claim-check into a proof-check against the OCG
 * `package_signature_sha256` pin.
 */
object CallerIdentityObserver {
    fun observe(activity: Activity): MeshObservedCaller? {
        val callingPackage = activity.callingPackage ?: return null
        val signingSha256 = signingCertSha256(activity, callingPackage) ?: return null
        return MeshObservedCaller(packageName = callingPackage, signingCertSha256 = signingSha256)
    }

    private fun signingCertSha256(activity: Activity, packageName: String): String? {
        val packageInfo = try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                activity.packageManager.getPackageInfo(
                    packageName,
                    PackageManager.PackageInfoFlags.of(PackageManager.GET_SIGNING_CERTIFICATES.toLong())
                )
            } else {
                @Suppress("DEPRECATION")
                activity.packageManager.getPackageInfo(packageName, PackageManager.GET_SIGNING_CERTIFICATES)
            }
        } catch (e: PackageManager.NameNotFoundException) {
            return null
        }
        val signingInfo = packageInfo.signingInfo ?: return null
        // With key rotation, current signer certificates apply; a rotated
        // lineage should be re-pinned in the OCG registry.
        val signer = signingInfo.apkContentsSigners.firstOrNull() ?: return null
        val digest = MessageDigest.getInstance("SHA-256").digest(signer.toByteArray())
        return digest.joinToString("") { "%02x".format(it) }
    }
}
