package ai.meshkit.core

import java.math.BigDecimal
import java.time.Instant
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFailsWith

class MeshTargetValidationTest {

    private val requestSeed = ByteArray(32) { (it + 1).toByte() }
    private val requestPublicKeyBase64 = "ebVWLo/mVPlAeLES6KmLp5AfhTrmlb7X4OORC60ElmQ="

    private val caller = MeshIdentity(
        appId = "app.hermes-chat",
        installId = "install-fixed-0001",
        bundleId = "ai.meshkit.sample.hermeschat",
        publicKeyId = "hermes-request-ed25519"
    )
    private val capability = MeshCapability(
        targetBundleId = "ai.meshkit.sample.dailymart",
        capabilityId = "grocery.purchase_essentials",
        version = "1.0"
    )
    private val policy = MeshTargetPolicy(
        allowedCallerAppId = "app.hermes-chat",
        targetBundleId = "ai.meshkit.sample.dailymart",
        capabilityId = "grocery.purchase_essentials"
    )
    private val trust = MeshSenderTrust(
        callerAppId = "app.hermes-chat",
        callerBundleId = "ai.meshkit.sample.hermeschat",
        callerPackageSignatureSha256 = "AA".repeat(32),
        requestSigningAlgorithm = "Ed25519",
        requestSigningKeyId = "hermes-request-ed25519",
        publicKeyBase64 = requestPublicKeyBase64
    )
    private val observedCaller = MeshObservedCaller(
        packageName = "ai.meshkit.sample.hermeschat",
        signingCertSha256 = "aa".repeat(32)
    )
    private val now: Instant = Instant.parse("2026-08-24T09:00:00Z")

    private fun signedRequest(
        payload: Map<String, String> = mapOf("items" to "milk", "budget_krw" to "100"),
        nonce: String = "nonce-0001"
    ): MeshRequest = MeshSignedRequestCrypto.sign(
        MeshRequest.create(
            requestId = "req-0001",
            caller = caller,
            target = capability,
            payload = payload,
            nonce = nonce,
            timestamp = "2026-08-24T09:00:00Z",
            signature = MeshSignature("Ed25519", "hermes-request-ed25519", "")
        ),
        Ed25519Jvm.signerFromSeed(requestSeed),
        keyId = "hermes-request-ed25519"
    )

    private fun invocationPolicy(
        userApproved: Boolean = true,
        approvedBudget: BigDecimal? = BigDecimal(100)
    ) = MeshInvocationPolicy(
        risk = "spend:money",
        consent = "budgeted_per_invocation",
        userApproved = userApproved,
        registrySignatureVerified = true,
        approvedBudget = approvedBudget
    )

    private fun accept(
        request: MeshRequest,
        invocation: MeshInvocationPolicy = invocationPolicy(),
        observed: MeshObservedCaller? = observedCaller,
        replayCache: MeshReplayCache = MeshReplayCache { true }
    ): MeshAuditEvent = MeshTarget.validateAndAccept(
        request = request,
        policy = policy,
        invocationPolicy = invocation,
        trust = trust,
        observedCaller = observed,
        replayCache = replayCache,
        now = now
    )

    @Test
    fun `accepts a valid signed request and emits an accepted audit event`() {
        val event = accept(signedRequest())
        assertEquals("accepted", event.status)
        assertEquals("req-0001", event.requestId)
    }

    @Test
    fun `rejects tampered payload via nonce-bound hash`() {
        val request = signedRequest()
        val tampered = request.copy(payload = request.payload + ("budget_krw" to "999999"))
        val error = assertFailsWith<MeshValidationException> { accept(tampered) }
        assertEquals(MeshValidationCode.PAYLOAD_HASH_MISMATCH, error.code)
    }

    @Test
    fun `rejects wrong signer key`() {
        val request = signedRequest()
        val wrongSeed = ByteArray(32) { (it + 7).toByte() }
        val resigned = MeshSignedRequestCrypto.sign(
            request.copy(signature = MeshSignature("Ed25519", "hermes-request-ed25519", "")),
            Ed25519Jvm.signerFromSeed(wrongSeed),
            keyId = "hermes-request-ed25519"
        )
        val error = assertFailsWith<MeshValidationException> { accept(resigned) }
        assertEquals(MeshValidationCode.SIGNATURE_MISMATCH, error.code)
    }

    @Test
    fun `rejects missing observed caller`() {
        val error = assertFailsWith<MeshValidationException> { accept(signedRequest(), observed = null) }
        assertEquals(MeshValidationCode.OBSERVED_CALLER_REQUIRED, error.code)
    }

    @Test
    fun `rejects observed caller package mismatch`() {
        val error = assertFailsWith<MeshValidationException> {
            accept(signedRequest(), observed = observedCaller.copy(packageName = "com.evil.app"))
        }
        assertEquals(MeshValidationCode.OBSERVED_CALLER_MISMATCH, error.code)
    }

    @Test
    fun `rejects observed caller signing certificate mismatch`() {
        val error = assertFailsWith<MeshValidationException> {
            accept(signedRequest(), observed = observedCaller.copy(signingCertSha256 = "bb".repeat(32)))
        }
        assertEquals(MeshValidationCode.OBSERVED_CALLER_SIGNATURE_MISMATCH, error.code)
    }

    @Test
    fun `rejects replayed nonce`() {
        val seen = mutableSetOf<String>()
        val cache = MeshReplayCache { nonce -> seen.add(nonce) }
        accept(signedRequest(), replayCache = cache)
        val error = assertFailsWith<MeshValidationException> { accept(signedRequest(), replayCache = cache) }
        assertEquals(MeshValidationCode.REPLAY_DETECTED, error.code)
    }

    @Test
    fun `rejects spend over approved budget`() {
        val request = signedRequest(payload = mapOf("items" to "milk", "budget_krw" to "101"))
        val error = assertFailsWith<MeshValidationException> { accept(request) }
        assertEquals(MeshValidationCode.BUDGET_EXCEEDED, error.code)
    }

    @Test
    fun `rejects spend without user consent`() {
        val error = assertFailsWith<MeshValidationException> {
            accept(signedRequest(), invocation = invocationPolicy(userApproved = false))
        }
        assertEquals(MeshValidationCode.CONSENT_REQUIRED, error.code)
    }

    @Test
    fun `rejects stale timestamp`() {
        val error = assertFailsWith<MeshValidationException> {
            MeshTarget.verifyFreshTimestamp(signedRequest(), maxAgeSeconds = 300, now = Instant.parse("2026-08-24T10:00:00Z"))
        }
        assertEquals(MeshValidationCode.STALE_TIMESTAMP, error.code)
    }
}
