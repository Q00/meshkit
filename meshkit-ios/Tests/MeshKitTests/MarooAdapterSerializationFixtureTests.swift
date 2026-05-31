import XCTest
@testable import MeshKit

final class MarooAdapterSerializationFixtureTests: XCTestCase {
    func testRequestAnchorSerializerEmitsCompleteMarooTestnetFixtureObject() throws {
        let adapter = try MeshMarooTestnetRequestAnchorAdapter(status: .pending)
        let payload = try requestAnchorPayload()
        let input = try MeshRequestAnchorProviderInput(
            payload: payload,
            providerIdentity: adapter.identity,
            submittedAt: "2026-05-31T00:20:00Z"
        )

        let transactionRequest = try MeshMarooTestnetRequestAnchorSerializer.transactionRequest(from: input)
        let emittedObject = try Self.sortedJSONObject(transactionRequest)

        XCTAssertEqual(emittedObject, Self.expectedAnchorTransactionFixture)
    }

    func testOKRWExecutionSerializerEmitsCompleteMarooTestnetPaymentFixtureObject() async throws {
        let fixture = try await paymentExecutionFixture(kind: .payment, amount: Decimal(4_900))
        let input = try MeshMarooTestnetPaymentExecutionProviderInput(
            paymentRequest: fixture.paymentRequest,
            providerIdentity: try MeshMarooTestnetChainProvider().identity,
            submittedAt: "2026-05-31T00:20:03Z"
        )

        let transactionRequest = try MeshMarooTestnetOKRWExecutionSerializer.transactionRequest(from: input)
        let emittedObject = try Self.sortedJSONObject(transactionRequest)

        XCTAssertEqual(emittedObject, Self.expectedOKRWPaymentTransactionFixture)
    }

    private static let expectedAnchorTransactionFixture = #"""
{
  "anchor_hash" : {
    "algorithm" : "sha256",
    "value" : "15a7eb061a06bad249dc32d726255b9577f515a517ef70f7c74b40602b8ad832"
  },
  "anchor_payload_identity" : "meshkit-request-anchor\/v1:ios-grocery-maroo-fixture-001:nonce-maroo-fixture-anchor:policy-hermes-dailymart-okrw-v1",
  "chain_id" : "maroo-testnet-1",
  "delegated_signer" : "app.hermes-chat:ai.meshkit.sample.hermeschat:demo-key",
  "explorer_base_url" : "https:\/\/explorer-testnet.maroo.io",
  "network" : "maroo-testnet",
  "policy_hash" : {
    "algorithm" : "sha256",
    "value" : "ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff"
  },
  "policy_id" : "policy-hermes-dailymart-okrw-v1",
  "provider" : "maroo",
  "request_id" : "ios-grocery-maroo-fixture-001",
  "request_nonce" : "nonce-maroo-fixture-anchor",
  "request_type" : "meshkit_request_anchor",
  "rpc_endpoint" : "https:\/\/rpc-testnet.maroo.io",
  "schema_version" : "maroo-testnet-request-anchor\/v1",
  "signed_mcp_request_hash" : {
    "algorithm" : "sha256",
    "value" : "24a6a1b58ce01208581ae37503121c48cd7467e4c1229379f3aad658211b8649"
  },
  "signed_mcp_request_signature" : {
    "algorithm" : "Ed25519",
    "keyId" : "demo-key",
    "value" : "fixture-ed25519-signature"
  },
  "submitted_at" : "2026-05-31T00:20:00Z",
  "target_owner" : "ai.meshkit.sample.dailymart"
}
"""#

    private static let expectedOKRWPaymentTransactionFixture = #"""
{
  "adapter_id" : "maroo-testnet-payment-executor-demo-adapter",
  "amount" : 4900,
  "anchor_metadata" : {
    "anchor_tx_hash" : "0xbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb",
    "anchoring_reference" : "maroo-anchor-ios-grocery-maroo-fixture-001",
    "policy_hash" : {
      "algorithm" : "sha256",
      "value" : "ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff"
    },
    "policy_id" : "policy-hermes-dailymart-okrw-v1",
    "request_nonce" : "nonce-maroo-fixture-payment-4900",
    "signed_mcp_request_hash" : {
      "algorithm" : "sha256",
      "value" : "052593308b571021e13fe46ffe6cbe1ddce9f8d9e3489d0b7a41e6c1e2da51d1"
    }
  },
  "anchor_tx_hash" : "0xbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb",
  "anchoring_reference" : "maroo-anchor-ios-grocery-maroo-fixture-001",
  "asset" : "OKRW",
  "authorization_id" : "auth-maroo-fixture-001",
  "authorization_status" : "approved",
  "caller_bundle_id" : "ai.meshkit.sample.hermeschat",
  "capability_id" : "grocery.purchase_essentials",
  "chain_id" : "maroo-testnet-1",
  "delegated_wallet_address" : "maroo1dailyMartAgentWallet",
  "execution_id" : "exec-maroo-fixture-001",
  "execution_kind" : "payment",
  "execution_link_hash" : {
    "algorithm" : "sha256",
    "value" : "53cb1a42f3f71ee7870f8f30626a3150ef1826deecfff0be3e71fdd245c70a8c"
  },
  "execution_link_identity" : "meshkit-maroo-execution-link\/v1:pay-maroo-fixture-001:exec-maroo-fixture-001:payment:nonce-maroo-fixture-payment-4900:policy-hermes-dailymart-okrw-v1",
  "memo" : "MeshKit|MCP|payment|OKRW|nonce-maroo-fixture-payment-4900|maroo-anchor-ios-grocery-maroo-fixture-001",
  "network" : "maroo-testnet",
  "payload_hash" : {
    "algorithm" : "sha256",
    "value" : "64ec2695797bcd26907869d52725fba491bd27ba178924fc32aaeb14ab648ba9"
  },
  "payment_id" : "pay-maroo-fixture-001",
  "policy_hash" : {
    "algorithm" : "sha256",
    "value" : "ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff"
  },
  "policy_id" : "policy-hermes-dailymart-okrw-v1",
  "provider" : "maroo",
  "recipient_address" : "maroo1dailyMartMerchant",
  "request_id" : "ios-grocery-maroo-fixture-001",
  "request_nonce" : "nonce-maroo-fixture-payment-4900",
  "request_type" : "meshkit_okrw_execution",
  "schema_version" : "maroo-testnet-okrw-execution\/v1",
  "signed_mcp_request_hash" : {
    "algorithm" : "sha256",
    "value" : "052593308b571021e13fe46ffe6cbe1ddce9f8d9e3489d0b7a41e6c1e2da51d1"
  },
  "submitted_at" : "2026-05-31T00:20:03Z",
  "target_bundle_id" : "ai.meshkit.sample.dailymart"
}
"""#

    private static func sortedJSONObject<T: Encodable>(_ value: T) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(value)
        return String(decoding: data, as: UTF8.self)
    }

    private func paymentExecutionFixture(
        kind: MeshAgentWalletExecutionKind,
        amount: Decimal
    ) async throws -> (paymentRequest: MeshPaymentExecutionRequest, originatingRequest: MeshRequest) {
        let originatingRequest = Self.signedDailyMartRequest(
            requestId: "ios-grocery-maroo-fixture-001",
            nonce: "nonce-maroo-fixture-\(kind.rawValue)-\(amount)",
            budget: "\(amount)"
        )
        let metadata = try MeshSignedRequestAnchorMetadata(request: originatingRequest)
        let policyHash = MeshPayloadHash(value: String(repeating: "f", count: 64))
        let executionRequest = try MeshAgentWalletExecutionRequest(
            executionId: "exec-maroo-fixture-001",
            kind: kind,
            requestAnchorMetadata: metadata,
            scope: MeshAgentWalletSpendingScope(
                merchantId: "merchant.dailymart",
                targetBundleId: "ai.meshkit.sample.dailymart",
                capabilityId: "grocery.purchase_essentials",
                consentGrantId: "grant-hermes-dailymart-001"
            ),
            amount: amount,
            currencyCode: "krw",
            tokenSymbol: "okrw",
            recipientAddress: "maroo1dailyMartMerchant",
            policyId: "policy-hermes-dailymart-okrw-v1",
            policyHash: policyHash
        )
        let decision = try MeshAgentWalletAuthorizationDecision(
            authorizationId: "auth-maroo-fixture-001",
            walletIdentity: MeshAgentWalletIdentity(
                walletId: "wallet-hermes-dailymart-okrw-v1",
                agentId: "agent.hermes-chat.daily-mart",
                walletAddress: "maroo1dailyMartAgentWallet",
                providerMetadata: MeshAgentWalletProviderMetadata(
                    chainProviderIdentity: try MeshMarooTestnetChainProvider().identity,
                    adapterId: "maroo-testnet-agent-wallet-adapter"
                ),
                signingBoundary: .providerSubmission
            ),
            executionRequest: executionRequest,
            status: .approved,
            approvedAmount: amount,
            decidedAt: "2026-05-31T00:20:01Z"
        )
        let anchor = try await MeshMarooTestnetRequestAnchorAdapter(
            status: .confirmed,
            transactionHash: "0x" + String(repeating: "b", count: 64)
        ).anchorSignedRequest(
            payload: try MeshRequestAnchorPayload(
                metadata: metadata,
                policyId: "policy-hermes-dailymart-okrw-v1",
                policyHash: policyHash
            ),
            submittedAt: "2026-05-31T00:20:02Z"
        )
        let paymentRequest = try MeshPaymentExecutionRequest(
            paymentId: "pay-maroo-fixture-001",
            authorizationDecision: decision,
            requestAnchor: anchor,
            requestedAt: "2026-05-31T00:20:02Z"
        )
        return (paymentRequest, originatingRequest)
    }

    private func requestAnchorPayload() throws -> MeshRequestAnchorPayload {
        try MeshRequestAnchorPayload(
            metadata: MeshSignedRequestAnchorMetadata(
                request: Self.signedDailyMartRequest(
                    requestId: "ios-grocery-maroo-fixture-001",
                    nonce: "nonce-maroo-fixture-anchor",
                    budget: "4900"
                )
            ),
            policyId: "policy-hermes-dailymart-okrw-v1",
            policyHash: MeshPayloadHash(value: String(repeating: "f", count: 64))
        )
    }

    private static func signedDailyMartRequest(
        requestId: String,
        nonce: String,
        budget: String
    ) -> MeshRequest {
        MeshRequest(
            requestId: requestId,
            caller: MeshIdentity(
                appId: "app.hermes-chat",
                installId: "ios-device",
                bundleId: "ai.meshkit.sample.hermeschat",
                publicKeyId: "demo-key"
            ),
            target: MeshCapability(
                targetBundleId: "ai.meshkit.sample.dailymart",
                capabilityId: "grocery.purchase_essentials",
                version: "1.0"
            ),
            payload: [
                "address_ref": "home.saved",
                "budget_krw": budget,
                "items": "laundry_detergent:1,toilet_paper:2,bottled_water_2l:6"
            ],
            nonce: nonce,
            timestamp: "2026-05-31T00:20:00Z",
            signature: MeshSignature(
                algorithm: "Ed25519",
                keyId: "demo-key",
                value: "fixture-ed25519-signature"
            )
        )
    }
}
