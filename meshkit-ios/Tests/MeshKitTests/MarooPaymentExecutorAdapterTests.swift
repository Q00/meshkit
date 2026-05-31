import CryptoKit
import XCTest
@testable import MeshKit

final class MarooPaymentExecutorAdapterTests: XCTestCase {
    private static let signingKey = Curve25519.Signing.PrivateKey()

    func testMarooTestnetPaymentExecutorInvokesExecutionBoundaryWithCanonicalOKRWPayment() async throws {
        let client = CapturingMarooPaymentExecutionSubmissionClient(
            transactionHash: "0x" + String(repeating: "4", count: 64),
            providerOutcome: "confirmed"
        )
        let adapter = try MeshMarooTestnetPaymentExecutorAdapter(submissionClient: client)
        let fixture = try await samplePaymentExecutionFixture(
            kind: .payment,
            amount: Decimal(4_900)
        )

        let result = try await adapter.executePayment(
            fixture.paymentRequest,
            originatingRequest: fixture.originatingRequest,
            submittedAt: "2026-05-31T00:00:09Z"
        )
        let capturedInputs = await client.snapshotInputs()
        let capturedTransactionRequests = await client.snapshotTransactionRequests()
        let capturedInput = try XCTUnwrap(capturedInputs.first)
        let capturedTransactionRequest = try XCTUnwrap(capturedTransactionRequests.first)

        XCTAssertEqual(capturedInputs.count, 1)
        XCTAssertEqual(capturedTransactionRequests.count, 1)
        XCTAssertEqual(capturedInput.providerMetadata, adapter.chainProvider.metadata)
        XCTAssertEqual(capturedInput.paymentRequest, fixture.paymentRequest)
        XCTAssertEqual(capturedInput.submittedAt, "2026-05-31T00:00:09Z")
        XCTAssertEqual(capturedTransactionRequest, try MeshMarooTestnetOKRWExecutionSerializer.transactionRequest(from: capturedInput))
        XCTAssertEqual(capturedTransactionRequest.executionKind, .payment)
        XCTAssertEqual(capturedTransactionRequest.asset, "OKRW")
        XCTAssertEqual(capturedTransactionRequest.amount, Decimal(4_900))
        XCTAssertEqual(capturedTransactionRequest.recipientAddress, "0x000000000000000000000000000000000000d417")
        XCTAssertEqual(capturedTransactionRequest.requestNonce, fixture.originatingRequest.nonce)
        XCTAssertEqual(capturedTransactionRequest.signedMCPRequestHash, fixture.paymentRequest.requestHash)
        XCTAssertEqual(capturedTransactionRequest.anchoringReference, fixture.paymentRequest.requestAnchor.identifier.anchorId)
        XCTAssertEqual(capturedTransactionRequest.anchorTransactionHash, fixture.paymentRequest.requestAnchor.identifier.transactionHash)
        XCTAssertEqual(capturedTransactionRequest.policyId, "policy-hermes-dailymart-okrw-v1")
        XCTAssertTrue(capturedInput.canonicalString.contains("provider=maroo"))
        XCTAssertTrue(capturedInput.canonicalString.contains("network=maroo-testnet"))
        XCTAssertTrue(capturedInput.canonicalString.contains("executionKind=payment"))
        XCTAssertTrue(capturedInput.canonicalString.contains("asset=OKRW"))
        XCTAssertTrue(capturedInput.canonicalString.contains("recipient=0x000000000000000000000000000000000000d417"))
        XCTAssertTrue(capturedInput.canonicalString.contains("requestNonce=nonce-maroo-okrw-capability-payment-4900"))
        XCTAssertTrue(capturedInput.executionLinkPayload.canonicalString.contains("requestId=ios-grocery-maroo-okrw-capability-001"))
        XCTAssertTrue(capturedInput.executionLinkPayload.canonicalString.contains("requestNonce=nonce-maroo-okrw-capability-payment-4900"))
        XCTAssertTrue(capturedInput.executionLinkPayload.canonicalString.contains("anchoringReference=\(fixture.paymentRequest.requestAnchor.identifier.anchorId)"))
        XCTAssertTrue(capturedInput.executionLinkPayload.canonicalString.contains("policyId=policy-hermes-dailymart-okrw-v1"))
        XCTAssertEqual(capturedInput.executionLinkPayload.signedRequestHash, fixture.paymentRequest.requestHash)
        XCTAssertEqual(capturedInput.executionLinkPayload.anchoringReference, fixture.paymentRequest.requestAnchor.identifier)
        XCTAssertEqual(capturedInput.executionLinkPayload.executionLinkHash.value.count, 64)
        XCTAssertTrue(capturedInput.canonicalString.contains("signedRequestHashValue=\(fixture.paymentRequest.requestHash.value)"))
        XCTAssertTrue(capturedInput.canonicalString.contains("anchoringReference=\(fixture.paymentRequest.requestAnchor.identifier.anchorId)"))
        XCTAssertTrue(capturedInput.canonicalString.contains("policyId=policy-hermes-dailymart-okrw-v1"))
        XCTAssertTrue(capturedInput.canonicalString.contains("policyHashValue=\(String(repeating: "f", count: 64))"))
        XCTAssertTrue(capturedInput.canonicalString.contains("executionLinkHashValue=\(capturedInput.executionLinkPayload.executionLinkHash.value)"))
        XCTAssertEqual(result.status, .confirmed)
        XCTAssertEqual(result.transactionHash, "0x" + String(repeating: "4", count: 64))
        XCTAssertEqual(result.providerExtensions["maroo"]?["executionKind"], "payment")
    }

    func testMAWSTransferSendBridgePostsTransferToolRequestAndMapsConfirmedTxHash() async throws {
        let txHash = "0x" + String(repeating: "9", count: 64)
        let transport = CapturingMAWSTransferHTTPTransport(responseObject: [
            "ok": true,
            "data": [
                "txHash": txHash,
                "status": "confirmed",
                "message": "transfer.send confirmed",
                "blockHash": "0x" + String(repeating: "a", count: 64),
                "blockNumber": 9_065_700,
                "confirmationCount": 2,
                "confirmedAt": "2026-05-31T00:00:20Z"
            ]
        ])
        let client = try MeshMAWSTransferSendBridgeClient(
            bridgeEndpoint: try XCTUnwrap(URL(string: "https://maws-bridge.example.test/transfer")),
            agentId: "agent-dailymart-001",
            authorizationHeader: "Bearer test-token",
            transport: transport
        )
        let adapter = try MeshMarooTestnetPaymentExecutorAdapter(submissionClient: client)
        let fixture = try await samplePaymentExecutionFixture(kind: .payment, amount: Decimal(100))

        let result = try await adapter.executePayment(
            fixture.paymentRequest,
            originatingRequest: fixture.originatingRequest,
            submittedAt: "2026-05-31T00:00:09Z"
        )
        let requests = await transport.snapshotRequests()
        let request = try XCTUnwrap(requests.first)
        let body = try XCTUnwrap(request.httpBody)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
        let arguments = try XCTUnwrap(object["arguments"] as? [String: Any])
        let meshkit = try XCTUnwrap(object["meshkit"] as? [String: Any])

        XCTAssertEqual(request.url?.absoluteString, "https://maws-bridge.example.test/transfer")
        XCTAssertEqual(request.value(forHTTPHeaderField: "authorization"), "Bearer test-token")
        XCTAssertEqual(object["schema_version"] as? String, "meshkit-maws-transfer-send-bridge/v1")
        XCTAssertEqual(object["tool"] as? String, "transfer.send")
        XCTAssertEqual(arguments["agentId"] as? String, "agent-dailymart-001")
        XCTAssertEqual(arguments["to"] as? String, "0x000000000000000000000000000000000000d417")
        XCTAssertEqual(arguments["amount"] as? String, "100")
        XCTAssertEqual(arguments["clientToken"] as? String, fixture.paymentRequest.paymentId)
        XCTAssertEqual(meshkit["request_type"] as? String, "meshkit_okrw_execution")
        XCTAssertEqual(meshkit["asset"] as? String, "OKRW")
        XCTAssertEqual(meshkit["signed_mcp_request_hash"] as? [String: String], [
            "algorithm": fixture.paymentRequest.requestHash.algorithm,
            "value": fixture.paymentRequest.requestHash.value
        ])
        XCTAssertEqual(result.status, .confirmed)
        XCTAssertEqual(result.transactionHash, txHash)
        XCTAssertEqual(result.providerExtensions["maroo"]?["resultSource"], "live")
    }

    func testMAWSTransferSendBridgeKeepsTxHashPendingUntilMarooConfirmationProofArrives() async throws {
        let txHash = "0x" + String(repeating: "8", count: 64)
        let transport = CapturingMAWSTransferHTTPTransport(responseObject: [
            "ok": true,
            "data": [
                "txHash": txHash,
                "status": "confirmed"
            ]
        ])
        let client = try MeshMAWSTransferSendBridgeClient(
            bridgeEndpoint: try XCTUnwrap(URL(string: "https://maws-bridge.example.test/transfer")),
            agentId: "agent-dailymart-001",
            transport: transport
        )
        let adapter = try MeshMarooTestnetPaymentExecutorAdapter(submissionClient: client)
        let fixture = try await samplePaymentExecutionFixture(kind: .payment, amount: Decimal(100))

        let result = try await adapter.executePayment(
            fixture.paymentRequest,
            originatingRequest: fixture.originatingRequest,
            submittedAt: "2026-05-31T00:00:09Z"
        )

        XCTAssertEqual(result.status, .pending)
        XCTAssertEqual(result.transactionHash, txHash)
        XCTAssertEqual(result.providerExtensions["maroo"]?["resultSource"], "live")
        XCTAssertEqual(result.message, "MAWS transfer.send returned txHash without maroo confirmation proof")
    }

    func testMAWSTransferSendBridgeMapsPolicyRejectedEnvelopeBeforeTxHash() async throws {
        let transport = CapturingMAWSTransferHTTPTransport(responseObject: [
            "ok": false,
            "error": [
                "code": "POLICY_REJECTED",
                "message": "spending limit blocked transfer.send"
            ]
        ])
        let client = try MeshMAWSTransferSendBridgeClient(
            bridgeEndpoint: try XCTUnwrap(URL(string: "https://maws-bridge.example.test/transfer")),
            agentId: "agent-dailymart-001",
            transport: transport
        )
        let adapter = try MeshMarooTestnetPaymentExecutorAdapter(submissionClient: client)
        let fixture = try await samplePaymentExecutionFixture(kind: .payment, amount: Decimal(100))

        let result = try await adapter.executePayment(
            fixture.paymentRequest,
            originatingRequest: fixture.originatingRequest,
            submittedAt: "2026-05-31T00:00:09Z"
        )

        XCTAssertEqual(result.status, .policyDenied)
        XCTAssertNil(result.transactionHash)
        XCTAssertEqual(result.errorPayload?.code, "policy_denied")
        XCTAssertEqual(result.message, "spending limit blocked transfer.send")
    }

    func testMarooNativeOKRWTransferBridgePostsNativeTransferRequestAndMapsConfirmedReceipt() async throws {
        let txHash = "0x" + String(repeating: "7", count: 64)
        let transport = CapturingMAWSTransferHTTPTransport(responseObject: [
            "ok": true,
            "data": [
                "txHash": txHash,
                "status": "confirmed",
                "message": "native OKRW confirmed",
                "blockHash": "0x" + String(repeating: "b", count: 64),
                "blockNumber": 9_066_001,
                "confirmationCount": 4,
                "confirmedAt": "2026-05-31T00:00:30Z"
            ]
        ])
        let client = try MeshMarooNativeOKRWTransferBridgeClient(
            bridgeEndpoint: try XCTUnwrap(URL(string: "http://127.0.0.1:8788/transfer")),
            authorizationHeader: "Bearer native-test",
            transport: transport
        )
        let adapter = try MeshMarooTestnetPaymentExecutorAdapter(submissionClient: client)
        let fixture = try await samplePaymentExecutionFixture(kind: .transfer, amount: Decimal(100))

        let result = try await adapter.executePayment(
            fixture.paymentRequest,
            originatingRequest: fixture.originatingRequest,
            submittedAt: "2026-05-31T00:00:09Z"
        )
        let requests = await transport.snapshotRequests()
        let request = try XCTUnwrap(requests.first)
        let body = try XCTUnwrap(request.httpBody)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
        let arguments = try XCTUnwrap(object["arguments"] as? [String: Any])
        let meshkit = try XCTUnwrap(object["meshkit"] as? [String: Any])

        XCTAssertEqual(request.url?.absoluteString, "http://127.0.0.1:8788/transfer")
        XCTAssertEqual(request.value(forHTTPHeaderField: "authorization"), "Bearer native-test")
        XCTAssertEqual(object["schema_version"] as? String, "meshkit-maroo-native-okrw-transfer-bridge/v1")
        XCTAssertEqual(object["tool"] as? String, "maroo.native_transfer")
        XCTAssertNil(arguments["agentId"])
        XCTAssertEqual(arguments["to"] as? String, "0x000000000000000000000000000000000000d417")
        XCTAssertEqual(arguments["amount"] as? String, "100")
        XCTAssertEqual(arguments["clientToken"] as? String, fixture.paymentRequest.paymentId)
        XCTAssertEqual(meshkit["execution_kind"] as? String, "transfer")
        XCTAssertEqual(meshkit["asset"] as? String, "OKRW")
        XCTAssertEqual(result.status, .confirmed)
        XCTAssertEqual(result.transactionHash, txHash)
        XCTAssertEqual(result.providerExtensions["maroo"]?["resultSource"], "live")
    }

    func testMarooNativeOKRWTransferBridgeKeepsTxHashPendingUntilReceiptProofArrives() async throws {
        let txHash = "0x" + String(repeating: "6", count: 64)
        let transport = CapturingMAWSTransferHTTPTransport(responseObject: [
            "ok": true,
            "data": [
                "txHash": txHash,
                "status": "confirmed"
            ]
        ])
        let client = try MeshMarooNativeOKRWTransferBridgeClient(
            bridgeEndpoint: try XCTUnwrap(URL(string: "http://127.0.0.1:8788/transfer")),
            transport: transport
        )
        let adapter = try MeshMarooTestnetPaymentExecutorAdapter(submissionClient: client)
        let fixture = try await samplePaymentExecutionFixture(kind: .transfer, amount: Decimal(100))

        let result = try await adapter.executePayment(
            fixture.paymentRequest,
            originatingRequest: fixture.originatingRequest,
            submittedAt: "2026-05-31T00:00:09Z"
        )

        XCTAssertEqual(result.status, .pending)
        XCTAssertEqual(result.transactionHash, txHash)
        XCTAssertEqual(result.providerExtensions["maroo"]?["resultSource"], "live")
        XCTAssertEqual(result.message, "maroo native OKRW bridge returned txHash without maroo confirmation proof")
    }

    func testOKRWSubmissionClientEnvironmentFactoryPrefersDirectMarooBridgeOverMAWS() throws {
        let client = try MeshMarooOKRWSubmissionClientEnvironmentFactory(environment: [
            MeshMarooOKRWSubmissionClientEnvironmentFactory.nativeBridgeURLKey: "http://127.0.0.1:8788/transfer",
            MeshMarooOKRWSubmissionClientEnvironmentFactory.nativeBridgeAuthorizationKey: "Bearer native",
            MeshMarooOKRWSubmissionClientEnvironmentFactory.mawsBridgeURLKey: "https://maws-bridge.example.test/transfer",
            MeshMarooOKRWSubmissionClientEnvironmentFactory.mawsAgentIdKey: "agent-dailymart-001",
            MeshMarooOKRWSubmissionClientEnvironmentFactory.mawsAuthorizationKey: "Bearer maws"
        ]).makeSubmissionClient()

        let nativeClient = try XCTUnwrap(client as? MeshMarooNativeOKRWTransferBridgeClient)
        XCTAssertEqual(nativeClient.bridgeEndpoint.absoluteString, "http://127.0.0.1:8788/transfer")
        XCTAssertEqual(nativeClient.authorizationHeader, "Bearer native")
    }

    func testOKRWSubmissionClientEnvironmentFactoryBuildsMAWSBridgeWithWAASToken() throws {
        let client = try MeshMarooOKRWSubmissionClientEnvironmentFactory(environment: [
            MeshMarooOKRWSubmissionClientEnvironmentFactory.mawsBridgeURLKey: "https://maws-bridge.example.test/transfer",
            MeshMarooOKRWSubmissionClientEnvironmentFactory.mawsAgentIdKey: "agent-dailymart-001",
            MeshMarooOKRWSubmissionClientEnvironmentFactory.waasAuthTokenKey: "waas-session-token"
        ]).makeSubmissionClient()

        let mawsClient = try XCTUnwrap(client as? MeshMAWSTransferSendBridgeClient)
        XCTAssertEqual(mawsClient.bridgeEndpoint.absoluteString, "https://maws-bridge.example.test/transfer")
        XCTAssertEqual(mawsClient.agentId, "agent-dailymart-001")
        XCTAssertEqual(mawsClient.authorizationHeader, "Bearer waas-session-token")
    }

    func testOKRWSubmissionClientEnvironmentFactoryFallsBackToPendingOnlyDeterministicClient() async throws {
        let client = try MeshMarooOKRWSubmissionClientEnvironmentFactory(environment: [:]).makeSubmissionClient()
        let deterministicClient = try XCTUnwrap(client as? MeshMarooTestnetDeterministicPaymentExecutionSubmissionClient)
        XCTAssertEqual(deterministicClient.executionStatus, .pending)
        XCTAssertNil(deterministicClient.transactionHash)
        XCTAssertEqual(
            deterministicClient.message,
            MeshMarooOKRWSubmissionClientEnvironmentFactory.fallbackMessage
        )
    }

    func testMarooExecutionLinkPayloadResolvesAnchoredMCPMetadataIntoCanonicalPayload() async throws {
        let fixture = try await samplePaymentExecutionFixture(kind: .payment, amount: Decimal(4_900))
        let providerIdentity = try MeshMarooTestnetChainProvider().identity
        let payload = try MeshMarooTestnetExecutionLinkPayload(
            paymentRequest: fixture.paymentRequest,
            providerIdentity: providerIdentity,
            submittedAt: "2026-05-31T00:00:09Z"
        )

        try payload.validate(paymentRequest: fixture.paymentRequest, providerIdentity: providerIdentity)

        XCTAssertEqual(payload.providerMetadata.provider, "maroo")
        XCTAssertEqual(payload.providerMetadata.network, "maroo-testnet")
        XCTAssertEqual(payload.adapterId, "maroo-testnet-payment-executor-demo-adapter")
        XCTAssertEqual(payload.paymentId, fixture.paymentRequest.paymentId)
        XCTAssertEqual(payload.authorizationId, fixture.paymentRequest.authorizationDecision.authorizationId)
        XCTAssertEqual(payload.executionId, fixture.paymentRequest.executionRequest.executionId)
        XCTAssertEqual(payload.executionKind, .payment)
        XCTAssertEqual(payload.asset, "OKRW")
        XCTAssertEqual(payload.amount, Decimal(4_900))
        XCTAssertEqual(payload.recipient, "0x000000000000000000000000000000000000d417")
        XCTAssertEqual(payload.requestId, fixture.originatingRequest.requestId)
        XCTAssertEqual(payload.requestNonce, fixture.originatingRequest.nonce)
        XCTAssertEqual(payload.callerBundleId, "ai.meshkit.sample.hermeschat")
        XCTAssertEqual(payload.targetBundleId, "ai.meshkit.sample.dailymart")
        XCTAssertEqual(payload.capabilityId, "grocery.purchase_essentials")
        XCTAssertEqual(payload.payloadHash, fixture.originatingRequest.payloadHash)
        XCTAssertEqual(payload.signedRequestHash, try MeshRequestAnchorCanonicalization.signedRequestHash(for: fixture.originatingRequest))
        XCTAssertEqual(payload.anchoringReference, fixture.paymentRequest.requestAnchor.identifier)
        XCTAssertEqual(payload.policyId, "policy-hermes-dailymart-okrw-v1")
        XCTAssertTrue(payload.canonicalString.contains("authorizationStatus=approved"))
        XCTAssertTrue(payload.canonicalString.contains("payloadHashValue=\(fixture.originatingRequest.payloadHash.value)"))
        XCTAssertTrue(payload.canonicalString.contains("signedRequestHashValue=\(fixture.paymentRequest.requestHash.value)"))
        XCTAssertTrue(payload.canonicalString.contains("anchoringTxHash=\(try XCTUnwrap(fixture.paymentRequest.requestAnchor.identifier.transactionHash))"))
        XCTAssertEqual(payload.executionLinkHash.algorithm, "sha256")
        XCTAssertEqual(payload.executionLinkHash.value.count, 64)
    }

    func testMarooExecutionLinkPayloadRejectsProviderAndAnchorMetadataMismatch() async throws {
        let fixture = try await samplePaymentExecutionFixture(kind: .payment, amount: Decimal(4_900))
        let payload = try MeshMarooTestnetExecutionLinkPayload(
            paymentRequest: fixture.paymentRequest,
            providerIdentity: try MeshMarooTestnetChainProvider().identity,
            submittedAt: "2026-05-31T00:00:09Z"
        )
        let wrongProviderIdentity = try MeshChainProviderIdentity(
            providerName: "other-provider",
            networkIdentity: "other-testnet",
            chainId: "other-testnet-1",
            rpcEndpoint: try XCTUnwrap(URL(string: "https://rpc.other-provider.example.invalid")),
            explorerBaseURL: try XCTUnwrap(URL(string: "https://explorer.other-provider.example.invalid"))
        )

        XCTAssertThrowsError(try payload.validate(providerIdentity: wrongProviderIdentity)) { error in
            XCTAssertEqual(error as? MeshKitValidationError, .signatureMismatch("execution link provider metadata mismatch"))
        }

        let tamperedMetadata = try MeshSignedRequestAnchorMetadata(
            requestId: "ios-grocery-maroo-okrw-capability-001",
            nonce: "nonce-tampered-anchor-link",
            timestamp: "2026-05-31T00:00:00Z",
            callerAppId: "app.hermes-chat",
            callerBundleId: "ai.meshkit.sample.hermeschat",
            targetBundleId: "ai.meshkit.sample.dailymart",
            capabilityId: "grocery.purchase_essentials",
            payloadHash: fixture.originatingRequest.payloadHash,
            signature: fixture.originatingRequest.signature,
            signedRequestHash: fixture.paymentRequest.requestHash
        )
        let tamperedAnchor = try MeshRequestAnchor(
            metadata: tamperedMetadata,
            identifier: fixture.paymentRequest.requestAnchor.identifier,
            status: fixture.paymentRequest.requestAnchor.status,
            submittedAt: fixture.paymentRequest.requestAnchor.submittedAt,
            observedAt: fixture.paymentRequest.requestAnchor.observedAt
        )
        XCTAssertThrowsError(try MeshPaymentExecutionRequest(
            paymentId: fixture.paymentRequest.paymentId,
            authorizationDecision: fixture.paymentRequest.authorizationDecision,
            requestAnchor: tamperedAnchor,
            requestedAt: "2026-05-31T00:00:02Z"
        )) { error in
            XCTAssertEqual(error as? MeshKitValidationError, .invalidPaymentExecution("requestAnchorMetadata"))
        }
    }

    func testMarooTestnetPaymentExecutorInvokesExecutionBoundaryWithCanonicalOKRWTransfer() async throws {
        let client = CapturingMarooPaymentExecutionSubmissionClient(
            transactionHash: "0x" + String(repeating: "5", count: 64),
            providerOutcome: "broadcast"
        )
        let adapter = try MeshMarooTestnetPaymentExecutorAdapter(submissionClient: client)
        let fixture = try await samplePaymentExecutionFixture(
            kind: .transfer,
            amount: Decimal(1_200)
        )

        let result = try await adapter.executePayment(
            fixture.paymentRequest,
            originatingRequest: fixture.originatingRequest,
            submittedAt: "2026-05-31T00:00:10Z"
        )
        let capturedInputs = await client.snapshotInputs()
        let capturedTransactionRequests = await client.snapshotTransactionRequests()
        let capturedInput = try XCTUnwrap(capturedInputs.first)
        let capturedTransactionRequest = try XCTUnwrap(capturedTransactionRequests.first)

        XCTAssertTrue(capturedInput.canonicalString.contains("executionKind=transfer"))
        XCTAssertTrue(capturedInput.canonicalString.contains("asset=OKRW"))
        XCTAssertTrue(capturedInput.canonicalString.contains("amount=1200"))
        XCTAssertTrue(capturedInput.canonicalString.contains("requestNonce=nonce-maroo-okrw-capability-transfer-1200"))
        XCTAssertEqual(capturedTransactionRequests.count, 1)
        XCTAssertEqual(capturedTransactionRequest.executionKind, .transfer)
        XCTAssertEqual(capturedTransactionRequest.asset, "OKRW")
        XCTAssertEqual(capturedTransactionRequest.requestNonce, fixture.originatingRequest.nonce)
        XCTAssertEqual(capturedTransactionRequest.anchoringReference, fixture.paymentRequest.requestAnchor.identifier.anchorId)
        XCTAssertEqual(result.kind, .transfer)
        XCTAssertEqual(result.status, .pending)
        XCTAssertEqual(result.transactionHash, "0x" + String(repeating: "5", count: 64))
        XCTAssertEqual(result.providerExtensions["maroo"]?["executionKind"], "transfer")
    }

    func testMarooOKRWExecutionSerializerMapsPaymentLinkageIntoTransactionRequestSchema() async throws {
        let fixture = try await samplePaymentExecutionFixture(
            kind: .payment,
            amount: Decimal(4_900)
        )
        let input = try MeshMarooTestnetPaymentExecutionProviderInput(
            paymentRequest: fixture.paymentRequest,
            providerIdentity: try MeshMarooTestnetChainProvider().identity,
            submittedAt: "2026-05-31T00:00:13Z"
        )

        let transactionRequest = try MeshMarooTestnetOKRWExecutionSerializer.transactionRequest(from: input)

        XCTAssertEqual(transactionRequest.version, "maroo-testnet-okrw-execution/v1")
        XCTAssertEqual(transactionRequest.requestType, "meshkit_okrw_execution")
        XCTAssertEqual(transactionRequest.provider, "maroo")
        XCTAssertEqual(transactionRequest.network, "maroo-testnet")
        XCTAssertEqual(transactionRequest.chainId, "maroo-testnet-1")
        XCTAssertEqual(transactionRequest.adapterId, "maroo-testnet-payment-executor-demo-adapter")
        XCTAssertEqual(
            transactionRequest.executionLinkIdentity,
            "meshkit-maroo-execution-link/v1:pay-maroo-okrw-capability-001:exec-maroo-okrw-capability-001:payment:nonce-maroo-okrw-capability-payment-4900:policy-hermes-dailymart-okrw-v1"
        )
        XCTAssertEqual(transactionRequest.executionLinkHash, input.executionLinkPayload.executionLinkHash)
        XCTAssertEqual(transactionRequest.paymentId, fixture.paymentRequest.paymentId)
        XCTAssertEqual(transactionRequest.authorizationId, fixture.paymentRequest.authorizationDecision.authorizationId)
        XCTAssertEqual(transactionRequest.authorizationStatus, .approved)
        XCTAssertEqual(transactionRequest.delegatedWalletAddress, "maroo1dailyMartAgentWallet")
        XCTAssertEqual(transactionRequest.executionId, fixture.paymentRequest.executionRequest.executionId)
        XCTAssertEqual(transactionRequest.executionKind, .payment)
        XCTAssertEqual(transactionRequest.asset, "OKRW")
        XCTAssertEqual(transactionRequest.amount, Decimal(4_900))
        XCTAssertEqual(transactionRequest.recipientAddress, "0x000000000000000000000000000000000000d417")
        XCTAssertEqual(
            transactionRequest.memo,
            "MeshKit|MCP|payment|OKRW|nonce-maroo-okrw-capability-payment-4900|\(fixture.paymentRequest.requestAnchor.identifier.anchorId)"
        )
        XCTAssertEqual(transactionRequest.anchorMetadata.signedMCPRequestHash, fixture.paymentRequest.requestHash)
        XCTAssertEqual(transactionRequest.anchorMetadata.requestNonce, fixture.originatingRequest.nonce)
        XCTAssertEqual(transactionRequest.anchorMetadata.anchoringReference, fixture.paymentRequest.requestAnchor.identifier.anchorId)
        XCTAssertEqual(transactionRequest.anchorMetadata.anchorTransactionHash, fixture.paymentRequest.requestAnchor.identifier.transactionHash)
        XCTAssertEqual(transactionRequest.anchorMetadata.policyId, "policy-hermes-dailymart-okrw-v1")
        XCTAssertEqual(transactionRequest.anchorMetadata.policyHash, fixture.paymentRequest.executionRequest.policyHash)
        XCTAssertEqual(transactionRequest.requestId, fixture.originatingRequest.requestId)
        XCTAssertEqual(transactionRequest.requestNonce, fixture.originatingRequest.nonce)
        XCTAssertEqual(transactionRequest.callerBundleId, "ai.meshkit.sample.hermeschat")
        XCTAssertEqual(transactionRequest.targetBundleId, "ai.meshkit.sample.dailymart")
        XCTAssertEqual(transactionRequest.capabilityId, "grocery.purchase_essentials")
        XCTAssertEqual(transactionRequest.payloadHash, fixture.originatingRequest.payloadHash)
        XCTAssertEqual(transactionRequest.signedMCPRequestHash, fixture.paymentRequest.requestHash)
        XCTAssertEqual(transactionRequest.anchoringReference, fixture.paymentRequest.requestAnchor.identifier.anchorId)
        XCTAssertEqual(transactionRequest.anchorTransactionHash, fixture.paymentRequest.requestAnchor.identifier.transactionHash)
        XCTAssertEqual(transactionRequest.policyId, "policy-hermes-dailymart-okrw-v1")
        XCTAssertEqual(transactionRequest.policyHash, fixture.paymentRequest.executionRequest.policyHash)
        XCTAssertEqual(transactionRequest.submittedAt, input.submittedAt)
    }

    func testMarooOKRWExecutionSerializerMapsTransferLinkageAndEncodesSchemaKeys() async throws {
        let fixture = try await samplePaymentExecutionFixture(
            kind: .transfer,
            amount: Decimal(1_200)
        )
        let input = try MeshMarooTestnetPaymentExecutionProviderInput(
            paymentRequest: fixture.paymentRequest,
            providerIdentity: try MeshMarooTestnetChainProvider().identity,
            submittedAt: "2026-05-31T00:00:14Z"
        )

        let transactionRequest = try MeshMarooTestnetOKRWExecutionSerializer.transactionRequest(from: input)
        let data = try JSONEncoder().encode(transactionRequest)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])

        XCTAssertEqual(transactionRequest.executionKind, .transfer)
        XCTAssertEqual(transactionRequest.amount, Decimal(1_200))
        XCTAssertTrue(transactionRequest.executionLinkIdentity.contains(":transfer:"))
        XCTAssertEqual(object["schema_version"] as? String, "maroo-testnet-okrw-execution/v1")
        XCTAssertEqual(object["request_type"] as? String, "meshkit_okrw_execution")
        XCTAssertEqual(object["execution_kind"] as? String, "transfer")
        XCTAssertEqual(object["asset"] as? String, "OKRW")
        XCTAssertEqual(object["recipient_address"] as? String, "0x000000000000000000000000000000000000d417")
        XCTAssertEqual(
            object["memo"] as? String,
            "MeshKit|MCP|transfer|OKRW|nonce-maroo-okrw-capability-transfer-1200|\(fixture.paymentRequest.requestAnchor.identifier.anchorId)"
        )
        XCTAssertEqual(object["request_nonce"] as? String, "nonce-maroo-okrw-capability-transfer-1200")
        XCTAssertEqual(object["anchoring_reference"] as? String, fixture.paymentRequest.requestAnchor.identifier.anchorId)
        XCTAssertEqual(object["anchor_tx_hash"] as? String, fixture.paymentRequest.requestAnchor.identifier.transactionHash)
        XCTAssertEqual(object["policy_id"] as? String, "policy-hermes-dailymart-okrw-v1")
        let anchorMetadata = try XCTUnwrap(object["anchor_metadata"] as? [String: Any])
        XCTAssertEqual(anchorMetadata["request_nonce"] as? String, "nonce-maroo-okrw-capability-transfer-1200")
        XCTAssertEqual(anchorMetadata["anchoring_reference"] as? String, fixture.paymentRequest.requestAnchor.identifier.anchorId)
        XCTAssertEqual(anchorMetadata["anchor_tx_hash"] as? String, fixture.paymentRequest.requestAnchor.identifier.transactionHash)
        XCTAssertEqual(anchorMetadata["policy_id"] as? String, "policy-hermes-dailymart-okrw-v1")
        XCTAssertEqual((anchorMetadata["signed_mcp_request_hash"] as? [String: Any])?["value"] as? String, fixture.paymentRequest.requestHash.value)
        XCTAssertEqual((anchorMetadata["policy_hash"] as? [String: Any])?["value"] as? String, String(repeating: "f", count: 64))
        XCTAssertEqual((object["execution_link_hash"] as? [String: Any])?["value"] as? String, input.executionLinkPayload.executionLinkHash.value)
        XCTAssertEqual(
            (object["signed_mcp_request_hash"] as? [String: Any])?["value"] as? String,
            fixture.paymentRequest.requestHash.value
        )
        XCTAssertEqual((object["policy_hash"] as? [String: Any])?["value"] as? String, String(repeating: "f", count: 64))
    }

    func testMarooTestnetPaymentExecutorRejectsExecutionBoundaryProviderMismatch() async throws {
        let wrongProvider = try MeshChainProviderMetadata(
            provider: "other-provider",
            network: "other-testnet",
            chainId: "other-testnet-1"
        )
        let client = CapturingMarooPaymentExecutionSubmissionClient(
            providerMetadataOverride: wrongProvider,
            transactionHash: "0x" + String(repeating: "6", count: 64),
            providerOutcome: "confirmed"
        )
        let adapter = try MeshMarooTestnetPaymentExecutorAdapter(submissionClient: client)
        let fixture = try await samplePaymentExecutionFixture(kind: .payment, amount: Decimal(700))

        do {
            _ = try await adapter.executePayment(
                fixture.paymentRequest,
                originatingRequest: fixture.originatingRequest,
                submittedAt: "2026-05-31T00:00:11Z"
            )
            XCTFail("Expected maroo payment adapter to reject a response from the wrong provider boundary")
        } catch {
            XCTAssertEqual(error as? MeshKitValidationError, .signatureMismatch("payment execution provider metadata mismatch"))
        }

        let capturedInputCount = await client.snapshotInputs().count
        XCTAssertEqual(capturedInputCount, 1)
    }

    func testMarooPaymentExecutionProviderInputRejectsProviderMetadataMismatchAndBadOutcomeTxSemantics() async throws {
        let fixture = try await samplePaymentExecutionFixture(kind: .payment, amount: Decimal(800))
        let wrongProviderIdentity = try MeshChainProviderIdentity(
            providerName: "other-provider",
            networkIdentity: "other-testnet",
            chainId: "other-testnet-1",
            rpcEndpoint: try XCTUnwrap(URL(string: "https://rpc.other-provider.example.invalid")),
            explorerBaseURL: try XCTUnwrap(URL(string: "https://explorer.other-provider.example.invalid"))
        )
        XCTAssertThrowsError(try MeshMarooTestnetPaymentExecutionProviderInput(
            paymentRequest: fixture.paymentRequest,
            providerIdentity: wrongProviderIdentity,
            submittedAt: "2026-05-31T00:00:12Z"
        )) { error in
            XCTAssertEqual(error as? MeshKitValidationError, .signatureMismatch("execution link provider metadata mismatch"))
        }
        XCTAssertThrowsError(try MeshMarooTestnetPaymentExecutionSubmissionResponse(
            providerMetadata: try MeshMarooTestnetChainProvider().metadata,
            providerOutcome: "confirmed",
            observedAt: "2026-05-31T00:00:12Z"
        )) { error in
            XCTAssertEqual(error as? MeshKitValidationError, .invalidPaymentExecution("transactionHash"))
        }
        XCTAssertThrowsError(try MeshMarooTestnetPaymentExecutionSubmissionResponse(
            providerMetadata: try MeshMarooTestnetChainProvider().metadata,
            transactionHash: "0x" + String(repeating: "7", count: 64),
            providerOutcome: "policy_denied",
            observedAt: "2026-05-31T00:00:12Z"
        )) { error in
            XCTAssertEqual(error as? MeshKitValidationError, .invalidPaymentExecution("transactionHash"))
        }
    }

    func testMarooOKRWExecutionTransactionRequestRejectsMissingMemoAndMismatchedAnchorMetadata() async throws {
        let fixture = try await samplePaymentExecutionFixture(kind: .payment, amount: Decimal(4_900))
        let input = try MeshMarooTestnetPaymentExecutionProviderInput(
            paymentRequest: fixture.paymentRequest,
            providerIdentity: try MeshMarooTestnetChainProvider().identity,
            submittedAt: "2026-05-31T00:00:15Z"
        )
        let transactionRequest = try MeshMarooTestnetOKRWExecutionSerializer.transactionRequest(from: input)

        XCTAssertThrowsError(try MeshMarooTestnetOKRWExecutionTransactionRequest(
            providerMetadata: input.providerMetadata,
            adapterId: transactionRequest.adapterId,
            executionLinkIdentity: transactionRequest.executionLinkIdentity,
            executionLinkHash: transactionRequest.executionLinkHash,
            paymentId: transactionRequest.paymentId,
            authorizationId: transactionRequest.authorizationId,
            authorizationStatus: transactionRequest.authorizationStatus,
            delegatedWalletAddress: transactionRequest.delegatedWalletAddress,
            executionId: transactionRequest.executionId,
            executionKind: transactionRequest.executionKind,
            asset: transactionRequest.asset,
            amount: transactionRequest.amount,
            recipientAddress: transactionRequest.recipientAddress,
            memo: "",
            anchorMetadata: transactionRequest.anchorMetadata,
            requestId: transactionRequest.requestId,
            requestNonce: transactionRequest.requestNonce,
            callerBundleId: transactionRequest.callerBundleId,
            targetBundleId: transactionRequest.targetBundleId,
            capabilityId: transactionRequest.capabilityId,
            payloadHash: transactionRequest.payloadHash,
            signedMCPRequestHash: transactionRequest.signedMCPRequestHash,
            anchoringReference: transactionRequest.anchoringReference,
            anchorTransactionHash: transactionRequest.anchorTransactionHash,
            policyId: transactionRequest.policyId,
            policyHash: transactionRequest.policyHash,
            submittedAt: transactionRequest.submittedAt
        )) { error in
            XCTAssertEqual(error as? MeshKitValidationError, .invalidPaymentExecution("memo"))
        }

        let mismatchedAnchorMetadata = try MeshMarooTestnetOKRWExecutionAnchorMetadata(
            signedMCPRequestHash: transactionRequest.signedMCPRequestHash,
            requestNonce: "nonce-maroo-mismatched-anchor-metadata",
            anchoringReference: transactionRequest.anchoringReference,
            anchorTransactionHash: transactionRequest.anchorTransactionHash,
            policyId: transactionRequest.policyId,
            policyHash: transactionRequest.policyHash
        )

        XCTAssertThrowsError(try MeshMarooTestnetOKRWExecutionTransactionRequest(
            providerMetadata: input.providerMetadata,
            adapterId: transactionRequest.adapterId,
            executionLinkIdentity: transactionRequest.executionLinkIdentity,
            executionLinkHash: transactionRequest.executionLinkHash,
            paymentId: transactionRequest.paymentId,
            authorizationId: transactionRequest.authorizationId,
            authorizationStatus: transactionRequest.authorizationStatus,
            delegatedWalletAddress: transactionRequest.delegatedWalletAddress,
            executionId: transactionRequest.executionId,
            executionKind: transactionRequest.executionKind,
            asset: transactionRequest.asset,
            amount: transactionRequest.amount,
            recipientAddress: transactionRequest.recipientAddress,
            memo: transactionRequest.memo,
            anchorMetadata: mismatchedAnchorMetadata,
            requestId: transactionRequest.requestId,
            requestNonce: transactionRequest.requestNonce,
            callerBundleId: transactionRequest.callerBundleId,
            targetBundleId: transactionRequest.targetBundleId,
            capabilityId: transactionRequest.capabilityId,
            payloadHash: transactionRequest.payloadHash,
            signedMCPRequestHash: transactionRequest.signedMCPRequestHash,
            anchoringReference: transactionRequest.anchoringReference,
            anchorTransactionHash: transactionRequest.anchorTransactionHash,
            policyId: transactionRequest.policyId,
            policyHash: transactionRequest.policyHash,
            submittedAt: transactionRequest.submittedAt
        )) { error in
            XCTAssertEqual(error as? MeshKitValidationError, .signatureMismatch("maroo OKRW execution anchor metadata mismatch"))
        }
    }

    func testMarooTestnetPaymentExecutorExposesOKRWCapabilityMetadataAndExecutesPayment() async throws {
        let adapter = try MeshMarooTestnetPaymentExecutorAdapter(
            executionStatus: .confirmed,
            transactionHash: "0xokrwcapability123"
        )
        let metadata = try adapter.loadCapabilityMetadata()

        XCTAssertEqual(metadata.identity.provider, "maroo")
        XCTAssertEqual(metadata.identity.network, "maroo-testnet")
        XCTAssertEqual(metadata.identity.chainId, "maroo-testnet-1")
        XCTAssertEqual(metadata.adapterId, "maroo-testnet-payment-executor-demo-adapter")
        XCTAssertEqual(metadata.supportedAssets, ["OKRW"])
        XCTAssertEqual(metadata.supportedExecutionKinds, [.payment, .transfer])
        XCTAssertEqual(
            metadata.paymentOperations,
            [
                try MeshPaymentOperationCapability(
                    executionKind: .payment,
                    asset: "OKRW",
                    requiredCapability: .executePayment
                ),
                try MeshPaymentOperationCapability(
                    executionKind: .transfer,
                    asset: "OKRW",
                    requiredCapability: .executeTransfer
                )
            ]
        )
        XCTAssertTrue(metadata.paymentOperations.allSatisfy(\.amountRequired))
        XCTAssertTrue(metadata.paymentOperations.allSatisfy(\.recipientRequired))
        XCTAssertTrue(metadata.paymentOperations.allSatisfy(\.requestHashLinkageRequired))
        XCTAssertTrue(metadata.paymentOperations.allSatisfy(\.anchoringReferenceRequired))
        XCTAssertTrue(metadata.paymentOperations.allSatisfy(\.policyBindingRequired))
        XCTAssertTrue(metadata.capabilities.contains(.executePayment))
        XCTAssertTrue(metadata.capabilities.contains(.executeTransfer))
        XCTAssertTrue(metadata.requestHashLinkage)
        XCTAssertTrue(metadata.policyBinding)
        XCTAssertEqual(metadata.statusValues, [.pending, .confirmed, .failed, .policyDenied])

        let encodedMetadata = try JSONEncoder().encode(metadata)
        let metadataObject = try XCTUnwrap(JSONSerialization.jsonObject(with: encodedMetadata) as? [String: Any])
        let operationObjects = try XCTUnwrap(metadataObject["paymentOperations"] as? [[String: Any]])
        XCTAssertEqual(operationObjects.count, 2)
        XCTAssertEqual(operationObjects[0]["executionKind"] as? String, "payment")
        XCTAssertEqual(operationObjects[0]["asset"] as? String, "OKRW")
        XCTAssertEqual(operationObjects[0]["requiredCapability"] as? String, "executePayment")
        XCTAssertEqual(operationObjects[1]["executionKind"] as? String, "transfer")
        XCTAssertEqual(operationObjects[1]["asset"] as? String, "OKRW")
        XCTAssertEqual(operationObjects[1]["requiredCapability"] as? String, "executeTransfer")

        let fixture = try await samplePaymentExecutionFixture(kind: .payment, amount: Decimal(4_900))
        let result = try await adapter.executePayment(
            fixture.paymentRequest,
            originatingRequest: fixture.originatingRequest,
            submittedAt: "2026-05-31T00:00:03Z"
        )

        XCTAssertEqual(result.identity.metadata, metadata.identity.metadata)
        XCTAssertEqual(result.status, .confirmed)
        XCTAssertEqual(result.tokenSymbol, "OKRW")
        XCTAssertEqual(result.amount, Decimal(4_900))
        XCTAssertEqual(result.recipientAddress, "0x000000000000000000000000000000000000d417")
        XCTAssertEqual(result.requestHash, fixture.paymentRequest.requestHash)
        XCTAssertEqual(result.transactionHash, "0xokrwcapability123")
        XCTAssertEqual(result.providerExtensions["maroo"]?["adapterId"], metadata.adapterId)
        XCTAssertEqual(result.providerExtensions["maroo"]?["asset"], "OKRW")
        XCTAssertEqual(result.providerExtensions["maroo"]?["executionKind"], "payment")
        XCTAssertEqual(result.providerExtensions["maroo"]?["requestHash"], fixture.paymentRequest.requestHash.value)
        XCTAssertEqual(result.providerExtensions["maroo"]?["policyId"], "policy-hermes-dailymart-okrw-v1")

        let transferFixture = try await samplePaymentExecutionFixture(kind: .transfer, amount: Decimal(1_200))
        let transferResult = try await adapter.executePayment(
            transferFixture.paymentRequest,
            originatingRequest: transferFixture.originatingRequest,
            submittedAt: "2026-05-31T00:00:04Z"
        )

        XCTAssertEqual(transferResult.kind, .transfer)
        XCTAssertEqual(transferResult.status, .confirmed)
        XCTAssertEqual(transferResult.tokenSymbol, "OKRW")
        XCTAssertEqual(transferResult.amount, Decimal(1_200))
        XCTAssertEqual(transferResult.recipientAddress, "0x000000000000000000000000000000000000d417")
        XCTAssertEqual(transferResult.requestHash, transferFixture.paymentRequest.requestHash)
        XCTAssertEqual(transferResult.providerExtensions["maroo"]?["executionKind"], "transfer")
        XCTAssertEqual(transferResult.providerExtensions["maroo"]?["requestHash"], transferFixture.paymentRequest.requestHash.value)
        XCTAssertEqual(transferResult.providerExtensions["maroo"]?["policyHash"], String(repeating: "f", count: 64))
    }

    func testMarooOKRWTransferCapabilityMetadataContractIsProviderNeutral() throws {
        let adapter = try MeshMarooTestnetPaymentExecutorAdapter()
        let metadata = try adapter.loadCapabilityMetadata()
        let transferOperation = try XCTUnwrap(
            metadata.paymentOperations.first { $0.executionKind == .transfer && $0.asset == "OKRW" }
        )

        XCTAssertEqual(metadata.identity.metadata, try MeshMarooTestnetChainProvider().metadata)
        XCTAssertEqual(metadata.adapterId, MeshMarooTestnetPaymentExecutorAdapter.adapterId)
        XCTAssertTrue(metadata.capabilities.contains(.executeTransfer))
        XCTAssertTrue(metadata.supportedExecutionKinds.contains(.transfer))
        XCTAssertTrue(try metadata.supportsAsset("okrw"))
        XCTAssertEqual(transferOperation.requiredCapability, .executeTransfer)
        XCTAssertTrue(transferOperation.amountRequired)
        XCTAssertTrue(transferOperation.recipientRequired)
        XCTAssertTrue(transferOperation.requestHashLinkageRequired)
        XCTAssertTrue(transferOperation.anchoringReferenceRequired)
        XCTAssertTrue(transferOperation.policyBindingRequired)

        let encoded = try JSONEncoder().encode(metadata)
        let decoded = try JSONDecoder().decode(MeshPaymentExecutionCapabilityMetadata.self, from: encoded)
        XCTAssertEqual(decoded, metadata)

        XCTAssertThrowsError(try MeshPaymentExecutionCapabilityMetadata(
            identity: metadata.identity,
            adapterId: metadata.adapterId,
            capabilities: [.executePayment],
            supportedExecutionKinds: [.transfer],
            supportedAssets: ["OKRW"],
            paymentOperations: [transferOperation],
            requestHashLinkage: true,
            policyBinding: true
        )) { error in
            XCTAssertEqual(error as? MeshKitValidationError, .invalidPaymentExecution("paymentOperations.requiredCapability"))
        }
    }

    func testMarooTestnetPaymentExecutorRunsThroughProviderNeutralProtocolForPaymentAndTransfer() async throws {
        let executor: any MeshPaymentExecutor = try MeshMarooTestnetPaymentExecutorAdapter(
            executionStatus: .pending,
            transactionHash: "0xokrwpending123"
        )
        let configuration = try executor.loadPaymentExecutorConfiguration()

        XCTAssertEqual(configuration.identity.provider, "maroo")
        XCTAssertEqual(configuration.identity.network, "maroo-testnet")
        XCTAssertTrue(configuration.supports(.executePayment))
        XCTAssertTrue(configuration.supports(.executeTransfer))
        XCTAssertFalse(configuration.supports(.lookupExecutionStatus))

        for kind in [MeshAgentWalletExecutionKind.payment, .transfer] {
            let fixture = try await samplePaymentExecutionFixture(kind: kind, amount: Decimal(900))
            let result = try await executor.executePayment(
                fixture.paymentRequest,
                originatingRequest: fixture.originatingRequest,
                submittedAt: "2026-05-31T00:00:05Z"
            )

            XCTAssertEqual(result.kind, kind)
            XCTAssertEqual(result.status, .pending)
            XCTAssertEqual(result.identity.metadata, configuration.identity.metadata)
            XCTAssertEqual(result.tokenSymbol, "OKRW")
            XCTAssertEqual(result.transactionHash, "0xokrwpending123")
            XCTAssertEqual(result.requestHash, fixture.paymentRequest.requestHash)
            XCTAssertEqual(result.providerExtensions["maroo"]?["executionKind"], kind.rawValue)
            XCTAssertEqual(result.providerExtensions["maroo"]?["requestHash"], fixture.paymentRequest.requestHash.value)
        }
    }

    func testMarooAdaptersLinkAnchoredSignedMCPRequestToOKRWExecutionRecord() async throws {
        let anchorClient = CapturingMarooIntegratedRequestAnchorSubmissionClient(
            transactionHash: "0x" + String(repeating: "9", count: 64),
            providerOutcome: "confirmed"
        )
        let paymentClient = CapturingMarooPaymentExecutionSubmissionClient(
            transactionHash: "0x" + String(repeating: "a", count: 64),
            providerOutcome: "confirmed"
        )
        let anchorAdapter = try MeshMarooTestnetRequestAnchorAdapter(submissionClient: anchorClient)
        let paymentAdapter = try MeshMarooTestnetPaymentExecutorAdapter(submissionClient: paymentClient)
        let request = signedDailyMartRequest(
            nonce: "nonce-maroo-integrated-anchor-to-okrw",
            budget: "4900"
        )
        let policyHash = MeshPayloadHash(value: String(repeating: "f", count: 64))
        let policy = try MeshAgentWalletDelegatedSpendingPolicy(
            policyId: "policy-hermes-dailymart-okrw-v1",
            policyHash: policyHash,
            consentGrantId: "grant-hermes-dailymart-001",
            merchantScope: "merchant.dailymart",
            capabilityScope: "grocery.purchase_essentials",
            singlePaymentMax: Decimal(5_000),
            sessionTotalLimit: Decimal(15_000),
            remainingLimit: Decimal(15_000),
            expiresAt: "2026-06-30T00:00:00Z",
            asset: "okrw",
            recipientAddress: "0x000000000000000000000000000000000000d417"
        )
        let submission = try MeshRequestAnchorSubmission(
            request: request,
            policy: policy,
            providerIdentity: anchorAdapter.identity,
            submittedAt: "2026-05-31T00:10:00Z"
        )
        let executionRequest = try MeshAgentWalletExecutionRequest(
            executionId: "exec-maroo-integrated-anchor-to-okrw",
            kind: .payment,
            requestAnchorMetadata: submission.payload.metadata,
            scope: MeshAgentWalletSpendingScope(
                merchantId: policy.merchantScope,
                targetBundleId: request.target.targetBundleId,
                capabilityId: policy.capabilityScope,
                consentGrantId: policy.consentGrantId
            ),
            amount: Decimal(4_900),
            currencyCode: "krw",
            tokenSymbol: "okrw",
            recipientAddress: try XCTUnwrap(policy.recipientAddress),
            policyId: policy.policyId,
            policyHash: policy.policyHash
        )
        let authorizationDecision = try MeshAgentWalletAuthorizationDecision(
            authorizationId: "auth-maroo-integrated-anchor-to-okrw",
            walletIdentity: MeshAgentWalletIdentity(
                walletId: "wallet-hermes-dailymart-okrw-v1",
                agentId: "agent.hermes-chat.daily-mart",
                walletAddress: "maroo1dailyMartAgentWallet",
                providerMetadata: MeshAgentWalletProviderMetadata(
                    chainProviderIdentity: anchorAdapter.identity,
                    adapterId: "maroo-testnet-agent-wallet-adapter"
                ),
                signingBoundary: .providerSubmission
            ),
            executionRequest: executionRequest,
            status: .approved,
            approvedAmount: Decimal(4_900),
            decidedAt: "2026-05-31T00:10:01Z"
        )
        let result = try await MeshRequestAnchorSubmissionModule(provider: anchorAdapter).submitAndExecute(
            submission,
            boundTo: request,
            policy: policy,
            authorizationDecision: authorizationDecision,
            paymentId: "pay-maroo-integrated-anchor-to-okrw",
            requestedAt: "2026-05-31T00:10:02Z",
            paymentSubmittedAt: "2026-05-31T00:10:03Z",
            executor: paymentAdapter
        )
        let anchorInputs = await anchorClient.snapshotInputs()
        let paymentInputs = await paymentClient.snapshotInputs()
        let paymentTransactionRequests = await paymentClient.snapshotTransactionRequests()
        let anchorInput = try XCTUnwrap(anchorInputs.first)
        let paymentInput = try XCTUnwrap(paymentInputs.first)
        let paymentTransactionRequest = try XCTUnwrap(paymentTransactionRequests.first)

        XCTAssertEqual(result.status, .confirmed)
        XCTAssertEqual(result.transactionHash, "0x" + String(repeating: "a", count: 64))
        XCTAssertEqual(result.identity.metadata, anchorAdapter.identity.metadata)
        XCTAssertEqual(result.requestHash, submission.payload.metadata.signedRequestHash)
        XCTAssertEqual(result.requestAnchorIdentifier.anchorId, "maroo-anchor-ios-grocery-maroo-okrw-capability-001")
        XCTAssertEqual(result.requestAnchorIdentifier.transactionHash, "0x" + String(repeating: "9", count: 64))
        XCTAssertEqual(result.providerExtensions["maroo"]?["requestHash"], submission.payload.metadata.signedRequestHash.value)
        XCTAssertEqual(result.providerExtensions["maroo"]?["anchoringReference"], result.requestAnchorIdentifier.anchorId)
        XCTAssertEqual(result.providerExtensions["maroo"]?["anchorTxHash"], result.requestAnchorIdentifier.transactionHash)
        XCTAssertEqual(result.providerExtensions["maroo"]?["policyId"], policy.policyId)
        XCTAssertEqual(result.providerExtensions["maroo"]?["policyHash"], policy.policyHash.value)
        XCTAssertEqual(anchorInput.payload.policyId, policy.policyId)
        XCTAssertEqual(anchorInput.payload.policyHash, policy.policyHash)
        XCTAssertEqual(anchorInput.payload.metadata.nonce, request.nonce)
        XCTAssertEqual(paymentInput.executionLinkPayload.signedRequestHash, submission.payload.metadata.signedRequestHash)
        XCTAssertEqual(paymentInput.executionLinkPayload.anchoringReference, result.requestAnchorIdentifier)
        XCTAssertEqual(paymentInput.executionLinkPayload.policyId, policy.policyId)
        XCTAssertEqual(paymentInput.executionLinkPayload.policyHash, policy.policyHash)
        XCTAssertEqual(paymentTransactionRequests.count, 1)
        XCTAssertEqual(paymentTransactionRequest.executionKind, .payment)
        XCTAssertEqual(paymentTransactionRequest.requestNonce, request.nonce)
        XCTAssertEqual(paymentTransactionRequest.signedMCPRequestHash, submission.payload.metadata.signedRequestHash)
        XCTAssertEqual(paymentTransactionRequest.anchoringReference, result.requestAnchorIdentifier.anchorId)
        XCTAssertEqual(paymentTransactionRequest.anchorTransactionHash, result.requestAnchorIdentifier.transactionHash)
        XCTAssertEqual(paymentTransactionRequest.policyId, policy.policyId)
        XCTAssertEqual(paymentTransactionRequest.policyHash, policy.policyHash)
        XCTAssertTrue(paymentInput.canonicalString.contains("executionLinkHashValue=\(paymentInput.executionLinkPayload.executionLinkHash.value)"))
        XCTAssertTrue(paymentInput.executionLinkPayload.canonicalString.contains("anchoringReference=\(result.requestAnchorIdentifier.anchorId)"))
    }

    func testMarooOKRWExecutionResultMapsIntoReceiptLinkageWithAnchoredRequestFields() async throws {
        let client = CapturingMarooPaymentExecutionSubmissionClient(
            transactionHash: "0x" + String(repeating: "e", count: 64),
            providerOutcome: "confirmed"
        )
        let adapter = try MeshMarooTestnetPaymentExecutorAdapter(submissionClient: client)
        let fixture = try await samplePaymentExecutionFixture(
            kind: .payment,
            amount: Decimal(4_900)
        )

        let result = try await adapter.executePayment(
            fixture.paymentRequest,
            originatingRequest: fixture.originatingRequest,
            submittedAt: "2026-05-31T00:00:23Z"
        )
        let linkage = try MeshPaymentExecutionReceiptLinkageMapper.map(
            paymentResult: result,
            executionRequest: fixture.paymentRequest.executionRequest,
            walletAddress: "maroo1dailyMartAgentWallet"
        )

        XCTAssertEqual(linkage.requestHash, fixture.paymentRequest.requestHash)
        XCTAssertEqual(linkage.anchoringReference, fixture.paymentRequest.requestAnchor.identifier.anchorId)
        XCTAssertEqual(
            linkage.executionAttemptId,
            try MeshChainProof.executionAttemptIdentity(
                paymentId: fixture.paymentRequest.paymentId,
                authorizationId: fixture.paymentRequest.authorizationDecision.authorizationId,
                executionId: fixture.paymentRequest.executionRequest.executionId
            )
        )
        XCTAssertEqual(linkage.txHash, "0x" + String(repeating: "e", count: 64))
        XCTAssertEqual(linkage.proof.requestHash, fixture.paymentRequest.requestHash)
        XCTAssertEqual(linkage.proof.anchoringReference, fixture.paymentRequest.requestAnchor.identifier.anchorId)
        XCTAssertEqual(linkage.proof.executionId, fixture.paymentRequest.executionRequest.executionId)
        XCTAssertEqual(linkage.proof.anchorTxHash, fixture.paymentRequest.requestAnchor.identifier.transactionHash)
        XCTAssertEqual(linkage.proof.txHash, "0x" + String(repeating: "e", count: 64))
        XCTAssertEqual(linkage.receiptResultFields["requestHash"], fixture.paymentRequest.requestHash.value)
        XCTAssertEqual(linkage.receiptResultFields["anchoringReference"], fixture.paymentRequest.requestAnchor.identifier.anchorId)
        XCTAssertEqual(linkage.receiptResultFields["executionAttemptId"], linkage.executionAttemptId)
        XCTAssertEqual(linkage.receiptResultFields["paymentId"], fixture.paymentRequest.paymentId)
        XCTAssertEqual(linkage.receiptResultFields["authorizationId"], fixture.paymentRequest.authorizationDecision.authorizationId)
        XCTAssertEqual(linkage.receiptResultFields["executionId"], fixture.paymentRequest.executionRequest.executionId)
        XCTAssertEqual(linkage.receiptResultFields["txHash"], "0x" + String(repeating: "e", count: 64))
        XCTAssertEqual(linkage.receiptResultFields["asset"], "OKRW")
        XCTAssertEqual(linkage.receiptResultFields["policyId"], fixture.paymentRequest.executionRequest.policyId)
        XCTAssertEqual(linkage.receiptResultFields["policyHash"], fixture.paymentRequest.executionRequest.policyHash.value)

        let receipt = try DailyMartTargetReceiptFactory(
            signer: MeshReceiptSigner.ed25519(
                keyId: "dailymart-receipt-key",
                privateKey: Self.signingKey
            )
        ).makeAcceptedCallReceipt(
            receiptId: "DM-2026-0531-okrw-linkage-receipt",
            request: fixture.originatingRequest,
            status: "purchased",
            baseResult: [
                "order_id": "DM-2026-0531-OKRW-LINKAGE",
                "total_krw": "4900",
                "payment_asset": "OKRW",
                "policy_verification": MeshDelegatedSpendingPolicyVerificationStatus.approved.rawValue
            ],
            chainProof: linkage.proof,
            nonce: "DM-2026-0531-okrw-linkage-receipt-nonce",
            timestamp: "2026-05-31T00:00:24Z"
        )
        let decodedReceipt = try MeshReceipt.decodedFromURLScheme(receipt.encodedForURLScheme())
        let ownershipProof = try MeshReceiptChainProofSerializer.targetOwnedProof(
            in: decodedReceipt,
            expectedTargetAppId: DailyMartTargetReceiptFactory.targetAppId,
            expectedTargetBundleId: DailyMartTargetReceiptFactory.targetBundleId,
            expectedRequest: fixture.originatingRequest
        )

        XCTAssertEqual(decodedReceipt.result["requestHash"], fixture.paymentRequest.requestHash.value)
        XCTAssertEqual(decodedReceipt.result["anchoringReference"], fixture.paymentRequest.requestAnchor.identifier.anchorId)
        XCTAssertEqual(decodedReceipt.result["executionAttemptId"], linkage.executionAttemptId)
        XCTAssertEqual(decodedReceipt.result["paymentId"], fixture.paymentRequest.paymentId)
        XCTAssertEqual(decodedReceipt.result["authorizationId"], fixture.paymentRequest.authorizationDecision.authorizationId)
        XCTAssertEqual(decodedReceipt.result["executionId"], fixture.paymentRequest.executionRequest.executionId)
        XCTAssertEqual(decodedReceipt.result["txHash"], "0x" + String(repeating: "e", count: 64))
        XCTAssertEqual(decodedReceipt.result["policyId"], fixture.paymentRequest.executionRequest.policyId)
        XCTAssertEqual(decodedReceipt.result["policyHash"], fixture.paymentRequest.executionRequest.policyHash.value)
        XCTAssertEqual(ownershipProof.proof.policyId, fixture.paymentRequest.executionRequest.policyId)
        XCTAssertEqual(ownershipProof.proof.policyHash, fixture.paymentRequest.executionRequest.policyHash)
        XCTAssertEqual(ownershipProof.anchoredRequestLinkage.requestHash, fixture.paymentRequest.requestHash)
        XCTAssertEqual(ownershipProof.anchoredRequestLinkage.anchoringReference, fixture.paymentRequest.requestAnchor.identifier.anchorId)
        XCTAssertEqual(ownershipProof.transactionReference?.value, "0x" + String(repeating: "e", count: 64))
    }

    func testMarooOKRWTransferReceiptLinkagePreservesPolicyMetadata() async throws {
        let client = CapturingMarooPaymentExecutionSubmissionClient(
            transactionHash: "0x" + String(repeating: "b", count: 64),
            providerOutcome: "confirmed"
        )
        let adapter = try MeshMarooTestnetPaymentExecutorAdapter(submissionClient: client)
        let fixture = try await samplePaymentExecutionFixture(
            kind: .transfer,
            amount: Decimal(1_200)
        )
        let expectedPolicyId = fixture.paymentRequest.executionRequest.policyId
        let expectedPolicyHash = fixture.paymentRequest.executionRequest.policyHash

        let result = try await adapter.executePayment(
            fixture.paymentRequest,
            originatingRequest: fixture.originatingRequest,
            submittedAt: "2026-05-31T00:00:25Z"
        )
        let linkage = try MeshPaymentExecutionReceiptLinkageMapper.map(
            paymentResult: result,
            executionRequest: fixture.paymentRequest.executionRequest,
            walletAddress: "maroo1dailyMartAgentWallet"
        )

        XCTAssertEqual(result.kind, .transfer)
        XCTAssertEqual(linkage.proof.policyId, expectedPolicyId)
        XCTAssertEqual(linkage.proof.policyHash, expectedPolicyHash)
        XCTAssertEqual(linkage.receiptResultFields["policyId"], expectedPolicyId)
        XCTAssertEqual(linkage.receiptResultFields["policyHash"], expectedPolicyHash.value)

        let receipt = try DailyMartTargetReceiptFactory(
            signer: MeshReceiptSigner.ed25519(
                keyId: "dailymart-receipt-key",
                privateKey: Self.signingKey
            )
        ).makeAcceptedCallReceipt(
            receiptId: "DM-2026-0531-okrw-transfer-linkage-receipt",
            request: fixture.originatingRequest,
            status: "purchased",
            baseResult: [
                "order_id": "DM-2026-0531-OKRW-TRANSFER-LINKAGE",
                "total_krw": "1200",
                "payment_asset": "OKRW",
                "policy_verification": MeshDelegatedSpendingPolicyVerificationStatus.approved.rawValue
            ],
            chainProof: linkage.proof,
            nonce: "DM-2026-0531-okrw-transfer-linkage-receipt-nonce",
            timestamp: "2026-05-31T00:00:26Z"
        )
        let decodedReceipt = try MeshReceipt.decodedFromURLScheme(receipt.encodedForURLScheme())
        let ownershipProof = try MeshReceiptChainProofSerializer.targetOwnedProof(
            in: decodedReceipt,
            expectedTargetAppId: DailyMartTargetReceiptFactory.targetAppId,
            expectedTargetBundleId: DailyMartTargetReceiptFactory.targetBundleId,
            expectedRequest: fixture.originatingRequest
        )

        XCTAssertEqual(decodedReceipt.result["policyId"], expectedPolicyId)
        XCTAssertEqual(decodedReceipt.result["policyHash"], expectedPolicyHash.value)
        XCTAssertEqual(ownershipProof.proof.policyId, expectedPolicyId)
        XCTAssertEqual(ownershipProof.proof.policyHash, expectedPolicyHash)
        XCTAssertEqual(ownershipProof.anchoredRequestLinkage.requestHash, fixture.paymentRequest.requestHash)
        XCTAssertEqual(ownershipProof.anchoredRequestLinkage.anchoringReference, fixture.paymentRequest.requestAnchor.identifier.anchorId)
        XCTAssertEqual(ownershipProof.transactionReference?.value, "0x" + String(repeating: "b", count: 64))
    }

    func testMarooOKRWReceiptLinkageRejectsPolicyMetadataDrift() async throws {
        let adapter = try MeshMarooTestnetPaymentExecutorAdapter(
            executionStatus: .confirmed,
            transactionHash: "0x" + String(repeating: "d", count: 64)
        )
        let fixture = try await samplePaymentExecutionFixture(
            kind: .payment,
            amount: Decimal(4_900)
        )
        let result = try await adapter.executePayment(
            fixture.paymentRequest,
            originatingRequest: fixture.originatingRequest,
            submittedAt: "2026-05-31T00:00:24Z"
        )
        let proof = try MeshChainProof(
            paymentResult: result,
            executionRequest: fixture.paymentRequest.executionRequest,
            walletAddress: "maroo1dailyMartAgentWallet"
        )
        var driftedPolicyIdFields = try proof.receiptResultFields()
        driftedPolicyIdFields["policyId"] = "policy-hermes-dailymart-okrw-drifted"
        var driftedPolicyHashFields = try proof.receiptResultFields()
        driftedPolicyHashFields["policyHash"] = String(repeating: "a", count: 64)

        XCTAssertThrowsError(try MeshPaymentExecutionReceiptLinkage(
            proof: proof,
            receiptResultFields: driftedPolicyIdFields
        )) { error in
            XCTAssertEqual(error as? MeshKitValidationError, .invalidChainProof("policyId"))
        }
        XCTAssertThrowsError(try MeshPaymentExecutionReceiptLinkage(
            proof: proof,
            receiptResultFields: driftedPolicyHashFields
        )) { error in
            XCTAssertEqual(error as? MeshKitValidationError, .invalidChainProof("policyHash"))
        }
    }

    func testMarooOKRWReceiptLinkageMapperRejectsMismatchedRequestHash() async throws {
        let adapter = try MeshMarooTestnetPaymentExecutorAdapter(
            executionStatus: .confirmed,
            transactionHash: "0x" + String(repeating: "f", count: 64)
        )
        let fixture = try await samplePaymentExecutionFixture(
            kind: .payment,
            amount: Decimal(4_900)
        )
        let result = try await adapter.executePayment(
            fixture.paymentRequest,
            originatingRequest: fixture.originatingRequest,
            submittedAt: "2026-05-31T00:00:25Z"
        )
        let request = fixture.originatingRequest
        let mismatchedMetadata = try MeshSignedRequestAnchorMetadata(
            requestId: request.requestId,
            nonce: request.nonce,
            timestamp: request.timestamp,
            callerAppId: request.caller.appId,
            callerBundleId: request.caller.bundleId,
            targetBundleId: request.target.targetBundleId,
            capabilityId: request.target.capabilityId,
            payloadHash: request.payloadHash,
            signature: request.signature,
            signedRequestHash: MeshPayloadHash(value: String(repeating: "0", count: 64))
        )
        let originalExecutionRequest = fixture.paymentRequest.executionRequest
        let mismatchedExecutionRequest = try MeshAgentWalletExecutionRequest(
            executionId: originalExecutionRequest.executionId,
            kind: originalExecutionRequest.kind,
            requestAnchorMetadata: mismatchedMetadata,
            scope: originalExecutionRequest.scope,
            amount: originalExecutionRequest.amount,
            currencyCode: originalExecutionRequest.currencyCode,
            tokenSymbol: originalExecutionRequest.tokenSymbol,
            recipientAddress: originalExecutionRequest.recipientAddress,
            policyId: originalExecutionRequest.policyId,
            policyHash: originalExecutionRequest.policyHash
        )

        XCTAssertThrowsError(try MeshPaymentExecutionReceiptLinkageMapper.map(
            paymentResult: result,
            executionRequest: mismatchedExecutionRequest,
            walletAddress: "maroo1DailyMartAgentWallet"
        )) { error in
            XCTAssertEqual(error as? MeshKitValidationError, .invalidChainProof("requestHash"))
        }
    }

    func testMarooTestnetPaymentExecutorMapsConfirmedPendingFailedAndPolicyDeniedOutcomes() async throws {
        struct Case {
            let status: MeshPaymentExecutionStatus
            let transactionHash: String?
            let authorizationStatus: MeshAgentWalletAuthorizationStatus
            let expectedMessage: String?
        }

        let cases = [
            Case(
                status: .confirmed,
                transactionHash: "0xokrwconfirmed123",
                authorizationStatus: .approved,
                expectedMessage: nil
            ),
            Case(
                status: .pending,
                transactionHash: nil,
                authorizationStatus: .approved,
                expectedMessage: "maroo testnet OKRW execution pending confirmation"
            ),
            Case(
                status: .failed,
                transactionHash: "0xokrwfailed123",
                authorizationStatus: .approved,
                expectedMessage: "maroo testnet OKRW execution failed"
            ),
            Case(
                status: .policyDenied,
                transactionHash: nil,
                authorizationStatus: .denied,
                expectedMessage: "policy-denied"
            )
        ]

        for testCase in cases {
            let adapter = try MeshMarooTestnetPaymentExecutorAdapter(
                executionStatus: testCase.status,
                transactionHash: testCase.transactionHash
            )
            let fixture = try await samplePaymentExecutionFixture(
                kind: .payment,
                amount: Decimal(700),
                authorizationStatus: testCase.authorizationStatus
            )

            let result = try await adapter.executePayment(
                fixture.paymentRequest,
                originatingRequest: fixture.originatingRequest,
                submittedAt: "2026-05-31T00:00:06Z"
            )

            XCTAssertEqual(result.status, testCase.status)
            XCTAssertEqual(result.transactionHash, testCase.transactionHash)
            XCTAssertEqual(result.message, testCase.expectedMessage)
            XCTAssertEqual(result.providerExtensions["maroo"]?["asset"], "OKRW")
            XCTAssertEqual(result.providerExtensions["maroo"]?["policyId"], "policy-hermes-dailymart-okrw-v1")
        }
    }

    func testMarooOKRWExecutionResponseNormalizationMapsSuccessPendingAndFailedResponses() async throws {
        struct Case {
            let providerOutcome: String
            let expectedOutcome: MeshMarooTestnetPaymentExecutionProviderOutcome
            let expectedStatus: MeshPaymentExecutionStatus
            let transactionHash: String?
            let expectedMessage: String?
            let expectedErrorCode: String?
        }

        let cases = [
            Case(
                providerOutcome: "success",
                expectedOutcome: .success,
                expectedStatus: .confirmed,
                transactionHash: "0x" + String(repeating: "8", count: 64),
                expectedMessage: nil,
                expectedErrorCode: nil
            ),
            Case(
                providerOutcome: "awaiting-confirmation",
                expectedOutcome: .pending,
                expectedStatus: .pending,
                transactionHash: nil,
                expectedMessage: "maroo testnet OKRW execution pending confirmation",
                expectedErrorCode: nil
            ),
            Case(
                providerOutcome: "rpc_error",
                expectedOutcome: .failure,
                expectedStatus: .failed,
                transactionHash: nil,
                expectedMessage: "maroo testnet OKRW execution failed",
                expectedErrorCode: "payment_execution_failed"
            )
        ]

        for testCase in cases {
            let client = CapturingMarooPaymentExecutionSubmissionClient(
                transactionHash: testCase.transactionHash,
                providerOutcome: testCase.providerOutcome
            )
            let adapter = try MeshMarooTestnetPaymentExecutorAdapter(submissionClient: client)
            let fixture = try await samplePaymentExecutionFixture(
                kind: .payment,
                amount: Decimal(700)
            )

            let result = try await adapter.executePayment(
                fixture.paymentRequest,
                originatingRequest: fixture.originatingRequest,
                submittedAt: "2026-05-31T00:00:06Z"
            )
            let response = try await client.snapshotResponse()
            let mapping = try XCTUnwrap(response.resultMapping)

            XCTAssertEqual(mapping.providerOutcome, testCase.expectedOutcome)
            XCTAssertEqual(mapping.executionStatus, testCase.expectedStatus)
            XCTAssertEqual(response.status, testCase.expectedStatus)
            XCTAssertEqual(result.status, testCase.expectedStatus)
            XCTAssertEqual(result.transactionHash, testCase.transactionHash)
            XCTAssertEqual(result.message, testCase.expectedMessage)
            XCTAssertEqual(result.errorPayload?.code, testCase.expectedErrorCode)
            XCTAssertEqual(result.providerExtensions["maroo"]?["providerOutcome"], testCase.expectedOutcome.rawValue)
            XCTAssertEqual(result.providerExtensions["maroo"]?["normalizedStatus"], testCase.expectedStatus.rawValue)
            XCTAssertEqual(result.providerExtensions["maroo"]?["errorCode"], testCase.expectedErrorCode)
            XCTAssertEqual(result.providerExtensions["maroo"]?["asset"], "OKRW")
            XCTAssertEqual(result.providerExtensions["maroo"]?["requestHash"], fixture.paymentRequest.requestHash.value)
        }
    }

    func testMarooConfirmedExecutionRequiresValidLiveConfirmationPayload() throws {
        let providerMetadata = try MeshMarooTestnetChainProvider().metadata
        let transactionHash = "0x" + String(repeating: "8", count: 64)
        let observedAt = "2026-05-31T00:00:17Z"
        let confirmationPayload = try MeshMarooTestnetPaymentConfirmationPayload(
            providerMetadata: providerMetadata,
            transactionHash: transactionHash,
            blockHash: "0x" + String(repeating: "9", count: 64),
            blockNumber: 91,
            confirmationCount: 1,
            confirmedAt: observedAt
        )

        let response = try MeshMarooTestnetPaymentExecutionSubmissionResponse(
            providerMetadata: providerMetadata,
            transactionHash: transactionHash,
            providerOutcome: "confirmed",
            observedAt: observedAt,
            confirmationPayload: confirmationPayload
        )

        XCTAssertEqual(response.status, .confirmed)
        XCTAssertEqual(response.confirmationPayload, confirmationPayload)

        XCTAssertThrowsError(try MeshMarooTestnetPaymentExecutionSubmissionResponse(
            providerMetadata: providerMetadata,
            transactionHash: transactionHash,
            providerOutcome: "confirmed",
            observedAt: observedAt
        )) { error in
            XCTAssertEqual(error as? MeshKitValidationError, .invalidPaymentExecution("confirmationPayload"))
        }

        let mismatchedConfirmationPayload = try MeshMarooTestnetPaymentConfirmationPayload(
            providerMetadata: providerMetadata,
            transactionHash: "0x" + String(repeating: "a", count: 64),
            blockHash: "0x" + String(repeating: "b", count: 64),
            blockNumber: 92,
            confirmationCount: 1,
            confirmedAt: observedAt
        )
        XCTAssertThrowsError(try MeshMarooTestnetPaymentExecutionSubmissionResponse(
            providerMetadata: providerMetadata,
            transactionHash: transactionHash,
            providerOutcome: "confirmed",
            observedAt: observedAt,
            confirmationPayload: mismatchedConfirmationPayload
        )) { error in
            XCTAssertEqual(error as? MeshKitValidationError, .invalidPaymentExecution("confirmationPayload.transactionHash"))
        }
    }

    func testMarooTransactionResponseNormalizesIntoProviderNeutralExecutionResultsForAllOutputShapes() async throws {
        struct Case {
            let providerOutcome: String
            let expectedOutcome: MeshMarooTestnetPaymentExecutionProviderOutcome
            let expectedStatus: MeshPaymentExecutionStatus
            let authorizationStatus: MeshAgentWalletAuthorizationStatus
            let transactionHash: String?
            let expectedMessage: String?
            let expectedErrorCode: String?
        }

        let cases = [
            Case(
                providerOutcome: "confirmed",
                expectedOutcome: .success,
                expectedStatus: .confirmed,
                authorizationStatus: .approved,
                transactionHash: "0x" + String(repeating: "c", count: 64),
                expectedMessage: nil,
                expectedErrorCode: nil
            ),
            Case(
                providerOutcome: "broadcast",
                expectedOutcome: .pending,
                expectedStatus: .pending,
                authorizationStatus: .approved,
                transactionHash: nil,
                expectedMessage: "maroo testnet OKRW execution pending confirmation",
                expectedErrorCode: nil
            ),
            Case(
                providerOutcome: "execution-reverted",
                expectedOutcome: .failure,
                expectedStatus: .failed,
                authorizationStatus: .approved,
                transactionHash: "0x" + String(repeating: "d", count: 64),
                expectedMessage: "maroo testnet OKRW execution failed",
                expectedErrorCode: "payment_execution_failed"
            ),
            Case(
                providerOutcome: "wallet-policy-denied",
                expectedOutcome: .policyDenied,
                expectedStatus: .policyDenied,
                authorizationStatus: .denied,
                transactionHash: nil,
                expectedMessage: "policy denied",
                expectedErrorCode: "policy_denied"
            )
        ]

        for testCase in cases {
            let fixture = try await samplePaymentExecutionFixture(
                kind: .payment,
                amount: Decimal(700),
                authorizationStatus: testCase.authorizationStatus
            )
            let providerMetadata = try MeshMarooTestnetChainProvider().metadata
            let observedAt = "2026-05-31T00:00:16Z"
            let response = try MeshMarooTestnetPaymentExecutionSubmissionResponse(
                providerMetadata: providerMetadata,
                transactionHash: testCase.transactionHash,
                providerOutcome: testCase.providerOutcome,
                observedAt: observedAt,
                confirmationPayload: try marooConfirmationPayload(
                    providerMetadata: providerMetadata,
                    transactionHash: testCase.transactionHash,
                    statusHint: testCase.providerOutcome,
                    observedAt: observedAt
                )
            )
            let mapping = try XCTUnwrap(response.resultMapping)
            let result = try response.normalizedExecutionResult(
                request: fixture.paymentRequest,
                identity: try MeshMarooTestnetChainProvider().identity,
                submittedAt: "2026-05-31T00:00:16Z",
                providerExtensions: [
                    "maroo": [
                        "providerOutcome": mapping.providerOutcome.rawValue,
                        "normalizedStatus": mapping.executionStatus.rawValue,
                        "requestHash": fixture.paymentRequest.requestHash.value
                    ]
                ]
            )

            XCTAssertEqual(mapping.providerOutcome, testCase.expectedOutcome)
            XCTAssertEqual(result.status, testCase.expectedStatus)
            XCTAssertEqual(result.transactionHash, testCase.transactionHash)
            XCTAssertEqual(result.message, testCase.expectedMessage)
            XCTAssertEqual(result.errorPayload?.code, testCase.expectedErrorCode)
            XCTAssertEqual(result.providerExtensions["maroo"]?["providerOutcome"], testCase.expectedOutcome.rawValue)
            XCTAssertEqual(result.providerExtensions["maroo"]?["normalizedStatus"], testCase.expectedStatus.rawValue)
            XCTAssertEqual(result.providerExtensions["maroo"]?["requestHash"], fixture.paymentRequest.requestHash.value)
        }
    }

    func testMarooInFlightTransactionStatesNormalizeToProviderNeutralPendingResults() async throws {
        let inFlightStates = [
            "accepted",
            "tx-queued",
            "broadcasted",
            "in-flight",
            "tx_in_mempool",
            "awaiting confirmation",
            "unconfirmed"
        ]

        for providerTransactionState in inFlightStates {
            let fixture = try await samplePaymentExecutionFixture(
                kind: .payment,
                amount: Decimal(700)
            )
            let response = try MeshMarooTestnetPaymentExecutionSubmissionResponse(
                providerMetadata: try MeshMarooTestnetChainProvider().metadata,
                providerTransactionState: providerTransactionState,
                observedAt: "2026-05-31T00:00:18Z"
            )
            let result = try response.normalizedExecutionResult(
                request: fixture.paymentRequest,
                identity: try MeshMarooTestnetChainProvider().identity,
                submittedAt: "2026-05-31T00:00:18Z",
                providerExtensions: [
                    "maroo": [
                        "providerTransactionState": providerTransactionState,
                        "providerOutcome": MeshMarooTestnetPaymentExecutionProviderOutcome.pending.rawValue,
                        "normalizedStatus": MeshPaymentExecutionStatus.pending.rawValue,
                        "requestHash": fixture.paymentRequest.requestHash.value
                    ]
                ]
            )

            XCTAssertEqual(response.status, .pending)
            XCTAssertEqual(response.providerOutcome, .pending)
            XCTAssertEqual(response.message, "maroo testnet OKRW execution pending confirmation")
            XCTAssertEqual(result.status, .pending)
            XCTAssertNil(result.transactionHash)
            XCTAssertNil(result.errorPayload)
            XCTAssertEqual(result.providerExtensions["maroo"]?["providerTransactionState"], providerTransactionState)
            XCTAssertEqual(result.providerExtensions["maroo"]?["normalizedStatus"], MeshPaymentExecutionStatus.pending.rawValue)
        }
    }

    func testMarooSuccessfulTransactionStatesNormalizeToProviderNeutralConfirmedResults() async throws {
        let successfulStates = [
            "success",
            "tx-succeeded",
            "confirmed",
            "tx_confirmed",
            "included",
            "mined",
            "receipt confirmed"
        ]

        for providerTransactionState in successfulStates {
            let transactionHash = "0x" + String(repeating: "a", count: 64)
            let client = CapturingMarooTransactionStateSubmissionClient(
                transactionHash: transactionHash,
                providerTransactionState: providerTransactionState
            )
            let adapter = try MeshMarooTestnetPaymentExecutorAdapter(submissionClient: client)
            let fixture = try await samplePaymentExecutionFixture(
                kind: .payment,
                amount: Decimal(700)
            )

            let result = try await adapter.executePayment(
                fixture.paymentRequest,
                originatingRequest: fixture.originatingRequest,
                submittedAt: "2026-05-31T00:00:19Z"
            )
            let response = try await client.snapshotResponse()
            let mapping = try MeshMarooTestnetTransactionStateMapping(
                providerTransactionState: providerTransactionState
            )

            XCTAssertEqual(mapping.providerOutcome, .success)
            XCTAssertEqual(mapping.executionStatus, .confirmed)
            XCTAssertEqual(response.status, .confirmed)
            XCTAssertEqual(response.providerOutcome, .success)
            XCTAssertNil(response.message)
            XCTAssertEqual(result.status, .confirmed)
            XCTAssertEqual(result.transactionHash, transactionHash)
            XCTAssertNil(result.errorPayload)
            XCTAssertEqual(result.providerExtensions["maroo"]?["providerOutcome"], MeshMarooTestnetPaymentExecutionProviderOutcome.success.rawValue)
            XCTAssertEqual(result.providerExtensions["maroo"]?["normalizedStatus"], MeshPaymentExecutionStatus.confirmed.rawValue)
        }
    }

    func testMarooFailedTransactionStatesNormalizeToProviderNeutralFailedResults() async throws {
        let failedStates = [
            "failed",
            "tx-failed",
            "execution reverted",
            "tx_execution_reverted",
            "receipt-failed",
            "rpc_error",
            "insufficient funds",
            "tx_timed_out"
        ]

        for providerTransactionState in failedStates {
            let transactionHash = "0x" + String(repeating: "b", count: 64)
            let client = CapturingMarooTransactionStateSubmissionClient(
                transactionHash: transactionHash,
                providerTransactionState: providerTransactionState
            )
            let adapter = try MeshMarooTestnetPaymentExecutorAdapter(submissionClient: client)
            let fixture = try await samplePaymentExecutionFixture(
                kind: .payment,
                amount: Decimal(700)
            )

            let result = try await adapter.executePayment(
                fixture.paymentRequest,
                originatingRequest: fixture.originatingRequest,
                submittedAt: "2026-05-31T00:00:20Z"
            )
            let response = try await client.snapshotResponse()
            let mapping = try MeshMarooTestnetTransactionStateMapping(
                providerTransactionState: providerTransactionState
            )

            XCTAssertEqual(mapping.providerOutcome, .failure)
            XCTAssertEqual(mapping.executionStatus, .failed)
            XCTAssertEqual(response.status, .failed)
            XCTAssertEqual(response.providerOutcome, .failure)
            XCTAssertEqual(response.message, "maroo testnet OKRW execution failed")
            XCTAssertEqual(result.status, .failed)
            XCTAssertEqual(result.transactionHash, transactionHash)
            XCTAssertEqual(result.message, "maroo testnet OKRW execution failed")
            XCTAssertEqual(result.errorPayload?.code, "payment_execution_failed")
            XCTAssertEqual(result.errorPayload?.message, "maroo testnet OKRW execution failed")
            XCTAssertEqual(result.providerExtensions["maroo"]?["providerOutcome"], MeshMarooTestnetPaymentExecutionProviderOutcome.failure.rawValue)
            XCTAssertEqual(result.providerExtensions["maroo"]?["normalizedStatus"], MeshPaymentExecutionStatus.failed.rawValue)
        }
    }

    func testMarooProviderExecutionResultNormalizationProducesReceiptPresentationStates() throws {
        struct Case {
            let providerOutcome: String
            let expectedOutcome: MeshMarooTestnetPaymentExecutionProviderOutcome
            let expectedPaymentStatus: MeshPaymentExecutionStatus
            let expectedProofType: MeshChainProofType
            let expectedChainStatus: MeshChainProofStatus
            let expectedPresentationState: MeshChainProofPresentationState
            let requiresTransactionProof: Bool
            let isTerminal: Bool
            let expectedErrorCode: String?
        }

        let cases: [Case] = [
            Case(
                providerOutcome: "success",
                expectedOutcome: .success,
                expectedPaymentStatus: .confirmed,
                expectedProofType: .paymentExecution,
                expectedChainStatus: .confirmed,
                expectedPresentationState: .paidComplete,
                requiresTransactionProof: true,
                isTerminal: true,
                expectedErrorCode: nil
            ),
            Case(
                providerOutcome: "awaiting-confirmation",
                expectedOutcome: .pending,
                expectedPaymentStatus: .pending,
                expectedProofType: .requestAnchor,
                expectedChainStatus: .pending,
                expectedPresentationState: .submittedNotFinal,
                requiresTransactionProof: false,
                isTerminal: false,
                expectedErrorCode: nil
            ),
            Case(
                providerOutcome: "rpc error",
                expectedOutcome: .failure,
                expectedPaymentStatus: .failed,
                expectedProofType: .paymentExecution,
                expectedChainStatus: .failed,
                expectedPresentationState: .attemptedFailed,
                requiresTransactionProof: false,
                isTerminal: true,
                expectedErrorCode: "payment_execution_failed"
            ),
            Case(
                providerOutcome: "spending-limit-exceeded",
                expectedOutcome: .policyDenied,
                expectedPaymentStatus: .policyDenied,
                expectedProofType: .policyDenial,
                expectedChainStatus: .failed,
                expectedPresentationState: .policyDenied,
                requiresTransactionProof: false,
                isTerminal: true,
                expectedErrorCode: "policy_denied"
            )
        ]

        for testCase in cases {
            let mapping = try MeshMarooTestnetPaymentExecutionResultMapping(
                providerOutcome: testCase.providerOutcome
            )
            let normalizedProofStatus = MeshChainProof.normalizedVerificationStatus(
                for: mapping.executionStatus
            )

            XCTAssertEqual(mapping.providerOutcome, testCase.expectedOutcome)
            XCTAssertEqual(mapping.executionStatus, testCase.expectedPaymentStatus)
            XCTAssertEqual(mapping.errorCode, testCase.expectedErrorCode)
            XCTAssertEqual(normalizedProofStatus.proofType, testCase.expectedProofType)
            XCTAssertEqual(normalizedProofStatus.status, testCase.expectedChainStatus)
            XCTAssertEqual(normalizedProofStatus.presentationState, testCase.expectedPresentationState)
            XCTAssertEqual(normalizedProofStatus.requiresTransactionProof, testCase.requiresTransactionProof)
            XCTAssertEqual(normalizedProofStatus.isTerminal, testCase.isTerminal)
        }
    }

    func testMarooStateMapperBlocksFallbackMockCachedAndSimulatedSourcesFromConfirmedPaymentOrTransfer() async throws {
        let providerMetadata = try MeshMarooTestnetChainProvider().metadata
        let identity = try MeshMarooTestnetChainProvider().identity
        let transactionHash = "0x" + String(repeating: "c", count: 64)
        let observedAt = "2026-05-31T00:00:24Z"
        let confirmationPayload = try MeshMarooTestnetPaymentConfirmationPayload(
            providerMetadata: providerMetadata,
            transactionHash: transactionHash,
            blockHash: "0x" + String(repeating: "d", count: 64),
            blockNumber: 24,
            confirmationCount: 1,
            confirmedAt: observedAt
        )
        let blockedSources: [MeshPaymentExecutionResultSource] = [
            .fallback,
            .mock,
            .cached,
            .simulated
        ]

        for source in blockedSources {
            let stateMapping = MeshPaymentExecutionResultSourceStateMapping(
                source: source,
                providerOutcome: .success
            )

            XCTAssertTrue(stateMapping.isSourceBlockedFromConfirmation)
            XCTAssertEqual(stateMapping.executionStatus, .pending)
            XCTAssertNil(stateMapping.errorCode)
            XCTAssertEqual(
                stateMapping.defaultMessage,
                "\(source.rawValue) execution awaiting live confirmation"
            )

            for kind in [MeshAgentWalletExecutionKind.payment, .transfer] {
                let fixture = try await samplePaymentExecutionFixture(
                    kind: kind,
                    amount: kind == .payment ? Decimal(4_900) : Decimal(1_200)
                )
                let response = try MeshMarooTestnetPaymentExecutionSubmissionResponse(
                    providerMetadata: providerMetadata,
                    transactionHash: transactionHash,
                    providerOutcome: "confirmed",
                    resultSource: source,
                    observedAt: observedAt,
                    confirmationPayload: confirmationPayload
                )
                let result = try response.normalizedExecutionResult(
                    request: fixture.paymentRequest,
                    identity: identity,
                    submittedAt: observedAt,
                    providerExtensions: [
                        "maroo": [
                            "resultSource": source.rawValue,
                            "providerOutcome": MeshMarooTestnetPaymentExecutionProviderOutcome.success.rawValue,
                            "normalizedStatus": response.status.rawValue,
                            "sourceConfirmationBlocked": "true"
                        ]
                    ]
                )
                let proofStatus = MeshChainProof.normalizedVerificationStatus(for: result.status)

                XCTAssertEqual(response.status, .pending)
                XCTAssertNil(response.confirmationPayload)
                XCTAssertEqual(result.kind, kind)
                XCTAssertNotEqual(result.status, .confirmed)
                XCTAssertEqual(result.status, .pending)
                XCTAssertEqual(result.message, "\(source.rawValue) execution awaiting live confirmation")
                XCTAssertEqual(result.providerExtensions["maroo"]?["resultSource"], source.rawValue)
                XCTAssertEqual(result.providerExtensions["maroo"]?["sourceConfirmationBlocked"], "true")
                XCTAssertEqual(proofStatus.status, .pending)
                XCTAssertEqual(proofStatus.presentationState, .submittedNotFinal)
                XCTAssertFalse(proofStatus.requiresTransactionProof)
            }
        }
    }

    func testMarooStateMapperUsesExplicitFallbackStatusWhenLiveConfirmationIsUnavailable() throws {
        struct Case {
            let source: MeshPaymentExecutionResultSource
            let providerOutcome: MeshMarooTestnetPaymentExecutionProviderOutcome
            let explicitStatus: MeshPaymentExecutionStatus
            let expectedStatus: MeshPaymentExecutionStatus
            let expectedErrorCode: String?
            let expectedMessage: String
            let expectedPresentationState: MeshChainProofPresentationState
        }

        let cases: [Case] = [
            Case(
                source: .fallback,
                providerOutcome: .success,
                explicitStatus: .pending,
                expectedStatus: .pending,
                expectedErrorCode: nil,
                expectedMessage: "fallback execution awaiting live confirmation",
                expectedPresentationState: .submittedNotFinal
            ),
            Case(
                source: .cached,
                providerOutcome: .failure,
                explicitStatus: .failed,
                expectedStatus: .failed,
                expectedErrorCode: "non_confirmed_execution_source",
                expectedMessage: "cached execution result cannot confirm payment",
                expectedPresentationState: .attemptedFailed
            ),
            Case(
                source: .simulated,
                providerOutcome: .policyDenied,
                explicitStatus: .policyDenied,
                expectedStatus: .policyDenied,
                expectedErrorCode: "policy_denied",
                expectedMessage: "policy denied",
                expectedPresentationState: .policyDenied
            )
        ]

        for testCase in cases {
            let mapping = MeshPaymentExecutionResultSourceStateMapping(
                source: testCase.source,
                providerOutcome: testCase.providerOutcome,
                explicitStatus: testCase.explicitStatus
            )
            let response = try MeshMarooTestnetPaymentExecutionSubmissionResponse(
                providerMetadata: try MeshMarooTestnetChainProvider().metadata,
                transactionHash: testCase.expectedStatus == .pending ? "0x" + String(repeating: "1", count: 64) : nil,
                status: testCase.explicitStatus,
                observedAt: "2026-05-31T00:01:00Z",
                providerOutcome: testCase.providerOutcome,
                resultSource: testCase.source
            )
            let proofStatus = MeshChainProof.normalizedVerificationStatus(for: response.status)

            XCTAssertTrue(mapping.isSourceBlockedFromConfirmation)
            XCTAssertEqual(mapping.executionStatus, testCase.expectedStatus)
            XCTAssertEqual(mapping.errorCode, testCase.expectedErrorCode)
            XCTAssertEqual(mapping.defaultMessage, testCase.expectedMessage)
            XCTAssertEqual(response.status, testCase.expectedStatus)
            XCTAssertEqual(response.message, testCase.expectedMessage)
            XCTAssertNil(response.confirmationPayload)
            XCTAssertEqual(response.sourceStateMapping?.executionStatus, testCase.expectedStatus)
            XCTAssertEqual(proofStatus.presentationState, testCase.expectedPresentationState)
            XCTAssertNotEqual(response.status, .confirmed)
        }
    }

    func testExternallyBlockedPaymentStateMapperNeverConfirmsWithoutLiveExecutionProof() throws {
        let providerMetadata = try MeshMarooTestnetChainProvider().metadata
        let transactionHash = "0x" + String(repeating: "e", count: 64)
        let observedAt = "2026-05-31T00:01:30Z"
        let confirmationPayload = try MeshMarooTestnetPaymentConfirmationPayload(
            providerMetadata: providerMetadata,
            transactionHash: transactionHash,
            blockHash: "0x" + String(repeating: "f", count: 64),
            blockNumber: 30,
            confirmationCount: 1,
            confirmedAt: observedAt
        )

        let externallyBlockedResponseWithoutOutcome = try MeshMarooTestnetPaymentExecutionSubmissionResponse(
            providerMetadata: providerMetadata,
            transactionHash: transactionHash,
            status: .confirmed,
            observedAt: observedAt,
            resultSource: .fallback,
            confirmationPayload: confirmationPayload
        )
        let externallyBlockedPendingProof = MeshChainProof.normalizedVerificationStatus(
            for: externallyBlockedResponseWithoutOutcome.status
        )
        XCTAssertEqual(externallyBlockedResponseWithoutOutcome.status, .pending)
        XCTAssertEqual(
            externallyBlockedResponseWithoutOutcome.message,
            "fallback execution awaiting live confirmation"
        )
        XCTAssertNil(externallyBlockedResponseWithoutOutcome.confirmationPayload)
        XCTAssertNotEqual(externallyBlockedResponseWithoutOutcome.status, .confirmed)
        XCTAssertEqual(externallyBlockedPendingProof.status, .pending)
        XCTAssertEqual(externallyBlockedPendingProof.presentationState, .submittedNotFinal)

        let failedMapping = MeshPaymentExecutionResultSourceStateMapping(
            source: .cached,
            providerOutcome: .failure,
            explicitStatus: .confirmed
        )
        let failedProof = MeshChainProof.normalizedVerificationStatus(for: failedMapping.executionStatus)
        XCTAssertEqual(failedMapping.executionStatus, .failed)
        XCTAssertEqual(failedMapping.errorCode, "non_confirmed_execution_source")
        XCTAssertNotEqual(failedMapping.executionStatus, .confirmed)
        XCTAssertEqual(failedProof.status, .failed)
        XCTAssertEqual(failedProof.presentationState, .attemptedFailed)

        let policyDeniedMapping = MeshPaymentExecutionResultSourceStateMapping(
            source: .simulated,
            providerOutcome: .policyDenied,
            explicitStatus: .confirmed
        )
        let policyDeniedProof = MeshChainProof.normalizedVerificationStatus(
            for: policyDeniedMapping.executionStatus
        )
        XCTAssertEqual(policyDeniedMapping.executionStatus, .policyDenied)
        XCTAssertEqual(policyDeniedMapping.errorCode, "policy_denied")
        XCTAssertNotEqual(policyDeniedMapping.executionStatus, .confirmed)
        XCTAssertEqual(policyDeniedProof.status, .failed)
        XCTAssertEqual(policyDeniedProof.presentationState, .policyDenied)
    }

    func testMarooTestnetPaymentExecutorRejectsUnsupportedAssetAndUnadvertisedStatusLookup() async throws {
        let adapter = try MeshMarooTestnetPaymentExecutorAdapter()
        let unsupportedAssetFixture = try await samplePaymentExecutionFixture(
            kind: .payment,
            amount: Decimal(300),
            tokenSymbol: "USDC"
        )

        do {
            _ = try await adapter.executePayment(
                unsupportedAssetFixture.paymentRequest,
                submittedAt: "2026-05-31T00:00:07Z"
            )
            XCTFail("Expected maroo OKRW adapter to reject non-OKRW execution")
        } catch {
            XCTAssertEqual(error as? MeshKitValidationError, .invalidPaymentExecution("asset"))
        }

        do {
            _ = try await adapter.paymentExecutionStatusWithProviderNeutralErrors(
                paymentId: "pay-maroo-okrw-capability-001",
                checkedAt: "2026-05-31T00:00:08Z"
            )
            XCTFail("Expected maroo demo adapter to reject status lookup until the capability is advertised")
        } catch {
            XCTAssertEqual(error as? MeshKitValidationError, .unsupportedCapability)
        }
    }

    func testMarooTestnetPaymentExecutorMapsSubmissionProviderFailureToFailedResult() async throws {
        let client = FailingMarooPaymentExecutionSubmissionClient(
            failure: MarooSubmissionProviderFailure(
                paymentExecutorFailureKind: .rpc,
                providerFailureCode: "MAROO RPC/-32003",
                providerFailureMessage: "maroo testnet RPC rejected OKRW execution"
            )
        )
        let adapter = try MeshMarooTestnetPaymentExecutorAdapter(submissionClient: client)
        let fixture = try await samplePaymentExecutionFixture(
            kind: .payment,
            amount: Decimal(4_900)
        )

        let result = try await adapter.executePayment(
            fixture.paymentRequest,
            originatingRequest: fixture.originatingRequest,
            submittedAt: "2026-05-31T00:00:10Z"
        )
        let submissionCount = await client.submissionCount()
        let transactionRequests = await client.snapshotTransactionRequests()
        let submittedTransactionRequest = try XCTUnwrap(transactionRequests.first)

        XCTAssertEqual(result.status, .failed)
        XCTAssertNil(result.transactionHash)
        XCTAssertEqual(result.message, "maroo testnet RPC rejected OKRW execution")
        XCTAssertEqual(result.errorPayload?.code, "maroo_rpc_-32003")
        XCTAssertEqual(result.errorPayload?.message, "maroo testnet RPC rejected OKRW execution")
        XCTAssertEqual(result.providerExtensions["maroo"]?["providerOutcome"], MeshMarooTestnetPaymentExecutionProviderOutcome.failure.rawValue)
        XCTAssertEqual(result.providerExtensions["maroo"]?["normalizedStatus"], MeshPaymentExecutionStatus.failed.rawValue)
        XCTAssertEqual(result.providerExtensions["maroo"]?["failureKind"], MeshPaymentExecutorFailureKind.rpc.rawValue)
        XCTAssertEqual(result.providerExtensions["maroo"]?["errorCode"], "maroo_rpc_-32003")
        XCTAssertEqual(result.providerExtensions["maroo"]?["exitCondition"], MeshExternalChainBlockerEvidence.exitCondition)
        XCTAssertEqual(result.providerExtensions["maroo"]?["blockerType"], MeshExternalChainBlockerType.paymentConfirmationUnavailable.rawValue)
        XCTAssertEqual(result.providerExtensions["maroo"]?["operation"], "executePayment")
        XCTAssertEqual(result.providerExtensions["maroo"]?["endpoint"], "https://rpc-testnet.maroo.io")
        XCTAssertEqual(result.providerExtensions["maroo"]?["requestNonce"], fixture.originatingRequest.nonce)
        XCTAssertEqual(result.providerExtensions["maroo"]?["requestHash"], fixture.paymentRequest.requestHash.value)
        XCTAssertEqual(result.providerExtensions["maroo"]?["anchoringReference"], fixture.paymentRequest.requestAnchor.identifier.anchorId)
        XCTAssertEqual(submissionCount, 1)
        XCTAssertEqual(transactionRequests.count, 1)
        XCTAssertEqual(submittedTransactionRequest.executionKind, .payment)
        XCTAssertEqual(submittedTransactionRequest.asset, "OKRW")
        XCTAssertEqual(submittedTransactionRequest.signedMCPRequestHash, fixture.paymentRequest.requestHash)
        XCTAssertEqual(submittedTransactionRequest.anchoringReference, fixture.paymentRequest.requestAnchor.identifier.anchorId)
    }

    func testMarooTestnetPaymentExecutorMapsOKRWContractAvailabilityFailureToExternalChainBlocker() async throws {
        let client = FailingMarooPaymentExecutionSubmissionClient(
            failure: MarooSubmissionProviderFailure(
                paymentExecutorFailureKind: .contractUnavailable,
                providerFailureCode: "OKRW_CONTRACT_UNAVAILABLE",
                providerFailureMessage: "maroo OKRW contract bytecode unavailable"
            )
        )
        let adapter = try MeshMarooTestnetPaymentExecutorAdapter(submissionClient: client)
        let fixture = try await samplePaymentExecutionFixture(
            kind: .payment,
            amount: Decimal(4_900)
        )

        let result = try await adapter.executePayment(
            fixture.paymentRequest,
            originatingRequest: fixture.originatingRequest,
            submittedAt: "2026-05-31T00:00:23Z"
        )

        XCTAssertEqual(result.status, .failed)
        XCTAssertNil(result.transactionHash)
        XCTAssertEqual(result.message, "maroo OKRW contract bytecode unavailable")
        XCTAssertEqual(result.errorPayload?.code, "okrw_contract_unavailable")
        XCTAssertEqual(result.errorPayload?.message, "maroo OKRW contract bytecode unavailable")
        XCTAssertEqual(result.providerExtensions["maroo"]?["providerOutcome"], MeshMarooTestnetPaymentExecutionProviderOutcome.failure.rawValue)
        XCTAssertEqual(result.providerExtensions["maroo"]?["normalizedStatus"], MeshPaymentExecutionStatus.failed.rawValue)
        XCTAssertEqual(result.providerExtensions["maroo"]?["failureKind"], MeshPaymentExecutorFailureKind.contractUnavailable.rawValue)
        XCTAssertEqual(result.providerExtensions["maroo"]?["exitCondition"], MeshExternalChainBlockerEvidence.exitCondition)
        XCTAssertEqual(result.providerExtensions["maroo"]?["blockerType"], MeshExternalChainBlockerType.okrwContractUnavailable.rawValue)
        XCTAssertEqual(result.providerExtensions["maroo"]?["operation"], "executePayment")
        XCTAssertEqual(result.providerExtensions["maroo"]?["endpoint"], "https://rpc-testnet.maroo.io")
        XCTAssertEqual(result.providerExtensions["maroo"]?["requestNonce"], fixture.originatingRequest.nonce)
        XCTAssertEqual(result.providerExtensions["maroo"]?["requestHash"], fixture.paymentRequest.requestHash.value)
        XCTAssertEqual(result.providerExtensions["maroo"]?["anchoringReference"], fixture.paymentRequest.requestAnchor.identifier.anchorId)
    }

    func testMarooTestnetPaymentExecutorMapsSpendingLimitProviderFailuresToPolicyDeniedResult() async throws {
        let client = FailingMarooPaymentExecutionSubmissionClient(
            failure: MarooSubmissionProviderFailure(
                paymentExecutorFailureKind: .policyDenied,
                providerFailureCode: "MAROO_SPENDING_LIMIT_EXCEEDED",
                providerFailureMessage: "spending limit exceeded for delegated OKRW policy"
            )
        )
        let adapter = try MeshMarooTestnetPaymentExecutorAdapter(submissionClient: client)
        let fixture = try await samplePaymentExecutionFixture(
            kind: .payment,
            amount: Decimal(4_900),
            authorizationStatus: .approved
        )

        let result = try await adapter.executePayment(
            fixture.paymentRequest,
            originatingRequest: fixture.originatingRequest,
            submittedAt: "2026-05-31T00:00:21Z"
        )
        let submissionCount = await client.submissionCount()

        XCTAssertEqual(result.status, .policyDenied)
        XCTAssertNil(result.transactionHash)
        XCTAssertNil(result.explorerURL)
        XCTAssertEqual(result.message, "spending limit exceeded for delegated OKRW policy")
        XCTAssertEqual(result.errorPayload?.code, "maroo_spending_limit_exceeded")
        XCTAssertEqual(result.errorPayload?.message, "spending limit exceeded for delegated OKRW policy")
        XCTAssertEqual(result.providerExtensions["maroo"]?["providerOutcome"], MeshMarooTestnetPaymentExecutionProviderOutcome.policyDenied.rawValue)
        XCTAssertEqual(result.providerExtensions["maroo"]?["normalizedStatus"], MeshPaymentExecutionStatus.policyDenied.rawValue)
        XCTAssertEqual(result.providerExtensions["maroo"]?["failureKind"], MeshPaymentExecutorFailureKind.policyDenied.rawValue)
        XCTAssertEqual(result.providerExtensions["maroo"]?["errorCode"], "maroo_spending_limit_exceeded")
        XCTAssertEqual(result.providerExtensions["maroo"]?["requestHash"], fixture.paymentRequest.requestHash.value)
        XCTAssertEqual(result.providerExtensions["maroo"]?["anchoringReference"], fixture.paymentRequest.requestAnchor.identifier.anchorId)
        XCTAssertEqual(submissionCount, 1)
    }

    func testMarooTestnetPaymentExecutorMapsProviderPolicyRejectionFailuresToPolicyDeniedResult() async throws {
        let client = FailingMarooPaymentExecutionSubmissionClient(
            failure: MarooSubmissionProviderFailure(
                paymentExecutorFailureKind: .policyDenied,
                providerFailureCode: "WALLET_POLICY_REJECTED",
                providerFailureMessage: "maroo wallet policy rejected delegated transfer"
            )
        )
        let adapter = try MeshMarooTestnetPaymentExecutorAdapter(submissionClient: client)
        let fixture = try await samplePaymentExecutionFixture(
            kind: .transfer,
            amount: Decimal(1_200),
            authorizationStatus: .approved
        )

        let result = try await adapter.executePayment(
            fixture.paymentRequest,
            originatingRequest: fixture.originatingRequest,
            submittedAt: "2026-05-31T00:00:22Z"
        )
        let transactionRequests = await client.snapshotTransactionRequests()
        let submittedTransactionRequest = try XCTUnwrap(transactionRequests.first)

        XCTAssertEqual(result.kind, .transfer)
        XCTAssertEqual(result.status, .policyDenied)
        XCTAssertNil(result.transactionHash)
        XCTAssertEqual(result.message, "maroo wallet policy rejected delegated transfer")
        XCTAssertEqual(result.errorPayload?.code, "wallet_policy_rejected")
        XCTAssertEqual(result.errorPayload?.message, "maroo wallet policy rejected delegated transfer")
        XCTAssertEqual(result.providerExtensions["maroo"]?["providerOutcome"], MeshMarooTestnetPaymentExecutionProviderOutcome.policyDenied.rawValue)
        XCTAssertEqual(result.providerExtensions["maroo"]?["normalizedStatus"], MeshPaymentExecutionStatus.policyDenied.rawValue)
        XCTAssertEqual(result.providerExtensions["maroo"]?["failureKind"], MeshPaymentExecutorFailureKind.policyDenied.rawValue)
        XCTAssertEqual(result.providerExtensions["maroo"]?["executionKind"], "transfer")
        XCTAssertEqual(transactionRequests.count, 1)
        XCTAssertEqual(submittedTransactionRequest.executionKind, .transfer)
        XCTAssertEqual(submittedTransactionRequest.signedMCPRequestHash, fixture.paymentRequest.requestHash)
        XCTAssertEqual(submittedTransactionRequest.policyId, "policy-hermes-dailymart-okrw-v1")
    }

    func testExternalChainBlockerEvidenceSerializesProviderNeutralTestnetAvailabilityFailure() throws {
        let identity = try MeshMarooTestnetChainProvider().identity
        let evidence = try MeshExternalChainBlockerEvidence(
            blockerType: .rpcUnavailable,
            identity: identity,
            endpoint: identity.rpcEndpoint,
            operation: "eth_blockNumber",
            observedAt: "2026-05-31T00:00:30Z",
            message: "maroo testnet RPC unavailable",
            requestHash: MeshPayloadHash(value: String(repeating: "a", count: 64)),
            requestNonce: "nonce-maroo-testnet-blocker",
            anchoringReference: "maroo-anchor-ios-grocery-blocker-001"
        )

        let data = try JSONEncoder().encode(evidence)
        let decoded = try JSONDecoder().decode(MeshExternalChainBlockerEvidence.self, from: data)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let extensionFields = evidence.providerExtensionFields

        XCTAssertEqual(decoded, evidence)
        XCTAssertEqual(object["exitCondition"] as? String, "BlockedByExternalChain")
        XCTAssertEqual(object["blockerType"] as? String, "rpc_unavailable")
        XCTAssertEqual((object["identity"] as? [String: Any])?["provider"] as? String, "maroo")
        XCTAssertEqual((object["identity"] as? [String: Any])?["network"] as? String, "maroo-testnet")
        XCTAssertEqual(object["endpoint"] as? String, "https://rpc-testnet.maroo.io")
        XCTAssertEqual(object["operation"] as? String, "eth_blockNumber")
        XCTAssertEqual(extensionFields["exitCondition"], "BlockedByExternalChain")
        XCTAssertEqual(extensionFields["blockerType"], "rpc_unavailable")
        XCTAssertEqual(extensionFields["requestNonce"], "nonce-maroo-testnet-blocker")
        XCTAssertEqual(extensionFields["requestHash"], String(repeating: "a", count: 64))
        XCTAssertNil(extensionFields["txHash"])
    }

    private func samplePaymentExecutionFixture(
        kind: MeshAgentWalletExecutionKind,
        amount: Decimal,
        authorizationStatus: MeshAgentWalletAuthorizationStatus = .approved,
        tokenSymbol: String = "okrw"
    ) async throws -> (paymentRequest: MeshPaymentExecutionRequest, originatingRequest: MeshRequest) {
        let originatingRequest = signedDailyMartRequest(
            nonce: "nonce-maroo-okrw-capability-\(kind.rawValue)-\(amount)",
            budget: "\(amount)"
        )
        let metadata = try MeshSignedRequestAnchorMetadata(request: originatingRequest)
        let policyHash = MeshPayloadHash(value: String(repeating: "f", count: 64))
        let executionRequest = try MeshAgentWalletExecutionRequest(
            executionId: "exec-maroo-okrw-capability-001",
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
            tokenSymbol: tokenSymbol,
            recipientAddress: "0x000000000000000000000000000000000000d417",
            policyId: "policy-hermes-dailymart-okrw-v1",
            policyHash: policyHash
        )
        let decision = try MeshAgentWalletAuthorizationDecision(
            authorizationId: "auth-maroo-okrw-capability-001",
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
            status: authorizationStatus,
            approvedAmount: authorizationStatus == .approved ? amount : nil,
            reason: authorizationStatus == .denied ? "policy-denied" : nil,
            decidedAt: "2026-05-31T00:00:01Z"
        )
        let anchorPayload = try MeshRequestAnchorPayload(
            metadata: metadata,
            policyId: "policy-hermes-dailymart-okrw-v1",
            policyHash: policyHash
        )
        let anchor = try await MeshMarooTestnetRequestAnchorAdapter(status: .confirmed)
            .anchorSignedRequest(payload: anchorPayload, submittedAt: "2026-05-31T00:00:02Z")

        let paymentRequest = try MeshPaymentExecutionRequest(
            paymentId: "pay-maroo-okrw-capability-001",
            authorizationDecision: decision,
            requestAnchor: anchor,
            requestedAt: "2026-05-31T00:00:02Z"
        )
        return (paymentRequest, originatingRequest)
    }

    private func signedDailyMartRequest(nonce: String, budget: String) -> MeshRequest {
        let unsigned = MeshRequest(
            requestId: "ios-grocery-maroo-okrw-capability-001",
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
                "items": "laundry_detergent:1,toilet_paper:2,bottled_water_2l:6",
                "address_ref": "home.saved",
                "budget_krw": budget
            ],
            nonce: nonce,
            timestamp: "2026-05-31T00:00:00Z",
            signature: MeshSignature(algorithm: "Ed25519", keyId: "demo-key", value: "")
        )
        let signature = try! Self.signingKey.signature(for: unsigned.signingInputData()).base64EncodedString()
        return MeshRequest(
            requestId: unsigned.requestId,
            caller: unsigned.caller,
            target: unsigned.target,
            payload: unsigned.payload,
            payloadHash: unsigned.payloadHash,
            nonce: unsigned.nonce,
            timestamp: unsigned.timestamp,
            signature: MeshSignature(algorithm: "Ed25519", keyId: "demo-key", value: signature)
        )
    }
}

private struct MarooSubmissionProviderFailure: Error, MeshPaymentExecutorProviderFailure {
    let paymentExecutorFailureKind: MeshPaymentExecutorFailureKind
    let providerFailureCode: String
    let providerFailureMessage: String
}

private final class FailingMarooPaymentExecutionSubmissionClient: MeshMarooTestnetPaymentExecutionSubmissionClient, @unchecked Sendable {
    private let failure: Error
    private(set) var inputs: [MeshMarooTestnetPaymentExecutionProviderInput] = []
    private(set) var transactionRequests: [MeshMarooTestnetOKRWExecutionTransactionRequest] = []

    init(failure: Error) {
        self.failure = failure
    }

    func submitOKRWExecution(
        _ transactionRequest: MeshMarooTestnetOKRWExecutionTransactionRequest,
        providerInput input: MeshMarooTestnetPaymentExecutionProviderInput
    ) async throws -> MeshMarooTestnetPaymentExecutionSubmissionResponse {
        transactionRequests.append(transactionRequest)
        inputs.append(input)
        throw failure
    }

    func submissionCount() async -> Int {
        inputs.count
    }

    func snapshotTransactionRequests() async -> [MeshMarooTestnetOKRWExecutionTransactionRequest] {
        transactionRequests
    }
}

private final class CapturingMarooPaymentExecutionSubmissionClient: MeshMarooTestnetPaymentExecutionSubmissionClient, @unchecked Sendable {
    private(set) var inputs: [MeshMarooTestnetPaymentExecutionProviderInput] = []
    private(set) var transactionRequests: [MeshMarooTestnetOKRWExecutionTransactionRequest] = []
    private let providerMetadataOverride: MeshChainProviderMetadata?
    private let transactionHash: String?
    private let providerOutcome: String

    init(
        providerMetadataOverride: MeshChainProviderMetadata? = nil,
        transactionHash: String?,
        providerOutcome: String
    ) {
        self.providerMetadataOverride = providerMetadataOverride
        self.transactionHash = transactionHash
        self.providerOutcome = providerOutcome
    }

    func submitOKRWExecution(
        _ transactionRequest: MeshMarooTestnetOKRWExecutionTransactionRequest,
        providerInput input: MeshMarooTestnetPaymentExecutionProviderInput
    ) async throws -> MeshMarooTestnetPaymentExecutionSubmissionResponse {
        transactionRequests.append(transactionRequest)
        inputs.append(input)
        return try MeshMarooTestnetPaymentExecutionSubmissionResponse(
            providerMetadata: providerMetadataOverride ?? input.providerMetadata,
            transactionHash: transactionHash,
            providerOutcome: providerOutcome,
            observedAt: input.submittedAt,
            confirmationPayload: try marooConfirmationPayload(
                providerMetadata: providerMetadataOverride ?? input.providerMetadata,
                transactionHash: transactionHash,
                statusHint: providerOutcome,
                observedAt: input.submittedAt
            )
        )
    }

    func snapshotInputs() async -> [MeshMarooTestnetPaymentExecutionProviderInput] {
        inputs
    }

    func snapshotTransactionRequests() async -> [MeshMarooTestnetOKRWExecutionTransactionRequest] {
        transactionRequests
    }

    func snapshotResponse() async throws -> MeshMarooTestnetPaymentExecutionSubmissionResponse {
        try XCTUnwrap(
            inputs.last.map {
                try MeshMarooTestnetPaymentExecutionSubmissionResponse(
                    providerMetadata: providerMetadataOverride ?? $0.providerMetadata,
                    transactionHash: transactionHash,
                    providerOutcome: providerOutcome,
                    observedAt: $0.submittedAt,
                    confirmationPayload: try marooConfirmationPayload(
                        providerMetadata: providerMetadataOverride ?? $0.providerMetadata,
                        transactionHash: transactionHash,
                        statusHint: providerOutcome,
                        observedAt: $0.submittedAt
                    )
                )
            }
        )
    }
}

private final class CapturingMarooTransactionStateSubmissionClient: MeshMarooTestnetPaymentExecutionSubmissionClient, @unchecked Sendable {
    private(set) var inputs: [MeshMarooTestnetPaymentExecutionProviderInput] = []
    private(set) var transactionRequests: [MeshMarooTestnetOKRWExecutionTransactionRequest] = []
    private let transactionHash: String?
    private let providerTransactionState: String

    init(transactionHash: String?, providerTransactionState: String) {
        self.transactionHash = transactionHash
        self.providerTransactionState = providerTransactionState
    }

    func submitOKRWExecution(
        _ transactionRequest: MeshMarooTestnetOKRWExecutionTransactionRequest,
        providerInput input: MeshMarooTestnetPaymentExecutionProviderInput
    ) async throws -> MeshMarooTestnetPaymentExecutionSubmissionResponse {
        transactionRequests.append(transactionRequest)
        inputs.append(input)
        return try MeshMarooTestnetPaymentExecutionSubmissionResponse(
            providerMetadata: input.providerMetadata,
            transactionHash: transactionHash,
            providerTransactionState: providerTransactionState,
            observedAt: input.submittedAt,
            confirmationPayload: try marooConfirmationPayload(
                providerMetadata: input.providerMetadata,
                transactionHash: transactionHash,
                statusHint: providerTransactionState,
                observedAt: input.submittedAt
            )
        )
    }

    func snapshotResponse() async throws -> MeshMarooTestnetPaymentExecutionSubmissionResponse {
        try XCTUnwrap(
            inputs.last.map {
                try MeshMarooTestnetPaymentExecutionSubmissionResponse(
                    providerMetadata: $0.providerMetadata,
                    transactionHash: transactionHash,
                    providerTransactionState: providerTransactionState,
                    observedAt: $0.submittedAt,
                    confirmationPayload: try marooConfirmationPayload(
                        providerMetadata: $0.providerMetadata,
                        transactionHash: transactionHash,
                        statusHint: providerTransactionState,
                        observedAt: $0.submittedAt
                    )
                )
            }
        )
    }
}

private actor CapturingMAWSTransferHTTPTransport: MeshOKRWTransferBridgeHTTPTransport {
    private(set) var requests: [URLRequest] = []
    private let data: Data
    private let statusCode: Int

    init(responseObject: [String: Any], statusCode: Int = 200) {
        self.data = try! JSONSerialization.data(withJSONObject: responseObject)
        self.statusCode = statusCode
    }

    func sendOKRWTransferBridgeRequest(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        requests.append(request)
        return (
            data,
            HTTPURLResponse(
                url: request.url!,
                statusCode: statusCode,
                httpVersion: "HTTP/1.1",
                headerFields: ["content-type": "application/json"]
            )!
        )
    }

    func snapshotRequests() -> [URLRequest] {
        requests
    }
}

private func marooConfirmationPayload(
    providerMetadata: MeshChainProviderMetadata,
    transactionHash: String?,
    statusHint: String,
    observedAt: String
) throws -> MeshMarooTestnetPaymentConfirmationPayload? {
    let normalizedStatus = try? MeshMarooTestnetPaymentExecutionProviderOutcome(providerValue: statusHint)
    let normalizedState = try? MeshMarooTestnetTransactionStateMapping(providerTransactionState: statusHint)
    guard normalizedStatus == .success || normalizedState?.providerOutcome == .success else {
        return nil
    }
    return try MeshMarooTestnetDeterministicPaymentExecutionSubmissionClient.deterministicConfirmationPayload(
        providerMetadata: providerMetadata,
        transactionHash: try XCTUnwrap(transactionHash),
        confirmedAt: observedAt
    )
}

private actor CapturingMarooIntegratedRequestAnchorSubmissionClient: MeshMarooTestnetRequestAnchorSubmissionClient {
    private(set) var inputs: [MeshRequestAnchorProviderInput] = []
    private let transactionHash: String?
    private let providerOutcome: String

    init(transactionHash: String?, providerOutcome: String) {
        self.transactionHash = transactionHash
        self.providerOutcome = providerOutcome
    }

    func submitRequestAnchor(
        _ input: MeshRequestAnchorProviderInput
    ) async throws -> MeshMarooTestnetRequestAnchorSubmissionResponse {
        inputs.append(input)
        return try MeshMarooTestnetRequestAnchorSubmissionResponse(
            providerMetadata: input.providerMetadata,
            anchorId: "maroo-anchor-\(input.payload.metadata.requestId)",
            transactionHash: transactionHash,
            providerOutcome: providerOutcome,
            observedAt: input.submittedAt
        )
    }

    func snapshotInputs() -> [MeshRequestAnchorProviderInput] {
        inputs
    }
}
