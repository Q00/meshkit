import Foundation
import XCTest
@testable import MeshKit

final class MeshAgentWalletRequestSigningModuleTests: XCTestCase {
    func testSignOnlyAPIProducesSignedRequestArtifactWithoutNetworkSubmissionOrExecutionStateMutation() throws {
        let recorder = SignOnlyCallRecorder()
        let wallet = try RecordingSignOnlyAgentWallet(
            identity: walletIdentity(),
            capabilities: [.signMCPRequest],
            recorder: recorder
        )
        let signer = MeshRequestSigner(algorithm: "Ed25519", keyId: caller.publicKeyId) { data in
            recorder.append("signer.signData")
            return Data("signature-\(data.count)".utf8)
        }
        let module = MeshAgentWalletRequestSigningModule(wallet: wallet)
        let policy = try delegatedSpendingPolicy()
        let accounting = try MeshAgentWalletDelegatedSpendAccounting(policy: policy)

        let artifact = try module.signRequestArtifact(
            caller: caller,
            target: target,
            signer: signer,
            requestId: "ios-grocery-sign-only-001",
            payload: requestPayload,
            nonce: "nonce-sign-only-001",
            timestamp: "2026-05-31T12:30:00Z",
            signedAt: "2026-05-31T12:30:01Z"
        )

        try artifact.validate()
        XCTAssertEqual(artifact.walletIdentity, wallet.identity)
        XCTAssertEqual(artifact.signedRequest.requestId, "ios-grocery-sign-only-001")
        XCTAssertEqual(artifact.signedRequest.nonce, "nonce-sign-only-001")
        XCTAssertEqual(artifact.signedRequest.signature.algorithm, "Ed25519")
        XCTAssertEqual(artifact.signedRequest.signature.keyId, caller.publicKeyId)
        XCTAssertFalse(artifact.signedRequest.signature.value.isEmpty)
        XCTAssertEqual(artifact.anchorMetadata.requestId, artifact.signedRequest.requestId)
        XCTAssertEqual(artifact.anchorMetadata.nonce, artifact.signedRequest.nonce)
        XCTAssertEqual(
            artifact.anchorMetadata.signedRequestHash,
            try MeshRequestAnchorCanonicalization.signedRequestHash(for: artifact.signedRequest)
        )
        XCTAssertEqual(accounting, try MeshAgentWalletDelegatedSpendAccounting(policy: policy))
        XCTAssertEqual(recorder.events(), [
            "wallet.loadWalletConfiguration",
            "signer.signData"
        ])
    }

    func testSignOnlyAPIRequiresExplicitWalletCapabilityBeforeCallingSigner() throws {
        let recorder = SignOnlyCallRecorder()
        let wallet = try RecordingSignOnlyAgentWallet(
            identity: walletIdentity(),
            capabilities: [.reportWalletAddress],
            recorder: recorder
        )
        let signer = MeshRequestSigner(algorithm: "Ed25519", keyId: caller.publicKeyId) { _ in
            recorder.append("signer.signData")
            return Data("unexpected-signature".utf8)
        }
        let module = MeshAgentWalletRequestSigningModule(wallet: wallet)

        XCTAssertThrowsError(
            try module.signRequestArtifact(
                caller: caller,
                target: target,
                signer: signer,
                requestId: "ios-grocery-sign-only-unsupported",
                payload: requestPayload,
                nonce: "nonce-sign-only-unsupported",
                timestamp: "2026-05-31T12:31:00Z",
                signedAt: "2026-05-31T12:31:01Z"
            )
        ) { error in
            XCTAssertEqual(error as? MeshKitValidationError, .unsupportedCapability)
        }
        XCTAssertEqual(recorder.events(), ["wallet.loadWalletConfiguration"])
    }

    private var caller: MeshIdentity {
        MeshIdentity(
            appId: "app.hermes-chat",
            installId: "ios-device",
            bundleId: "ai.meshkit.sample.hermeschat",
            publicKeyId: "sample-ios-ed25519"
        )
    }

    private var target: MeshCapability {
        MeshCapability(
            targetBundleId: "ai.meshkit.sample.dailymart",
            capabilityId: "grocery.purchase_essentials",
            version: "1.0"
        )
    }

    private var requestPayload: [String: String] {
        [
            "items": "laundry_detergent:1",
            "address_ref": "home.saved",
            "budget_krw": "42",
            "merchantScope": "merchant.dailymart",
            "capabilityScope": "grocery.purchase_essentials",
            "consentGrantId": "grant-hermes-dailymart-001",
            "policyId": "policy-hermes-dailymart-okrw-v1",
            "policyHash": String(repeating: "f", count: 64)
        ]
    }

    private func delegatedSpendingPolicy() throws -> MeshAgentWalletDelegatedSpendingPolicy {
        try MeshAgentWalletDelegatedSpendingPolicy(
            policyId: "policy-hermes-dailymart-okrw-v1",
            policyHash: MeshPayloadHash(value: String(repeating: "f", count: 64)),
            consentGrantId: "grant-hermes-dailymart-001",
            merchantScope: "merchant.dailymart",
            capabilityScope: "grocery.purchase_essentials",
            singlePaymentMax: Decimal(100),
            sessionTotalLimit: Decimal(500),
            remainingLimit: Decimal(500),
            expiresAt: "2026-06-30T00:00:00Z",
            asset: "OKRW",
            recipientAddress: "maroo1DailyMartMerchant"
        )
    }

    private func walletIdentity() throws -> MeshAgentWalletIdentity {
        try MeshAgentWalletIdentity(
            walletId: "wallet-sign-only",
            agentId: "agent.hermes-chat.daily-mart",
            walletAddress: "maroo1DailyMartAgentWallet",
            providerMetadata: MeshAgentWalletProviderMetadata(
                provider: "demo",
                network: "testnet",
                chainId: "demo-testnet",
                adapterId: "sign-only-test-agent-wallet"
            ),
            signingBoundary: .localSignature
        )
    }
}

private final class SignOnlyCallRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var recordedEvents: [String] = []

    func append(_ event: String) {
        lock.lock()
        defer { lock.unlock() }
        recordedEvents.append(event)
    }

    func events() -> [String] {
        lock.lock()
        defer { lock.unlock() }
        return recordedEvents
    }
}

private struct RecordingSignOnlyAgentWallet: MeshAgentWallet {
    let identity: MeshAgentWalletIdentity
    let capabilities: [MeshAgentWalletCapability]
    let recorder: SignOnlyCallRecorder

    func loadWalletConfiguration() throws -> MeshAgentWalletConfiguration {
        recorder.append("wallet.loadWalletConfiguration")
        return try MeshAgentWalletConfiguration(identity: identity, capabilities: capabilities)
    }

    func reportWalletAddress() throws -> String {
        recorder.append("wallet.reportWalletAddress")
        return identity.walletAddress
    }

    func delegatedSpendingLimit() throws -> MeshAgentWalletDelegatedSpendingLimit {
        recorder.append("wallet.delegatedSpendingLimit")
        throw MeshKitValidationError.unsupportedCapability
    }

    func signingBoundary() throws -> MeshAgentWalletSigningBoundary {
        recorder.append("wallet.signingBoundary")
        return identity.signingBoundary
    }

    func signRequestAnchorPayload(
        _ payload: MeshAgentWalletAnchorSigningPayload,
        signedAt: String
    ) throws -> MeshAgentWalletAnchorSignature {
        recorder.append("wallet.signRequestAnchorPayload")
        throw MeshKitValidationError.signatureRequired
    }

    func signExecutionAuthorizationPayload(
        _ payload: MeshAgentWalletExecutionAuthorizationPayload,
        signedAt: String
    ) throws -> MeshAgentWalletExecutionAuthorization {
        recorder.append("wallet.signExecutionAuthorizationPayload")
        throw MeshKitValidationError.signatureRequired
    }

    func authorizeExecution(
        _ request: MeshAgentWalletExecutionRequest,
        decidedAt: String
    ) throws -> MeshAgentWalletAuthorizationDecision {
        recorder.append("wallet.authorizeExecution")
        throw MeshKitValidationError.invalidPaymentExecution("authorizationDecision")
    }
}
