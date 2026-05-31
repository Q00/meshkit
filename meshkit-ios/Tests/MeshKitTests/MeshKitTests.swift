import CryptoKit
import XCTest
@testable import MeshKit

final class MeshKitTests: XCTestCase {
    private struct StaticChainProvider: MeshChainProvider {
        let identity: MeshChainProviderIdentity
        let capabilities: [MeshChainProviderCapability]
        let observedNetwork: String?
        let healthStatus: MeshChainProviderHealthStatus

        func loadProviderConfiguration() throws -> MeshChainProviderConfiguration {
            try MeshChainProviderConfiguration(identity: identity, capabilities: capabilities)
        }

        func identifyNetwork() throws -> MeshChainProviderIdentity {
            try loadProviderConfiguration().require(.identifyNetwork)
            return identity
        }

        func connect(checkedAt: String) async throws -> MeshChainProviderConnection {
            try loadProviderConfiguration().require(.loadProviderConfiguration)
            return try MeshChainProviderConnection(
                identity: identity,
                status: .connected,
                capabilities: capabilities,
                observedNetwork: observedNetwork ?? identity.network,
                checkedAt: checkedAt
            )
        }

        func checkHealth(checkedAt: String) async throws -> MeshChainProviderHealth {
            try loadProviderConfiguration().require(.checkHealth)
            return try MeshChainProviderHealth(
                identity: identity,
                status: healthStatus,
                capabilities: capabilities,
                checkedAt: checkedAt,
                latencyMilliseconds: healthStatus == .healthy ? 42 : nil,
                latestBlockHeight: healthStatus == .healthy ? 123_456 : nil,
                message: healthStatus == .healthy ? nil : "rpc unavailable"
            )
        }
    }

    private struct StaticRequestAnchorProvider: MeshRequestAnchorProvider {
        let identity: MeshChainProviderIdentity
        let capabilities: [MeshChainProviderCapability]
        let status: MeshRequestAnchorStatus
        let knownAnchorIds: Set<String>?

        init(
            identity: MeshChainProviderIdentity,
            capabilities: [MeshChainProviderCapability],
            status: MeshRequestAnchorStatus,
            knownAnchorIds: Set<String>? = nil
        ) {
            self.identity = identity
            self.capabilities = capabilities
            self.status = status
            self.knownAnchorIds = knownAnchorIds
        }

        func anchorSignedRequest(
            metadata: MeshSignedRequestAnchorMetadata,
            submittedAt: String
        ) async throws -> MeshRequestAnchor {
            guard capabilities.contains(.anchorSignedRequest) else {
                throw MeshKitValidationError.unsupportedCapability
            }
            return try MeshRequestAnchor(
                metadata: metadata,
                identifier: MeshRequestAnchorIdentifier(
                    identity: identity,
                    anchorId: "anchor-\(metadata.requestId)",
                    transactionHash: "0xanchor123"
                ),
                status: status,
                submittedAt: submittedAt,
                observedAt: submittedAt
            )
        }

        func requestAnchorStatus(
            identifier: MeshRequestAnchorIdentifier,
            checkedAt: String
        ) async throws -> MeshRequestAnchor {
            guard capabilities.contains(.lookupRequestAnchorStatus) else {
                throw MeshKitValidationError.unsupportedCapability
            }
            if let knownAnchorIds, !knownAnchorIds.contains(identifier.anchorId) {
                throw MeshKitValidationError.requestAnchorReferenceNotFound(identifier.anchorId)
            }
            let metadata = try MeshSignedRequestAnchorMetadata(
                requestId: "ios-anchor-status-001",
                nonce: "nonce-anchor-status",
                timestamp: checkedAt,
                callerAppId: "app.hermes-chat",
                callerBundleId: "ai.meshkit.sample.hermeschat",
                targetBundleId: "ai.meshkit.sample.dailymart",
                capabilityId: "grocery.purchase_essentials",
                payloadHash: MeshPayloadHash(value: String(repeating: "a", count: 64)),
                signature: MeshSignature(algorithm: "Ed25519", keyId: "demo-key", value: "signature"),
                signedRequestHash: MeshPayloadHash(value: String(repeating: "b", count: 64))
            )
            return try MeshRequestAnchor(
                metadata: metadata,
                identifier: identifier,
                status: status,
                submittedAt: checkedAt,
                observedAt: checkedAt
            )
        }
    }

    private struct FailingRequestAnchorProvider: MeshRequestAnchorProvider {
        let identity: MeshChainProviderIdentity
        let capabilities: [MeshChainProviderCapability]

        func anchorSignedRequest(
            metadata: MeshSignedRequestAnchorMetadata,
            submittedAt: String
        ) async throws -> MeshRequestAnchor {
            try MeshChainProviderConfiguration(identity: identity, capabilities: capabilities).require(.anchorSignedRequest)
            try metadata.validate()
            guard !submittedAt.isEmpty else {
                throw MeshKitValidationError.invalidChainProviderIdentity("submittedAt")
            }
            throw MeshKitValidationError.invalidChainProviderIdentity("request anchor submission failed")
        }

        func requestAnchorStatus(
            identifier: MeshRequestAnchorIdentifier,
            checkedAt: String
        ) async throws -> MeshRequestAnchor {
            try MeshChainProviderConfiguration(identity: identity, capabilities: capabilities).require(.lookupRequestAnchorStatus)
            try identifier.validate()
            guard !checkedAt.isEmpty else {
                throw MeshKitValidationError.invalidChainProviderIdentity("checkedAt")
            }
            throw MeshKitValidationError.invalidChainProviderIdentity("request anchor status unavailable")
        }
    }

    private struct StaticAgentWallet: MeshAgentWallet {
        let identity: MeshAgentWalletIdentity
        let capabilities: [MeshAgentWalletCapability]
        let spendingLimit: MeshAgentWalletDelegatedSpendingLimit?
        let anchorSigningKey: Curve25519.Signing.PrivateKey?
        var delegatedPolicy: MeshAgentWalletDelegatedSpendingPolicy? = nil

        func loadWalletConfiguration() throws -> MeshAgentWalletConfiguration {
            try MeshAgentWalletConfiguration(identity: identity, capabilities: capabilities)
        }

        func reportWalletAddress() throws -> String {
            try loadWalletConfiguration().require(.reportWalletAddress)
            return identity.walletAddress
        }

        func delegatedSpendingLimit() throws -> MeshAgentWalletDelegatedSpendingLimit {
            try loadWalletConfiguration().require(.reportDelegatedSpendingLimit)
            guard let spendingLimit else {
                throw MeshKitValidationError.invalidAgentWalletIdentity("spendingLimit")
            }
            return spendingLimit
        }

        func signingBoundary() throws -> MeshAgentWalletSigningBoundary {
            try loadWalletConfiguration().require(.exposeSigningBoundary)
            return identity.signingBoundary
        }

        func signRequestAnchorPayload(
            _ payload: MeshAgentWalletAnchorSigningPayload,
            signedAt: String
        ) throws -> MeshAgentWalletAnchorSignature {
            try loadWalletConfiguration().require(.signRequestAnchorPayload)
            guard let anchorSigningKey else {
                throw MeshKitValidationError.signatureRequired
            }
            let signature = try anchorSigningKey.signature(for: payload.signingInputData()).base64EncodedString()
            return try MeshAgentWalletAnchorSignature(
                walletIdentity: identity,
                payload: payload,
                signature: MeshSignature(
                    algorithm: "Ed25519",
                    keyId: "\(identity.walletId)#request-anchor",
                    value: signature
                ),
                signedAt: signedAt
            )
        }

        func signExecutionAuthorizationPayload(
            _ payload: MeshAgentWalletExecutionAuthorizationPayload,
            signedAt: String
        ) throws -> MeshAgentWalletExecutionAuthorization {
            try loadWalletConfiguration().require(.signExecutionAuthorizationPayload)
            guard let anchorSigningKey else {
                throw MeshKitValidationError.signatureRequired
            }
            let signature = try anchorSigningKey.signature(for: payload.signingInputData()).base64EncodedString()
            return try MeshAgentWalletExecutionAuthorization(
                walletIdentity: identity,
                payload: payload,
                signature: MeshSignature(
                    algorithm: "Ed25519",
                    keyId: "\(identity.walletId)#execution-authorization",
                    value: signature
                ),
                signedAt: signedAt
            )
        }

        func authorizeExecution(
            _ request: MeshAgentWalletExecutionRequest,
            decidedAt: String
        ) throws -> MeshAgentWalletAuthorizationDecision {
            try loadWalletConfiguration().require(.authorizeExecution)
            if let delegatedPolicy {
                let result = try delegatedPolicy.evaluateExecutionRequest(request, requestedAt: decidedAt)
                switch result.status {
                case .allowed:
                    return try MeshAgentWalletAuthorizationDecision(
                        authorizationId: "auth-\(request.executionId)",
                        walletIdentity: identity,
                        executionRequest: request,
                        status: .approved,
                        approvedAmount: result.approvedAmount,
                        decidedAt: decidedAt
                    )
                case .denied:
                    return try MeshAgentWalletAuthorizationDecision(
                        authorizationId: "auth-\(request.executionId)",
                        walletIdentity: identity,
                        executionRequest: request,
                        status: .denied,
                        reason: result.reason,
                        decidedAt: decidedAt
                    )
                }
            }
            let limit = try delegatedSpendingLimit()
            guard request.scope == limit.scope else {
                return try MeshAgentWalletAuthorizationDecision(
                    authorizationId: "auth-\(request.executionId)",
                    walletIdentity: identity,
                    executionRequest: request,
                    status: .denied,
                    reason: "scope-mismatch",
                    decidedAt: decidedAt
                )
            }
            guard request.amount <= limit.limitAmount else {
                return try MeshAgentWalletAuthorizationDecision(
                    authorizationId: "auth-\(request.executionId)",
                    walletIdentity: identity,
                    executionRequest: request,
                    status: .denied,
                    reason: "delegated-limit-exceeded",
                    decidedAt: decidedAt
                )
            }
            return try MeshAgentWalletAuthorizationDecision(
                authorizationId: "auth-\(request.executionId)",
                walletIdentity: identity,
                executionRequest: request,
                status: .approved,
                approvedAmount: request.amount,
                decidedAt: decidedAt
            )
        }
    }

    private struct StaticPaymentExecutor: MeshPaymentExecutor {
        let identity: MeshChainProviderIdentity
        let capabilities: [MeshPaymentExecutorCapability]
        let status: MeshPaymentExecutionStatus
        let transactionHash: String?
        let lookupRequest: MeshPaymentExecutionRequest?

        func loadPaymentExecutorConfiguration() throws -> MeshPaymentExecutorConfiguration {
            try MeshPaymentExecutorConfiguration(identity: identity, capabilities: capabilities)
        }

        func executePayment(
            _ request: MeshPaymentExecutionRequest,
            submittedAt: String
        ) async throws -> MeshPaymentExecutionResult {
            let requiredCapability: MeshPaymentExecutorCapability = request.executionRequest.kind == .payment
                ? .executePayment
                : .executeTransfer
            try loadPaymentExecutorConfiguration().require(requiredCapability)

            if request.authorizationDecision.status == .denied {
                return try MeshPaymentExecutionResult(
                    request: request,
                    identity: identity,
                    status: .policyDenied,
                    observedAt: submittedAt,
                    message: request.authorizationDecision.reason
                )
            }

            return try MeshPaymentExecutionResult(
                request: request,
                identity: identity,
                status: status,
                transactionHash: transactionHash,
                observedAt: submittedAt,
                message: status == .failed ? "provider execution failed" : nil
            )
        }

        func paymentExecutionStatus(paymentId: String, checkedAt: String) async throws -> MeshPaymentExecutionResult {
            try loadPaymentExecutorConfiguration().require(.lookupExecutionStatus)
            guard let lookupRequest, lookupRequest.paymentId == paymentId else {
                throw MeshKitValidationError.invalidPaymentExecution("paymentId")
            }
            return try MeshPaymentExecutionResult(
                request: lookupRequest,
                identity: identity,
                status: status,
                transactionHash: transactionHash,
                observedAt: checkedAt
            )
        }
    }

    private struct ProviderSpecificPaymentFailure: Error, MeshPaymentExecutorProviderFailure {
        let paymentExecutorFailureKind: MeshPaymentExecutorFailureKind
        let providerFailureCode: String
        let providerFailureMessage: String
    }

    private struct UnknownPaymentExecutionFailure: Error {}

    private struct FailingPaymentExecutor: MeshPaymentExecutor {
        let identity: MeshChainProviderIdentity
        let capabilities: [MeshPaymentExecutorCapability]
        let executionError: Error
        let statusError: Error

        func loadPaymentExecutorConfiguration() throws -> MeshPaymentExecutorConfiguration {
            try MeshPaymentExecutorConfiguration(identity: identity, capabilities: capabilities)
        }

        func executePayment(
            _ request: MeshPaymentExecutionRequest,
            submittedAt: String
        ) async throws -> MeshPaymentExecutionResult {
            let requiredCapability: MeshPaymentExecutorCapability = request.executionRequest.kind == .payment
                ? .executePayment
                : .executeTransfer
            try loadPaymentExecutorConfiguration().require(requiredCapability)
            throw executionError
        }

        func paymentExecutionStatus(paymentId: String, checkedAt: String) async throws -> MeshPaymentExecutionResult {
            try loadPaymentExecutorConfiguration().require(.lookupExecutionStatus)
            throw statusError
        }
    }

    private final class RecordingPaymentExecutor: MeshPaymentExecutor, @unchecked Sendable {
        let identity: MeshChainProviderIdentity
        let capabilities: [MeshPaymentExecutorCapability]
        private(set) var executionCallCount = 0
        private(set) var executedRequests: [MeshPaymentExecutionRequest] = []

        init(identity: MeshChainProviderIdentity, capabilities: [MeshPaymentExecutorCapability]) {
            self.identity = identity
            self.capabilities = capabilities
        }

        func loadPaymentExecutorConfiguration() throws -> MeshPaymentExecutorConfiguration {
            try MeshPaymentExecutorConfiguration(identity: identity, capabilities: capabilities)
        }

        func executePayment(
            _ request: MeshPaymentExecutionRequest,
            submittedAt: String
        ) async throws -> MeshPaymentExecutionResult {
            executionCallCount += 1
            executedRequests.append(request)
            return try MeshPaymentExecutionResult(
                request: request,
                identity: identity,
                status: .pending,
                observedAt: submittedAt
            )
        }

        func paymentExecutionStatus(paymentId: String, checkedAt: String) async throws -> MeshPaymentExecutionResult {
            throw MeshKitValidationError.invalidPaymentExecution("paymentId")
        }
    }

    private struct RebindingPaymentExecutor: MeshPaymentExecutor {
        let identity: MeshChainProviderIdentity
        let capabilities: [MeshPaymentExecutorCapability]
        let reboundRequest: MeshPaymentExecutionRequest

        func loadPaymentExecutorConfiguration() throws -> MeshPaymentExecutorConfiguration {
            try MeshPaymentExecutorConfiguration(identity: identity, capabilities: capabilities)
        }

        func executePayment(
            _ request: MeshPaymentExecutionRequest,
            submittedAt: String
        ) async throws -> MeshPaymentExecutionResult {
            try request.validate()
            return try MeshPaymentExecutionResult(
                request: reboundRequest,
                identity: identity,
                status: .pending,
                observedAt: submittedAt
            )
        }

        func paymentExecutionStatus(paymentId: String, checkedAt: String) async throws -> MeshPaymentExecutionResult {
            throw MeshKitValidationError.invalidPaymentExecution("paymentId")
        }
    }

    func testChainProviderIdentityCarriesProviderNeutralNetworkContract() throws {
        let identity = try MeshChainProviderIdentity(
            providerName: "maroo",
            networkIdentity: "maroo-testnet",
            chainId: "maroo-testnet-1",
            rpcEndpoint: try XCTUnwrap(URL(string: "https://rpc-testnet.example.invalid")),
            explorerBaseURL: try XCTUnwrap(URL(string: "https://explorer-testnet.example.invalid"))
        )

        XCTAssertEqual(identity.providerName, "maroo")
        XCTAssertEqual(identity.networkIdentity, "maroo-testnet")
        XCTAssertEqual(identity.chainId, "maroo-testnet-1")
        XCTAssertEqual(identity.rpcEndpoint.absoluteString, "https://rpc-testnet.example.invalid")
        XCTAssertEqual(
            try identity.explorerURL(transactionHash: "0xabc123").absoluteString,
            "https://explorer-testnet.example.invalid/tx/0xabc123"
        )
    }

    func testChainProviderMetadataCarriesProviderNeutralChainIdShape() throws {
        let metadata = try MeshChainProviderMetadata(
            provider: " MAROO ",
            network: " Maroo-Testnet ",
            chainId: " MAROO-Testnet-1 "
        )

        XCTAssertEqual(metadata.provider, "maroo")
        XCTAssertEqual(metadata.network, "maroo-testnet")
        XCTAssertEqual(metadata.chainId, "maroo-testnet-1")

        let data = try JSONEncoder().encode(metadata)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(object["provider"] as? String, "maroo")
        XCTAssertEqual(object["network"] as? String, "maroo-testnet")
        XCTAssertEqual(object["chainId"] as? String, "maroo-testnet-1")
        XCTAssertNil(object["providerName"])
        XCTAssertNil(object["networkIdentity"])

        let decoded = try JSONDecoder().decode(MeshChainProviderMetadata.self, from: data)
        XCTAssertEqual(decoded, metadata)
    }

    func testChainProviderInterfaceExposesMetadataFromSingleProviderContract() async throws {
        let provider = StaticChainProvider(
            identity: try sampleChainProviderIdentity(),
            capabilities: [.loadProviderConfiguration, .identifyNetwork, .checkHealth],
            observedNetwork: "maroo-testnet",
            healthStatus: .healthy
        )

        let interface: any MeshChainProvider = provider
        XCTAssertEqual(interface.metadata.provider, "maroo")
        XCTAssertEqual(interface.metadata.network, "maroo-testnet")
        XCTAssertEqual(interface.metadata.chainId, "maroo-testnet-1")
        XCTAssertEqual(interface.metadata, provider.identity.metadata)

        let connection = try await interface.connect(checkedAt: "2026-05-31T00:00:00Z")
        XCTAssertEqual(connection.identity.metadata, interface.metadata)
    }

    func testAgentWalletIdentityCarriesStableIdentifiersAndProviderMetadata() throws {
        let identity = try sampleAgentWalletIdentity()

        XCTAssertEqual(identity.walletId, "wallet-hermes-dailymart-okrw-v1")
        XCTAssertEqual(identity.agentId, "agent.hermes-chat.daily-mart")
        XCTAssertEqual(identity.walletAddress, "maroo1dailyMartAgentWallet")
        XCTAssertEqual(identity.providerMetadata.provider, "maroo")
        XCTAssertEqual(identity.providerMetadata.network, "maroo-testnet")
        XCTAssertEqual(identity.providerMetadata.chainId, "maroo-testnet-1")
        XCTAssertEqual(identity.providerMetadata.rpcEndpoint?.absoluteString, "https://rpc-testnet.example.invalid")
        XCTAssertEqual(identity.providerMetadata.explorerBaseUrl?.absoluteString, "https://explorer-testnet.example.invalid")
        XCTAssertEqual(identity.providerMetadata.adapterId, "maroo-testnet-demo-adapter")
        XCTAssertEqual(identity.signingBoundary, .providerSubmission)
    }

    func testAgentWalletIdentityNormalizesProviderMetadataWithoutHardCodingProvider() throws {
        let metadata = try MeshAgentWalletProviderMetadata(
            provider: " MAROO ",
            network: " Maroo-Testnet ",
            chainId: " MAROO-Testnet-1 ",
            rpcEndpoint: try XCTUnwrap(URL(string: "HTTPS://RPC-Testnet.Example.Invalid/")),
            explorerBaseUrl: try XCTUnwrap(URL(string: "HTTPS://Explorer-Testnet.Example.Invalid/")),
            adapterId: " MAROO-Testnet-Demo-Adapter "
        )
        let identity = try MeshAgentWalletIdentity(
            walletId: "wallet-hermes-dailymart-okrw-v1",
            agentId: "agent.hermes-chat.daily-mart",
            walletAddress: "maroo1dailyMartAgentWallet",
            providerMetadata: metadata,
            signingBoundary: .externalWalletApp
        )

        XCTAssertEqual(identity.providerMetadata.provider, "maroo")
        XCTAssertEqual(identity.providerMetadata.network, "maroo-testnet")
        XCTAssertEqual(identity.providerMetadata.chainId, "maroo-testnet-1")
        XCTAssertEqual(identity.providerMetadata.rpcEndpoint?.absoluteString, "https://rpc-testnet.example.invalid")
        XCTAssertEqual(identity.providerMetadata.explorerBaseUrl?.absoluteString, "https://explorer-testnet.example.invalid")
        XCTAssertEqual(identity.providerMetadata.adapterId, "maroo-testnet-demo-adapter")
        XCTAssertEqual(identity.walletAddress, "maroo1dailyMartAgentWallet")
    }

    func testAgentWalletIdentityCodableUsesProviderNeutralContractKeys() throws {
        let identity = try sampleAgentWalletIdentity()

        let data = try JSONEncoder().encode(identity)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(object["walletId"] as? String, "wallet-hermes-dailymart-okrw-v1")
        XCTAssertEqual(object["agentId"] as? String, "agent.hermes-chat.daily-mart")
        XCTAssertEqual(object["walletAddress"] as? String, "maroo1dailyMartAgentWallet")
        XCTAssertEqual(object["signingBoundary"] as? String, "providerSubmission")

        let providerMetadata = try XCTUnwrap(object["providerMetadata"] as? [String: Any])
        XCTAssertEqual(providerMetadata["provider"] as? String, "maroo")
        XCTAssertEqual(providerMetadata["network"] as? String, "maroo-testnet")
        XCTAssertEqual(providerMetadata["chainId"] as? String, "maroo-testnet-1")
        XCTAssertEqual(providerMetadata["rpcEndpoint"] as? String, "https://rpc-testnet.example.invalid")
        XCTAssertEqual(providerMetadata["explorerBaseUrl"] as? String, "https://explorer-testnet.example.invalid")
        XCTAssertEqual(providerMetadata["adapterId"] as? String, "maroo-testnet-demo-adapter")
        XCTAssertNil(providerMetadata["providerName"])

        let decoded = try JSONDecoder().decode(MeshAgentWalletIdentity.self, from: data)
        XCTAssertEqual(decoded, identity)
    }

    func testAgentWalletConfigurationDiscoversProviderNeutralCapabilities() throws {
        let wallet = try StaticAgentWallet(
            identity: sampleAgentWalletIdentity(),
            capabilities: [
                .reportWalletAddress,
                .validatePolicy,
                .exposeSigningBoundary,
                .reportWalletAddress,
                .accountForConfirmedSpend,
                .signRequestAnchorPayload
            ],
            spendingLimit: nil,
            anchorSigningKey: nil
        )

        let configuration = try wallet.loadWalletConfiguration()
        XCTAssertEqual(configuration.identity.providerMetadata.provider, "maroo")
        XCTAssertEqual(configuration.capabilities, [
            .accountForConfirmedSpend,
            .exposeSigningBoundary,
            .reportWalletAddress,
            .signRequestAnchorPayload,
            .validatePolicy
        ])
        XCTAssertTrue(configuration.supports(.validatePolicy))
        XCTAssertTrue(configuration.supports(.signRequestAnchorPayload))
        XCTAssertFalse(configuration.supports(.submitTransaction))
        XCTAssertEqual(try wallet.reportWalletAddress(), "maroo1dailyMartAgentWallet")
        XCTAssertEqual(try wallet.signingBoundary(), .providerSubmission)
        XCTAssertThrowsError(try configuration.require(.submitTransaction)) { error in
            XCTAssertEqual(error as? MeshKitValidationError, .unsupportedCapability)
        }
    }

    func testAgentWalletAddressReportingContractRunsAgainstMockAdapter() throws {
        let identity = try MeshAgentWalletIdentity(
            walletId: "wallet-mock-agent-001",
            agentId: "agent.mock-caller.daily-mart",
            walletAddress: "mock1agentwalletaddress001",
            providerMetadata: MeshAgentWalletProviderMetadata(
                provider: "mockchain",
                network: "local-testnet",
                chainId: "mockchain-local-1",
                rpcEndpoint: try XCTUnwrap(URL(string: "https://rpc.mockchain.example.invalid")),
                explorerBaseUrl: try XCTUnwrap(URL(string: "https://explorer.mockchain.example.invalid")),
                adapterId: "mock-agent-wallet-adapter"
            ),
            signingBoundary: .localSignature
        )
        let wallet = StaticAgentWallet(
            identity: identity,
            capabilities: [.reportWalletAddress],
            spendingLimit: nil,
            anchorSigningKey: nil
        )

        let configuration = try wallet.loadWalletConfiguration()

        XCTAssertTrue(configuration.supports(.reportWalletAddress))
        XCTAssertEqual(configuration.identity.providerMetadata.provider, "mockchain")
        XCTAssertEqual(configuration.identity.providerMetadata.network, "local-testnet")
        XCTAssertEqual(configuration.identity.providerMetadata.chainId, "mockchain-local-1")
        XCTAssertEqual(configuration.identity.walletAddress, "mock1agentwalletaddress001")
        XCTAssertEqual(try wallet.reportWalletAddress(), "mock1agentwalletaddress001")
    }

    func testMarooAgentWalletAdapterReportsAddressThroughProviderNeutralInterface() throws {
        let wallet = try MeshMarooAgentWalletAdapter(
            chainProviderIdentity: sampleChainProviderIdentity(),
            walletId: "wallet-hermes-dailymart-okrw-v1",
            agentId: "agent.hermes-chat.daily-mart",
            walletAddress: "maroo1dailyMartAgentWallet"
        )

        try assertAgentWalletAddressReportingContract(
            wallet,
            expectedProvider: "maroo",
            expectedNetwork: "maroo-testnet",
            expectedChainId: "maroo-testnet-1",
            expectedWalletAddress: "maroo1dailyMartAgentWallet"
        )
        XCTAssertEqual(try wallet.signingBoundary(), .providerSubmission)
        XCTAssertEqual(
            try wallet.loadWalletConfiguration().identity.providerMetadata.adapterId,
            "maroo-testnet-agent-wallet-adapter"
        )

        XCTAssertThrowsError(try MeshMarooAgentWalletAdapter(
            chainProviderIdentity: sampleChainProviderIdentity(),
            walletId: "wallet-hermes-dailymart-okrw-v1",
            agentId: "agent.hermes-chat.daily-mart",
            walletAddress: "maroo1dailyMartAgentWallet",
            capabilities: [.reportWalletAddress, .authorizeExecution]
        )) { error in
            XCTAssertEqual(error as? MeshKitValidationError, .unsupportedCapability)
        }
    }

    func testAgentWalletDelegatedSpendingLimitCarriesProviderNeutralPolicyContract() throws {
        let spendingLimit = try sampleDelegatedSpendingLimit()
        let wallet = try StaticAgentWallet(
            identity: sampleAgentWalletIdentity(),
            capabilities: [
                .reportWalletAddress,
                .reportDelegatedSpendingLimit,
                .validatePolicy
            ],
            spendingLimit: spendingLimit,
            anchorSigningKey: nil
        )

        let exposedLimit = try wallet.delegatedSpendingLimit()
        XCTAssertEqual(exposedLimit.limitAmount, Decimal(10_000))
        XCTAssertEqual(exposedLimit.availableLimit, Decimal(8_500))
        XCTAssertEqual(exposedLimit.currencyCode, "KRW")
        XCTAssertEqual(exposedLimit.tokenSymbol, "OKRW")
        XCTAssertEqual(exposedLimit.scope.merchantId, "merchant.dailymart")
        XCTAssertEqual(exposedLimit.scope.targetBundleId, "ai.meshkit.sample.dailymart")
        XCTAssertEqual(exposedLimit.scope.capabilityId, "grocery.purchase_essentials")
        XCTAssertEqual(exposedLimit.scope.consentGrantId, "grant-hermes-dailymart-001")
        XCTAssertEqual(exposedLimit.expiresAt, "2026-06-30T00:00:00Z")
        XCTAssertEqual(exposedLimit.policyMetadata?.policyId, "policy-hermes-dailymart-okrw-v1")
        XCTAssertEqual(exposedLimit.policyMetadata?.policyHash.value, String(repeating: "f", count: 64))
        XCTAssertEqual(exposedLimit.policyMetadata?.asset, "OKRW")
        XCTAssertEqual(exposedLimit.policyMetadata?.recipientAddress, "maroo1dailyMartMerchant")
        XCTAssertTrue(try wallet.loadWalletConfiguration().supports(.reportDelegatedSpendingLimit))
    }

    func testAgentWalletDelegatedSpendingLimitDefaultsAvailableLimitToLimitAmountForSimpleAdapters() throws {
        let spendingLimit = try MeshAgentWalletDelegatedSpendingLimit(
            limitAmount: Decimal(10_000),
            currencyCode: "krw",
            tokenSymbol: "okrw",
            scope: sampleDelegatedSpendingScope(),
            expiresAt: "2026-06-30T00:00:00Z"
        )

        XCTAssertEqual(spendingLimit.availableLimit, Decimal(10_000))
        XCTAssertNil(spendingLimit.policyMetadata)
    }

    func testAgentWalletSignsRequestAnchoringPayloadWithProviderNeutralContract() throws {
        let signingKey = Curve25519.Signing.PrivateKey()
        let request = dailyMartRequest(nonce: "nonce-wallet-anchor-sign")
        let metadata = try MeshSignedRequestAnchorMetadata(request: request)
        let payload = try MeshAgentWalletAnchorSigningPayload(
            requestAnchorMetadata: metadata,
            policyId: "policy-hermes-dailymart-okrw-v1",
            policyHash: MeshPayloadHash(value: String(repeating: "c", count: 64)),
            walletAddress: "maroo1dailyMartAgentWallet"
        )
        let wallet = try StaticAgentWallet(
            identity: sampleAgentWalletIdentity(),
            capabilities: [
                .reportWalletAddress,
                .exposeSigningBoundary,
                .signRequestAnchorPayload
            ],
            spendingLimit: nil,
            anchorSigningKey: signingKey
        )

        let anchorSignature = try wallet.signRequestAnchorPayload(
            payload,
            signedAt: "2026-05-31T00:00:00Z"
        )

        XCTAssertEqual(anchorSignature.walletIdentity.walletId, "wallet-hermes-dailymart-okrw-v1")
        XCTAssertEqual(anchorSignature.walletIdentity.providerMetadata.provider, "maroo")
        XCTAssertEqual(anchorSignature.payload.requestAnchorMetadata.requestId, request.requestId)
        XCTAssertEqual(anchorSignature.payload.requestAnchorMetadata.nonce, "nonce-wallet-anchor-sign")
        XCTAssertEqual(anchorSignature.payload.policyId, "policy-hermes-dailymart-okrw-v1")
        XCTAssertEqual(anchorSignature.payload.walletAddress, "maroo1dailyMartAgentWallet")
        XCTAssertEqual(anchorSignature.signature.algorithm, "Ed25519")
        XCTAssertEqual(anchorSignature.signature.keyId, "wallet-hermes-dailymart-okrw-v1#request-anchor")
        XCTAssertEqual(anchorSignature.signedAt, "2026-05-31T00:00:00Z")

        let publicKey = signingKey.publicKey
        let signatureData = try XCTUnwrap(Data(base64Encoded: anchorSignature.signature.value))
        XCTAssertTrue(publicKey.isValidSignature(signatureData, for: try payload.signingInputData()))
    }

    func testAgentWalletAnchorSigningPayloadCodableUsesStableContractKeys() throws {
        let metadata = try MeshSignedRequestAnchorMetadata(
            request: dailyMartRequest(nonce: "nonce-wallet-anchor-codable")
        )
        let payload = try MeshAgentWalletAnchorSigningPayload(
            requestAnchorMetadata: metadata,
            policyId: "policy-hermes-dailymart-okrw-v1",
            policyHash: MeshPayloadHash(value: String(repeating: "d", count: 64)),
            walletAddress: "maroo1dailyMartAgentWallet"
        )

        let data = try JSONEncoder().encode(payload)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(object["signingPurpose"] as? String, "meshkit-agent-wallet-request-anchor/v1")
        XCTAssertEqual(object["policyId"] as? String, "policy-hermes-dailymart-okrw-v1")
        XCTAssertEqual((object["policyHash"] as? [String: Any])?["algorithm"] as? String, "sha256")
        XCTAssertEqual((object["requestAnchorMetadata"] as? [String: Any])?["nonce"] as? String, "nonce-wallet-anchor-codable")
        XCTAssertNil(object["marooSignature"])

        let decoded = try JSONDecoder().decode(MeshAgentWalletAnchorSigningPayload.self, from: data)
        XCTAssertEqual(decoded, payload)
    }

    func testAgentWalletSignsExecutableWalletOperationAuthorizationWithDistinctPurpose() throws {
        let signingKey = Curve25519.Signing.PrivateKey()
        let request = dailyMartRequest(nonce: "nonce-wallet-execution-sign", budget: "4900")
        let policy = try sampleDelegatedSpendingPolicy()
        let executionRequest = try MeshAgentWalletExecutionRequest(
            executionId: "exec-wallet-operation-sign",
            kind: .payment,
            requestAnchorMetadata: MeshSignedRequestAnchorMetadata(request: request),
            scope: sampleDelegatedSpendingScope(),
            amount: Decimal(4_900),
            currencyCode: "krw",
            tokenSymbol: "okrw",
            recipientAddress: try XCTUnwrap(policy.recipientAddress),
            policyId: policy.policyId,
            policyHash: policy.policyHash
        )
        let payload = try MeshAgentWalletExecutionAuthorizationPayload(
            executionRequest: executionRequest,
            policyId: policy.policyId,
            policyHash: policy.policyHash,
            walletAddress: "maroo1dailyMartAgentWallet"
        )
        let wallet = try StaticAgentWallet(
            identity: sampleAgentWalletIdentity(),
            capabilities: [
                .reportWalletAddress,
                .exposeSigningBoundary,
                .signExecutionAuthorizationPayload
            ],
            spendingLimit: nil,
            anchorSigningKey: signingKey
        )

        let authorization = try wallet.signExecutionAuthorizationPayload(
            payload,
            signedAt: "2026-05-31T00:00:01Z"
        )
        let decision = try MeshAgentWalletAuthorizationDecision(
            authorizationId: "auth-wallet-operation-sign",
            walletIdentity: wallet.identity,
            executionRequest: executionRequest,
            status: .approved,
            approvedAmount: Decimal(4_900),
            decidedAt: "2026-05-31T00:00:01Z",
            executionAuthorization: authorization
        )

        XCTAssertTrue(try wallet.loadWalletConfiguration().supports(.signExecutionAuthorizationPayload))
        XCTAssertEqual(authorization.walletIdentity.walletId, "wallet-hermes-dailymart-okrw-v1")
        XCTAssertEqual(authorization.payload.signingPurpose, "meshkit-agent-wallet-execution-authorization/v1")
        XCTAssertEqual(authorization.payload.executionRequest.executionId, "exec-wallet-operation-sign")
        XCTAssertEqual(authorization.payload.executionRequest.kind, .payment)
        XCTAssertEqual(authorization.payload.policyId, policy.policyId)
        XCTAssertEqual(authorization.payload.policyHash, policy.policyHash)
        XCTAssertEqual(authorization.signature.algorithm, "Ed25519")
        XCTAssertEqual(authorization.signature.keyId, "wallet-hermes-dailymart-okrw-v1#execution-authorization")
        XCTAssertEqual(authorization.signedAt, "2026-05-31T00:00:01Z")
        XCTAssertNoThrow(try decision.validateExecutionAuthorizationBoundary())

        let signatureData = try XCTUnwrap(Data(base64Encoded: authorization.signature.value))
        XCTAssertTrue(signingKey.publicKey.isValidSignature(signatureData, for: try payload.signingInputData()))
    }

    func testAgentWalletExecutableOperationSigningRequiresCapabilityAndWalletBinding() throws {
        let request = dailyMartRequest(nonce: "nonce-wallet-execution-requires-capability", budget: "4900")
        let policy = try sampleDelegatedSpendingPolicy()
        let executionRequest = try MeshAgentWalletExecutionRequest(
            executionId: "exec-wallet-operation-requires-capability",
            kind: .transfer,
            requestAnchorMetadata: MeshSignedRequestAnchorMetadata(request: request),
            scope: sampleDelegatedSpendingScope(),
            amount: Decimal(4_900),
            currencyCode: "krw",
            tokenSymbol: "okrw",
            recipientAddress: try XCTUnwrap(policy.recipientAddress),
            policyId: policy.policyId,
            policyHash: policy.policyHash
        )
        let payload = try MeshAgentWalletExecutionAuthorizationPayload(
            executionRequest: executionRequest,
            policyId: policy.policyId,
            policyHash: policy.policyHash,
            walletAddress: "maroo1dailyMartAgentWallet"
        )
        let wallet = try StaticAgentWallet(
            identity: sampleAgentWalletIdentity(),
            capabilities: [.reportWalletAddress],
            spendingLimit: nil,
            anchorSigningKey: Curve25519.Signing.PrivateKey()
        )

        XCTAssertThrowsError(try wallet.signExecutionAuthorizationPayload(payload, signedAt: "2026-05-31T00:00:01Z")) { error in
            XCTAssertEqual(error as? MeshKitValidationError, .unsupportedCapability)
        }

        let mismatchedPayload = try MeshAgentWalletExecutionAuthorizationPayload(
            executionRequest: executionRequest,
            policyId: policy.policyId,
            policyHash: policy.policyHash,
            walletAddress: "maroo1differentWallet"
        )
        XCTAssertThrowsError(try MeshAgentWalletExecutionAuthorization(
            walletIdentity: sampleAgentWalletIdentity(),
            payload: mismatchedPayload,
            signature: MeshSignature(algorithm: "Ed25519", keyId: "agent-wallet-key", value: "signature"),
            signedAt: "2026-05-31T00:00:01Z"
        )) { error in
            XCTAssertEqual(error as? MeshKitValidationError, .invalidAgentWalletIdentity("walletAddress"))
        }
    }

    func testAgentWalletRequestAnchorSigningRequiresCapabilityAndValidWalletBinding() throws {
        let metadata = try MeshSignedRequestAnchorMetadata(
            request: dailyMartRequest(nonce: "nonce-wallet-anchor-requires-capability")
        )
        let payload = try MeshAgentWalletAnchorSigningPayload(
            requestAnchorMetadata: metadata,
            policyId: "policy-hermes-dailymart-okrw-v1",
            policyHash: MeshPayloadHash(value: String(repeating: "e", count: 64)),
            walletAddress: "maroo1dailyMartAgentWallet"
        )
        let wallet = try StaticAgentWallet(
            identity: sampleAgentWalletIdentity(),
            capabilities: [.reportWalletAddress],
            spendingLimit: nil,
            anchorSigningKey: Curve25519.Signing.PrivateKey()
        )

        XCTAssertThrowsError(try wallet.signRequestAnchorPayload(payload, signedAt: "2026-05-31T00:00:00Z")) { error in
            XCTAssertEqual(error as? MeshKitValidationError, .unsupportedCapability)
        }

        let mismatchedPayload = try MeshAgentWalletAnchorSigningPayload(
            requestAnchorMetadata: metadata,
            policyId: "policy-hermes-dailymart-okrw-v1",
            policyHash: MeshPayloadHash(value: String(repeating: "e", count: 64)),
            walletAddress: "maroo1differentWallet"
        )
        XCTAssertThrowsError(try MeshAgentWalletAnchorSignature(
            walletIdentity: sampleAgentWalletIdentity(),
            payload: mismatchedPayload,
            signature: MeshSignature(algorithm: "Ed25519", keyId: "agent-wallet-key", value: "signature"),
            signedAt: "2026-05-31T00:00:00Z"
        )) { error in
            XCTAssertEqual(error as? MeshKitValidationError, .invalidAgentWalletIdentity("walletAddress"))
        }

        XCTAssertThrowsError(try MeshAgentWalletAnchorSigningPayload(
            requestAnchorMetadata: metadata,
            policyId: "policy-hermes-dailymart-okrw-v1",
            policyHash: MeshPayloadHash(value: "not-a-sha256"),
            walletAddress: "maroo1dailyMartAgentWallet"
        )) { error in
            XCTAssertEqual(error as? MeshKitValidationError, .invalidAgentWalletIdentity("policyHash.value"))
        }
    }

    func testAgentWalletDelegatedSpendingLimitCodableUsesStableContractKeys() throws {
        let spendingLimit = try sampleDelegatedSpendingLimit()

        let data = try JSONEncoder().encode(spendingLimit)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertNotNil(object["limitAmount"])
        XCTAssertNotNil(object["availableLimit"])
        XCTAssertEqual(object["currencyCode"] as? String, "KRW")
        XCTAssertEqual(object["tokenSymbol"] as? String, "OKRW")
        XCTAssertEqual(object["expiresAt"] as? String, "2026-06-30T00:00:00Z")

        let scope = try XCTUnwrap(object["scope"] as? [String: Any])
        XCTAssertEqual(scope["merchantId"] as? String, "merchant.dailymart")
        XCTAssertEqual(scope["targetBundleId"] as? String, "ai.meshkit.sample.dailymart")
        XCTAssertEqual(scope["capabilityId"] as? String, "grocery.purchase_essentials")
        XCTAssertEqual(scope["consentGrantId"] as? String, "grant-hermes-dailymart-001")

        let policyMetadata = try XCTUnwrap(object["policyMetadata"] as? [String: Any])
        XCTAssertEqual(policyMetadata["policyId"] as? String, "policy-hermes-dailymart-okrw-v1")
        XCTAssertEqual((policyMetadata["policyHash"] as? [String: Any])?["algorithm"] as? String, "sha256")
        XCTAssertEqual((policyMetadata["policyHash"] as? [String: Any])?["value"] as? String, String(repeating: "f", count: 64))
        XCTAssertEqual(policyMetadata["consentGrantId"] as? String, "grant-hermes-dailymart-001")
        XCTAssertEqual(policyMetadata["merchantScope"] as? String, "merchant.dailymart")
        XCTAssertEqual(policyMetadata["capabilityScope"] as? String, "grocery.purchase_essentials")
        XCTAssertEqual(policyMetadata["asset"] as? String, "OKRW")
        XCTAssertEqual(policyMetadata["recipientAddress"] as? String, "maroo1dailyMartMerchant")

        let decoded = try JSONDecoder().decode(MeshAgentWalletDelegatedSpendingLimit.self, from: data)
        XCTAssertEqual(decoded, spendingLimit)
    }

    func testAgentWalletDelegatedSpendingLimitRejectsInvalidContractFields() throws {
        let scope = try sampleDelegatedSpendingScope()

        XCTAssertThrowsError(try MeshAgentWalletDelegatedSpendingLimit(
            limitAmount: 0,
            tokenSymbol: "OKRW",
            scope: scope,
            expiresAt: "2026-06-30T00:00:00Z"
        )) { error in
            XCTAssertEqual(error as? MeshKitValidationError, .invalidAgentWalletIdentity("limitAmount"))
        }

        XCTAssertThrowsError(try MeshAgentWalletDelegatedSpendingLimit(
            limitAmount: 10_000,
            scope: scope,
            expiresAt: "2026-06-30T00:00:00Z"
        )) { error in
            XCTAssertEqual(error as? MeshKitValidationError, .invalidAgentWalletIdentity("currencyCode"))
        }

        XCTAssertThrowsError(try MeshAgentWalletSpendingScope(
            merchantId: "merchant.dailymart",
            targetBundleId: "ai.meshkit.sample.dailymart",
            capabilityId: "grocery.purchase\nforged",
            consentGrantId: "grant-hermes-dailymart-001"
        )) { error in
            XCTAssertEqual(error as? MeshKitValidationError, .invalidAgentWalletIdentity("capabilityId"))
        }

        XCTAssertThrowsError(try MeshAgentWalletDelegatedSpendingLimit(
            limitAmount: 10_000,
            availableLimit: 10_001,
            tokenSymbol: "OKRW",
            scope: scope,
            expiresAt: " 2026-06-30T00:00:00Z "
        )) { error in
            XCTAssertEqual(error as? MeshKitValidationError, .invalidAgentWalletIdentity("expiresAt"))
        }

        XCTAssertThrowsError(try MeshAgentWalletDelegatedSpendingLimit(
            limitAmount: 10_000,
            availableLimit: 10_001,
            tokenSymbol: "OKRW",
            scope: scope,
            expiresAt: "2026-06-30T00:00:00Z"
        )) { error in
            XCTAssertEqual(error as? MeshKitValidationError, .invalidAgentWalletIdentity("availableLimit"))
        }

        XCTAssertThrowsError(try MeshAgentWalletDelegatedSpendingLimit(
            limitAmount: 10_000,
            availableLimit: 8_500,
            tokenSymbol: "OKRW",
            scope: scope,
            expiresAt: "2026-06-30T00:00:00Z",
            policyMetadata: MeshAgentWalletDelegatedSpendingPolicyMetadata(
                policyId: "policy-hermes-dailymart-okrw-v1",
                policyHash: MeshPayloadHash(value: String(repeating: "f", count: 64)),
                consentGrantId: "grant-other-001",
                merchantScope: "merchant.dailymart",
                capabilityScope: "grocery.purchase_essentials",
                expiresAt: "2026-06-30T00:00:00Z",
                asset: "OKRW"
            )
        )) { error in
            XCTAssertEqual(error as? MeshKitValidationError, .invalidAgentWalletIdentity("policyMetadata.consentGrantId"))
        }
    }

    func testAgentWalletDelegatedSpendingPolicyValidatesProviderNeutralInputShape() throws {
        let policy = try sampleDelegatedSpendingPolicy()

        try policy.validatePolicyInput(
            amount: Decimal(4_900),
            merchantScope: "merchant.dailymart",
            capabilityScope: "grocery.purchase_essentials",
            consentGrantId: "grant-hermes-dailymart-001",
            asset: "okrw",
            recipientAddress: "maroo1dailyMartMerchant"
        )

        let data = try JSONEncoder().encode(policy)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(object["policyId"] as? String, "policy-hermes-dailymart-okrw-v1")
        XCTAssertEqual((object["policyHash"] as? [String: Any])?["algorithm"] as? String, "sha256")
        XCTAssertEqual((object["policyHash"] as? [String: Any])?["value"] as? String, String(repeating: "f", count: 64))
        XCTAssertEqual(object["consentGrantId"] as? String, "grant-hermes-dailymart-001")
        XCTAssertEqual(object["merchantScope"] as? String, "merchant.dailymart")
        XCTAssertEqual(object["capabilityScope"] as? String, "grocery.purchase_essentials")
        XCTAssertNotNil(object["singlePaymentMax"])
        XCTAssertNotNil(object["sessionTotalLimit"])
        XCTAssertNotNil(object["remainingLimit"])
        XCTAssertEqual(object["expiresAt"] as? String, "2026-06-30T00:00:00Z")
        XCTAssertEqual(object["asset"] as? String, "OKRW")
        XCTAssertEqual(object["recipientAddress"] as? String, "maroo1dailyMartMerchant")

        let decoded = try JSONDecoder().decode(MeshAgentWalletDelegatedSpendingPolicy.self, from: data)
        XCTAssertEqual(decoded, policy)
    }

    func testAgentWalletDelegatedSpendingPolicyRejectsMissingRequiredJSONFields() throws {
        let requiredFields = [
            "policyId",
            "policyHash",
            "consentGrantId",
            "merchantScope",
            "capabilityScope",
            "singlePaymentMax",
            "sessionTotalLimit",
            "remainingLimit",
            "expiresAt",
            "asset"
        ]

        for missingField in requiredFields {
            var object = sampleDelegatedSpendingPolicyJSONObject()
            object.removeValue(forKey: missingField)
            let data = try JSONSerialization.data(withJSONObject: object)

            XCTAssertThrowsError(
                try JSONDecoder().decode(MeshAgentWalletDelegatedSpendingPolicy.self, from: data),
                "Expected missing \(missingField) to be rejected"
            )
        }
    }

    private final class PaymentSubmissionBoundaryLog: @unchecked Sendable {
        private(set) var events: [String] = []

        func append(_ event: String) {
            events.append(event)
        }
    }

    private struct BoundaryRequestAnchorProvider: MeshRequestAnchorProvider {
        let identity: MeshChainProviderIdentity
        let capabilities: [MeshChainProviderCapability]
        let log: PaymentSubmissionBoundaryLog

        func anchorSignedRequest(
            metadata: MeshSignedRequestAnchorMetadata,
            submittedAt: String
        ) async throws -> MeshRequestAnchor {
            try MeshChainProviderConfiguration(identity: identity, capabilities: capabilities).require(.anchorSignedRequest)
            let anchor = try MeshRequestAnchor(
                metadata: metadata,
                identifier: MeshRequestAnchorIdentifier(
                    identity: identity,
                    anchorId: "anchor-\(metadata.requestId)",
                    transactionHash: "0xanchorBoundary001"
                ),
                status: .confirmed,
                submittedAt: submittedAt,
                observedAt: submittedAt
            )
            log.append("anchor:\(anchor.identifier.anchorId)")
            return anchor
        }

        func requestAnchorStatus(
            identifier: MeshRequestAnchorIdentifier,
            checkedAt: String
        ) async throws -> MeshRequestAnchor {
            throw MeshKitValidationError.unsupportedCapability
        }
    }

    private final class BoundaryPaymentExecutor: MeshPaymentExecutor, @unchecked Sendable {
        let identity: MeshChainProviderIdentity
        let capabilities: [MeshPaymentExecutorCapability]
        let log: PaymentSubmissionBoundaryLog
        private(set) var executionCallCount = 0

        init(
            identity: MeshChainProviderIdentity,
            capabilities: [MeshPaymentExecutorCapability],
            log: PaymentSubmissionBoundaryLog
        ) {
            self.identity = identity
            self.capabilities = capabilities
            self.log = log
        }

        func loadPaymentExecutorConfiguration() throws -> MeshPaymentExecutorConfiguration {
            try MeshPaymentExecutorConfiguration(identity: identity, capabilities: capabilities)
        }

        func executePayment(
            _ request: MeshPaymentExecutionRequest,
            submittedAt: String
        ) async throws -> MeshPaymentExecutionResult {
            try request.validate()
            let requiredCapability: MeshPaymentExecutorCapability = request.executionRequest.kind == .payment
                ? .executePayment
                : .executeTransfer
            try loadPaymentExecutorConfiguration().require(requiredCapability)
            executionCallCount += 1
            log.append("\(request.executionRequest.kind.rawValue):\(request.requestAnchor.identifier.anchorId)")
            return try MeshPaymentExecutionResult(
                request: request,
                identity: identity,
                status: .pending,
                observedAt: submittedAt
            )
        }

        func paymentExecutionStatus(paymentId: String, checkedAt: String) async throws -> MeshPaymentExecutionResult {
            throw MeshKitValidationError.invalidPaymentExecution("paymentId")
        }
    }

    func testAgentWalletDelegatedSpendingPolicyRejectsInvalidFieldsAndPolicyInputs() throws {
        XCTAssertThrowsError(try MeshAgentWalletDelegatedSpendingPolicy(
            policyId: "policy-hermes-dailymart-okrw-v1",
            policyHash: MeshPayloadHash(value: "not-a-sha256"),
            consentGrantId: "grant-hermes-dailymart-001",
            merchantScope: "merchant.dailymart",
            capabilityScope: "grocery.purchase_essentials",
            singlePaymentMax: Decimal(5_000),
            sessionTotalLimit: Decimal(10_000),
            remainingLimit: Decimal(10_000),
            expiresAt: "2026-06-30T00:00:00Z",
            asset: "OKRW"
        )) { error in
            XCTAssertEqual(error as? MeshKitValidationError, .invalidAgentWalletIdentity("policyHash.value"))
        }

        XCTAssertThrowsError(try MeshAgentWalletDelegatedSpendingPolicy(
            policyId: "policy-hermes-dailymart-okrw-v1",
            policyHash: MeshPayloadHash(value: String(repeating: "f", count: 64)),
            consentGrantId: "grant-hermes-dailymart-001",
            merchantScope: "merchant.dailymart",
            capabilityScope: "grocery.purchase_essentials",
            singlePaymentMax: Decimal(12_000),
            sessionTotalLimit: Decimal(10_000),
            remainingLimit: Decimal(10_000),
            expiresAt: "2026-06-30T00:00:00Z",
            asset: "OKRW"
        )) { error in
            XCTAssertEqual(error as? MeshKitValidationError, .invalidAgentWalletIdentity("singlePaymentMax"))
        }

        XCTAssertThrowsError(try MeshAgentWalletDelegatedSpendingPolicy(
            policyId: "policy-hermes-dailymart-okrw-v1",
            policyHash: MeshPayloadHash(value: String(repeating: "f", count: 64)),
            consentGrantId: "grant-hermes-dailymart-001",
            merchantScope: "merchant.dailymart",
            capabilityScope: "grocery.purchase_essentials",
            singlePaymentMax: Decimal(5_000),
            sessionTotalLimit: Decimal(10_000),
            remainingLimit: Decimal(10_001),
            expiresAt: "2026-06-30T00:00:00Z",
            asset: "OKRW"
        )) { error in
            XCTAssertEqual(error as? MeshKitValidationError, .invalidAgentWalletIdentity("remainingLimit"))
        }

        let policy = try sampleDelegatedSpendingPolicy()
        XCTAssertThrowsError(try policy.validatePolicyInput(
            amount: Decimal(5_001),
            merchantScope: "merchant.dailymart",
            capabilityScope: "grocery.purchase_essentials",
            consentGrantId: "grant-hermes-dailymart-001",
            asset: "OKRW"
        )) { error in
            XCTAssertEqual(error as? MeshKitValidationError, .invalidAgentWalletIdentity("singlePaymentMax"))
        }

        XCTAssertThrowsError(try policy.validatePolicyInput(
            amount: Decimal(4_900),
            merchantScope: "merchant.other",
            capabilityScope: "grocery.purchase_essentials",
            consentGrantId: "grant-hermes-dailymart-001",
            asset: "OKRW",
            recipientAddress: "maroo1dailyMartMerchant"
        )) { error in
            XCTAssertEqual(error as? MeshKitValidationError, .invalidAgentWalletIdentity("merchantScope"))
        }
    }

    func testAgentWalletDelegatedSpendingPolicyAllowsValidExecutionAcrossAmountAssetRecipientAndTime() throws {
        let policy = try sampleDelegatedSpendingPolicy()
        let executionRequest = try sampleAgentWalletExecutionRequest(
            kind: .payment,
            amount: Decimal(4_900),
            nonce: "nonce-wallet-policy-allow"
        )

        let result = try policy.evaluateExecutionRequest(
            executionRequest,
            requestedAt: "2026-05-31T00:00:00Z"
        )

        XCTAssertEqual(result.policyId, "policy-hermes-dailymart-okrw-v1")
        XCTAssertEqual(result.executionId, "exec-ios-grocery-test-001")
        XCTAssertEqual(result.status, .allowed)
        XCTAssertEqual(result.approvedAmount, Decimal(4_900))
        XCTAssertNil(result.reason)
        XCTAssertEqual(result.evaluatedAt, "2026-05-31T00:00:00Z")
    }

    func testAgentWalletDelegatedSpendingPolicyDeniesRecipientAssetAndExpiredExecutions() throws {
        let policy = try sampleDelegatedSpendingPolicy()
        let wrongRecipientRequest = try sampleAgentWalletExecutionRequest(
            kind: .payment,
            amount: Decimal(4_900),
            nonce: "nonce-wallet-policy-recipient-denied",
            recipientAddress: "maroo1unapprovedMerchant"
        )
        let wrongAssetRequest = try MeshAgentWalletExecutionRequest(
            executionId: "exec-ios-grocery-test-asset-denied",
            kind: .payment,
            requestAnchorMetadata: MeshSignedRequestAnchorMetadata(
                request: dailyMartRequest(nonce: "nonce-wallet-policy-asset-denied", budget: "4900")
            ),
            scope: sampleDelegatedSpendingScope(),
            amount: Decimal(4_900),
            currencyCode: "USD",
            tokenSymbol: "USDC",
            recipientAddress: "maroo1dailyMartMerchant",
            policyId: "policy-hermes-dailymart-okrw-v1",
            policyHash: MeshPayloadHash(value: String(repeating: "f", count: 64))
        )
        let expiredRequest = try sampleAgentWalletExecutionRequest(
            kind: .payment,
            amount: Decimal(4_900),
            nonce: "nonce-wallet-policy-expired-denied"
        )

        let recipientResult = try policy.evaluateExecutionRequest(
            wrongRecipientRequest,
            requestedAt: "2026-05-31T00:00:00Z"
        )
        let assetResult = try policy.evaluateExecutionRequest(
            wrongAssetRequest,
            requestedAt: "2026-05-31T00:00:00Z"
        )
        let expiredResult = try policy.evaluateExecutionRequest(
            expiredRequest,
            requestedAt: "2026-07-01T00:00:00Z"
        )

        XCTAssertEqual(recipientResult.status, .denied)
        XCTAssertEqual(recipientResult.reason, "policy-recipient-address-mismatch")
        XCTAssertEqual(assetResult.status, .denied)
        XCTAssertEqual(assetResult.reason, "policy-asset-mismatch")
        XCTAssertEqual(expiredResult.status, .denied)
        XCTAssertEqual(expiredResult.reason, "policy-expired")
    }

    func testAgentWalletDelegatedSpendingPolicyDeniesLimitViolationsWithExplicitReasons() throws {
        let policy = try sampleDelegatedSpendingPolicy()
        let aboveSinglePaymentMaxRequest = try sampleAgentWalletExecutionRequest(
            kind: .payment,
            amount: Decimal(5_001),
            nonce: "nonce-wallet-policy-single-payment-denied"
        )
        let remainingLimitPolicy = try MeshAgentWalletDelegatedSpendingPolicy(
            policyId: "policy-hermes-dailymart-okrw-v1",
            policyHash: MeshPayloadHash(value: String(repeating: "f", count: 64)),
            consentGrantId: "grant-hermes-dailymart-001",
            merchantScope: "merchant.dailymart",
            capabilityScope: "grocery.purchase_essentials",
            singlePaymentMax: Decimal(5_000),
            sessionTotalLimit: Decimal(10_000),
            remainingLimit: Decimal(4_000),
            expiresAt: "2026-06-30T00:00:00Z",
            asset: "OKRW",
            recipientAddress: "maroo1dailyMartMerchant"
        )
        let aboveRemainingLimitRequest = try sampleAgentWalletExecutionRequest(
            kind: .transfer,
            amount: Decimal(4_900),
            nonce: "nonce-wallet-policy-remaining-limit-denied"
        )

        let singlePaymentResult = try policy.evaluateExecutionRequest(
            aboveSinglePaymentMaxRequest,
            requestedAt: "2026-05-31T00:00:00Z"
        )
        let remainingLimitResult = try remainingLimitPolicy.evaluateExecutionRequest(
            aboveRemainingLimitRequest,
            requestedAt: "2026-05-31T00:00:00Z"
        )

        XCTAssertEqual(singlePaymentResult.status, .denied)
        XCTAssertNil(singlePaymentResult.approvedAmount)
        XCTAssertEqual(singlePaymentResult.reason, "policy-single-payment-max-exceeded")
        XCTAssertEqual(remainingLimitResult.status, .denied)
        XCTAssertNil(remainingLimitResult.approvedAmount)
        XCTAssertEqual(remainingLimitResult.reason, "policy-remaining-limit-exceeded")
    }

    func testAgentWalletSpendAccountingRecordsAttemptsAndPendingReservationsAgainstLimit() throws {
        let policy = try sampleDelegatedSpendingPolicy()
        let firstRequest = try sampleAgentWalletExecutionRequest(
            executionId: "exec-wallet-accounting-001",
            kind: .payment,
            amount: Decimal(4_900),
            nonce: "nonce-wallet-accounting-001"
        )
        let secondRequest = try sampleAgentWalletExecutionRequest(
            executionId: "exec-wallet-accounting-002",
            kind: .payment,
            amount: Decimal(4_900),
            nonce: "nonce-wallet-accounting-002"
        )
        let thirdRequest = try sampleAgentWalletExecutionRequest(
            executionId: "exec-wallet-accounting-003",
            kind: .transfer,
            amount: Decimal(300),
            nonce: "nonce-wallet-accounting-003"
        )

        let emptyAccounting = try MeshAgentWalletDelegatedSpendAccounting(policy: policy)
        let attempted = try emptyAccounting.recordingAttemptedExecution(
            firstRequest,
            recordedAt: "2026-05-31T00:00:00Z"
        )
        let firstReserved = try attempted.reservingPendingExecution(
            firstRequest,
            recordedAt: "2026-05-31T00:00:01Z"
        )
        let secondReserved = try firstReserved.reservingPendingExecution(
            secondRequest,
            recordedAt: "2026-05-31T00:00:02Z"
        )

        XCTAssertEqual(attempted.attemptedExecutionCount, 1)
        XCTAssertEqual(attempted.attemptedAmount, Decimal(4_900))
        XCTAssertEqual(attempted.pendingReservedAmount, Decimal(0))
        XCTAssertEqual(firstReserved.pendingReservedAmount, Decimal(4_900))
        XCTAssertEqual(firstReserved.availableLimit, Decimal(5_100))
        XCTAssertEqual(secondReserved.pendingReservedAmount, Decimal(9_800))
        XCTAssertEqual(secondReserved.availableLimit, Decimal(200))
        XCTAssertFalse(try secondReserved.canReserve(thirdRequest, requestedAt: "2026-05-31T00:00:03Z"))
        XCTAssertThrowsError(try secondReserved.reservingPendingExecution(
            thirdRequest,
            recordedAt: "2026-05-31T00:00:03Z"
        )) { error in
            XCTAssertEqual(error as? MeshKitValidationError, .invalidAgentWalletIdentity("availableLimit"))
        }
    }

    func testAgentWalletSpendAccountingSettlesPendingReservationsForConfirmedFailedAndDeniedExecutions() throws {
        let policy = try sampleDelegatedSpendingPolicy()
        let confirmedRequest = try sampleAgentWalletExecutionRequest(
            executionId: "exec-wallet-accounting-confirmed",
            kind: .payment,
            amount: Decimal(4_900),
            nonce: "nonce-wallet-accounting-confirmed"
        )
        let failedRequest = try sampleAgentWalletExecutionRequest(
            executionId: "exec-wallet-accounting-failed",
            kind: .payment,
            amount: Decimal(4_900),
            nonce: "nonce-wallet-accounting-failed"
        )
        let deniedRequest = try sampleAgentWalletExecutionRequest(
            executionId: "exec-wallet-accounting-denied",
            kind: .payment,
            amount: Decimal(5_001),
            nonce: "nonce-wallet-accounting-denied"
        )

        let reserved = try MeshAgentWalletDelegatedSpendAccounting(policy: policy)
            .reservingPendingExecution(confirmedRequest, recordedAt: "2026-05-31T00:00:00Z")
            .reservingPendingExecution(failedRequest, recordedAt: "2026-05-31T00:00:01Z")
        let confirmed = try reserved.recordingConfirmedSpend(
            confirmedRequest,
            recordedAt: "2026-05-31T00:00:02Z"
        )
        let failed = try confirmed.recordingFailedExecution(
            failedRequest,
            recordedAt: "2026-05-31T00:00:03Z",
            reason: "provider-execution-failed"
        )
        let denied = try failed.recordingPolicyDeniedExecution(
            deniedRequest,
            recordedAt: "2026-05-31T00:00:04Z",
            reason: "policy-single-payment-max-exceeded"
        )

        XCTAssertEqual(reserved.pendingReservedAmount, Decimal(9_800))
        XCTAssertEqual(confirmed.pendingReservedAmount, Decimal(4_900))
        XCTAssertEqual(confirmed.confirmedSpendAmount, Decimal(4_900))
        XCTAssertEqual(failed.pendingReservedAmount, Decimal(0))
        XCTAssertEqual(failed.failedAttemptAmount, Decimal(4_900))
        XCTAssertEqual(failed.availableLimit, Decimal(5_100))
        XCTAssertEqual(denied.attemptedExecutionCount, 2)
        XCTAssertEqual(denied.confirmedSpendAmount, Decimal(4_900))
        XCTAssertEqual(denied.availableLimit, Decimal(5_100))
        XCTAssertEqual(denied.records.last?.status, .policyDenied)
        XCTAssertEqual(denied.records.last?.reason, "policy-single-payment-max-exceeded")
        XCTAssertEqual(denied.policyDeniedExecutionCount, 1)
        XCTAssertEqual(denied.policyDeniedAuditRecords.last?.executionId, deniedRequest.executionId)
    }

    func testAgentWalletSpendAccountingAuditsPolicyDeniedExecutionsWithoutReservingOrConsumingLimit() throws {
        let policy = try sampleDelegatedSpendingPolicy()
        let reservedRequest = try sampleAgentWalletExecutionRequest(
            executionId: "exec-wallet-accounting-reserved-before-denial",
            kind: .payment,
            amount: Decimal(4_900),
            nonce: "nonce-wallet-accounting-reserved-before-denial"
        )
        let deniedSinglePaymentRequest = try sampleAgentWalletExecutionRequest(
            executionId: "exec-wallet-accounting-denied-single-payment",
            kind: .payment,
            amount: Decimal(5_001),
            nonce: "nonce-wallet-accounting-denied-single-payment"
        )
        let deniedRemainingLimitRequest = try sampleAgentWalletExecutionRequest(
            executionId: "exec-wallet-accounting-denied-remaining-limit",
            kind: .payment,
            amount: Decimal(4_900),
            nonce: "nonce-wallet-accounting-denied-remaining-limit"
        )

        let reserved = try MeshAgentWalletDelegatedSpendAccounting(policy: policy)
            .reservingPendingExecution(
                reservedRequest,
                recordedAt: "2026-05-31T00:00:00Z"
            )
        let firstDenied = try reserved.recordingPolicyDeniedExecution(
            deniedSinglePaymentRequest,
            recordedAt: "2026-05-31T00:00:01Z",
            reason: "policy-single-payment-max-exceeded"
        )
        let secondDenied = try firstDenied.recordingPolicyDeniedExecution(
            deniedRemainingLimitRequest,
            recordedAt: "2026-05-31T00:00:02Z",
            reason: "policy-remaining-limit-exceeded"
        )

        XCTAssertEqual(reserved.pendingReservedAmount, Decimal(4_900))
        XCTAssertEqual(reserved.confirmedSpendAmount, Decimal(0))
        XCTAssertEqual(reserved.attemptedExecutionCount, 1)
        XCTAssertEqual(reserved.attemptedAmount, Decimal(4_900))
        XCTAssertEqual(reserved.availableLimit, Decimal(5_100))

        XCTAssertEqual(firstDenied.pendingReservedAmount, reserved.pendingReservedAmount)
        XCTAssertEqual(firstDenied.confirmedSpendAmount, reserved.confirmedSpendAmount)
        XCTAssertEqual(firstDenied.attemptedExecutionCount, reserved.attemptedExecutionCount)
        XCTAssertEqual(firstDenied.attemptedAmount, reserved.attemptedAmount)
        XCTAssertEqual(firstDenied.availableLimit, reserved.availableLimit)
        XCTAssertEqual(firstDenied.policyDeniedExecutionCount, 1)

        XCTAssertEqual(secondDenied.pendingReservedAmount, reserved.pendingReservedAmount)
        XCTAssertEqual(secondDenied.confirmedSpendAmount, reserved.confirmedSpendAmount)
        XCTAssertEqual(secondDenied.attemptedExecutionCount, reserved.attemptedExecutionCount)
        XCTAssertEqual(secondDenied.attemptedAmount, reserved.attemptedAmount)
        XCTAssertEqual(secondDenied.availableLimit, reserved.availableLimit)
        XCTAssertEqual(secondDenied.policyDeniedExecutionCount, 2)
        XCTAssertEqual(
            secondDenied.policyDeniedAuditRecords.map(\.executionId),
            [
                deniedSinglePaymentRequest.executionId,
                deniedRemainingLimitRequest.executionId
            ]
        )
        XCTAssertEqual(
            secondDenied.policyDeniedAuditRecords.map(\.reason),
            [
                "policy-single-payment-max-exceeded",
                "policy-remaining-limit-exceeded"
            ]
        )
    }

    func testAgentWalletSpendAccountingConvertsPendingExecutionResultsToConfirmedRemainingLimit() throws {
        let policy = try sampleDelegatedSpendingPolicy()
        let firstPaymentRequest = try samplePaymentExecutionRequest(
            executionId: "exec-wallet-result-confirmed-001",
            kind: .payment,
            amount: Decimal(4_900),
            nonce: "nonce-wallet-result-confirmed-001",
            authorizationStatus: .approved
        )
        let secondPaymentRequest = try samplePaymentExecutionRequest(
            executionId: "exec-wallet-result-confirmed-002",
            kind: .payment,
            amount: Decimal(4_900),
            nonce: "nonce-wallet-result-confirmed-002",
            authorizationStatus: .approved
        )
        let firstPendingResult = try MeshPaymentExecutionResult(
            request: firstPaymentRequest,
            identity: try sampleChainProviderIdentity(),
            status: .pending,
            observedAt: "2026-05-31T00:00:01Z"
        )
        let firstConfirmedResult = try MeshPaymentExecutionResult(
            request: firstPaymentRequest,
            identity: try sampleChainProviderIdentity(),
            status: .confirmed,
            transactionHash: "0xokrwconfirmedspend001",
            observedAt: "2026-05-31T00:00:02Z"
        )
        let secondPendingResult = try MeshPaymentExecutionResult(
            request: secondPaymentRequest,
            identity: try sampleChainProviderIdentity(),
            status: .pending,
            observedAt: "2026-05-31T00:00:03Z"
        )
        let secondConfirmedResult = try MeshPaymentExecutionResult(
            request: secondPaymentRequest,
            identity: try sampleChainProviderIdentity(),
            status: .confirmed,
            transactionHash: "0xokrwconfirmedspend002",
            observedAt: "2026-05-31T00:00:04Z"
        )

        let firstPending = try MeshAgentWalletDelegatedSpendAccounting(policy: policy)
            .recordingPaymentExecutionResult(
                firstPendingResult,
                for: firstPaymentRequest,
                recordedAt: "2026-05-31T00:00:01Z"
            )
        let idempotentPending = try firstPending.recordingPaymentExecutionResult(
            firstPendingResult,
            for: firstPaymentRequest,
            recordedAt: "2026-05-31T00:00:01Z"
        )
        let firstConfirmed = try idempotentPending.recordingPaymentExecutionResult(
            firstConfirmedResult,
            for: firstPaymentRequest,
            recordedAt: "2026-05-31T00:00:02Z"
        )
        let secondPending = try firstConfirmed.recordingPaymentExecutionResult(
            secondPendingResult,
            for: secondPaymentRequest,
            recordedAt: "2026-05-31T00:00:03Z"
        )
        let secondConfirmed = try secondPending.recordingPaymentExecutionResult(
            secondConfirmedResult,
            for: secondPaymentRequest,
            recordedAt: "2026-05-31T00:00:04Z"
        )
        let updatedPolicy = try secondConfirmed.policySnapshotAfterConfirmedSpend()
        let aboveUpdatedRemainingLimitRequest = try sampleAgentWalletExecutionRequest(
            executionId: "exec-wallet-result-over-remaining",
            kind: .payment,
            amount: Decimal(300),
            nonce: "nonce-wallet-result-over-remaining"
        )
        let remainingLimitDecision = try updatedPolicy.evaluateExecutionRequest(
            aboveUpdatedRemainingLimitRequest,
            requestedAt: "2026-05-31T00:00:05Z"
        )

        XCTAssertEqual(firstPending.pendingReservedAmount, Decimal(4_900))
        XCTAssertEqual(firstPending.availableLimit, Decimal(5_100))
        XCTAssertEqual(idempotentPending.records.count, firstPending.records.count)
        XCTAssertEqual(firstConfirmed.pendingReservedAmount, Decimal(0))
        XCTAssertEqual(firstConfirmed.confirmedSpendAmount, Decimal(4_900))
        XCTAssertEqual(firstConfirmed.remainingLimitAfterConfirmedSpend, Decimal(5_100))
        XCTAssertEqual(try firstConfirmed.policySnapshotAfterConfirmedSpend().remainingLimit, Decimal(5_100))
        XCTAssertEqual(secondPending.pendingReservedAmount, Decimal(4_900))
        XCTAssertEqual(secondPending.availableLimit, Decimal(200))
        XCTAssertEqual(secondConfirmed.pendingReservedAmount, Decimal(0))
        XCTAssertEqual(secondConfirmed.confirmedSpendAmount, Decimal(9_800))
        XCTAssertEqual(secondConfirmed.remainingLimitAfterConfirmedSpend, Decimal(200))
        XCTAssertEqual(updatedPolicy.remainingLimit, Decimal(200))
        XCTAssertEqual(remainingLimitDecision.status, .denied)
        XCTAssertEqual(remainingLimitDecision.reason, "policy-remaining-limit-exceeded")
    }

    func testAgentWalletSpendAccountingReconcilesFailedPendingExecutionWithoutConfirmedSpendImpact() throws {
        let policy = try sampleDelegatedSpendingPolicy()
        let failedPaymentRequest = try samplePaymentExecutionRequest(
            executionId: "exec-wallet-result-failed-001",
            kind: .payment,
            amount: Decimal(4_900),
            nonce: "nonce-wallet-result-failed-001",
            authorizationStatus: .approved
        )
        let retryPaymentRequest = try samplePaymentExecutionRequest(
            executionId: "exec-wallet-result-retry-confirmed-001",
            kind: .payment,
            amount: Decimal(4_900),
            nonce: "nonce-wallet-result-retry-confirmed-001",
            authorizationStatus: .approved
        )
        let pendingResult = try MeshPaymentExecutionResult(
            request: failedPaymentRequest,
            identity: try sampleChainProviderIdentity(),
            status: .pending,
            observedAt: "2026-05-31T00:00:01Z"
        )
        let failedResult = try MeshPaymentExecutionResult(
            request: failedPaymentRequest,
            identity: try sampleChainProviderIdentity(),
            status: .failed,
            observedAt: "2026-05-31T00:00:02Z",
            message: "provider-execution-failed"
        )
        let retryPendingResult = try MeshPaymentExecutionResult(
            request: retryPaymentRequest,
            identity: try sampleChainProviderIdentity(),
            status: .pending,
            observedAt: "2026-05-31T00:00:03Z"
        )
        let retryConfirmedResult = try MeshPaymentExecutionResult(
            request: retryPaymentRequest,
            identity: try sampleChainProviderIdentity(),
            status: .confirmed,
            transactionHash: "0xokrwretryconfirmed001",
            observedAt: "2026-05-31T00:00:04Z"
        )

        let pending = try MeshAgentWalletDelegatedSpendAccounting(policy: policy)
            .recordingPaymentExecutionResult(
                pendingResult,
                for: failedPaymentRequest,
                recordedAt: "2026-05-31T00:00:01Z"
            )
        let failed = try pending.recordingPaymentExecutionResult(
            failedResult,
            for: failedPaymentRequest,
            recordedAt: "2026-05-31T00:00:02Z"
        )
        let idempotentFailed = try failed.recordingPaymentExecutionResult(
            failedResult,
            for: failedPaymentRequest,
            recordedAt: "2026-05-31T00:00:02Z"
        )
        let retryPending = try idempotentFailed.recordingPaymentExecutionResult(
            retryPendingResult,
            for: retryPaymentRequest,
            recordedAt: "2026-05-31T00:00:03Z"
        )
        let retryConfirmed = try retryPending.recordingPaymentExecutionResult(
            retryConfirmedResult,
            for: retryPaymentRequest,
            recordedAt: "2026-05-31T00:00:04Z"
        )

        XCTAssertEqual(pending.pendingReservedAmount, Decimal(4_900))
        XCTAssertEqual(failed.pendingReservedAmount, Decimal(0))
        XCTAssertEqual(failed.confirmedSpendAmount, Decimal(0))
        XCTAssertEqual(failed.failedAttemptAmount, Decimal(4_900))
        XCTAssertEqual(failed.availableLimit, Decimal(10_000))
        XCTAssertEqual(idempotentFailed.records.count, failed.records.count)
        XCTAssertEqual(retryPending.pendingReservedAmount, Decimal(4_900))
        XCTAssertEqual(retryPending.confirmedSpendAmount, Decimal(0))
        XCTAssertEqual(retryConfirmed.pendingReservedAmount, Decimal(0))
        XCTAssertEqual(retryConfirmed.confirmedSpendAmount, Decimal(4_900))
        XCTAssertEqual(retryConfirmed.availableLimit, Decimal(5_100))
    }

    func testAgentWalletSpendAccountingKeepsConfirmedSpendWhenLateFailedResultArrives() throws {
        let policy = try sampleDelegatedSpendingPolicy()
        let paymentRequest = try samplePaymentExecutionRequest(
            executionId: "exec-wallet-result-confirmed-then-failed",
            kind: .payment,
            amount: Decimal(4_900),
            nonce: "nonce-wallet-result-confirmed-then-failed",
            authorizationStatus: .approved
        )
        let pendingResult = try MeshPaymentExecutionResult(
            request: paymentRequest,
            identity: try sampleChainProviderIdentity(),
            status: .pending,
            observedAt: "2026-05-31T00:00:01Z"
        )
        let confirmedResult = try MeshPaymentExecutionResult(
            request: paymentRequest,
            identity: try sampleChainProviderIdentity(),
            status: .confirmed,
            transactionHash: "0xokrwconfirmedbeforefailed001",
            observedAt: "2026-05-31T00:00:02Z"
        )
        let lateFailedResult = try MeshPaymentExecutionResult(
            request: paymentRequest,
            identity: try sampleChainProviderIdentity(),
            status: .failed,
            observedAt: "2026-05-31T00:00:03Z",
            message: "late-provider-failure"
        )

        let pending = try MeshAgentWalletDelegatedSpendAccounting(policy: policy)
            .recordingPaymentExecutionResult(
                pendingResult,
                for: paymentRequest,
                recordedAt: "2026-05-31T00:00:01Z"
            )
        let confirmed = try pending.recordingPaymentExecutionResult(
            confirmedResult,
            for: paymentRequest,
            recordedAt: "2026-05-31T00:00:02Z"
        )
        let reconciled = try confirmed.recordingPaymentExecutionResult(
            lateFailedResult,
            for: paymentRequest,
            recordedAt: "2026-05-31T00:00:03Z"
        )

        XCTAssertEqual(reconciled.records.count, confirmed.records.count)
        XCTAssertEqual(reconciled.pendingReservedAmount, Decimal(0))
        XCTAssertEqual(reconciled.confirmedSpendAmount, Decimal(4_900))
        XCTAssertEqual(reconciled.failedAttemptAmount, Decimal(0))
        XCTAssertEqual(reconciled.availableLimit, Decimal(5_100))
    }

    func testAgentWalletSpendAccountingReleasesPendingReservationWithoutSpendImpact() throws {
        let policy = try sampleDelegatedSpendingPolicy()
        let request = try sampleAgentWalletExecutionRequest(
            executionId: "exec-wallet-release-pending-001",
            kind: .transfer,
            amount: Decimal(4_900),
            nonce: "nonce-wallet-release-pending-001"
        )

        let pending = try MeshAgentWalletDelegatedSpendAccounting(policy: policy)
            .reservingPendingExecution(request, recordedAt: "2026-05-31T00:00:00Z")
        let released = try pending.releasingPendingReservation(
            request,
            recordedAt: "2026-05-31T00:00:01Z",
            reason: "provider-cancelled-before-submission"
        )
        let idempotentRelease = try released.releasingPendingReservation(
            request,
            recordedAt: "2026-05-31T00:00:02Z",
            reason: "provider-cancelled-before-submission"
        )

        XCTAssertEqual(pending.pendingReservedAmount, Decimal(4_900))
        XCTAssertEqual(released.pendingReservedAmount, Decimal(0))
        XCTAssertEqual(released.confirmedSpendAmount, Decimal(0))
        XCTAssertEqual(released.failedAttemptAmount, Decimal(0))
        XCTAssertEqual(released.availableLimit, Decimal(10_000))
        XCTAssertEqual(released.records.last?.status, .released)
        XCTAssertEqual(idempotentRelease.records.count, released.records.count)
    }

    func testAgentWalletAuthorizationUsesDelegatedPolicyEvaluationForAllowDecision() throws {
        let wallet = try StaticAgentWallet(
            identity: sampleAgentWalletIdentity(),
            capabilities: [
                .authorizeExecution,
                .reportDelegatedSpendingLimit,
                .validatePolicy
            ],
            spendingLimit: sampleDelegatedSpendingLimit(),
            anchorSigningKey: nil,
            delegatedPolicy: sampleDelegatedSpendingPolicy()
        )
        let executionRequest = try sampleAgentWalletExecutionRequest(
            kind: .payment,
            amount: Decimal(4_900),
            nonce: "nonce-wallet-policy-auth-allow"
        )

        let decision = try wallet.authorizeExecution(
            executionRequest,
            decidedAt: "2026-05-31T00:00:00Z"
        )

        XCTAssertEqual(decision.status, .approved)
        XCTAssertEqual(decision.approvedAmount, Decimal(4_900))
        XCTAssertNil(decision.reason)
    }

    func testAgentWalletAuthorizationReturnsPolicyDeniedResultWithExplicitLimitReason() async throws {
        let wallet = try StaticAgentWallet(
            identity: sampleAgentWalletIdentity(),
            capabilities: [
                .authorizeExecution,
                .reportDelegatedSpendingLimit,
                .validatePolicy
            ],
            spendingLimit: sampleDelegatedSpendingLimit(),
            anchorSigningKey: nil,
            delegatedPolicy: sampleDelegatedSpendingPolicy()
        )
        let executionRequest = try sampleAgentWalletExecutionRequest(
            kind: .payment,
            amount: Decimal(5_001),
            nonce: "nonce-wallet-policy-auth-denied"
        )
        let decision = try wallet.authorizeExecution(
            executionRequest,
            decidedAt: "2026-05-31T00:00:00Z"
        )
        let paymentRequest = try MeshPaymentExecutionRequest(
            paymentId: "pay-ios-grocery-policy-denied-001",
            authorizationDecision: decision,
            requestAnchor: sampleRequestAnchor(
                metadata: executionRequest.requestAnchorMetadata,
                status: .confirmed
            ),
            requestedAt: "2026-05-31T00:00:01Z"
        )
        let executor = try StaticPaymentExecutor(
            identity: try sampleChainProviderIdentity(),
            capabilities: [.executePayment],
            status: .confirmed,
            transactionHash: "0xshouldnotbeused",
            lookupRequest: nil
        )

        let result = try await executor.executePayment(
            paymentRequest,
            submittedAt: "2026-05-31T00:00:02Z"
        )

        XCTAssertEqual(decision.status, .denied)
        XCTAssertNil(decision.approvedAmount)
        XCTAssertEqual(decision.reason, "policy-single-payment-max-exceeded")
        XCTAssertEqual(result.status, .policyDenied)
        XCTAssertNil(result.transactionHash)
        XCTAssertNil(result.explorerURL)
        XCTAssertEqual(result.message, "policy-single-payment-max-exceeded")
    }

    func testAgentWalletAuthorizationApprovesProviderNeutralPaymentExecutionWithinDelegatedLimit() throws {
        let wallet = try StaticAgentWallet(
            identity: sampleAgentWalletIdentity(),
            capabilities: [
                .authorizeExecution,
                .reportDelegatedSpendingLimit,
                .validatePolicy
            ],
            spendingLimit: sampleDelegatedSpendingLimit(),
            anchorSigningKey: nil
        )
        let executionRequest = try sampleAgentWalletExecutionRequest(
            kind: .payment,
            amount: Decimal(4_900),
            nonce: "nonce-wallet-payment-auth"
        )

        let decision = try wallet.authorizeExecution(
            executionRequest,
            decidedAt: "2026-05-31T00:00:00Z"
        )

        XCTAssertEqual(decision.authorizationId, "auth-exec-ios-grocery-test-001")
        XCTAssertEqual(decision.walletIdentity.providerMetadata.provider, "maroo")
        XCTAssertEqual(decision.executionRequest.kind, .payment)
        XCTAssertEqual(decision.executionRequest.requestAnchorMetadata.requestId, "ios-grocery-test-001")
        XCTAssertEqual(decision.executionRequest.requestAnchorMetadata.nonce, "nonce-wallet-payment-auth")
        XCTAssertEqual(decision.executionRequest.amount, Decimal(4_900))
        XCTAssertEqual(decision.executionRequest.currencyCode, "KRW")
        XCTAssertEqual(decision.executionRequest.tokenSymbol, "OKRW")
        XCTAssertEqual(decision.executionRequest.recipientAddress, "maroo1dailyMartMerchant")
        XCTAssertEqual(decision.status, .approved)
        XCTAssertEqual(decision.approvedAmount, Decimal(4_900))
        XCTAssertNil(decision.reason)
    }

    func testAgentWalletAuthorizationDeniesProviderNeutralTransferExecutionAboveDelegatedLimit() throws {
        let wallet = try StaticAgentWallet(
            identity: sampleAgentWalletIdentity(),
            capabilities: [
                .authorizeExecution,
                .reportDelegatedSpendingLimit,
                .validatePolicy
            ],
            spendingLimit: sampleDelegatedSpendingLimit(),
            anchorSigningKey: nil
        )
        let executionRequest = try sampleAgentWalletExecutionRequest(
            kind: .transfer,
            amount: Decimal(10_001),
            nonce: "nonce-wallet-transfer-denied"
        )

        let decision = try wallet.authorizeExecution(
            executionRequest,
            decidedAt: "2026-05-31T00:00:00Z"
        )

        XCTAssertEqual(decision.executionRequest.kind, .transfer)
        XCTAssertEqual(decision.executionRequest.amount, Decimal(10_001))
        XCTAssertEqual(decision.status, .denied)
        XCTAssertNil(decision.approvedAmount)
        XCTAssertEqual(decision.reason, "delegated-limit-exceeded")
    }

    func testAgentWalletAuthorizationRequiresCapabilityAndValidDecisionShape() throws {
        let wallet = try StaticAgentWallet(
            identity: sampleAgentWalletIdentity(),
            capabilities: [.reportDelegatedSpendingLimit],
            spendingLimit: sampleDelegatedSpendingLimit(),
            anchorSigningKey: nil
        )
        let executionRequest = try sampleAgentWalletExecutionRequest(
            kind: .payment,
            amount: Decimal(100),
            nonce: "nonce-wallet-auth-requires-capability"
        )

        XCTAssertThrowsError(try wallet.authorizeExecution(
            executionRequest,
            decidedAt: "2026-05-31T00:00:00Z"
        )) { error in
            XCTAssertEqual(error as? MeshKitValidationError, .unsupportedCapability)
        }

        XCTAssertThrowsError(try MeshAgentWalletAuthorizationDecision(
            authorizationId: "auth-invalid-denial",
            walletIdentity: sampleAgentWalletIdentity(),
            executionRequest: executionRequest,
            status: .denied,
            approvedAmount: Decimal(100),
            reason: "policy-denied",
            decidedAt: "2026-05-31T00:00:00Z"
        )) { error in
            XCTAssertEqual(error as? MeshKitValidationError, .invalidAgentWalletIdentity("approvedAmount"))
        }

        XCTAssertThrowsError(try MeshAgentWalletExecutionRequest(
            executionId: "exec-invalid",
            kind: .payment,
            requestAnchorMetadata: MeshSignedRequestAnchorMetadata(
                request: dailyMartRequest(nonce: "nonce-wallet-auth-invalid")
            ),
            scope: sampleDelegatedSpendingScope(),
            amount: Decimal(100),
            recipientAddress: "maroo1dailyMartMerchant",
            policyId: "policy-hermes-dailymart-okrw-v1",
            policyHash: MeshPayloadHash(value: String(repeating: "f", count: 64))
        )) { error in
            XCTAssertEqual(error as? MeshKitValidationError, .invalidAgentWalletIdentity("currencyCode"))
        }
    }

    func testPaymentExecutorConfigurationDiscoversMinimumProviderNeutralCapabilities() throws {
        let executor = try StaticPaymentExecutor(
            identity: try sampleChainProviderIdentity(),
            capabilities: [.executePayment, .lookupExecutionStatus, .executePayment],
            status: .pending,
            transactionHash: nil,
            lookupRequest: nil
        )

        let configuration = try executor.loadPaymentExecutorConfiguration()

        XCTAssertEqual(configuration.identity.provider, "maroo")
        XCTAssertEqual(configuration.identity.network, "maroo-testnet")
        XCTAssertEqual(configuration.capabilities, [.executePayment, .lookupExecutionStatus])
        XCTAssertTrue(configuration.supports(.executePayment))
        XCTAssertFalse(configuration.supports(.executeTransfer))
        XCTAssertThrowsError(try configuration.require(.executeTransfer)) { error in
            XCTAssertEqual(error as? MeshKitValidationError, .unsupportedCapability)
        }
    }

    func testPaymentExecutorMapsProviderTransportFailuresToProviderNeutralCapabilityErrors() async throws {
        let paymentRequest = try samplePaymentExecutionRequest(
            kind: .payment,
            amount: Decimal(4_900),
            nonce: "nonce-payment-transport-failure",
            authorizationStatus: .approved
        )
        let executor = FailingPaymentExecutor(
            identity: try sampleChainProviderIdentity(),
            capabilities: [.executePayment, .lookupExecutionStatus],
            executionError: ProviderSpecificPaymentFailure(
                paymentExecutorFailureKind: .transport,
                providerFailureCode: "MAROO_HTTP_BAD_RESPONSE",
                providerFailureMessage: "maroo testnet transport returned malformed response"
            ),
            statusError: MeshKitValidationError.invalidPaymentExecution("unused")
        )

        do {
            _ = try await executor.executePaymentWithProviderNeutralErrors(
                paymentRequest,
                submittedAt: "2026-05-31T00:01:00Z"
            )
            XCTFail("Expected provider transport failure to map to capability error")
        } catch {
            let capabilityError = try XCTUnwrap(error as? MeshPaymentExecutorCapabilityError)
            XCTAssertEqual(capabilityError.capability, .executePayment)
            XCTAssertEqual(capabilityError.failureKind, .transport)
            XCTAssertEqual(capabilityError.code, "maroo_http_bad_response")
            XCTAssertEqual(capabilityError.message, "maroo testnet transport returned malformed response")

            let data = try JSONEncoder().encode(capabilityError)
            let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
            XCTAssertEqual(object["capability"] as? String, "executePayment")
            XCTAssertEqual(object["failureKind"] as? String, "transport")
            XCTAssertEqual(object["code"] as? String, "maroo_http_bad_response")
            XCTAssertNil(object["marooError"])
        }
    }

    func testPaymentExecutorMapsProviderRPCFailuresToLookupCapabilityErrors() async throws {
        let paymentRequest = try samplePaymentExecutionRequest(
            kind: .payment,
            amount: Decimal(4_900),
            nonce: "nonce-payment-rpc-failure",
            authorizationStatus: .approved
        )
        let executor = FailingPaymentExecutor(
            identity: try sampleChainProviderIdentity(),
            capabilities: [.executePayment, .lookupExecutionStatus],
            executionError: MeshKitValidationError.invalidPaymentExecution("unused"),
            statusError: ProviderSpecificPaymentFailure(
                paymentExecutorFailureKind: .rpc,
                providerFailureCode: "JSON_RPC_-32000",
                providerFailureMessage: "maroo rpc rejected payment status lookup"
            )
        )

        do {
            _ = try await executor.paymentExecutionStatusWithProviderNeutralErrors(
                paymentId: paymentRequest.paymentId,
                checkedAt: "2026-05-31T00:01:01Z"
            )
            XCTFail("Expected provider RPC failure to map to lookup capability error")
        } catch {
            let capabilityError = try XCTUnwrap(error as? MeshPaymentExecutorCapabilityError)
            XCTAssertEqual(capabilityError.capability, .lookupExecutionStatus)
            XCTAssertEqual(capabilityError.failureKind, .rpc)
            XCTAssertEqual(capabilityError.code, "json_rpc_-32000")
            XCTAssertEqual(capabilityError.message, "maroo rpc rejected payment status lookup")
        }
    }

    func testPaymentExecutorMapsChainOriginatedExecutionErrorsToStableCapabilityErrors() async throws {
        let paymentRequest = try samplePaymentExecutionRequest(
            kind: .payment,
            amount: Decimal(4_900),
            nonce: "nonce-payment-chain-originated-error",
            authorizationStatus: .approved
        )
        let executor = FailingPaymentExecutor(
            identity: try sampleChainProviderIdentity(),
            capabilities: [.executePayment],
            executionError: try MeshPaymentExecutorChainError(
                failureKind: .rpc,
                code: "JSON-RPC -32003: execution reverted",
                message: "OKRW contract reverted delegated payment"
            ),
            statusError: MeshKitValidationError.invalidPaymentExecution("unused")
        )

        do {
            _ = try await executor.executePaymentWithProviderNeutralErrors(
                paymentRequest,
                submittedAt: "2026-05-31T00:01:01Z"
            )
            XCTFail("Expected chain-originated execution error to map to capability error")
        } catch {
            let capabilityError = try XCTUnwrap(error as? MeshPaymentExecutorCapabilityError)
            XCTAssertEqual(capabilityError.capability, .executePayment)
            XCTAssertEqual(capabilityError.failureKind, .rpc)
            XCTAssertEqual(capabilityError.code, "json-rpc_-32003_execution_reverted")
            XCTAssertEqual(capabilityError.message, "OKRW contract reverted delegated payment")
        }
    }

    func testPaymentExecutorMapsNetworkFailuresToTransferCapabilityErrors() async throws {
        let transferRequest = try samplePaymentExecutionRequest(
            kind: .transfer,
            amount: Decimal(3_200),
            nonce: "nonce-payment-network-failure",
            authorizationStatus: .approved
        )
        let executor = FailingPaymentExecutor(
            identity: try sampleChainProviderIdentity(),
            capabilities: [.executeTransfer],
            executionError: URLError(.notConnectedToInternet),
            statusError: MeshKitValidationError.invalidPaymentExecution("unused")
        )

        do {
            _ = try await executor.executePaymentWithProviderNeutralErrors(
                transferRequest,
                submittedAt: "2026-05-31T00:01:02Z"
            )
            XCTFail("Expected URL network failure to map to transfer capability error")
        } catch {
            let capabilityError = try XCTUnwrap(error as? MeshPaymentExecutorCapabilityError)
            XCTAssertEqual(capabilityError.capability, .executeTransfer)
            XCTAssertEqual(capabilityError.failureKind, .network)
            XCTAssertEqual(capabilityError.code, "url_error_-1009")
            XCTAssertEqual(capabilityError.message, "provider network failure")
        }
    }

    func testPaymentExecutorMapsProviderTransferFailuresToTransferCapabilityErrors() async throws {
        let transferRequest = try samplePaymentExecutionRequest(
            kind: .transfer,
            amount: Decimal(3_200),
            nonce: "nonce-provider-transfer-failure",
            authorizationStatus: .approved
        )
        let executor = FailingPaymentExecutor(
            identity: try sampleChainProviderIdentity(),
            capabilities: [.executeTransfer],
            executionError: ProviderSpecificPaymentFailure(
                paymentExecutorFailureKind: .rpc,
                providerFailureCode: "MAROO_TRANSFER_REVERTED",
                providerFailureMessage: "maroo transfer execution reverted"
            ),
            statusError: MeshKitValidationError.invalidPaymentExecution("unused")
        )

        do {
            _ = try await executor.executePaymentWithProviderNeutralErrors(
                transferRequest,
                submittedAt: "2026-05-31T00:01:03Z"
            )
            XCTFail("Expected provider transfer failure to map to transfer capability error")
        } catch {
            let capabilityError = try XCTUnwrap(error as? MeshPaymentExecutorCapabilityError)
            XCTAssertEqual(capabilityError.capability, .executeTransfer)
            XCTAssertEqual(capabilityError.failureKind, .rpc)
            XCTAssertEqual(capabilityError.code, "maroo_transfer_reverted")
            XCTAssertEqual(capabilityError.message, "maroo transfer execution reverted")
        }
    }

    func testPaymentExecutorMapsProviderPolicyDenialsToProviderNeutralCapabilityErrors() async throws {
        let paymentRequest = try samplePaymentExecutionRequest(
            kind: .payment,
            amount: Decimal(5_001),
            nonce: "nonce-provider-policy-denial",
            authorizationStatus: .approved
        )
        let executor = FailingPaymentExecutor(
            identity: try sampleChainProviderIdentity(),
            capabilities: [.executePayment],
            executionError: ProviderSpecificPaymentFailure(
                paymentExecutorFailureKind: .policyDenied,
                providerFailureCode: "WALLET_POLICY_DENIED",
                providerFailureMessage: "policy-single-payment-max-exceeded"
            ),
            statusError: MeshKitValidationError.invalidPaymentExecution("unused")
        )

        do {
            _ = try await executor.executePaymentWithProviderNeutralErrors(
                paymentRequest,
                submittedAt: "2026-05-31T00:01:04Z"
            )
            XCTFail("Expected provider policy denial to map to payment capability error")
        } catch {
            let capabilityError = try XCTUnwrap(error as? MeshPaymentExecutorCapabilityError)
            XCTAssertEqual(capabilityError.capability, .executePayment)
            XCTAssertEqual(capabilityError.failureKind, .policyDenied)
            XCTAssertEqual(capabilityError.code, "wallet_policy_denied")
            XCTAssertEqual(capabilityError.message, "policy-single-payment-max-exceeded")

            let data = try JSONEncoder().encode(capabilityError)
            let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
            XCTAssertEqual(object["capability"] as? String, "executePayment")
            XCTAssertEqual(object["failureKind"] as? String, "policyDenied")
            XCTAssertEqual(object["code"] as? String, "wallet_policy_denied")
        }
    }

    func testPaymentExecutorMapsDelegatedSpendingPolicyValidationDenialsToCapabilityErrors() async throws {
        let scenarios: [
            (
                kind: MeshAgentWalletExecutionKind,
                policyError: MeshKitValidationError,
                expectedCapability: MeshPaymentExecutorCapability,
                expectedCode: String
            )
        ] = [
            (.payment, .invalidAgentWalletIdentity("singlePaymentMax"), .executePayment, "policy-single-payment-max-exceeded"),
            (.payment, .invalidAgentWalletIdentity("remainingLimit"), .executePayment, "policy-remaining-limit-exceeded"),
            (.transfer, .invalidAgentWalletIdentity("capabilityScope"), .executeTransfer, "policy-capability-scope-mismatch"),
            (.transfer, .invalidAgentWalletIdentity("consentGrantId"), .executeTransfer, "policy-consent-grant-mismatch")
        ]

        for scenario in scenarios {
            let request = try samplePaymentExecutionRequest(
                kind: scenario.kind,
                amount: Decimal(5_001),
                nonce: "nonce-policy-validation-\(scenario.expectedCode)-\(scenario.kind.rawValue)",
                authorizationStatus: .approved
            )
            let executor = FailingPaymentExecutor(
                identity: try sampleChainProviderIdentity(),
                capabilities: [scenario.expectedCapability],
                executionError: scenario.policyError,
                statusError: MeshKitValidationError.invalidPaymentExecution("unused")
            )

            do {
                _ = try await executor.executePaymentWithProviderNeutralErrors(
                    request,
                    submittedAt: "2026-05-31T00:01:05Z"
                )
                XCTFail("Expected delegated spending policy denial to map to capability error")
            } catch {
                let capabilityError = try XCTUnwrap(error as? MeshPaymentExecutorCapabilityError)
                XCTAssertEqual(capabilityError.capability, scenario.expectedCapability)
                XCTAssertEqual(capabilityError.failureKind, .policyDenied)
                XCTAssertEqual(capabilityError.code, scenario.expectedCode)
                XCTAssertEqual(capabilityError.message, scenario.expectedCode)
            }
        }
    }

    func testPaymentExecutorMapsURLTransportFailuresToProviderNeutralCapabilityErrors() throws {
        let executor = FailingPaymentExecutor(
            identity: try sampleChainProviderIdentity(),
            capabilities: [.executePayment],
            executionError: URLError(.badServerResponse),
            statusError: MeshKitValidationError.invalidPaymentExecution("unused")
        )

        let capabilityError = try executor.providerNeutralCapabilityError(
            for: URLError(.badServerResponse),
            capability: .executePayment
        )

        XCTAssertEqual(capabilityError.capability, .executePayment)
        XCTAssertEqual(capabilityError.failureKind, .transport)
        XCTAssertEqual(capabilityError.code, "url_error_-1011")
        XCTAssertEqual(capabilityError.message, "provider transport failure")
    }

    func testPaymentExecutorMapsUnknownExecutionErrorsToStableFallbackCapabilityError() async throws {
        let transferRequest = try samplePaymentExecutionRequest(
            kind: .transfer,
            amount: Decimal(3_200),
            nonce: "nonce-payment-unknown-execution-error",
            authorizationStatus: .approved
        )
        let executor = FailingPaymentExecutor(
            identity: try sampleChainProviderIdentity(),
            capabilities: [.executeTransfer],
            executionError: UnknownPaymentExecutionFailure(),
            statusError: MeshKitValidationError.invalidPaymentExecution("unused")
        )

        do {
            _ = try await executor.executePaymentWithProviderNeutralErrors(
                transferRequest,
                submittedAt: "2026-05-31T00:01:06Z"
            )
            XCTFail("Expected unknown execution error to map to fallback capability error")
        } catch {
            let capabilityError = try XCTUnwrap(error as? MeshPaymentExecutorCapabilityError)
            XCTAssertEqual(capabilityError.capability, .executeTransfer)
            XCTAssertEqual(capabilityError.failureKind, .rpc)
            XCTAssertEqual(capabilityError.code, MeshPaymentExecutorCapabilityError.fallbackExecutionErrorCode)
            XCTAssertEqual(capabilityError.message, MeshPaymentExecutorCapabilityError.fallbackExecutionErrorMessage)
        }
    }

    func testPaymentExecutorMapsMalformedProviderExecutionErrorsToStableFallbackCapabilityError() async throws {
        let paymentRequest = try samplePaymentExecutionRequest(
            kind: .payment,
            amount: Decimal(4_900),
            nonce: "nonce-payment-malformed-provider-error",
            authorizationStatus: .approved
        )
        let executor = FailingPaymentExecutor(
            identity: try sampleChainProviderIdentity(),
            capabilities: [.executePayment],
            executionError: ProviderSpecificPaymentFailure(
                paymentExecutorFailureKind: .rpc,
                providerFailureCode: "\n",
                providerFailureMessage: ""
            ),
            statusError: MeshKitValidationError.invalidPaymentExecution("unused")
        )

        do {
            _ = try await executor.executePaymentWithProviderNeutralErrors(
                paymentRequest,
                submittedAt: "2026-05-31T00:01:07Z"
            )
            XCTFail("Expected malformed provider execution error to map to fallback capability error")
        } catch {
            let capabilityError = try XCTUnwrap(error as? MeshPaymentExecutorCapabilityError)
            XCTAssertEqual(capabilityError.capability, .executePayment)
            XCTAssertEqual(capabilityError.failureKind, .rpc)
            XCTAssertEqual(capabilityError.code, MeshPaymentExecutorCapabilityError.fallbackExecutionErrorCode)
            XCTAssertEqual(capabilityError.message, MeshPaymentExecutorCapabilityError.fallbackExecutionErrorMessage)
        }
    }

    func testPaymentExecutionRequestBindsAuthorizationToSignedRequestAnchor() throws {
        let executionRequest = try sampleAgentWalletExecutionRequest(
            kind: .payment,
            amount: Decimal(4_900),
            nonce: "nonce-payment-execution-request"
        )
        let decision = try MeshAgentWalletAuthorizationDecision(
            authorizationId: "auth-payment-execution-request",
            walletIdentity: sampleAgentWalletIdentity(),
            executionRequest: executionRequest,
            status: .approved,
            approvedAmount: Decimal(4_900),
            decidedAt: "2026-05-31T00:00:00Z"
        )
        let anchor = try sampleRequestAnchor(
            metadata: executionRequest.requestAnchorMetadata,
            status: .confirmed
        )

        let paymentRequest = try MeshPaymentExecutionRequest(
            paymentId: "pay-ios-grocery-test-001",
            authorizationDecision: decision,
            requestAnchor: anchor,
            requestedAt: "2026-05-31T00:00:01Z"
        )

        XCTAssertEqual(paymentRequest.paymentId, "pay-ios-grocery-test-001")
        XCTAssertEqual(paymentRequest.authorizationDecision.authorizationId, "auth-payment-execution-request")
        XCTAssertEqual(paymentRequest.executionRequest.kind, .payment)
        XCTAssertEqual(paymentRequest.executionRequest.tokenSymbol, "OKRW")
        XCTAssertEqual(paymentRequest.requestAnchor.metadata.nonce, "nonce-payment-execution-request")
        XCTAssertEqual(paymentRequest.requestAnchor.identifier.identity.provider, "maroo")
        XCTAssertEqual(paymentRequest.asset, "OKRW")
        XCTAssertEqual(paymentRequest.amount, Decimal(4_900))
        XCTAssertEqual(paymentRequest.recipient, "maroo1dailyMartMerchant")
        XCTAssertEqual(paymentRequest.requestHash, executionRequest.requestAnchorMetadata.signedRequestHash)

        let data = try JSONEncoder().encode(paymentRequest)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(object["asset"] as? String, "OKRW")
        XCTAssertEqual(object["amount"] as? Int, 4_900)
        XCTAssertEqual(object["recipient"] as? String, "maroo1dailyMartMerchant")
        XCTAssertEqual((object["requestHash"] as? [String: Any])?["algorithm"] as? String, "sha256")
        XCTAssertEqual((object["requestHash"] as? [String: Any])?["value"] as? String, executionRequest.requestAnchorMetadata.signedRequestHash.value)

        let decoded = try JSONDecoder().decode(MeshPaymentExecutionRequest.self, from: data)
        XCTAssertEqual(decoded, paymentRequest)
    }

    func testPaymentExecutionIntentExposesProviderNeutralContractFields() throws {
        let paymentRequest = try samplePaymentExecutionRequest(
            kind: .payment,
            amount: Decimal(4_900),
            nonce: "nonce-payment-intent-provider-neutral",
            authorizationStatus: .approved
        )

        let intent = try paymentRequest.executionIntent

        XCTAssertEqual(intent.kind, .payment)
        XCTAssertEqual(intent.asset, "OKRW")
        XCTAssertEqual(intent.amount, Decimal(4_900))
        XCTAssertEqual(intent.recipient, "maroo1dailyMartMerchant")
        XCTAssertEqual(intent.requestHash, paymentRequest.requestHash)
        XCTAssertEqual(intent.requestNonce, "nonce-payment-intent-provider-neutral")
        XCTAssertEqual(intent.anchoringReference, paymentRequest.requestAnchor.identifier)
        XCTAssertEqual(intent.policyId, paymentRequest.executionRequest.policyId)
        XCTAssertEqual(intent.policyHash, paymentRequest.executionRequest.policyHash)
        XCTAssertEqual(intent.paymentId, paymentRequest.paymentId)

        let data = try JSONEncoder().encode(intent)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(object["kind"] as? String, "payment")
        XCTAssertEqual(object["asset"] as? String, "OKRW")
        XCTAssertEqual(object["amount"] as? Int, 4_900)
        XCTAssertEqual(object["recipient"] as? String, "maroo1dailyMartMerchant")
        XCTAssertEqual(object["requestNonce"] as? String, "nonce-payment-intent-provider-neutral")
        XCTAssertEqual(object["policyId"] as? String, "policy-hermes-dailymart-okrw-v1")
        XCTAssertNil(object["provider"])
        XCTAssertNil(object["network"])
        XCTAssertNil(object["maroo"])

        let decoded = try JSONDecoder().decode(MeshPaymentExecutionIntent.self, from: data)
        XCTAssertEqual(decoded, intent)
    }

    func testPaymentExecutorCapabilityInputExposesProviderNeutralExecutionFields() throws {
        let paymentRequest = try samplePaymentExecutionRequest(
            kind: .payment,
            amount: Decimal(4_900),
            nonce: "nonce-payment-capability-input",
            authorizationStatus: .approved
        )

        let input = try MeshPaymentExecutorCapabilityInput(paymentRequest: paymentRequest)

        XCTAssertEqual(input.capability, .executePayment)
        XCTAssertEqual(input.asset, "OKRW")
        XCTAssertEqual(input.amount, Decimal(4_900))
        XCTAssertEqual(input.recipient, "maroo1dailyMartMerchant")
        XCTAssertEqual(input.requestHash, paymentRequest.requestHash)
        XCTAssertTrue(input.requestHashLinkage)

        let data = try JSONEncoder().encode(input)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(object["capability"] as? String, "executePayment")
        XCTAssertEqual(object["asset"] as? String, "OKRW")
        XCTAssertEqual(object["amount"] as? Int, 4_900)
        XCTAssertEqual(object["recipient"] as? String, "maroo1dailyMartMerchant")
        XCTAssertEqual((object["requestHash"] as? [String: Any])?["algorithm"] as? String, "sha256")
        XCTAssertEqual((object["requestHash"] as? [String: Any])?["value"] as? String, paymentRequest.requestHash.value)
        XCTAssertEqual(object["requestHashLinkage"] as? Bool, true)
        XCTAssertNil(object["provider"])
        XCTAssertNil(object["network"])
        XCTAssertNil(object["maroo"])

        let decoded = try JSONDecoder().decode(MeshPaymentExecutorCapabilityInput.self, from: data)
        XCTAssertEqual(decoded, input)
    }

    func testPaymentExecutorCapabilityInputValidatesRequiredExecutionFields() throws {
        let validHash = MeshPayloadHash(value: String(repeating: "a", count: 64))

        XCTAssertThrowsError(try MeshPaymentExecutorCapabilityInput(
            capability: .executePayment,
            asset: "",
            amount: Decimal(1),
            recipient: "merchant1recipient",
            requestHash: validHash
        )) { error in
            XCTAssertEqual(error as? MeshKitValidationError, .invalidPaymentExecution("asset"))
        }

        XCTAssertThrowsError(try MeshPaymentExecutorCapabilityInput(
            capability: .executePayment,
            asset: "OKRW",
            amount: Decimal(0),
            recipient: "merchant1recipient",
            requestHash: validHash
        )) { error in
            XCTAssertEqual(error as? MeshKitValidationError, .invalidPaymentExecution("amount"))
        }

        XCTAssertThrowsError(try MeshPaymentExecutorCapabilityInput(
            capability: .executePayment,
            asset: "OKRW",
            amount: Decimal(1),
            recipient: " merchant1recipient ",
            requestHash: validHash
        )) { error in
            XCTAssertEqual(error as? MeshKitValidationError, .invalidPaymentExecution("recipient"))
        }

        XCTAssertThrowsError(try MeshPaymentExecutorCapabilityInput(
            capability: .executePayment,
            asset: "OKRW",
            amount: Decimal(1),
            recipient: "merchant1recipient",
            requestHash: MeshPayloadHash(value: String(repeating: "z", count: 64))
        )) { error in
            XCTAssertEqual(error as? MeshKitValidationError, .invalidPaymentExecution("requestHash.value"))
        }

        XCTAssertThrowsError(try MeshPaymentExecutorCapabilityInput(
            capability: .executePayment,
            asset: "OKRW",
            amount: Decimal(1),
            recipient: "merchant1recipient",
            requestHash: validHash,
            requestHashLinkage: false
        )) { error in
            XCTAssertEqual(error as? MeshKitValidationError, .invalidPaymentExecution("requestHashLinkage"))
        }
    }

    func testOKRWPaymentAndTransferIntentWrappersBindAssetAndExecutionKind() throws {
        let paymentRequest = try samplePaymentExecutionRequest(
            kind: .payment,
            amount: Decimal(4_900),
            nonce: "nonce-okrw-payment-intent",
            authorizationStatus: .approved
        )
        let transferRequest = try samplePaymentExecutionRequest(
            kind: .transfer,
            amount: Decimal(1_200),
            nonce: "nonce-okrw-transfer-intent",
            authorizationStatus: .approved
        )

        let paymentIntent = try MeshOKRWPaymentIntent(paymentRequest: paymentRequest)
        let transferIntent = try MeshOKRWTransferIntent(paymentRequest: transferRequest)

        XCTAssertEqual(paymentIntent.executionIntent.kind, .payment)
        XCTAssertEqual(paymentIntent.executionIntent.asset, "OKRW")
        XCTAssertEqual(paymentIntent.executionIntent.requestHash, paymentRequest.requestHash)
        XCTAssertEqual(transferIntent.executionIntent.kind, .transfer)
        XCTAssertEqual(transferIntent.executionIntent.asset, "OKRW")
        XCTAssertEqual(transferIntent.executionIntent.requestHash, transferRequest.requestHash)

        XCTAssertThrowsError(try MeshOKRWPaymentIntent(paymentRequest: transferRequest)) { error in
            XCTAssertEqual(error as? MeshKitValidationError, .invalidPaymentExecution("kind"))
        }
        XCTAssertThrowsError(try MeshOKRWTransferIntent(paymentRequest: paymentRequest)) { error in
            XCTAssertEqual(error as? MeshKitValidationError, .invalidPaymentExecution("kind"))
        }

        let usdcIntent = try MeshPaymentExecutionIntent(
            kind: .payment,
            asset: "USDC",
            amount: Decimal(10),
            recipient: "maroo1dailyMartMerchant",
            requestHash: paymentRequest.requestHash,
            requestNonce: paymentRequest.executionRequest.requestAnchorMetadata.nonce,
            anchoringReference: paymentRequest.requestAnchor.identifier,
            policyId: paymentRequest.executionRequest.policyId,
            policyHash: paymentRequest.executionRequest.policyHash,
            paymentId: paymentRequest.paymentId
        )
        XCTAssertThrowsError(try MeshOKRWPaymentIntent(executionIntent: usdcIntent)) { error in
            XCTAssertEqual(error as? MeshKitValidationError, .invalidPaymentExecution("asset"))
        }

        let encodedTransfer = try JSONEncoder().encode(transferIntent)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: encodedTransfer) as? [String: Any])
        let executionIntent = try XCTUnwrap(object["executionIntent"] as? [String: Any])
        XCTAssertEqual(executionIntent["kind"] as? String, "transfer")
        XCTAssertEqual(executionIntent["asset"] as? String, "OKRW")
        XCTAssertEqual(executionIntent["requestNonce"] as? String, "nonce-okrw-transfer-intent")
    }

    func testPaymentExecutorDispatchesOKRWPaymentAndTransferIntentsWithoutProviderSpecificCoupling() async throws {
        let neutralIdentity = try MeshChainProviderIdentity(
            providerName: "demo-chain",
            networkIdentity: "demo-testnet",
            chainId: "demo-testnet-1",
            rpcEndpoint: try XCTUnwrap(URL(string: "https://rpc.demo-chain.example.invalid")),
            explorerBaseURL: try XCTUnwrap(URL(string: "https://explorer.demo-chain.example.invalid"))
        )
        let executor = RecordingPaymentExecutor(
            identity: neutralIdentity,
            capabilities: [.executePayment, .executeTransfer]
        )
        let paymentRequest = try samplePaymentExecutionRequest(
            kind: .payment,
            amount: Decimal(4_900),
            nonce: "nonce-okrw-intent-dispatch-payment",
            authorizationStatus: .approved
        )
        let transferRequest = try samplePaymentExecutionRequest(
            kind: .transfer,
            amount: Decimal(1_200),
            nonce: "nonce-okrw-intent-dispatch-transfer",
            authorizationStatus: .approved
        )

        let paymentResult = try await executor.executeOKRWPaymentIntent(
            MeshOKRWPaymentIntent(paymentRequest: paymentRequest),
            request: paymentRequest,
            submittedAt: "2026-05-31T00:02:00Z"
        )
        let transferResult = try await executor.executeOKRWTransferIntent(
            MeshOKRWTransferIntent(paymentRequest: transferRequest),
            request: transferRequest,
            submittedAt: "2026-05-31T00:02:01Z"
        )

        XCTAssertEqual(executor.executionCallCount, 2)
        XCTAssertEqual(executor.executedRequests.map(\.executionRequest.kind), [.payment, .transfer])
        XCTAssertEqual(paymentResult.identity.provider, "demo-chain")
        XCTAssertEqual(transferResult.identity.provider, "demo-chain")
        XCTAssertEqual(paymentResult.kind, .payment)
        XCTAssertEqual(transferResult.kind, .transfer)
        XCTAssertEqual(paymentResult.tokenSymbol, "OKRW")
        XCTAssertEqual(transferResult.tokenSymbol, "OKRW")
        XCTAssertNil(paymentResult.providerExtensions["maroo"])
        XCTAssertNil(transferResult.providerExtensions["maroo"])
    }

    func testOKRWIntentDispatchRejectsMismatchedIntentBeforeExecutorBoundary() async throws {
        let executor = RecordingPaymentExecutor(
            identity: try sampleChainProviderIdentity(),
            capabilities: [.executePayment, .executeTransfer]
        )
        let paymentRequest = try samplePaymentExecutionRequest(
            kind: .payment,
            amount: Decimal(4_900),
            nonce: "nonce-okrw-intent-dispatch-payment-source",
            authorizationStatus: .approved
        )
        let otherPaymentRequest = try samplePaymentExecutionRequest(
            kind: .payment,
            amount: Decimal(4_900),
            nonce: "nonce-okrw-intent-dispatch-payment-other",
            authorizationStatus: .approved
        )
        let staleIntent = try MeshOKRWPaymentIntent(paymentRequest: otherPaymentRequest)

        do {
            _ = try await executor.executeOKRWPaymentIntent(
                staleIntent,
                request: paymentRequest,
                submittedAt: "2026-05-31T00:02:02Z"
            )
            XCTFail("Expected mismatched OKRW intent to be rejected before provider execution")
        } catch {
            XCTAssertEqual(error as? MeshKitValidationError, .invalidPaymentExecution("executionIntent"))
        }

        XCTAssertEqual(executor.executionCallCount, 0)
    }

    func testPaymentExecutorExecutesApprovedOKRWPaymentWithProviderNeutralResultShape() async throws {
        let paymentRequest = try samplePaymentExecutionRequest(
            kind: .payment,
            amount: Decimal(4_900),
            nonce: "nonce-payment-confirmed",
            authorizationStatus: .approved
        )
        let executor = try StaticPaymentExecutor(
            identity: try sampleChainProviderIdentity(),
            capabilities: [.executePayment, .lookupExecutionStatus],
            status: .confirmed,
            transactionHash: "0xokrwpayment123",
            lookupRequest: paymentRequest
        )

        let result = try await executor.executePayment(
            paymentRequest,
            submittedAt: "2026-05-31T00:00:02Z"
        )
        let lookedUp = try await executor.paymentExecutionStatus(
            paymentId: paymentRequest.paymentId,
            checkedAt: "2026-05-31T00:00:03Z"
        )

        XCTAssertEqual(result.paymentId, "pay-ios-grocery-test-001")
        XCTAssertEqual(result.authorizationId, "auth-exec-ios-grocery-test-001")
        XCTAssertEqual(result.identity.provider, "maroo")
        XCTAssertEqual(result.kind, .payment)
        XCTAssertEqual(result.status, .confirmed)
        XCTAssertEqual(result.amount, Decimal(4_900))
        XCTAssertEqual(result.currencyCode, "KRW")
        XCTAssertEqual(result.tokenSymbol, "OKRW")
        XCTAssertEqual(result.recipientAddress, "maroo1dailyMartMerchant")
        XCTAssertEqual(result.requestAnchorIdentifier.anchorId, "anchor-ios-grocery-test-001")
        XCTAssertEqual(result.transactionHash, "0xokrwpayment123")
        XCTAssertEqual(result.txHash, "0xokrwpayment123")
        XCTAssertEqual(result.executionStatus, .confirmed)
        XCTAssertNil(result.errorPayload)
        XCTAssertEqual(result.explorerURL?.absoluteString, "https://explorer-testnet.example.invalid/tx/0xokrwpayment123")
        XCTAssertEqual(result.observedAt, "2026-05-31T00:00:02Z")
        XCTAssertEqual(lookedUp.status, .confirmed)
        XCTAssertEqual(lookedUp.observedAt, "2026-05-31T00:00:03Z")

        let data = try JSONEncoder().encode(result)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(object["paymentId"] as? String, "pay-ios-grocery-test-001")
        XCTAssertEqual(object["authorizationId"] as? String, "auth-exec-ios-grocery-test-001")
        XCTAssertEqual(object["kind"] as? String, "payment")
        XCTAssertEqual(object["status"] as? String, "confirmed")
        XCTAssertEqual(object["executionStatus"] as? String, "confirmed")
        XCTAssertEqual(object["tokenSymbol"] as? String, "OKRW")
        XCTAssertEqual(object["transactionHash"] as? String, "0xokrwpayment123")
        XCTAssertEqual(object["txHash"] as? String, "0xokrwpayment123")
        XCTAssertNil(object["errorPayload"])
        XCTAssertNil(object["marooReceipt"])

        let decoded = try JSONDecoder().decode(MeshPaymentExecutionResult.self, from: data)
        XCTAssertEqual(decoded, result)
    }

    func testDemoPaymentExecutorExecutesOKRWPaymentRequestsWithNormalizedExecutionStates() async throws {
        let scenarios: [(MeshPaymentExecutionStatus, String?, String?)] = [
            (.confirmed, "0xokrwconfirmed001", nil),
            (.pending, nil, nil),
            (.failed, nil, "maroo testnet rpc unavailable")
        ]

        for (status, transactionHash, message) in scenarios {
            let paymentRequest = try samplePaymentExecutionRequest(
                kind: .payment,
                amount: Decimal(4_900),
                nonce: "nonce-demo-okrw-\(status.rawValue)",
                authorizationStatus: .approved
            )
            let executor = try MeshDemoPaymentExecutor(
                identity: try sampleChainProviderIdentity(),
                capabilities: [.executePayment],
                executionStatus: status,
                transactionHash: transactionHash,
                message: message
            )

            let result = try await executor.executePayment(
                paymentRequest,
                submittedAt: "2026-05-31T00:00:10Z"
            )

            XCTAssertEqual(result.identity.provider, "maroo")
            XCTAssertEqual(result.identity.network, "maroo-testnet")
            XCTAssertEqual(result.kind, .payment)
            XCTAssertEqual(result.status, status)
            XCTAssertEqual(result.currencyCode, "KRW")
            XCTAssertEqual(result.tokenSymbol, "OKRW")
            XCTAssertEqual(result.amount, Decimal(4_900))
            XCTAssertEqual(result.recipientAddress, "maroo1dailyMartMerchant")
            XCTAssertEqual(result.requestAnchorIdentifier.anchorId, "anchor-ios-grocery-test-001")
            XCTAssertEqual(result.signedRequestHash, paymentRequest.executionRequest.requestAnchorMetadata.signedRequestHash)
            XCTAssertEqual(result.transactionHash, transactionHash)
            XCTAssertEqual(result.message, message ?? (status == .failed ? "demo payment execution failed" : nil))

            if let transactionHash {
                XCTAssertEqual(
                    result.explorerURL?.absoluteString,
                    "https://explorer-testnet.example.invalid/tx/\(transactionHash)"
                )
            } else {
                XCTAssertNil(result.explorerURL)
            }

            let encoded = try JSONEncoder().encode(result)
            let object = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
            XCTAssertEqual(object["status"] as? String, status.rawValue)
            XCTAssertEqual(object["executionStatus"] as? String, status.rawValue)
            XCTAssertEqual(object["kind"] as? String, "payment")
            XCTAssertEqual(object["tokenSymbol"] as? String, "OKRW")
            XCTAssertEqual(object["txHash"] as? String, transactionHash)
            if status == .failed {
                let errorPayload = try XCTUnwrap(object["errorPayload"] as? [String: Any])
                XCTAssertEqual(errorPayload["code"] as? String, "payment_execution_failed")
                XCTAssertEqual(errorPayload["message"] as? String, message)
            } else {
                XCTAssertNil(object["errorPayload"])
            }
            XCTAssertNil(object["marooReceipt"])
        }
    }

    func testPaymentExecutionResponseSchemaExposesStatusTxHashAndErrorPayload() async throws {
        let failedPaymentRequest = try samplePaymentExecutionRequest(
            kind: .payment,
            amount: Decimal(4_900),
            nonce: "nonce-payment-schema-failed",
            authorizationStatus: .approved
        )
        let failedExecutor = try MeshDemoPaymentExecutor(
            identity: try sampleChainProviderIdentity(),
            capabilities: [.executePayment],
            executionStatus: .failed,
            message: "maroo testnet rpc unavailable"
        )

        let failedResult = try await failedExecutor.executePayment(
            failedPaymentRequest,
            submittedAt: "2026-05-31T00:00:15Z"
        )
        XCTAssertEqual(failedResult.executionStatus, .failed)
        XCTAssertNil(failedResult.txHash)
        XCTAssertEqual(failedResult.errorPayload?.code, "payment_execution_failed")
        XCTAssertEqual(failedResult.errorPayload?.message, "maroo testnet rpc unavailable")

        let failedData = try JSONEncoder().encode(failedResult)
        var failedObject = try XCTUnwrap(JSONSerialization.jsonObject(with: failedData) as? [String: Any])
        XCTAssertEqual(failedObject["executionStatus"] as? String, "failed")
        XCTAssertNil(failedObject["txHash"])
        let failedPayload = try XCTUnwrap(failedObject["errorPayload"] as? [String: Any])
        XCTAssertEqual(failedPayload["code"] as? String, "payment_execution_failed")
        XCTAssertEqual(failedPayload["message"] as? String, "maroo testnet rpc unavailable")

        failedObject["executionStatus"] = "confirmed"
        let mismatchedStatusData = try JSONSerialization.data(withJSONObject: failedObject)
        XCTAssertThrowsError(try JSONDecoder().decode(MeshPaymentExecutionResult.self, from: mismatchedStatusData)) { error in
            XCTAssertEqual(error as? MeshKitValidationError, .invalidPaymentExecution("executionStatus"))
        }

        let confirmedPaymentRequest = try samplePaymentExecutionRequest(
            kind: .payment,
            amount: Decimal(4_900),
            nonce: "nonce-payment-schema-confirmed",
            authorizationStatus: .approved
        )
        let confirmedExecutor = try MeshDemoPaymentExecutor(
            identity: try sampleChainProviderIdentity(),
            capabilities: [.executePayment],
            executionStatus: .confirmed,
            transactionHash: "0xokrwschema001"
        )
        let confirmedResult = try await confirmedExecutor.executePayment(
            confirmedPaymentRequest,
            submittedAt: "2026-05-31T00:00:16Z"
        )
        XCTAssertEqual(confirmedResult.executionStatus, .confirmed)
        XCTAssertEqual(confirmedResult.txHash, "0xokrwschema001")
        XCTAssertNil(confirmedResult.errorPayload)

        let confirmedData = try JSONEncoder().encode(confirmedResult)
        var confirmedObject = try XCTUnwrap(JSONSerialization.jsonObject(with: confirmedData) as? [String: Any])
        XCTAssertEqual(confirmedObject["executionStatus"] as? String, "confirmed")
        XCTAssertEqual(confirmedObject["txHash"] as? String, "0xokrwschema001")
        XCTAssertNil(confirmedObject["errorPayload"])

        confirmedObject["txHash"] = "0xnot-the-transaction-hash"
        let mismatchedTxHashData = try JSONSerialization.data(withJSONObject: confirmedObject)
        XCTAssertThrowsError(try JSONDecoder().decode(MeshPaymentExecutionResult.self, from: mismatchedTxHashData)) { error in
            XCTAssertEqual(error as? MeshKitValidationError, .invalidPaymentExecution("txHash"))
        }
    }

    func testPaymentExecutionResultModelRecordsStatusAndTxHashForSuccessfulPendingAndFailedExecutions() throws {
        let scenarios: [
            (
                status: MeshPaymentExecutionStatus,
                transactionHash: String,
                message: String?
            )
        ] = [
            (.confirmed, "0xokrwmodelconfirmed001", nil),
            (.pending, "0xokrwmodelpending001", nil),
            (.failed, "0xokrwmodelfailed001", "maroo testnet rpc unavailable")
        ]

        for scenario in scenarios {
            let paymentRequest = try samplePaymentExecutionRequest(
                kind: .payment,
                amount: Decimal(4_900),
                nonce: "nonce-payment-result-model-\(scenario.status.rawValue)",
                authorizationStatus: .approved
            )

            let result = try MeshPaymentExecutionResult(
                request: paymentRequest,
                identity: try sampleChainProviderIdentity(),
                status: scenario.status,
                transactionHash: scenario.transactionHash,
                observedAt: "2026-05-31T00:00:17Z",
                message: scenario.message
            )

            XCTAssertEqual(result.status, scenario.status)
            XCTAssertEqual(result.executionStatus, scenario.status)
            XCTAssertEqual(result.transactionHash, scenario.transactionHash)
            XCTAssertEqual(result.txHash, scenario.transactionHash)
            XCTAssertEqual(
                result.explorerURL?.absoluteString,
                "https://explorer-testnet.example.invalid/tx/\(scenario.transactionHash)"
            )
            if scenario.status == .failed {
                XCTAssertEqual(result.errorPayload?.code, "payment_execution_failed")
                XCTAssertEqual(result.errorPayload?.message, scenario.message)
            } else {
                XCTAssertNil(result.errorPayload)
            }

            let data = try JSONEncoder().encode(result)
            let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
            XCTAssertEqual(object["status"] as? String, scenario.status.rawValue)
            XCTAssertEqual(object["executionStatus"] as? String, scenario.status.rawValue)
            XCTAssertEqual(object["transactionHash"] as? String, scenario.transactionHash)
            XCTAssertEqual(object["txHash"] as? String, scenario.transactionHash)

            let decoded = try JSONDecoder().decode(MeshPaymentExecutionResult.self, from: data)
            XCTAssertEqual(decoded.status, scenario.status)
            XCTAssertEqual(decoded.transactionHash, scenario.transactionHash)
            XCTAssertEqual(decoded.txHash, scenario.transactionHash)
        }
    }

    func testDemoPaymentExecutorNormalizesProviderOutcomesToExecutionStates() async throws {
        let scenarios: [
            (
                providerOutcome: MeshPaymentExecutionStatus,
                authorizationStatus: MeshAgentWalletAuthorizationStatus,
                expectedStatus: MeshPaymentExecutionStatus,
                transactionHash: String?,
                expectedMessage: String?
            )
        ] = [
            (.confirmed, .approved, .confirmed, "0xokrwconfirmedmapped001", nil),
            (.pending, .approved, .pending, nil, nil),
            (.failed, .approved, .failed, nil, "maroo testnet rpc unavailable"),
            (.confirmed, .denied, .policyDenied, "0xmustnotappear", "delegated-limit-exceeded")
        ]

        for scenario in scenarios {
            let paymentRequest = try samplePaymentExecutionRequest(
                kind: .payment,
                amount: scenario.authorizationStatus == .approved ? Decimal(4_900) : Decimal(10_001),
                nonce: "nonce-demo-provider-outcome-\(scenario.expectedStatus.rawValue)",
                authorizationStatus: scenario.authorizationStatus
            )
            let executor = try MeshDemoPaymentExecutor(
                identity: try sampleChainProviderIdentity(),
                capabilities: [.executePayment],
                executionStatus: scenario.providerOutcome,
                transactionHash: scenario.transactionHash,
                message: scenario.expectedMessage
            )

            let result = try await executor.executePayment(
                paymentRequest,
                submittedAt: "2026-05-31T00:00:14Z"
            )

            XCTAssertEqual(result.status, scenario.expectedStatus)
            XCTAssertEqual(result.kind, .payment)
            XCTAssertEqual(result.tokenSymbol, "OKRW")
            XCTAssertEqual(result.currencyCode, "KRW")
            XCTAssertEqual(result.signedRequestHash, paymentRequest.executionRequest.requestAnchorMetadata.signedRequestHash)
            XCTAssertEqual(result.observedAt, "2026-05-31T00:00:14Z")

            switch scenario.expectedStatus {
            case .confirmed:
                XCTAssertEqual(result.transactionHash, scenario.transactionHash)
                XCTAssertEqual(
                    result.explorerURL?.absoluteString,
                    "https://explorer-testnet.example.invalid/tx/\(try XCTUnwrap(scenario.transactionHash))"
                )
                XCTAssertNil(result.message)
            case .pending:
                XCTAssertNil(result.transactionHash)
                XCTAssertNil(result.explorerURL)
                XCTAssertNil(result.message)
            case .failed:
                XCTAssertNil(result.transactionHash)
                XCTAssertNil(result.explorerURL)
                XCTAssertEqual(result.message, scenario.expectedMessage)
            case .policyDenied:
                XCTAssertNil(result.transactionHash)
                XCTAssertNil(result.explorerURL)
                XCTAssertEqual(result.message, "delegated-limit-exceeded")
            }

            let encoded = try JSONEncoder().encode(result)
            let object = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
            XCTAssertEqual(object["status"] as? String, scenario.expectedStatus.rawValue)
            XCTAssertNil(object["marooReceipt"])
        }
    }

    func testPaymentExecutorMapsConfirmedProviderExecutionOutcomesToConfirmedStatus() throws {
        let confirmedOutcomes = [
            "confirmed",
            "complete",
            "completed",
            "executed",
            "finalized",
            "finalised",
            "included",
            "mined",
            "success",
            "succeeded",
            " SUCCESS ",
            "finalized"
        ]

        for outcome in confirmedOutcomes {
            XCTAssertEqual(
                try MeshPaymentExecutionStatus(providerExecutionOutcome: outcome),
                .confirmed,
                "Expected provider outcome \(outcome) to map to confirmed"
            )
        }

        XCTAssertThrowsError(try MeshPaymentExecutionStatus(providerExecutionOutcome: "settlement_unknown")) { error in
            XCTAssertEqual(error as? MeshKitValidationError, .invalidPaymentExecution("providerExecutionOutcome"))
        }
    }

    func testPaymentExecutorMapsPendingProviderExecutionOutcomesToPendingStatus() throws {
        let pendingOutcomes = [
            "pending",
            "accepted",
            "awaiting-confirmation",
            "broadcast",
            "broadcasted",
            "in flight",
            "in_mempool",
            "mempool",
            "processing",
            "queued",
            "submitted",
            "unconfirmed",
            " PROCESSING "
        ]

        for outcome in pendingOutcomes {
            XCTAssertEqual(
                try MeshPaymentExecutionStatus(providerExecutionOutcome: outcome),
                .pending,
                "Expected provider outcome \(outcome) to map to pending"
            )
        }
    }

    func testPaymentExecutorMapsFailedProviderExecutionOutcomesToFailedStatus() throws {
        let failedOutcomes = [
            "failed",
            "failure",
            "reverted",
            "execution-reverted",
            "contract reverted",
            "rejected",
            "declined",
            "error",
            "execution_error",
            "provider-error",
            "rpc error",
            "timeout",
            "timed out",
            "dropped",
            "expired",
            "cancelled",
            "canceled",
            "insufficient-funds",
            "insufficient balance",
            " RPC_ERROR "
        ]

        for outcome in failedOutcomes {
            XCTAssertEqual(
                try MeshPaymentExecutionStatus(providerExecutionOutcome: outcome),
                .failed,
                "Expected provider outcome \(outcome) to map to failed"
            )
        }
    }

    func testPaymentExecutorMapsPolicyDeniedProviderExecutionOutcomesToPolicyDeniedStatus() throws {
        let policyDeniedOutcomes = [
            "denied",
            "policy-denied",
            "policy denied",
            "policydenied",
            "policy-rejected",
            "policy rejection",
            "policy_declined",
            "authorization-denied",
            "auth denied",
            "wallet-denied",
            "wallet_policy_denied",
            "spending-limit-denied",
            "spending limit exceeded",
            "delegated-limit-exceeded",
            "limit_exceeded",
            " POLICY_DENIED "
        ]

        for outcome in policyDeniedOutcomes {
            XCTAssertEqual(
                try MeshPaymentExecutionStatus(providerExecutionOutcome: outcome),
                .policyDenied,
                "Expected provider outcome \(outcome) to map to policyDenied"
            )
        }
    }

    func testDemoPaymentExecutorExecutesOKRWTransferRequestsWithNormalizedExecutionStates() async throws {
        let scenarios: [(MeshPaymentExecutionStatus, String?, String?)] = [
            (.confirmed, nil, nil),
            (.confirmed, "0xokrwtransferprovider001", nil),
            (.pending, nil, nil),
            (.failed, nil, "maroo testnet transfer unavailable")
        ]

        for (index, scenario) in scenarios.enumerated() {
            let (status, transactionHash, message) = scenario
            let paymentRequest = try samplePaymentExecutionRequest(
                kind: .transfer,
                amount: Decimal(3_200),
                nonce: "nonce-demo-okrw-transfer-\(status.rawValue)-\(index)",
                authorizationStatus: .approved
            )
            let executor = try MeshDemoPaymentExecutor(
                identity: try sampleChainProviderIdentity(),
                capabilities: [.executeTransfer],
                executionStatus: status,
                transactionHash: transactionHash,
                message: message
            )

            let result = try await executor.executePayment(
                paymentRequest,
                submittedAt: "2026-05-31T00:00:12Z"
            )

            XCTAssertEqual(result.identity.provider, "maroo")
            XCTAssertEqual(result.identity.network, "maroo-testnet")
            XCTAssertEqual(result.kind, .transfer)
            XCTAssertEqual(result.status, status)
            XCTAssertEqual(result.currencyCode, "KRW")
            XCTAssertEqual(result.tokenSymbol, "OKRW")
            XCTAssertEqual(result.amount, Decimal(3_200))
            XCTAssertEqual(result.recipientAddress, "maroo1dailyMartMerchant")
            XCTAssertEqual(result.requestAnchorIdentifier.anchorId, "anchor-ios-grocery-test-001")
            XCTAssertEqual(result.signedRequestHash, paymentRequest.executionRequest.requestAnchorMetadata.signedRequestHash)
            XCTAssertEqual(result.observedAt, "2026-05-31T00:00:12Z")
            XCTAssertEqual(result.message, message ?? (status == .failed ? "demo payment execution failed" : nil))

            if status == .confirmed {
                XCTAssertNotNil(result.transactionHash)
                XCTAssertEqual(result.transactionHash?.prefix(2), "0x")
                if let transactionHash {
                    XCTAssertEqual(result.transactionHash, transactionHash)
                    XCTAssertEqual(result.txHash, transactionHash)
                } else {
                    XCTAssertEqual(result.transactionHash?.count, 66)
                }
                XCTAssertEqual(
                    result.explorerURL?.absoluteString,
                    "https://explorer-testnet.example.invalid/tx/\(try XCTUnwrap(result.transactionHash))"
                )
            } else {
                XCTAssertNil(result.transactionHash)
                XCTAssertNil(result.explorerURL)
            }

            let encoded = try JSONEncoder().encode(result)
            let object = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
            XCTAssertEqual(object["kind"] as? String, "transfer")
            XCTAssertEqual(object["status"] as? String, status.rawValue)
            XCTAssertEqual(object["tokenSymbol"] as? String, "OKRW")
            XCTAssertNil(object["marooReceipt"])
        }
    }

    func testDemoPaymentExecutorReturnsPolicyDeniedOKRWTransferWithoutChainProof() async throws {
        let paymentRequest = try samplePaymentExecutionRequest(
            kind: .transfer,
            amount: Decimal(10_001),
            nonce: "nonce-demo-okrw-transfer-policy-denied",
            authorizationStatus: .denied
        )
        let executor = try MeshDemoPaymentExecutor(
            identity: try sampleChainProviderIdentity(),
            capabilities: [.executeTransfer],
            executionStatus: .confirmed,
            transactionHash: "0xshouldnotappear"
        )

        let result = try await executor.executePayment(
            paymentRequest,
            submittedAt: "2026-05-31T00:00:13Z"
        )

        XCTAssertEqual(result.identity.provider, "maroo")
        XCTAssertEqual(result.kind, .transfer)
        XCTAssertEqual(result.status, .policyDenied)
        XCTAssertEqual(result.currencyCode, "KRW")
        XCTAssertEqual(result.tokenSymbol, "OKRW")
        XCTAssertEqual(result.amount, Decimal(10_001))
        XCTAssertEqual(result.message, "delegated-limit-exceeded")
        XCTAssertEqual(result.signedRequestHash, paymentRequest.executionRequest.requestAnchorMetadata.signedRequestHash)
        XCTAssertNil(result.transactionHash)
        XCTAssertNil(result.explorerURL)

        let encoded = try JSONEncoder().encode(result)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        XCTAssertEqual(object["kind"] as? String, "transfer")
        XCTAssertEqual(object["status"] as? String, "policyDenied")
        XCTAssertNil(object["transactionHash"])
        XCTAssertNil(object["marooReceipt"])
    }

    func testDemoPaymentExecutorReturnsPolicyDeniedOKRWExecutionWithoutChainProof() async throws {
        let paymentRequest = try samplePaymentExecutionRequest(
            kind: .payment,
            amount: Decimal(10_001),
            nonce: "nonce-demo-okrw-policy-denied",
            authorizationStatus: .denied
        )
        let executor = try MeshDemoPaymentExecutor(
            identity: try sampleChainProviderIdentity(),
            capabilities: [.executePayment],
            executionStatus: .confirmed,
            transactionHash: "0xshouldnotappear"
        )

        let result = try await executor.executePayment(
            paymentRequest,
            submittedAt: "2026-05-31T00:00:11Z"
        )

        XCTAssertEqual(result.status, .policyDenied)
        XCTAssertEqual(result.kind, .payment)
        XCTAssertEqual(result.tokenSymbol, "OKRW")
        XCTAssertEqual(result.message, "delegated-limit-exceeded")
        XCTAssertNil(result.transactionHash)
        XCTAssertNil(result.explorerURL)
    }

    func testPaymentExecutorReturnsPolicyDeniedResultWithoutTransactionProof() async throws {
        let paymentRequest = try samplePaymentExecutionRequest(
            kind: .transfer,
            amount: Decimal(10_001),
            nonce: "nonce-payment-policy-denied",
            authorizationStatus: .denied
        )
        let executor = try StaticPaymentExecutor(
            identity: try sampleChainProviderIdentity(),
            capabilities: [.executeTransfer],
            status: .confirmed,
            transactionHash: "0xshould-not-be-used",
            lookupRequest: nil
        )

        let result = try await executor.executePayment(
            paymentRequest,
            submittedAt: "2026-05-31T00:00:04Z"
        )

        XCTAssertEqual(result.kind, .transfer)
        XCTAssertEqual(result.status, .policyDenied)
        XCTAssertNil(result.transactionHash)
        XCTAssertNil(result.explorerURL)
        XCTAssertEqual(result.message, "delegated-limit-exceeded")
        XCTAssertEqual(result.signedRequestHash, paymentRequest.executionRequest.requestAnchorMetadata.signedRequestHash)
    }

    func testPaymentExecutorResultsBindEveryStatusToOriginatingSignedRequestHash() async throws {
        let scenarios: [
            (
                status: MeshPaymentExecutionStatus,
                authorizationStatus: MeshAgentWalletAuthorizationStatus,
                amount: Decimal,
                transactionHash: String?,
                message: String?
            )
        ] = [
            (.confirmed, .approved, Decimal(4_900), "0xokrwboundconfirmed001", nil),
            (.pending, .approved, Decimal(4_900), nil, nil),
            (.failed, .approved, Decimal(4_900), nil, "maroo testnet rpc unavailable"),
            (.policyDenied, .denied, Decimal(10_001), nil, "delegated-limit-exceeded")
        ]

        for scenario in scenarios {
            let paymentRequest = try samplePaymentExecutionRequest(
                kind: .payment,
                amount: scenario.amount,
                nonce: "nonce-payment-result-binding-\(scenario.status.rawValue)",
                authorizationStatus: scenario.authorizationStatus
            )
            let executor = try MeshDemoPaymentExecutor(
                identity: try sampleChainProviderIdentity(),
                capabilities: [.executePayment],
                executionStatus: scenario.status == .policyDenied ? .confirmed : scenario.status,
                transactionHash: scenario.transactionHash,
                message: scenario.message
            )

            let result = try await executor.executePayment(
                paymentRequest,
                submittedAt: "2026-05-31T00:00:06Z"
            )

            XCTAssertEqual(result.status, scenario.status)
            XCTAssertEqual(result.requestHash, paymentRequest.requestHash)
            XCTAssertEqual(result.signedRequestHash, paymentRequest.requestHash)
            XCTAssertNoThrow(try result.validate(originatingSignedRequestHash: paymentRequest.requestHash))

            let data = try JSONEncoder().encode(result)
            let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
            XCTAssertEqual((object["requestHash"] as? [String: Any])?["algorithm"] as? String, "sha256")
            XCTAssertEqual((object["requestHash"] as? [String: Any])?["value"] as? String, paymentRequest.requestHash.value)
            XCTAssertEqual((object["signedRequestHash"] as? [String: Any])?["value"] as? String, paymentRequest.requestHash.value)

            var mismatchedObject = object
            mismatchedObject["requestHash"] = [
                "algorithm": "sha256",
                "value": String(repeating: "b", count: 64)
            ]
            let mismatchedData = try JSONSerialization.data(withJSONObject: mismatchedObject)
            XCTAssertThrowsError(try JSONDecoder().decode(MeshPaymentExecutionResult.self, from: mismatchedData)) { error in
                XCTAssertEqual(error as? MeshKitValidationError, .invalidPaymentExecution("requestHash"))
            }
        }
    }

    func testPaymentExecutorPropagatesProviderTransactionHashForPendingExecutions() async throws {
        let paymentRequest = try samplePaymentExecutionRequest(
            kind: .payment,
            amount: Decimal(4_900),
            nonce: "nonce-payment-pending-provider-tx",
            authorizationStatus: .approved
        )
        let executor = try StaticPaymentExecutor(
            identity: try sampleChainProviderIdentity(),
            capabilities: [.executePayment, .lookupExecutionStatus],
            status: .pending,
            transactionHash: "0xpendingprovider001",
            lookupRequest: paymentRequest
        )

        let result = try await executor.executePayment(
            paymentRequest,
            submittedAt: "2026-05-31T00:00:08Z"
        )

        XCTAssertEqual(result.status, .pending)
        XCTAssertEqual(result.transactionHash, "0xpendingprovider001")
        XCTAssertEqual(result.txHash, "0xpendingprovider001")
        XCTAssertEqual(
            result.explorerURL?.absoluteString,
            "https://explorer-testnet.example.invalid/tx/0xpendingprovider001"
        )

        let data = try JSONEncoder().encode(result)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(object["transactionHash"] as? String, "0xpendingprovider001")
        XCTAssertEqual(object["txHash"] as? String, "0xpendingprovider001")

        var providerObject = object
        providerObject.removeValue(forKey: "explorerURL")
        let providerData = try JSONSerialization.data(withJSONObject: providerObject)
        let decoded = try JSONDecoder().decode(MeshPaymentExecutionResult.self, from: providerData)
        XCTAssertEqual(decoded.transactionHash, "0xpendingprovider001")
        XCTAssertEqual(
            decoded.explorerURL?.absoluteString,
            "https://explorer-testnet.example.invalid/tx/0xpendingprovider001"
        )

        let lookupResult = try await executor.paymentExecutionStatus(
            paymentId: paymentRequest.paymentId,
            checkedAt: "2026-05-31T00:00:09Z"
        )
        XCTAssertEqual(lookupResult.status, .pending)
        XCTAssertEqual(lookupResult.transactionHash, "0xpendingprovider001")

        let proof = try MeshChainProof(
            paymentResult: result,
            executionRequest: paymentRequest.executionRequest,
            walletAddress: "maroo1dailyMartAgentWallet"
        )
        let receiptFields = try proof.receiptResultFields()
        XCTAssertEqual(proof.status, .pending)
        XCTAssertEqual(proof.presentationState, .submittedNotFinal)
        XCTAssertNil(proof.txHash)
        XCTAssertNil(proof.explorerUrl)
        XCTAssertNil(receiptFields["txHash"])
        XCTAssertNil(receiptFields["explorerUrl"])
    }

    func testPaymentExecutionRejectsMismatchedAnchorsAndInvalidResultShapes() throws {
        let paymentRequest = try samplePaymentExecutionRequest(
            kind: .payment,
            amount: Decimal(100),
            nonce: "nonce-payment-invalid-shape",
            authorizationStatus: .approved
        )
        let mismatchedAnchor = try sampleRequestAnchor(
            metadata: MeshSignedRequestAnchorMetadata(
                request: dailyMartRequest(nonce: "nonce-payment-different-anchor")
            ),
            status: .confirmed
        )

        XCTAssertThrowsError(try MeshPaymentExecutionRequest(
            paymentId: "pay-invalid-anchor",
            authorizationDecision: paymentRequest.authorizationDecision,
            requestAnchor: mismatchedAnchor,
            requestedAt: "2026-05-31T00:00:05Z"
        )) { error in
            XCTAssertEqual(error as? MeshKitValidationError, .invalidPaymentExecution("requestAnchorMetadata"))
        }

        let data = try JSONEncoder().encode(paymentRequest)
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        object.removeValue(forKey: "requestHash")
        let missingRequestHashData = try JSONSerialization.data(withJSONObject: object)
        XCTAssertThrowsError(try JSONDecoder().decode(MeshPaymentExecutionRequest.self, from: missingRequestHashData)) { error in
            XCTAssertEqual(error as? MeshKitValidationError, .invalidPaymentExecution("requestHash"))
        }

        object["requestHash"] = [
            "algorithm": "sha256",
            "value": "not-a-sha256"
        ]
        let malformedRequestHashData = try JSONSerialization.data(withJSONObject: object)
        XCTAssertThrowsError(try JSONDecoder().decode(MeshPaymentExecutionRequest.self, from: malformedRequestHashData)) { error in
            XCTAssertEqual(error as? MeshKitValidationError, .invalidPaymentExecution("requestHash.value"))
        }

        object["requestHash"] = [
            "algorithm": "sha256",
            "value": String(repeating: "b", count: 64)
        ]
        let mismatchedRequestHashData = try JSONSerialization.data(withJSONObject: object)
        XCTAssertThrowsError(try JSONDecoder().decode(MeshPaymentExecutionRequest.self, from: mismatchedRequestHashData)) { error in
            XCTAssertEqual(error as? MeshKitValidationError, .invalidPaymentExecution("requestHash"))
        }

        XCTAssertThrowsError(try MeshPaymentExecutionResult(
            request: paymentRequest,
            identity: try sampleChainProviderIdentity(),
            status: .confirmed,
            observedAt: "2026-05-31T00:00:05Z"
        )) { error in
            XCTAssertEqual(error as? MeshKitValidationError, .invalidPaymentExecution("transactionHash"))
        }

        XCTAssertThrowsError(try MeshPaymentExecutionResult(
            request: paymentRequest,
            identity: try sampleChainProviderIdentity(),
            status: .policyDenied,
            transactionHash: "0xnotallowed",
            observedAt: "2026-05-31T00:00:05Z"
        )) { error in
            XCTAssertEqual(error as? MeshKitValidationError, .invalidPaymentExecution("transactionHash"))
        }
    }

    func testPaymentExecutorRejectsMismatchedSignedRequestHashBeforePaymentOrTransferExecution() async throws {
        for executionKind in [MeshAgentWalletExecutionKind.payment, .transfer] {
            let originatingRequest = dailyMartRequest(
                nonce: "nonce-payment-origin-\(executionKind.rawValue)",
                budget: "4900"
            )
            let validMetadata = try MeshSignedRequestAnchorMetadata(request: originatingRequest)
            let tamperedMetadata = try MeshSignedRequestAnchorMetadata(
                requestId: validMetadata.requestId,
                nonce: validMetadata.nonce,
                timestamp: validMetadata.timestamp,
                callerAppId: validMetadata.callerAppId,
                callerBundleId: validMetadata.callerBundleId,
                targetBundleId: validMetadata.targetBundleId,
                capabilityId: validMetadata.capabilityId,
                payloadHash: validMetadata.payloadHash,
                signature: validMetadata.signature,
                signedRequestHash: MeshPayloadHash(value: String(repeating: "b", count: 64))
            )
            let executionRequest = try MeshAgentWalletExecutionRequest(
                executionId: "exec-mismatched-request-hash-\(executionKind.rawValue)",
                kind: executionKind,
                requestAnchorMetadata: tamperedMetadata,
                scope: sampleDelegatedSpendingScope(),
                amount: Decimal(4_900),
                currencyCode: "krw",
                tokenSymbol: "okrw",
                recipientAddress: "maroo1dailyMartMerchant",
                policyId: "policy-hermes-dailymart-okrw-v1",
                policyHash: MeshPayloadHash(value: String(repeating: "f", count: 64))
            )
            let authorizationDecision = try MeshAgentWalletAuthorizationDecision(
                authorizationId: "auth-mismatched-request-hash-\(executionKind.rawValue)",
                walletIdentity: sampleAgentWalletIdentity(),
                executionRequest: executionRequest,
                status: .approved,
                approvedAmount: Decimal(4_900),
                decidedAt: "2026-05-31T00:00:00Z"
            )
            let paymentRequest = try MeshPaymentExecutionRequest(
                paymentId: "pay-mismatched-request-hash-\(executionKind.rawValue)",
                authorizationDecision: authorizationDecision,
                requestAnchor: sampleRequestAnchor(metadata: tamperedMetadata, status: .confirmed),
                requestedAt: "2026-05-31T00:00:01Z"
            )
            let executor = RecordingPaymentExecutor(
                identity: try sampleChainProviderIdentity(),
                capabilities: [.executePayment, .executeTransfer]
            )

            do {
                _ = try await executor.executePayment(
                    paymentRequest,
                    originatingRequest: originatingRequest,
                    submittedAt: "2026-05-31T00:00:02Z"
                )
                XCTFail("Expected mismatched signed request hash to reject \(executionKind.rawValue) execution")
            } catch {
                XCTAssertEqual(error as? MeshKitValidationError, .invalidPaymentExecution("requestHash"))
            }

            XCTAssertEqual(executor.executionCallCount, 0)
        }
    }

    func testPaymentExecutorRejectsResultReboundToDifferentSignedRequestHash() async throws {
        let originatingRequest = dailyMartRequest(
            nonce: "nonce-payment-result-origin",
            budget: "4900"
        )
        let validPaymentRequest = try samplePaymentExecutionRequest(
            kind: .payment,
            amount: Decimal(4_900),
            nonce: "nonce-payment-result-origin",
            authorizationStatus: .approved
        )
        let reboundPaymentRequest = try samplePaymentExecutionRequest(
            kind: .payment,
            amount: Decimal(4_900),
            nonce: "nonce-payment-result-rebound",
            authorizationStatus: .approved
        )
        let executor = RebindingPaymentExecutor(
            identity: try sampleChainProviderIdentity(),
            capabilities: [.executePayment],
            reboundRequest: reboundPaymentRequest
        )

        do {
            _ = try await executor.executePayment(
                validPaymentRequest,
                originatingRequest: originatingRequest,
                submittedAt: "2026-05-31T00:00:07Z"
            )
            XCTFail("Expected payment executor result rebound to reject")
        } catch {
            XCTAssertEqual(error as? MeshKitValidationError, .invalidPaymentExecution("requestHash"))
        }
    }

    func testChainProofConfigurationDiscoversMinimumProviderNeutralCapabilities() throws {
        let configuration = try MeshChainProofConfiguration(capabilities: [
            .constructPaymentExecutionProof,
            .constructRequestAnchorProof,
            .serializeReceiptResult,
            .constructPaymentExecutionProof
        ])

        XCTAssertEqual(configuration.capabilities, [
            .constructPaymentExecutionProof,
            .constructRequestAnchorProof,
            .serializeReceiptResult
        ])
        XCTAssertTrue(configuration.supports(.constructRequestAnchorProof))
        XCTAssertFalse(configuration.supports(.constructPolicyDenialProof))
        XCTAssertThrowsError(try configuration.require(.constructPolicyDenialProof)) { error in
            XCTAssertEqual(error as? MeshKitValidationError, .unsupportedCapability)
        }
        XCTAssertEqual(configuration.supportedProofTypes, [
            .paymentExecution,
            .requestAnchor
        ])
        XCTAssertTrue(configuration.supports(proofType: .requestAnchor))
        XCTAssertFalse(configuration.supports(proofType: .policyDenial))
        XCTAssertThrowsError(try configuration.require(proofType: .policyDenial)) { error in
            XCTAssertEqual(error as? MeshKitValidationError, .unsupportedCapability)
        }
    }

    func testChainProofFeatureDetectionReportsProviderNeutralMinimumProofTypes() throws {
        let detection = try MeshChainProofConfiguration.featureDetection(capabilities: [
            .constructPolicyDenialProof,
            .constructRequestAnchorProof,
            .serializeReceiptResult,
            .constructRequestAnchorProof
        ])

        XCTAssertEqual(detection.capabilities, [
            .constructPolicyDenialProof,
            .constructRequestAnchorProof,
            .serializeReceiptResult
        ])
        XCTAssertEqual(detection.minimumSupportedProofTypes, [
            .policyDenial,
            .requestAnchor
        ])
        XCTAssertEqual(detection.supportedProofTypes, detection.minimumSupportedProofTypes)
        XCTAssertTrue(detection.supports(.requestAnchor))
        XCTAssertTrue(detection.supports(.policyDenial))
        XCTAssertFalse(detection.supports(.paymentExecution))
    }

    func testChainProofFeatureDetectionRejectsProviderSpecificOrUnbackedProofAdvertising() throws {
        XCTAssertThrowsError(
            try MeshChainProofConfiguration.featureDetection(
                capabilities: [.constructRequestAnchorProof],
                advertisedProofTypes: [.paymentExecution]
            )
        ) { error in
            XCTAssertEqual(error as? MeshKitValidationError, .unsupportedCapability)
        }

        let narrowedDetection = try MeshChainProofConfiguration.featureDetection(
            capabilities: [
                .constructPaymentExecutionProof,
                .constructPolicyDenialProof,
                .constructRequestAnchorProof
            ],
            advertisedProofTypes: [.requestAnchor]
        )

        XCTAssertEqual(narrowedDetection.minimumSupportedProofTypes, [
            .paymentExecution,
            .policyDenial,
            .requestAnchor
        ])
        XCTAssertEqual(narrowedDetection.supportedProofTypes, [.requestAnchor])
    }

    func testChainProofVerificationStatusNormalizationCoversAllPresentationStates() throws {
        let scenarios: [
            (
                paymentStatus: MeshPaymentExecutionStatus,
                expectedProofType: MeshChainProofType,
                expectedStatus: MeshChainProofStatus,
                expectedPresentationState: MeshChainProofPresentationState,
                expectedRequiresTransactionProof: Bool,
                expectedIsTerminal: Bool
            )
        ] = [
            (.confirmed, .paymentExecution, .confirmed, .paidComplete, true, true),
            (.pending, .requestAnchor, .pending, .submittedNotFinal, false, false),
            (.failed, .paymentExecution, .failed, .attemptedFailed, false, true),
            (.policyDenied, .policyDenial, .failed, .policyDenied, false, true)
        ]

        for scenario in scenarios {
            let normalized = MeshChainProof.normalizedVerificationStatus(for: scenario.paymentStatus)

            XCTAssertEqual(normalized.proofType, scenario.expectedProofType)
            XCTAssertEqual(normalized.status, scenario.expectedStatus)
            XCTAssertEqual(normalized.presentationState, scenario.expectedPresentationState)
            XCTAssertEqual(normalized.requiresTransactionProof, scenario.expectedRequiresTransactionProof)
            XCTAssertEqual(normalized.isTerminal, scenario.expectedIsTerminal)
        }
    }

    func testChainProofCarriesRequiredProviderNeutralContractFields() throws {
        let paymentRequest = try samplePaymentExecutionRequest(
            kind: .payment,
            amount: Decimal(4_900),
            nonce: "nonce-chain-proof-confirmed",
            authorizationStatus: .approved
        )
        let paymentResult = try MeshPaymentExecutionResult(
            request: paymentRequest,
            identity: try sampleChainProviderIdentity(),
            status: .confirmed,
            transactionHash: "0xokrwproof123",
            observedAt: "2026-05-31T00:00:20Z"
        )

        let proof = try MeshChainProof(
            paymentResult: paymentResult,
            executionRequest: paymentRequest.executionRequest,
            walletAddress: "maroo1dailyMartAgentWallet"
        )

        XCTAssertEqual(proof.provider, "maroo")
        XCTAssertEqual(proof.network, "maroo-testnet")
        XCTAssertEqual(proof.chainId, "maroo-testnet-1")
        XCTAssertEqual(proof.proofType, .paymentExecution)
        XCTAssertEqual(proof.status, .confirmed)
        XCTAssertEqual(proof.presentationState, .paidComplete)
        XCTAssertEqual(proof.requestHash, paymentRequest.executionRequest.requestAnchorMetadata.signedRequestHash)
        XCTAssertEqual(proof.requestNonce, "nonce-chain-proof-confirmed")
        XCTAssertEqual(proof.policyId, "policy-hermes-dailymart-okrw-v1")
        XCTAssertEqual(proof.policyHash.value, String(repeating: "f", count: 64))
        XCTAssertEqual(proof.walletAddress, "maroo1dailyMartAgentWallet")
        XCTAssertEqual(proof.amount, Decimal(4_900))
        XCTAssertEqual(proof.asset, "OKRW")
        XCTAssertEqual(proof.recipient, "maroo1dailyMartMerchant")
        XCTAssertEqual(proof.anchoringReference, "anchor-ios-grocery-test-001")
        XCTAssertEqual(proof.anchorTxHash, "0xanchor123")
        XCTAssertEqual(proof.txHash, "0xokrwproof123")
        XCTAssertEqual(proof.explorerUrl?.absoluteString, "https://explorer-testnet.example.invalid/tx/0xokrwproof123")
        XCTAssertEqual(proof.confirmedAt, "2026-05-31T00:00:20Z")
    }

    func testChainProofPreservesPolicyDeniedPaymentErrorPayload() throws {
        let paymentRequest = try samplePaymentExecutionRequest(
            kind: .payment,
            amount: Decimal(10_001),
            nonce: "nonce-chain-proof-policy-denied-error-payload",
            authorizationStatus: .denied
        )
        let paymentResult = try MeshPaymentExecutionResult(
            request: paymentRequest,
            identity: try sampleChainProviderIdentity(),
            status: .policyDenied,
            observedAt: "2026-05-31T00:00:23Z",
            message: "fallback policy denied",
            errorPayload: MeshPaymentExecutionErrorPayload(
                code: "wallet_policy_denied",
                message: "policy-single-payment-max-exceeded"
            )
        )

        let proof = try MeshChainProof(
            paymentResult: paymentResult,
            executionRequest: paymentRequest.executionRequest,
            walletAddress: "maroo1dailyMartAgentWallet"
        )
        let receiptFields = try proof.receiptResultFields()

        XCTAssertEqual(proof.proofType, .policyDenial)
        XCTAssertEqual(proof.status, .failed)
        XCTAssertEqual(proof.presentationState, .policyDenied)
        XCTAssertEqual(proof.errorCode, "wallet_policy_denied")
        XCTAssertEqual(proof.errorMessage, "policy-single-payment-max-exceeded")
        XCTAssertEqual(receiptFields["errorCode"], "wallet_policy_denied")
        XCTAssertEqual(receiptFields["errorMessage"], "policy-single-payment-max-exceeded")
        XCTAssertNil(proof.txHash)
        XCTAssertNil(receiptFields["txHash"])
    }

    func testChainProofCodableShapeIsAdapterAgnostic() throws {
        let proof = try MeshChainProof(
            provider: " MAROO ",
            chainId: " MAROO-Testnet-1 ",
            network: " Maroo-Testnet ",
            proofType: .requestAnchor,
            status: .pending,
            presentationState: .submittedNotFinal,
            requestHash: MeshPayloadHash(value: String(repeating: "a", count: 64)),
            requestNonce: "nonce-chain-proof-pending",
            policyId: "policy-hermes-dailymart-okrw-v1",
            policyHash: MeshPayloadHash(value: String(repeating: "b", count: 64)),
            walletAddress: "maroo1dailyMartAgentWallet",
            amount: Decimal(4_900),
            asset: "okrw",
            recipient: "maroo1dailyMartMerchant",
            anchoringReference: "anchor-ios-grocery-test-001",
            anchorTxHash: "0xanchor123",
            submittedAt: "2026-05-31T00:00:21Z"
        )

        let data = try JSONEncoder().encode(proof)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])

        XCTAssertEqual(object["provider"] as? String, "maroo")
        XCTAssertEqual(object["network"] as? String, "maroo-testnet")
        XCTAssertEqual(object["chainId"] as? String, "maroo-testnet-1")
        XCTAssertEqual(object["proofType"] as? String, "request_anchor")
        XCTAssertEqual(object["status"] as? String, "pending")
        XCTAssertEqual(object["presentationState"] as? String, "submitted_not_final")
        XCTAssertEqual((object["requestHash"] as? [String: Any])?["algorithm"] as? String, "sha256")
        XCTAssertEqual(object["requestNonce"] as? String, "nonce-chain-proof-pending")
        XCTAssertEqual(object["policyId"] as? String, "policy-hermes-dailymart-okrw-v1")
        XCTAssertEqual((object["policyHash"] as? [String: Any])?["algorithm"] as? String, "sha256")
        XCTAssertEqual(object["walletAddress"] as? String, "maroo1dailyMartAgentWallet")
        XCTAssertEqual(object["asset"] as? String, "OKRW")
        XCTAssertEqual(object["anchoringReference"] as? String, "anchor-ios-grocery-test-001")
        XCTAssertEqual(object["anchorTxHash"] as? String, "0xanchor123")
        XCTAssertNil(object["marooReceipt"])
        XCTAssertNil(object["marooProof"])
        XCTAssertNil(object["providerName"])

        let receiptFields = try proof.receiptResultFields()
        XCTAssertEqual(receiptFields["chainProvider"], "maroo")
        XCTAssertEqual(receiptFields["chainProofType"], "request_anchor")
        XCTAssertEqual(receiptFields["presentationState"], "submitted_not_final")
        XCTAssertEqual(receiptFields["requestHash"], String(repeating: "a", count: 64))
        XCTAssertNil(receiptFields["txHash"])

        let decoded = try JSONDecoder().decode(MeshChainProof.self, from: data)
        XCTAssertEqual(decoded, proof)
    }

    func testChainProofBuildsProviderNeutralSignedRequestAnchorProof() throws {
        let request = dailyMartRequest(nonce: "nonce-chain-proof-anchor-binding", budget: "4900")
        let metadata = try MeshSignedRequestAnchorMetadata(request: request)
        let policyHash = MeshPayloadHash(value: String(repeating: "f", count: 64))
        let anchorPayload = try MeshRequestAnchorPayload(
            metadata: metadata,
            policyId: "policy-hermes-dailymart-okrw-v1",
            policyHash: policyHash
        )
        let anchor = try MeshRequestAnchor(
            metadata: metadata,
            payload: anchorPayload,
            identifier: MeshRequestAnchorIdentifier(
                identity: try sampleChainProviderIdentity(),
                anchorId: "anchor-ios-grocery-anchor-binding",
                transactionHash: "0xanchorbinding123"
            ),
            status: .confirmed,
            submittedAt: "2026-05-31T00:00:24Z",
            observedAt: "2026-05-31T00:00:25Z"
        )

        let proof = try MeshChainProof(
            requestAnchor: anchor,
            walletAddress: "maroo1dailyMartAgentWallet",
            amount: Decimal(4_900),
            asset: "okrw",
            recipient: "maroo1dailyMartMerchant"
        )

        XCTAssertNoThrow(try proof.validateSignedRequestAnchorProof(anchor))
        XCTAssertEqual(proof.provider, "maroo")
        XCTAssertEqual(proof.chainId, "maroo-testnet-1")
        XCTAssertEqual(proof.network, "maroo-testnet")
        XCTAssertEqual(proof.proofType, .requestAnchor)
        XCTAssertEqual(proof.status, .pending)
        XCTAssertEqual(proof.presentationState, .submittedNotFinal)
        XCTAssertEqual(proof.requestHash, metadata.signedRequestHash)
        XCTAssertEqual(proof.requestNonce, request.nonce)
        XCTAssertEqual(proof.policyId, "policy-hermes-dailymart-okrw-v1")
        XCTAssertEqual(proof.policyHash, policyHash)
        XCTAssertEqual(proof.anchoringReference, "anchor-ios-grocery-anchor-binding")
        XCTAssertEqual(proof.anchorTxHash, "0xanchorbinding123")
        XCTAssertNil(proof.txHash)
    }

    func testChainProofRejectsSignedRequestAnchorProofMismatches() throws {
        let request = dailyMartRequest(nonce: "nonce-chain-proof-anchor-mismatch", budget: "4900")
        let metadata = try MeshSignedRequestAnchorMetadata(request: request)
        let policyHash = MeshPayloadHash(value: String(repeating: "f", count: 64))
        let anchor = try MeshRequestAnchor(
            metadata: metadata,
            payload: MeshRequestAnchorPayload(
                metadata: metadata,
                policyId: "policy-hermes-dailymart-okrw-v1",
                policyHash: policyHash
            ),
            identifier: MeshRequestAnchorIdentifier(
                identity: try sampleChainProviderIdentity(),
                anchorId: "anchor-ios-grocery-anchor-mismatch",
                transactionHash: "0xanchormismatch123"
            ),
            status: .pending,
            submittedAt: "2026-05-31T00:00:24Z"
        )
        let proof = try MeshChainProof(
            requestAnchor: anchor,
            walletAddress: "maroo1dailyMartAgentWallet",
            amount: Decimal(4_900),
            asset: "OKRW",
            recipient: "maroo1dailyMartMerchant"
        )
        let tamperedHashProof = try MeshChainProof(
            provider: proof.provider,
            chainId: proof.chainId,
            network: proof.network,
            proofType: proof.proofType,
            status: proof.status,
            presentationState: proof.presentationState,
            requestHash: MeshPayloadHash(value: String(repeating: "a", count: 64)),
            requestNonce: proof.requestNonce,
            policyId: proof.policyId,
            policyHash: proof.policyHash,
            walletAddress: proof.walletAddress,
            amount: proof.amount,
            asset: proof.asset,
            recipient: proof.recipient,
            anchoringReference: proof.anchoringReference,
            anchorTxHash: proof.anchorTxHash,
            submittedAt: proof.submittedAt
        )
        XCTAssertThrowsError(try tamperedHashProof.validateSignedRequestAnchorProof(anchor)) { error in
            XCTAssertEqual(error as? MeshKitValidationError, .invalidChainProof("requestHash"))
        }
        XCTAssertThrowsError(try MeshChainProof(
            provider: proof.provider,
            chainId: proof.chainId,
            network: proof.network,
            proofType: proof.proofType,
            status: proof.status,
            presentationState: proof.presentationState,
            requestHash: proof.requestHash,
            requestNonce: proof.requestNonce,
            policyId: proof.policyId,
            policyHash: proof.policyHash,
            walletAddress: proof.walletAddress,
            amount: proof.amount,
            asset: proof.asset,
            recipient: proof.recipient,
            anchoringReference: proof.anchoringReference,
            anchorTxHash: proof.anchorTxHash,
            txHash: "0xpaymenthashmustnotproveanchor",
            submittedAt: proof.submittedAt
        )) { error in
            XCTAssertEqual(error as? MeshKitValidationError, .invalidChainProof("txHash"))
        }
        XCTAssertThrowsError(try proof.validateSignedRequestAnchorProof(
            anchor,
            policyHash: MeshPayloadHash(value: String(repeating: "b", count: 64))
        )) { error in
            XCTAssertEqual(error as? MeshKitValidationError, .invalidChainProof("policyHash"))
        }
    }

    func testChainProofRejectsTamperedSignedRequestAnchorNoncePolicyIdAndPolicyHash() throws {
        let request = dailyMartRequest(nonce: "nonce-chain-proof-anchor-tamper", budget: "4900")
        let metadata = try MeshSignedRequestAnchorMetadata(request: request)
        let policyHash = MeshPayloadHash(value: String(repeating: "f", count: 64))
        let anchor = try MeshRequestAnchor(
            metadata: metadata,
            payload: MeshRequestAnchorPayload(
                metadata: metadata,
                policyId: "policy-hermes-dailymart-okrw-v1",
                policyHash: policyHash
            ),
            identifier: MeshRequestAnchorIdentifier(
                identity: try sampleChainProviderIdentity(),
                anchorId: "anchor-ios-grocery-anchor-tamper",
                transactionHash: "0xanchortamper123"
            ),
            status: .confirmed,
            submittedAt: "2026-05-31T00:00:24Z"
        )
        let proof = try MeshChainProof(
            requestAnchor: anchor,
            walletAddress: "maroo1dailyMartAgentWallet",
            amount: Decimal(4_900),
            asset: "OKRW",
            recipient: "maroo1dailyMartMerchant"
        )
        func tamperedProof(
            requestNonce: String? = nil,
            policyId: String? = nil,
            policyHash: MeshPayloadHash? = nil
        ) throws -> MeshChainProof {
            try MeshChainProof(
                provider: proof.provider,
                chainId: proof.chainId,
                network: proof.network,
                proofType: proof.proofType,
                status: proof.status,
                presentationState: proof.presentationState,
                requestHash: proof.requestHash,
                requestNonce: requestNonce ?? proof.requestNonce,
                policyId: policyId ?? proof.policyId,
                policyHash: policyHash ?? proof.policyHash,
                walletAddress: proof.walletAddress,
                amount: proof.amount,
                asset: proof.asset,
                recipient: proof.recipient,
                anchoringReference: proof.anchoringReference,
                anchorTxHash: proof.anchorTxHash,
                submittedAt: proof.submittedAt
            )
        }

        let tamperedNonceProof = try tamperedProof(
            requestNonce: "nonce-chain-proof-anchor-tampered"
        )
        let tamperedPolicyIdProof = try tamperedProof(
            policyId: "policy-hermes-dailymart-okrw-tampered"
        )
        let tamperedPolicyHashProof = try tamperedProof(
            policyHash: MeshPayloadHash(value: String(repeating: "b", count: 64))
        )

        XCTAssertThrowsError(try tamperedNonceProof.validateSignedRequestAnchorProof(anchor)) { error in
            XCTAssertEqual(error as? MeshKitValidationError, .invalidChainProof("requestNonce"))
        }
        XCTAssertThrowsError(try tamperedPolicyIdProof.validateSignedRequestAnchorProof(anchor)) { error in
            XCTAssertEqual(error as? MeshKitValidationError, .invalidChainProof("policyId"))
        }
        XCTAssertThrowsError(try tamperedPolicyHashProof.validateSignedRequestAnchorProof(anchor)) { error in
            XCTAssertEqual(error as? MeshKitValidationError, .invalidChainProof("policyHash"))
        }
    }

    func testReceiptChainProofSerializerEmbedsDailyMartProofInSignedReceiptPayload() throws {
        let targetKey = Curve25519.Signing.PrivateKey()
        let request = dailyMartRequest(nonce: "nonce-receipt-chain-proof", budget: "4900")
        let proof = try MeshChainProof(
            provider: "maroo",
            chainId: "maroo-testnet-1",
            network: "maroo-testnet",
            proofType: .paymentExecution,
            status: .confirmed,
            presentationState: .paidComplete,
            requestHash: MeshRequestAnchorCanonicalization.signedRequestHash(for: request),
            requestNonce: request.nonce,
            policyId: "policy-hermes-dailymart-okrw-v1",
            policyHash: MeshPayloadHash(value: String(repeating: "f", count: 64)),
            walletAddress: "maroo1dailyMartAgentWallet",
            amount: Decimal(4_900),
            asset: "OKRW",
            recipient: "maroo1dailyMartMerchant",
            anchoringReference: "anchor-ios-grocery-test-001",
            anchorTxHash: "0xanchor123",
            txHash: "0xokrwreceiptproof001",
            explorerUrl: try XCTUnwrap(URL(string: "https://explorer-testnet.example.invalid/tx/0xokrwreceiptproof001")),
            submittedAt: "2026-05-31T00:00:20Z",
            confirmedAt: "2026-05-31T00:00:20Z"
        )
        let result = try MeshReceiptChainProofSerializer.receiptResultFields(
            baseResult: [
                "order_id": "DM-2026-0509-002",
                "total_krw": "4900",
                "payment_asset": "OKRW"
            ],
            proof: proof
        )

        let receipt = try MeshReceiptSigner.ed25519(
            keyId: "dailymart-receipt-key",
            privateKey: targetKey
        ).makeReceipt(
            receiptId: "receipt-chain-proof-001",
            request: request,
            targetAppId: "app.dailymart",
            targetBundleId: "ai.meshkit.sample.dailymart",
            status: "purchased",
            result: result,
            nonce: "receipt-chain-proof-nonce-001",
            timestamp: ISO8601DateFormatter().string(from: Date())
        )

        let decodedReceipt = try MeshReceipt.decodedFromURLScheme(receipt.encodedForURLScheme())
        let decodedProof = try MeshReceiptChainProofSerializer.decodeProof(from: decodedReceipt.result)
        let verifiedReceipt = try MeshReceiptVerifier.verify(
            decodedReceipt,
            trust: MeshReceiptTrust(
                targetAppId: "app.dailymart",
                targetBundleId: "ai.meshkit.sample.dailymart",
                receiptSigningAlgorithm: "Ed25519",
                receiptSigningKeyId: "dailymart-receipt-key",
                publicKey: targetKey.publicKey.rawRepresentation.base64EncodedString()
            ),
            maxAgeSeconds: 60
        )

        XCTAssertEqual(verifiedReceipt.result["order_id"], "DM-2026-0509-002")
        XCTAssertEqual(verifiedReceipt.result["chainProofVersion"], MeshReceiptChainProofPayload.version)
        XCTAssertEqual(verifiedReceipt.result["chainProofEncoding"], "base64-json")
        XCTAssertEqual(verifiedReceipt.result["chainProvider"], "maroo")
        XCTAssertEqual(verifiedReceipt.result["chainNetwork"], "maroo-testnet")
        XCTAssertEqual(verifiedReceipt.result["chainProofType"], "payment_execution")
        XCTAssertEqual(verifiedReceipt.result["chainStatus"], "confirmed")
        XCTAssertEqual(verifiedReceipt.result["presentationState"], "paid_complete")
        XCTAssertEqual(verifiedReceipt.result["txHash"], "0xokrwreceiptproof001")
        XCTAssertEqual(verifiedReceipt.result["requestNonce"], "nonce-receipt-chain-proof")
        XCTAssertEqual(decodedProof, proof)
        XCTAssertEqual(decodedProof.requestHash, try MeshRequestAnchorCanonicalization.signedRequestHash(for: request))
    }

    func testTargetOwnedReceiptChainProofOwnershipBindsProofToSignedRequest() throws {
        let targetKey = Curve25519.Signing.PrivateKey()
        let request = dailyMartRequest(nonce: "nonce-receipt-chain-proof-owner", budget: "4900")
        let proof = try MeshChainProof(
            provider: "maroo",
            chainId: "maroo-testnet-1",
            network: "maroo-testnet",
            proofType: .paymentExecution,
            status: .confirmed,
            presentationState: .paidComplete,
            requestHash: MeshRequestAnchorCanonicalization.signedRequestHash(for: request),
            requestNonce: request.nonce,
            policyId: "policy-hermes-dailymart-okrw-v1",
            policyHash: MeshPayloadHash(value: String(repeating: "f", count: 64)),
            walletAddress: "maroo1dailyMartAgentWallet",
            amount: Decimal(4_900),
            asset: "OKRW",
            recipient: "maroo1dailyMartMerchant",
            anchoringReference: "anchor-ios-grocery-owner-proof",
            anchorTxHash: "0xanchorownerproof001",
            txHash: "0xokrwownerproof001",
            explorerUrl: try XCTUnwrap(URL(string: "https://explorer-testnet.example.invalid/tx/0xokrwownerproof001")),
            submittedAt: "2026-05-31T00:00:20Z",
            confirmedAt: "2026-05-31T00:00:22Z"
        )
        let targetOwnedResult = try MeshReceiptOwnershipMapper.targetOwnedResultFields(
            baseResult: ["order_id": "DM-2026-0531-OWNER-PROOF", "payment_asset": "OKRW"],
            targetAppId: "app.dailymart",
            targetBundleId: "ai.meshkit.sample.dailymart"
        )
        let receipt = try MeshReceiptSigner.ed25519(
            keyId: "dailymart-receipt-key",
            privateKey: targetKey
        ).makeReceipt(
            receiptId: "receipt-chain-proof-owner-001",
            request: request,
            targetAppId: "app.dailymart",
            targetBundleId: "ai.meshkit.sample.dailymart",
            status: "purchased",
            result: MeshReceiptChainProofSerializer.receiptResultFields(
                baseResult: targetOwnedResult,
                proof: proof
            ),
            nonce: "receipt-chain-proof-owner-nonce-001",
            timestamp: ISO8601DateFormatter().string(from: Date())
        )

        let ownershipProof = try MeshReceiptChainProofSerializer.targetOwnedProof(
            in: receipt,
            expectedTargetAppId: "app.dailymart",
            expectedTargetBundleId: "ai.meshkit.sample.dailymart",
            expectedRequest: request
        )

        XCTAssertEqual(ownershipProof.receiptId, "receipt-chain-proof-owner-001")
        XCTAssertEqual(ownershipProof.ownership.receiptOwner, "app.dailymart#ai.meshkit.sample.dailymart")
        XCTAssertEqual(ownershipProof.proof, proof)
        XCTAssertEqual(ownershipProof.proofReference.value, "anchor-ios-grocery-owner-proof")
        XCTAssertEqual(ownershipProof.transactionReference?.value, "0xokrwownerproof001")
    }

    func testTargetOwnedReceiptChainProofOwnershipSerializesAnchoredMCPRequestLinkage() throws {
        let targetKey = Curve25519.Signing.PrivateKey()
        let request = dailyMartRequest(nonce: "nonce-receipt-chain-proof-linkage", budget: "4900")
        let requestHash = try MeshRequestAnchorCanonicalization.signedRequestHash(for: request)
        let proof = try MeshChainProof(
            provider: "maroo",
            chainId: "maroo-testnet-1",
            network: "maroo-testnet",
            proofType: .paymentExecution,
            status: .confirmed,
            presentationState: .paidComplete,
            requestHash: requestHash,
            requestNonce: request.nonce,
            policyId: "policy-hermes-dailymart-okrw-v1",
            policyHash: MeshPayloadHash(value: String(repeating: "f", count: 64)),
            walletAddress: "maroo1dailyMartAgentWallet",
            amount: Decimal(4_900),
            asset: "OKRW",
            recipient: "maroo1dailyMartMerchant",
            anchoringReference: "anchor-ios-grocery-linkage-proof",
            anchorTxHash: "0xanchorlinkageproof001",
            txHash: "0xokrwlinkageproof001",
            explorerUrl: try XCTUnwrap(URL(string: "https://explorer-testnet.example.invalid/tx/0xokrwlinkageproof001")),
            submittedAt: "2026-05-31T00:00:20Z",
            confirmedAt: "2026-05-31T00:00:22Z"
        )
        let receipt = try MeshReceiptSigner.ed25519(
            keyId: "dailymart-receipt-key",
            privateKey: targetKey
        ).makeReceipt(
            receiptId: "receipt-chain-proof-linkage-001",
            request: request,
            targetAppId: "app.dailymart",
            targetBundleId: "ai.meshkit.sample.dailymart",
            status: "purchased",
            result: MeshReceiptChainProofSerializer.receiptResultFields(
                baseResult: MeshReceiptOwnershipMapper.targetOwnedResultFields(
                    baseResult: ["order_id": "DM-2026-0531-LINKAGE"],
                    targetAppId: "app.dailymart",
                    targetBundleId: "ai.meshkit.sample.dailymart"
                ),
                proof: proof
            ),
            nonce: "receipt-chain-proof-linkage-nonce-001",
            timestamp: ISO8601DateFormatter().string(from: Date())
        )

        let ownershipProof = try MeshReceiptChainProofSerializer.targetOwnedProof(
            in: receipt,
            expectedTargetAppId: "app.dailymart",
            expectedTargetBundleId: "ai.meshkit.sample.dailymart",
            expectedRequest: request
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let encodedOwnershipProof = try encoder.encode(ownershipProof)
        let decodedOwnershipProof = try JSONDecoder().decode(
            MeshReceiptChainProofOwnership.self,
            from: encodedOwnershipProof
        )

        XCTAssertEqual(ownershipProof.anchoredRequestLinkage.receiptId, "receipt-chain-proof-linkage-001")
        XCTAssertEqual(ownershipProof.anchoredRequestLinkage.requestId, request.requestId)
        XCTAssertEqual(ownershipProof.anchoredRequestLinkage.requestHash, requestHash)
        XCTAssertEqual(ownershipProof.anchoredRequestLinkage.anchoringReference, "anchor-ios-grocery-linkage-proof")
        XCTAssertEqual(decodedOwnershipProof, ownershipProof)
        XCTAssertEqual(decodedOwnershipProof.anchoredRequestLinkage.requestHash, requestHash)
        XCTAssertEqual(
            decodedOwnershipProof.anchoredRequestLinkage.anchoringReference,
            "anchor-ios-grocery-linkage-proof"
        )
    }

    func testTargetOwnedReceiptChainProofOwnershipRejectsCallerOwnedReceiptFields() throws {
        let targetKey = Curve25519.Signing.PrivateKey()
        let request = dailyMartRequest(nonce: "nonce-receipt-chain-proof-caller-owned", budget: "4900")
        let proof = try MeshChainProof(
            provider: "maroo",
            chainId: "maroo-testnet-1",
            network: "maroo-testnet",
            proofType: .paymentExecution,
            status: .confirmed,
            presentationState: .paidComplete,
            requestHash: MeshRequestAnchorCanonicalization.signedRequestHash(for: request),
            requestNonce: request.nonce,
            policyId: "policy-hermes-dailymart-okrw-v1",
            policyHash: MeshPayloadHash(value: String(repeating: "f", count: 64)),
            walletAddress: "maroo1dailyMartAgentWallet",
            amount: Decimal(4_900),
            asset: "OKRW",
            recipient: "maroo1dailyMartMerchant",
            anchoringReference: "anchor-ios-grocery-caller-owned-proof",
            anchorTxHash: "0xanchorcallerowned001",
            txHash: "0xokrwcallerowned001",
            explorerUrl: try XCTUnwrap(URL(string: "https://explorer-testnet.example.invalid/tx/0xokrwcallerowned001")),
            submittedAt: "2026-05-31T00:00:20Z",
            confirmedAt: "2026-05-31T00:00:22Z"
        )
        let callerOwner = try MeshReceiptOwnershipMapper.ownerIdentifier(
            targetAppId: request.caller.appId,
            targetBundleId: request.caller.bundleId
        )
        let receipt = try MeshReceiptSigner.ed25519(
            keyId: "dailymart-receipt-key",
            privateKey: targetKey
        ).makeReceipt(
            receiptId: "receipt-chain-proof-caller-owned-001",
            request: request,
            targetAppId: "app.dailymart",
            targetBundleId: "ai.meshkit.sample.dailymart",
            status: "purchased",
            result: MeshReceiptChainProofSerializer.receiptResultFields(
                baseResult: [
                    "order_id": "DM-2026-0531-CALLER-OWNED",
                    "receiptOwner": callerOwner,
                    "targetReceiptOwner": callerOwner
                ],
                proof: proof
            ),
            nonce: "receipt-chain-proof-caller-owned-nonce-001",
            timestamp: ISO8601DateFormatter().string(from: Date())
        )

        XCTAssertThrowsError(try MeshReceiptChainProofSerializer.targetOwnedProof(
            in: receipt,
            expectedTargetAppId: "app.dailymart",
            expectedTargetBundleId: "ai.meshkit.sample.dailymart",
            expectedRequest: request
        )) { error in
            XCTAssertEqual(error as? MeshKitValidationError, .targetIdentityMismatch)
        }
    }

    func testTargetOwnedReceiptChainProofOwnershipRejectsMismatchedSignedRequestBinding() throws {
        let targetKey = Curve25519.Signing.PrivateKey()
        let request = dailyMartRequest(nonce: "nonce-receipt-chain-proof-binding", budget: "4900")
        let proof = try MeshChainProof(
            provider: "maroo",
            chainId: "maroo-testnet-1",
            network: "maroo-testnet",
            proofType: .paymentExecution,
            status: .confirmed,
            presentationState: .paidComplete,
            requestHash: MeshRequestAnchorCanonicalization.signedRequestHash(for: request),
            requestNonce: "nonce-receipt-chain-proof-binding-forged",
            policyId: "policy-hermes-dailymart-okrw-v1",
            policyHash: MeshPayloadHash(value: String(repeating: "f", count: 64)),
            walletAddress: "maroo1dailyMartAgentWallet",
            amount: Decimal(4_900),
            asset: "OKRW",
            recipient: "maroo1dailyMartMerchant",
            anchoringReference: "anchor-ios-grocery-binding-proof",
            anchorTxHash: "0xanchorbindingproof001",
            txHash: "0xokrwbindingproof001",
            explorerUrl: try XCTUnwrap(URL(string: "https://explorer-testnet.example.invalid/tx/0xokrwbindingproof001")),
            submittedAt: "2026-05-31T00:00:20Z",
            confirmedAt: "2026-05-31T00:00:22Z"
        )
        let receipt = try MeshReceiptSigner.ed25519(
            keyId: "dailymart-receipt-key",
            privateKey: targetKey
        ).makeReceipt(
            receiptId: "receipt-chain-proof-binding-001",
            request: request,
            targetAppId: "app.dailymart",
            targetBundleId: "ai.meshkit.sample.dailymart",
            status: "purchased",
            result: MeshReceiptChainProofSerializer.receiptResultFields(
                baseResult: MeshReceiptOwnershipMapper.targetOwnedResultFields(
                    baseResult: ["order_id": "DM-2026-0531-BINDING"],
                    targetAppId: "app.dailymart",
                    targetBundleId: "ai.meshkit.sample.dailymart"
                ),
                proof: proof
            ),
            nonce: "receipt-chain-proof-binding-nonce-001",
            timestamp: ISO8601DateFormatter().string(from: Date())
        )

        XCTAssertThrowsError(try MeshReceiptChainProofSerializer.targetOwnedProof(
            in: receipt,
            expectedTargetAppId: "app.dailymart",
            expectedTargetBundleId: "ai.meshkit.sample.dailymart",
            expectedRequest: request
        )) { error in
            XCTAssertEqual(error as? MeshKitValidationError, .invalidChainProof("requestNonce"))
        }
    }

    func testMarooAdapterMetadataStaysInsideProviderScopedChainProofExtensions() throws {
        let targetKey = Curve25519.Signing.PrivateKey()
        let request = dailyMartRequest(nonce: "nonce-receipt-maroo-extension", budget: "4900")
        let paymentRequest = try samplePaymentExecutionRequest(
            kind: .payment,
            amount: Decimal(4_900),
            nonce: request.nonce,
            authorizationStatus: .approved
        )
        let paymentResult = try MeshPaymentExecutionResult(
            request: paymentRequest,
            identity: try sampleChainProviderIdentity(),
            status: .confirmed,
            transactionHash: "0xokrwmarooextension001",
            observedAt: "2026-05-31T00:00:30Z",
            providerExtensions: [
                " Maroo ": [
                    "adapterId": "maroo-testnet-demo-adapter",
                    "rpcEndpoint": "https://rpc-testnet.maroo.io",
                    "okrwContract": "maroo1okrwcontract001"
                ]
            ]
        )
        let proof = try MeshChainProof(
            paymentResult: paymentResult,
            executionRequest: paymentRequest.executionRequest,
            walletAddress: "maroo1dailyMartAgentWallet"
        )

        let result = try MeshReceiptChainProofSerializer.receiptResultFields(
            baseResult: [
                "order_id": "DM-2026-0531-MAROO-EXT",
                "payment_asset": "OKRW"
            ],
            proof: proof
        )
        let receipt = try MeshReceiptSigner.ed25519(
            keyId: "dailymart-receipt-key",
            privateKey: targetKey
        ).makeReceipt(
            receiptId: "receipt-maroo-extension-001",
            request: request,
            targetAppId: "app.dailymart",
            targetBundleId: "ai.meshkit.sample.dailymart",
            status: "purchased",
            result: result,
            nonce: "receipt-maroo-extension-nonce-001",
            timestamp: ISO8601DateFormatter().string(from: Date())
        )

        let encodedReceipt = try receipt.encodedForURLScheme()
        let decodedReceipt = try MeshReceipt.decodedFromURLScheme(encodedReceipt)
        let decodedProof = try MeshReceiptChainProofSerializer.decodeProof(from: decodedReceipt.result)

        XCTAssertEqual(decodedProof.providerExtensions["maroo"]?["adapterId"], "maroo-testnet-demo-adapter")
        XCTAssertEqual(decodedProof.providerExtensions["maroo"]?["rpcEndpoint"], "https://rpc-testnet.maroo.io")
        XCTAssertEqual(decodedProof.providerExtensions["maroo"]?["okrwContract"], "maroo1okrwcontract001")
        XCTAssertNil(decodedReceipt.result["providerExtensions"])
        XCTAssertNil(decodedReceipt.result["maroo"])
        XCTAssertNil(decodedReceipt.result["marooReceipt"])
        XCTAssertNil(decodedReceipt.result["marooMetadata"])
        XCTAssertNil(decodedReceipt.result["rpcEndpoint"])
        XCTAssertNil(decodedReceipt.result["okrwContract"])
        XCTAssertNoThrow(try MeshReceipt.validateProviderNeutralCoreSchema(
            jsonData: Data(base64Encoded: encodedReceipt)!
        ))

        var leakedCoreReceipt = try XCTUnwrap(
            JSONSerialization.jsonObject(with: Data(base64Encoded: encodedReceipt)!) as? [String: Any]
        )
        leakedCoreReceipt["marooMetadata"] = ["rpcEndpoint": "https://rpc-testnet.maroo.io"]
        let leakedCoreReceiptData = try JSONSerialization.data(withJSONObject: leakedCoreReceipt, options: [.sortedKeys])
        XCTAssertThrowsError(try MeshReceipt.validateProviderNeutralCoreSchema(jsonData: leakedCoreReceiptData)) { error in
            XCTAssertEqual(error as? MeshKitValidationError, .invalidSecurityField("receipt.marooMetadata"))
        }
    }

    func testChainProofReferenceNormalizationMapsProviderSpecificInputs() throws {
        let identity = try sampleChainProviderIdentity()

        let transactionReference = try MeshChainProofReference.transaction(
            identity: identity,
            providerFields: [
                "tx_hash": "0XABCDEF1234"
            ]
        )
        let proofReference = try MeshChainProofReference.proof(
            identity: identity,
            providerFields: [
                "request_anchor_id": "anchor-ios-grocery-test-001"
            ]
        )

        XCTAssertEqual(transactionReference.provider, "maroo")
        XCTAssertEqual(transactionReference.network, "maroo-testnet")
        XCTAssertEqual(transactionReference.chainId, "maroo-testnet-1")
        XCTAssertEqual(transactionReference.referenceType, .transaction)
        XCTAssertEqual(transactionReference.value, "0xabcdef1234")
        XCTAssertEqual(
            transactionReference.canonicalReference,
            "chainproof://maroo/maroo-testnet/maroo-testnet-1/transaction/0xabcdef1234"
        )
        XCTAssertEqual(
            transactionReference.explorerUrl?.absoluteString,
            "https://explorer-testnet.example.invalid/tx/0xabcdef1234"
        )

        XCTAssertEqual(proofReference.referenceType, .proof)
        XCTAssertEqual(proofReference.value, "anchor-ios-grocery-test-001")
        XCTAssertEqual(
            proofReference.canonicalReference,
            "chainproof://maroo/maroo-testnet/maroo-testnet-1/proof/anchor-ios-grocery-test-001"
        )
        XCTAssertNil(proofReference.explorerUrl)
    }

    func testChainProofProducesCanonicalTransactionAndProofReferences() throws {
        let proof = try MeshChainProof(
            provider: " MAROO ",
            chainId: " MAROO-Testnet-1 ",
            network: " Maroo-Testnet ",
            proofType: .paymentExecution,
            status: .confirmed,
            presentationState: .paidComplete,
            requestHash: MeshPayloadHash(value: String(repeating: "a", count: 64)),
            requestNonce: "nonce-chain-proof-reference",
            policyId: "policy-hermes-dailymart-okrw-v1",
            policyHash: MeshPayloadHash(value: String(repeating: "b", count: 64)),
            walletAddress: "maroo1dailyMartAgentWallet",
            amount: Decimal(4_900),
            asset: "OKRW",
            recipient: "maroo1dailyMartMerchant",
            anchoringReference: "anchor-ios-grocery-test-001",
            anchorTxHash: "0XANCHOR123",
            txHash: "0XOKRWPROOF123",
            explorerUrl: try XCTUnwrap(URL(string: "https://explorer-testnet.example.invalid/tx/0xokrwproof123")),
            submittedAt: "2026-05-31T00:00:21Z",
            confirmedAt: "2026-05-31T00:00:22Z"
        )

        let transactionReference = try XCTUnwrap(proof.transactionReference())
        let proofReference = try proof.proofReference()

        XCTAssertEqual(transactionReference.value, "0xokrwproof123")
        XCTAssertEqual(
            transactionReference.canonicalReference,
            "chainproof://maroo/maroo-testnet/maroo-testnet-1/transaction/0xokrwproof123"
        )
        XCTAssertEqual(
            transactionReference.explorerUrl?.absoluteString,
            "https://explorer-testnet.example.invalid/tx/0xokrwproof123"
        )
        XCTAssertEqual(proofReference.value, "anchor-ios-grocery-test-001")
        XCTAssertEqual(
            proofReference.canonicalReference,
            "chainproof://maroo/maroo-testnet/maroo-testnet-1/proof/anchor-ios-grocery-test-001"
        )
    }

    func testChainProofReferenceNormalizationRejectsMissingOrUnstableProviderInputs() throws {
        XCTAssertThrowsError(try MeshChainProofReference.transaction(
            identity: try sampleChainProviderIdentity(),
            providerFields: ["providerReceipt": "0xabc123"]
        )) { error in
            XCTAssertEqual(error as? MeshKitValidationError, .invalidChainProof("transactionHash"))
        }

        XCTAssertThrowsError(try MeshChainProofReference.proof(
            identity: try sampleChainProviderIdentity(),
            providerFields: ["proof_id": "anchor/forged"]
        )) { error in
            XCTAssertEqual(error as? MeshKitValidationError, .invalidChainProof("proofReference"))
        }
    }

    func testChainProofStatusRulesCoverPendingFailedAndPolicyDeniedPresentationStates() async throws {
        let scenarios: [
            (
                executionStatus: MeshPaymentExecutionStatus,
                authorizationStatus: MeshAgentWalletAuthorizationStatus,
                amount: Decimal,
                transactionHash: String?,
                message: String?,
                expectedProofType: MeshChainProofType,
                expectedStatus: MeshChainProofStatus,
                expectedPresentationState: MeshChainProofPresentationState,
                expectedErrorCode: String?
            )
        ] = [
            (.pending, .approved, Decimal(4_900), nil, nil, .requestAnchor, .pending, .submittedNotFinal, nil),
            (.failed, .approved, Decimal(4_900), nil, "maroo testnet rpc unavailable", .paymentExecution, .failed, .attemptedFailed, "payment_execution_failed"),
            (.confirmed, .denied, Decimal(10_001), "0xmustnotappear", "delegated-limit-exceeded", .policyDenial, .failed, .policyDenied, "policy_denied")
        ]

        for scenario in scenarios {
            let paymentRequest = try samplePaymentExecutionRequest(
                kind: .payment,
                amount: scenario.amount,
                nonce: "nonce-chain-proof-\(scenario.expectedPresentationState.rawValue)",
                authorizationStatus: scenario.authorizationStatus
            )
            let executor = try MeshDemoPaymentExecutor(
                identity: try sampleChainProviderIdentity(),
                capabilities: [.executePayment],
                executionStatus: scenario.executionStatus,
                transactionHash: scenario.transactionHash,
                message: scenario.message
            )

            let paymentResult = try await executor.executePayment(
                paymentRequest,
                submittedAt: "2026-05-31T00:00:22Z"
            )
            let proof = try MeshChainProof(
                paymentResult: paymentResult,
                executionRequest: paymentRequest.executionRequest,
                walletAddress: "maroo1dailyMartAgentWallet"
            )

            XCTAssertEqual(proof.proofType, scenario.expectedProofType)
            XCTAssertEqual(proof.status, scenario.expectedStatus)
            XCTAssertEqual(proof.presentationState, scenario.expectedPresentationState)
            XCTAssertEqual(proof.errorCode, scenario.expectedErrorCode)
            XCTAssertEqual(proof.requestNonce, "nonce-chain-proof-\(scenario.expectedPresentationState.rawValue)")

            if scenario.expectedPresentationState == .policyDenied {
                XCTAssertNil(proof.txHash)
                XCTAssertNil(proof.confirmedAt)
                XCTAssertEqual(proof.errorMessage, "delegated-limit-exceeded")
            }
        }
    }

    func testChainProofRejectsMissingRequiredFieldsAndInvalidConditionalShapes() throws {
        XCTAssertThrowsError(try MeshChainProof(
            provider: "demo-provider",
            chainId: "demo-chain",
            network: "demo-testnet",
            proofType: .paymentExecution,
            status: .confirmed,
            presentationState: .paidComplete,
            requestHash: MeshPayloadHash(value: String(repeating: "a", count: 64)),
            requestNonce: "nonce-chain-proof-invalid",
            policyId: "policy-hermes-dailymart-okrw-v1",
            policyHash: MeshPayloadHash(value: String(repeating: "b", count: 64)),
            walletAddress: "wallet1",
            amount: Decimal(4_900),
            asset: "OKRW",
            recipient: "merchant1",
            anchoringReference: "anchor-001",
            submittedAt: "2026-05-31T00:00:23Z",
            confirmedAt: "2026-05-31T00:00:23Z"
        )) { error in
            XCTAssertEqual(error as? MeshKitValidationError, .invalidChainProof("txHash"))
        }

        XCTAssertThrowsError(try MeshChainProof(
            provider: "demo-provider",
            chainId: "demo-chain",
            network: "demo-testnet",
            proofType: .policyDenial,
            status: .failed,
            presentationState: .policyDenied,
            requestHash: MeshPayloadHash(value: String(repeating: "a", count: 64)),
            requestNonce: "nonce-chain-proof-policy-invalid",
            policyId: "policy-hermes-dailymart-okrw-v1",
            policyHash: MeshPayloadHash(value: String(repeating: "b", count: 64)),
            walletAddress: "wallet1",
            amount: Decimal(10_001),
            asset: "OKRW",
            recipient: "merchant1",
            anchoringReference: "anchor-001",
            txHash: "0xnotallowed",
            errorCode: "policy_denied",
            errorMessage: "delegated-limit-exceeded",
            submittedAt: "2026-05-31T00:00:23Z"
        )) { error in
            XCTAssertEqual(error as? MeshKitValidationError, .invalidChainProof("txHash"))
        }

        XCTAssertThrowsError(try MeshChainProof(
            provider: "demo-provider",
            chainId: "demo-chain",
            network: "demo-testnet",
            proofType: .requestAnchor,
            status: .pending,
            presentationState: .submittedNotFinal,
            requestHash: MeshPayloadHash(value: String(repeating: "a", count: 64)),
            requestNonce: "nonce-chain-proof-pending-tx-invalid",
            policyId: "policy-hermes-dailymart-okrw-v1",
            policyHash: MeshPayloadHash(value: String(repeating: "b", count: 64)),
            walletAddress: "wallet1",
            amount: Decimal(4_900),
            asset: "OKRW",
            recipient: "merchant1",
            anchoringReference: "anchor-001",
            txHash: "0xpendingnotconfirmed",
            submittedAt: "2026-05-31T00:00:23Z"
        )) { error in
            XCTAssertEqual(error as? MeshKitValidationError, .invalidChainProof("txHash"))
        }

        XCTAssertThrowsError(try MeshChainProof(
            provider: "demo-provider",
            chainId: "demo-chain",
            network: "demo-testnet",
            proofType: .paymentExecution,
            status: .failed,
            presentationState: .attemptedFailed,
            requestHash: MeshPayloadHash(value: String(repeating: "a", count: 64)),
            requestNonce: "nonce-chain-proof-failed-tx-invalid",
            policyId: "policy-hermes-dailymart-okrw-v1",
            policyHash: MeshPayloadHash(value: String(repeating: "b", count: 64)),
            walletAddress: "wallet1",
            amount: Decimal(4_900),
            asset: "OKRW",
            recipient: "merchant1",
            anchoringReference: "anchor-001",
            txHash: "0xfailednotconfirmed",
            errorCode: "payment_execution_failed",
            errorMessage: "provider failed before confirmation",
            submittedAt: "2026-05-31T00:00:23Z"
        )) { error in
            XCTAssertEqual(error as? MeshKitValidationError, .invalidChainProof("txHash"))
        }

        XCTAssertThrowsError(try MeshChainProof(
            provider: "demo-provider",
            chainId: "demo-chain",
            network: "demo-testnet",
            proofType: .requestAnchor,
            status: .pending,
            presentationState: .submittedNotFinal,
            requestHash: MeshPayloadHash(value: "not-a-sha256"),
            requestNonce: "nonce-chain-proof-hash-invalid",
            policyId: "policy-hermes-dailymart-okrw-v1",
            policyHash: MeshPayloadHash(value: String(repeating: "b", count: 64)),
            walletAddress: "wallet1",
            amount: Decimal(4_900),
            asset: "OKRW",
            recipient: "merchant1",
            anchoringReference: "anchor-001",
            submittedAt: "2026-05-31T00:00:23Z"
        )) { error in
            XCTAssertEqual(error as? MeshKitValidationError, .invalidChainProof("requestHash.value"))
        }

    }

    func testAgentWalletIdentityRejectsUnstableOrInvalidContractFields() throws {
        XCTAssertThrowsError(try MeshAgentWalletIdentity(
            walletId: " wallet-with-padding ",
            agentId: "agent.hermes-chat.daily-mart",
            walletAddress: "maroo1dailyMartAgentWallet",
            providerMetadata: sampleAgentWalletProviderMetadata(),
            signingBoundary: .localSignature
        )) { error in
            XCTAssertEqual(error as? MeshKitValidationError, .invalidAgentWalletIdentity("walletId"))
        }

        XCTAssertThrowsError(try MeshAgentWalletIdentity(
            walletId: "wallet-hermes-dailymart-okrw-v1",
            agentId: "agent.hermes\nforged",
            walletAddress: "maroo1dailyMartAgentWallet",
            providerMetadata: sampleAgentWalletProviderMetadata(),
            signingBoundary: .localSignature
        )) { error in
            XCTAssertEqual(error as? MeshKitValidationError, .invalidAgentWalletIdentity("agentId"))
        }

        XCTAssertThrowsError(try MeshAgentWalletProviderMetadata(
            provider: "maroo",
            network: "maroo-testnet",
            chainId: "maroo-testnet-1",
            rpcEndpoint: try XCTUnwrap(URL(string: "file:///tmp/rpc"))
        )) { error in
            XCTAssertEqual(error as? MeshKitValidationError, .invalidAgentWalletIdentity("rpcEndpoint"))
        }
    }

    func testChainProviderIdentityNormalizesNetworkMetadataContract() throws {
        let identity = try MeshChainProviderIdentity(
            providerName: " MAROO ",
            networkIdentity: " Maroo-Testnet ",
            chainId: " MAROO-Testnet-1 ",
            rpcEndpoint: try XCTUnwrap(URL(string: "HTTPS://RPC-Testnet.Example.Invalid/")),
            explorerBaseURL: try XCTUnwrap(URL(string: "HTTPS://Explorer-Testnet.Example.Invalid/"))
        )

        XCTAssertEqual(identity.provider, "maroo")
        XCTAssertEqual(identity.network, "maroo-testnet")
        XCTAssertEqual(identity.chainId, "maroo-testnet-1")
        XCTAssertEqual(identity.rpcEndpoint.absoluteString, "https://rpc-testnet.example.invalid")
        XCTAssertEqual(identity.explorerBaseUrl?.absoluteString, "https://explorer-testnet.example.invalid")
    }

    func testChainProviderIdentityCodableUsesProviderNeutralContractKeys() throws {
        let identity = try MeshChainProviderIdentity(
            providerName: "maroo",
            networkIdentity: "maroo-testnet",
            chainId: "maroo-testnet-1",
            rpcEndpoint: try XCTUnwrap(URL(string: "https://rpc-testnet.example.invalid")),
            explorerBaseURL: try XCTUnwrap(URL(string: "https://explorer-testnet.example.invalid"))
        )

        let data = try JSONEncoder().encode(identity)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(object["provider"] as? String, "maroo")
        XCTAssertEqual(object["network"] as? String, "maroo-testnet")
        XCTAssertEqual(object["chainId"] as? String, "maroo-testnet-1")
        XCTAssertEqual(object["rpcEndpoint"] as? String, "https://rpc-testnet.example.invalid")
        XCTAssertEqual(object["explorerBaseUrl"] as? String, "https://explorer-testnet.example.invalid")
        XCTAssertNil(object["providerName"])
        XCTAssertNil(object["networkIdentity"])
        XCTAssertNil(object["explorerBaseURL"])

        let decoded = try JSONDecoder().decode(MeshChainProviderIdentity.self, from: data)
        XCTAssertEqual(decoded, identity)
    }

    func testChainProviderIdentityDecodesLegacyFieldNamesIntoNormalizedContract() throws {
        let data = Data("""
        {
          "providerName": " MAROO ",
          "networkIdentity": " Maroo-Testnet ",
          "chainId": " MAROO-Testnet-1 ",
          "rpcEndpoint": "HTTPS://RPC-Testnet.Example.Invalid/",
          "explorerBaseURL": "HTTPS://Explorer-Testnet.Example.Invalid/"
        }
        """.utf8)

        let identity = try JSONDecoder().decode(MeshChainProviderIdentity.self, from: data)
        XCTAssertEqual(identity.provider, "maroo")
        XCTAssertEqual(identity.network, "maroo-testnet")
        XCTAssertEqual(identity.chainId, "maroo-testnet-1")
        XCTAssertEqual(identity.rpcEndpoint.absoluteString, "https://rpc-testnet.example.invalid")
        XCTAssertEqual(identity.explorerBaseUrl?.absoluteString, "https://explorer-testnet.example.invalid")
    }

    func testChainProviderIdentityRejectsInvalidContractFields() throws {
        XCTAssertThrowsError(try MeshChainProviderIdentity(
            providerName: "maroo\nforged",
            networkIdentity: "maroo-testnet",
            chainId: "maroo-testnet-1",
            rpcEndpoint: try XCTUnwrap(URL(string: "https://rpc-testnet.example.invalid")),
            explorerBaseURL: nil
        )) { error in
            XCTAssertEqual(error as? MeshKitValidationError, .invalidChainProviderIdentity("providerName"))
        }

        XCTAssertThrowsError(try MeshChainProviderIdentity(
            providerName: "maroo",
            networkIdentity: "maroo-testnet",
            chainId: " ",
            rpcEndpoint: try XCTUnwrap(URL(string: "https://rpc-testnet.example.invalid")),
            explorerBaseURL: nil
        )) { error in
            XCTAssertEqual(error as? MeshKitValidationError, .invalidChainProviderIdentity("chainId"))
        }

        XCTAssertThrowsError(try MeshChainProviderIdentity(
            providerName: "maroo",
            networkIdentity: "maroo-testnet",
            chainId: "maroo-testnet-1",
            rpcEndpoint: try XCTUnwrap(URL(string: "file:///tmp/rpc")),
            explorerBaseURL: nil
        )) { error in
            XCTAssertEqual(error as? MeshKitValidationError, .invalidChainProviderIdentity("rpcEndpoint"))
        }
    }

    func testChainProviderExplorerURLRequiresConfiguredBaseAndSafeHash() throws {
        let identity = try MeshChainProviderIdentity(
            providerName: "demo-provider",
            networkIdentity: "demo-testnet",
            chainId: "demo-chain",
            rpcEndpoint: try XCTUnwrap(URL(string: "https://rpc.example.invalid")),
            explorerBaseURL: nil
        )

        XCTAssertThrowsError(try identity.explorerURL(transactionHash: "0xabc123")) { error in
            XCTAssertEqual(error as? MeshKitValidationError, .chainProviderExplorerUnavailable)
        }

        let explorerIdentity = try MeshChainProviderIdentity(
            providerName: "demo-provider",
            networkIdentity: "demo-testnet",
            chainId: "demo-chain",
            rpcEndpoint: try XCTUnwrap(URL(string: "https://rpc.example.invalid")),
            explorerBaseURL: try XCTUnwrap(URL(string: "https://explorer.example.invalid"))
        )
        XCTAssertThrowsError(try explorerIdentity.explorerURL(transactionHash: "0xabc\nforged")) { error in
            XCTAssertEqual(error as? MeshKitValidationError, .invalidChainProviderIdentity("transactionHash"))
        }
        XCTAssertThrowsError(try explorerIdentity.explorerURL(transactionHash: "0xabc123?view=raw")) { error in
            XCTAssertEqual(error as? MeshKitValidationError, .invalidChainProviderIdentity("transactionHash"))
        }
        XCTAssertThrowsError(try explorerIdentity.explorerURL(transactionHash: "0xabc123/receipt")) { error in
            XCTAssertEqual(error as? MeshKitValidationError, .invalidChainProviderIdentity("transactionHash"))
        }
    }

    func testChainProviderConstructsExplorerURLForTransactionEntity() throws {
        let provider = try StaticChainProvider(
            identity: try sampleChainProviderIdentity(),
            capabilities: [.loadProviderConfiguration, .constructExplorerURL],
            observedNetwork: "maroo-testnet",
            healthStatus: .healthy
        )

        let interface: any MeshChainProvider = provider
        let entityURL = try interface.explorerURL(for: .transaction(hash: "0xabc123"))
        let transactionHashURL = try interface.explorerURL(transactionHash: "0xabc123")

        XCTAssertEqual(entityURL.absoluteString, "https://explorer-testnet.example.invalid/tx/0xabc123")
        XCTAssertEqual(transactionHashURL, entityURL)
    }

    func testChainProviderConstructsTransactionExplorerURLsPerNetwork() throws {
        let cases: [(identity: MeshChainProviderIdentity, transactionHash: String, expectedURL: String)] = [
            (
                try MeshMarooTestnetChainProvider().identity,
                "0x" + String(repeating: "a", count: 64),
                "https://explorer-testnet.maroo.io/tx/0x\(String(repeating: "a", count: 64))"
            ),
            (
                try MeshChainProviderIdentity(
                    providerName: "agentos-demo",
                    networkIdentity: "demo-rollup-testnet",
                    chainId: "demo-rollup-1",
                    rpcEndpoint: try XCTUnwrap(URL(string: "https://rpc.demo-rollup.example.invalid")),
                    explorerBaseURL: try XCTUnwrap(URL(string: "https://explorer.demo-rollup.example.invalid/network/demo-rollup"))
                ),
                "demoTx987654321",
                "https://explorer.demo-rollup.example.invalid/network/demo-rollup/tx/demoTx987654321"
            )
        ]

        for testCase in cases {
            let provider = StaticChainProvider(
                identity: testCase.identity,
                capabilities: [.loadProviderConfiguration, .constructExplorerURL],
                observedNetwork: testCase.identity.network,
                healthStatus: .healthy
            )

            XCTAssertEqual(
                try provider.explorerURL(transactionHash: testCase.transactionHash).absoluteString,
                testCase.expectedURL
            )
            XCTAssertEqual(
                try testCase.identity.explorerURL(for: .transaction(hash: testCase.transactionHash)).absoluteString,
                testCase.expectedURL
            )
        }
    }

    func testChainProviderConstructsExplorerURLForAccountAndAddressEntities() throws {
        let provider = try StaticChainProvider(
            identity: try sampleChainProviderIdentity(),
            capabilities: [.loadProviderConfiguration, .constructExplorerURL],
            observedNetwork: "maroo-testnet",
            healthStatus: .healthy
        )

        let interface: any MeshChainProvider = provider
        let accountURL = try interface.explorerURL(for: .account(address: "maroo1dailyMartAgentWallet"))
        let accountHelperURL = try interface.explorerURL(accountAddress: "maroo1dailyMartAgentWallet")
        let addressURL = try interface.explorerURL(for: .address(value: "maroo1customerAddress001"))
        let addressHelperURL = try interface.explorerURL(address: "maroo1customerAddress001")

        XCTAssertEqual(
            accountURL.absoluteString,
            "https://explorer-testnet.example.invalid/account/maroo1dailyMartAgentWallet"
        )
        XCTAssertEqual(accountHelperURL, accountURL)
        XCTAssertEqual(
            addressURL.absoluteString,
            "https://explorer-testnet.example.invalid/address/maroo1customerAddress001"
        )
        XCTAssertEqual(addressHelperURL, addressURL)
    }

    func testChainProviderConstructsAddressExplorerURLsPerNetwork() throws {
        let cases: [(
            identity: MeshChainProviderIdentity,
            accountAddress: String,
            address: String,
            expectedAccountURL: String,
            expectedAddressURL: String
        )] = [
            (
                try MeshMarooTestnetChainProvider().identity,
                "maroo1dailyMartAgentWallet",
                "maroo1customerAddress001",
                "https://explorer-testnet.maroo.io/account/maroo1dailyMartAgentWallet",
                "https://explorer-testnet.maroo.io/address/maroo1customerAddress001"
            ),
            (
                try MeshChainProviderIdentity(
                    providerName: "agentos-demo",
                    networkIdentity: "demo-rollup-testnet",
                    chainId: "demo-rollup-1",
                    rpcEndpoint: try XCTUnwrap(URL(string: "https://rpc.demo-rollup.example.invalid")),
                    explorerBaseURL: try XCTUnwrap(URL(string: "https://explorer.demo-rollup.example.invalid/network/demo-rollup"))
                ),
                "demoAccount777",
                "demoAddress888",
                "https://explorer.demo-rollup.example.invalid/network/demo-rollup/account/demoAccount777",
                "https://explorer.demo-rollup.example.invalid/network/demo-rollup/address/demoAddress888"
            )
        ]

        for testCase in cases {
            let provider = StaticChainProvider(
                identity: testCase.identity,
                capabilities: [.loadProviderConfiguration, .constructExplorerURL],
                observedNetwork: testCase.identity.network,
                healthStatus: .healthy
            )

            XCTAssertEqual(
                try provider.explorerURL(accountAddress: testCase.accountAddress).absoluteString,
                testCase.expectedAccountURL
            )
            XCTAssertEqual(
                try provider.explorerURL(address: testCase.address).absoluteString,
                testCase.expectedAddressURL
            )
            XCTAssertEqual(
                try testCase.identity.explorerURL(for: .account(address: testCase.accountAddress)).absoluteString,
                testCase.expectedAccountURL
            )
            XCTAssertEqual(
                try testCase.identity.explorerURL(for: .address(value: testCase.address)).absoluteString,
                testCase.expectedAddressURL
            )
        }
    }

    func testChainProviderConstructsExplorerURLForBlockEntity() throws {
        let provider = try StaticChainProvider(
            identity: try sampleChainProviderIdentity(),
            capabilities: [.loadProviderConfiguration, .constructExplorerURL],
            observedNetwork: "maroo-testnet",
            healthStatus: .healthy
        )

        let interface: any MeshChainProvider = provider
        let blockURL = try interface.explorerURL(for: .block(value: "123456"))
        let blockHelperURL = try interface.explorerURL(block: "123456")

        XCTAssertEqual(blockURL.absoluteString, "https://explorer-testnet.example.invalid/block/123456")
        XCTAssertEqual(blockHelperURL, blockURL)
    }

    func testChainProviderBlockExplorerURLRequiresSafeIdentifier() throws {
        let provider = try StaticChainProvider(
            identity: try sampleChainProviderIdentity(),
            capabilities: [.loadProviderConfiguration, .constructExplorerURL],
            observedNetwork: "maroo-testnet",
            healthStatus: .healthy
        )

        XCTAssertThrowsError(try provider.explorerURL(for: .block(value: "123\n456"))) { error in
            XCTAssertEqual(error as? MeshKitValidationError, .invalidChainProviderIdentity("block"))
        }
    }

    func testChainProviderExplorerURLRequiresConstructCapability() throws {
        let provider = try StaticChainProvider(
            identity: try sampleChainProviderIdentity(),
            capabilities: [.loadProviderConfiguration],
            observedNetwork: "maroo-testnet",
            healthStatus: .healthy
        )

        XCTAssertThrowsError(try provider.explorerURL(for: .transaction(hash: "0xabc123"))) { error in
            XCTAssertEqual(error as? MeshKitValidationError, .unsupportedCapability)
        }
    }

    func testChainProviderConfigurationDiscoversConnectionCapabilities() throws {
        let identity = try sampleChainProviderIdentity()
        let configuration = try MeshChainProviderConfiguration(
            identity: identity,
            capabilities: [.checkHealth, .identifyNetwork, .loadProviderConfiguration, .identifyNetwork]
        )

        XCTAssertEqual(configuration.identity, identity)
        XCTAssertEqual(configuration.capabilities, [.checkHealth, .identifyNetwork, .loadProviderConfiguration])
        XCTAssertTrue(configuration.supports(.checkHealth))
        XCTAssertFalse(configuration.supports(.constructExplorerURL))
        XCTAssertNoThrow(try configuration.require(.identifyNetwork))
        XCTAssertThrowsError(try configuration.require(.constructExplorerURL)) { error in
            XCTAssertEqual(error as? MeshKitValidationError, .unsupportedCapability)
        }
    }

    func testChainProviderNetworkIdentityCapabilityIsProviderNeutral() throws {
        let endpointConfiguration = try MeshChainProviderEndpointConfiguration(
            rpcEndpoint: try XCTUnwrap(URL(string: "HTTPS://RPC.AgentOS.Example.Invalid/")),
            explorerBaseURL: try XCTUnwrap(URL(string: "HTTPS://Explorer.AgentOS.Example.Invalid/"))
        )
        let identity = try MeshChainProviderIdentity(
            providerName: "AgentOS-Demo",
            networkIdentity: "Demo-Testnet",
            chainId: "Demo-Chain-1",
            endpointConfiguration: endpointConfiguration
        )
        let provider = StaticChainProvider(
            identity: identity,
            capabilities: [.loadProviderConfiguration, .identifyNetwork],
            observedNetwork: "demo-testnet",
            healthStatus: .degraded
        )

        let networkIdentity = try provider.identifyNetwork()
        let encoded = try JSONEncoder().encode(networkIdentity)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])

        XCTAssertEqual(networkIdentity.provider, "agentos-demo")
        XCTAssertEqual(networkIdentity.network, "demo-testnet")
        XCTAssertEqual(networkIdentity.chainId, "demo-chain-1")
        XCTAssertEqual(networkIdentity.rpcEndpoint.absoluteString, "https://rpc.agentos.example.invalid")
        XCTAssertEqual(networkIdentity.explorerBaseUrl?.absoluteString, "https://explorer.agentos.example.invalid")
        XCTAssertEqual(object["provider"] as? String, "agentos-demo")
        XCTAssertEqual(object["network"] as? String, "demo-testnet")
        XCTAssertEqual(object["chainId"] as? String, "demo-chain-1")
        XCTAssertNil(object["maroo"])
    }

    func testChainProviderNetworkIdentityRequiresAdvertisedCapability() throws {
        let provider = StaticChainProvider(
            identity: try sampleChainProviderIdentity(),
            capabilities: [.loadProviderConfiguration],
            observedNetwork: "maroo-testnet",
            healthStatus: .degraded
        )

        XCTAssertThrowsError(try provider.identifyNetwork()) { error in
            XCTAssertEqual(error as? MeshKitValidationError, .unsupportedCapability)
        }
    }

    func testChainProviderEndpointConfigurationResolvesConfiguredRPCEndpoint() throws {
        let defaults = try MeshChainProviderEndpointConfiguration(
            rpcEndpoint: try XCTUnwrap(URL(string: "HTTPS://RPC.Default.Example.Invalid/")),
            explorerBaseURL: try XCTUnwrap(URL(string: "HTTPS://Explorer.Default.Example.Invalid/"))
        )

        let resolved = try MeshChainProviderEndpointConfiguration.resolved(
            defaults: defaults,
            rpcEndpoint: try XCTUnwrap(URL(string: "HTTPS://RPC.Configured.Example.Invalid/"))
        )

        XCTAssertEqual(defaults.rpcEndpoint.absoluteString, "https://rpc.default.example.invalid")
        XCTAssertEqual(defaults.explorerBaseUrl?.absoluteString, "https://explorer.default.example.invalid")
        XCTAssertEqual(resolved.rpcEndpoint.absoluteString, "https://rpc.configured.example.invalid")
        XCTAssertEqual(resolved.explorerBaseUrl?.absoluteString, "https://explorer.default.example.invalid")
    }

    func testChainProviderEndpointConfigurationRejectsInvalidConfiguredEndpoint() throws {
        let defaults = try MeshChainProviderEndpointConfiguration(
            rpcEndpoint: try XCTUnwrap(URL(string: "https://rpc.default.example.invalid")),
            explorerBaseURL: nil
        )

        XCTAssertThrowsError(try MeshChainProviderEndpointConfiguration.resolved(
            defaults: defaults,
            rpcEndpoint: try XCTUnwrap(URL(string: "file:///tmp/rpc"))
        )) { error in
            XCTAssertEqual(error as? MeshKitValidationError, .invalidChainProviderIdentity("rpcEndpoint"))
        }
    }

    func testChainProviderEndpointConfigurationRejectsMissingConfiguredRPCEndpoint() throws {
        XCTAssertThrowsError(try MeshChainProviderEndpointConfiguration.configured(
            rpcEndpoint: nil,
            explorerBaseURL: try XCTUnwrap(URL(string: "https://explorer.agentos.example.invalid"))
        )) { error in
            XCTAssertEqual(error as? MeshKitValidationError, .invalidChainProviderIdentity("rpcEndpoint"))
        }
    }

    func testChainProviderConfigurationExposesResolvedEndpointProviderNeutrally() throws {
        let endpointConfiguration = try MeshChainProviderEndpointConfiguration(
            rpcEndpoint: try XCTUnwrap(URL(string: "HTTPS://RPC.AgentOS.Example.Invalid/")),
            explorerBaseURL: try XCTUnwrap(URL(string: "HTTPS://Explorer.AgentOS.Example.Invalid/"))
        )
        let identity = try MeshChainProviderIdentity(
            providerName: "agentos-demo",
            networkIdentity: "demo-testnet",
            chainId: "demo-chain-1",
            endpointConfiguration: endpointConfiguration
        )
        let configuration = try MeshChainProviderConfiguration(
            identity: identity,
            capabilities: [.loadProviderConfiguration, .identifyNetwork]
        )

        XCTAssertEqual(configuration.endpointConfiguration.rpcEndpoint.absoluteString, "https://rpc.agentos.example.invalid")
        XCTAssertEqual(configuration.endpointConfiguration.explorerBaseUrl?.absoluteString, "https://explorer.agentos.example.invalid")
        XCTAssertEqual(configuration.identity.rpcEndpoint, configuration.endpointConfiguration.rpcEndpoint)
    }

    func testMarooTestnetChainProviderExposesCanonicalChainIdMetadata() throws {
        let provider = try MeshMarooTestnetChainProvider()

        let configuration = try provider.loadProviderConfiguration()
        let identity = try provider.identifyNetwork()
        let metadata = provider.metadata

        XCTAssertEqual(MeshMarooTestnetChainProvider.chainId, "maroo-testnet-1")
        XCTAssertEqual(configuration.identity.provider, "maroo")
        XCTAssertEqual(configuration.identity.network, "maroo-testnet")
        XCTAssertEqual(configuration.identity.chainId, "maroo-testnet-1")
        XCTAssertEqual(configuration.identity.rpcEndpoint.absoluteString, "https://rpc-testnet.maroo.io")
        XCTAssertEqual(configuration.identity.explorerBaseUrl?.absoluteString, "https://explorer-testnet.maroo.io")
        XCTAssertEqual(identity, configuration.identity)
        XCTAssertEqual(metadata.provider, "maroo")
        XCTAssertEqual(metadata.network, "maroo-testnet")
        XCTAssertEqual(metadata.chainId, "maroo-testnet-1")
        XCTAssertEqual(metadata.providerName, "maroo")
        XCTAssertEqual(metadata.networkIdentity, "maroo-testnet")
        XCTAssertTrue(configuration.supports(.constructExplorerURL))
        XCTAssertTrue(configuration.supports(.identifyNetwork))
        XCTAssertTrue(configuration.supports(.loadProviderConfiguration))
    }

    func testChainProviderMetadataExposesSupportedMarooAdapterValues() throws {
        let provider = try MeshMarooTestnetChainProvider()

        let supportedAdapterMetadata = provider.metadata

        XCTAssertEqual(supportedAdapterMetadata.providerName, MeshMarooTestnetChainProvider.providerName)
        XCTAssertEqual(supportedAdapterMetadata.networkIdentity, MeshMarooTestnetChainProvider.networkIdentity)
        XCTAssertEqual(supportedAdapterMetadata.chainId, MeshMarooTestnetChainProvider.chainId)
        XCTAssertEqual(supportedAdapterMetadata.provider, "maroo")
        XCTAssertEqual(supportedAdapterMetadata.network, "maroo-testnet")
        XCTAssertEqual(supportedAdapterMetadata.chainId, "maroo-testnet-1")
    }

    func testMarooTestnetChainProviderHandlesEndpointNormalizationAndExplorerURLs() throws {
        let provider = try MeshMarooTestnetChainProvider(
            rpcEndpoint: try XCTUnwrap(URL(string: "HTTPS://RPC-Testnet.Maroo.IO/")),
            explorerBaseURL: try XCTUnwrap(URL(string: "HTTPS://Explorer-Testnet.Maroo.IO/")),
            capabilities: [.loadProviderConfiguration, .identifyNetwork, .constructExplorerURL, .constructExplorerURL]
        )

        let configuration = try provider.loadProviderConfiguration()
        let explorerURL = try configuration.identity.explorerURL(transactionHash: "0xabc123")
        let providerExplorerURL = try provider.explorerURL(for: .transaction(hash: "0xabc123"))

        XCTAssertEqual(configuration.identity.chainId, "maroo-testnet-1")
        XCTAssertEqual(configuration.identity.rpcEndpoint.absoluteString, "https://rpc-testnet.maroo.io")
        XCTAssertEqual(configuration.identity.explorerBaseUrl?.absoluteString, "https://explorer-testnet.maroo.io")
        XCTAssertEqual(configuration.capabilities, [.constructExplorerURL, .identifyNetwork, .loadProviderConfiguration])
        XCTAssertEqual(explorerURL.absoluteString, "https://explorer-testnet.maroo.io/tx/0xabc123")
        XCTAssertEqual(providerExplorerURL, explorerURL)
    }

    func testMarooTestnetChainProviderResolvesConfiguredEndpointIntoRuntimeReports() async throws {
        let provider = try MeshMarooTestnetChainProvider(
            rpcEndpoint: try XCTUnwrap(URL(string: "HTTPS://RPC-Override.Maroo.Example.Invalid/")),
            explorerBaseURL: try XCTUnwrap(URL(string: "HTTPS://Explorer-Override.Maroo.Example.Invalid/")),
            observedNetwork: "maroo-testnet",
            healthStatus: .degraded,
            healthMessage: "configured maroo rpc endpoint not checked"
        )

        let configuration = try provider.loadProviderConfiguration()
        let connection = try await provider.connect(checkedAt: "2026-05-31T00:00:00Z")
        let health = try await provider.checkHealth(checkedAt: "2026-05-31T00:00:00Z")

        XCTAssertEqual(configuration.endpointConfiguration.rpcEndpoint.absoluteString, "https://rpc-override.maroo.example.invalid")
        XCTAssertEqual(connection.rpcEndpoint.absoluteString, "https://rpc-override.maroo.example.invalid")
        XCTAssertEqual(health.rpcEndpoint.absoluteString, "https://rpc-override.maroo.example.invalid")
        XCTAssertEqual(configuration.endpointConfiguration.explorerBaseUrl?.absoluteString, "https://explorer-override.maroo.example.invalid")
        XCTAssertEqual(health.message, "configured maroo rpc endpoint not checked")
    }

    func testMarooTestnetChainProviderRejectsMissingConfiguredRPCEndpoint() throws {
        XCTAssertThrowsError(try MeshMarooTestnetChainProvider(configuredRPCEndpoint: nil)) { error in
            XCTAssertEqual(error as? MeshKitValidationError, .invalidChainProviderIdentity("rpcEndpoint"))
        }
    }

    func testMarooTestnetChainProviderRejectsInvalidConfiguredRPCEndpointFragment() throws {
        XCTAssertThrowsError(try MeshMarooTestnetChainProvider(
            configuredRPCEndpoint: try XCTUnwrap(URL(string: "https://rpc-testnet.maroo.io#not-sent-to-rpc"))
        )) { error in
            XCTAssertEqual(error as? MeshKitValidationError, .invalidChainProviderIdentity("rpcEndpoint"))
        }
    }

    func testMarooTestnetChainProviderReportsConfiguredConnectionWithoutLiveChainProof() async throws {
        let provider = try MeshMarooTestnetChainProvider(observedNetwork: " Maroo-Testnet ")

        let connection = try await provider.connect(checkedAt: "2026-05-31T00:00:00Z")
        let health = try await provider.checkHealth(checkedAt: "2026-05-31T00:00:00Z")

        XCTAssertEqual(connection.identity.chainId, "maroo-testnet-1")
        XCTAssertEqual(connection.status, .configured)
        XCTAssertEqual(connection.observedNetwork, "maroo-testnet")
        XCTAssertEqual(connection.rpcEndpoint.absoluteString, "https://rpc-testnet.maroo.io")
        XCTAssertEqual(health.identity.chainId, "maroo-testnet-1")
        XCTAssertEqual(health.status, .unavailable)
        XCTAssertEqual(health.message, "maroo testnet rpc not checked")
        XCTAssertNil(health.latestBlockHeight)
        XCTAssertNil(health.latencyMilliseconds)
    }

    func testChainProviderProtocolConnectsAndReportsObservedNetwork() async throws {
        let provider = try StaticChainProvider(
            identity: try sampleChainProviderIdentity(),
            capabilities: [.loadProviderConfiguration, .identifyNetwork, .checkHealth],
            observedNetwork: "maroo-testnet",
            healthStatus: .healthy
        )

        let configuration = try provider.loadProviderConfiguration()
        let network = try provider.identifyNetwork()
        let connection = try await provider.connect(checkedAt: "2026-05-31T00:00:00Z")

        XCTAssertEqual(configuration.identity.provider, "maroo")
        XCTAssertEqual(network.network, "maroo-testnet")
        XCTAssertEqual(connection.status, .connected)
        XCTAssertEqual(connection.rpcEndpoint.absoluteString, "https://rpc-testnet.example.invalid")
        XCTAssertEqual(connection.observedNetwork, "maroo-testnet")
        XCTAssertTrue(connection.capabilities.contains(.checkHealth))
    }

    func testChainProviderHealthRequiresDiscoveredHealthCapability() async throws {
        let provider = try StaticChainProvider(
            identity: try sampleChainProviderIdentity(),
            capabilities: [.loadProviderConfiguration, .identifyNetwork],
            observedNetwork: nil,
            healthStatus: .healthy
        )

        do {
            _ = try await provider.checkHealth(checkedAt: "2026-05-31T00:00:00Z")
            XCTFail("Expected health check to require advertised checkHealth capability")
        } catch {
            XCTAssertEqual(error as? MeshKitValidationError, .unsupportedCapability)
        }
    }

    func testChainProviderHealthSerializesProviderNeutralStatusContract() async throws {
        let provider = try StaticChainProvider(
            identity: try sampleChainProviderIdentity(),
            capabilities: [.loadProviderConfiguration, .identifyNetwork, .checkHealth],
            observedNetwork: nil,
            healthStatus: .healthy
        )

        let health = try await provider.checkHealth(checkedAt: "2026-05-31T00:00:00Z")
        XCTAssertEqual(health.status, .healthy)
        XCTAssertEqual(health.latencyMilliseconds, 42)
        XCTAssertEqual(health.latestBlockHeight, 123_456)

        let data = try JSONEncoder().encode(health)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual((object["identity"] as? [String: Any])?["provider"] as? String, "maroo")
        XCTAssertEqual(object["status"] as? String, "healthy")
        XCTAssertEqual(object["rpcEndpoint"] as? String, "https://rpc-testnet.example.invalid")
        XCTAssertEqual(object["checkedAt"] as? String, "2026-05-31T00:00:00Z")
        XCTAssertEqual(object["latencyMilliseconds"] as? Int, 42)
        XCTAssertEqual(object["latestBlockHeight"] as? Int, 123_456)
        XCTAssertNil(object["providerName"])

        let decoded = try JSONDecoder().decode(MeshChainProviderHealth.self, from: data)
        XCTAssertEqual(decoded, health)
    }

    func testChainProviderStatusInspectionCombinesConnectionAndHealthProviderNeutrally() async throws {
        let provider = try StaticChainProvider(
            identity: try sampleChainProviderIdentity(),
            capabilities: [.loadProviderConfiguration, .identifyNetwork, .checkHealth],
            observedNetwork: "maroo-testnet",
            healthStatus: .healthy
        )

        let inspection = try await MeshChainProviderStatusInspectionModule(provider: provider)
            .inspectStatus(checkedAt: "2026-05-31T00:00:00Z")

        XCTAssertEqual(inspection.configuration.identity.provider, "maroo")
        XCTAssertEqual(inspection.connection.status, .connected)
        XCTAssertEqual(inspection.connection.observedNetwork, "maroo-testnet")
        XCTAssertEqual(inspection.health.status, .healthy)
        XCTAssertEqual(inspection.health.latestBlockHeight, 123_456)
        XCTAssertEqual(inspection.connection.identity, inspection.configuration.identity)
        XCTAssertEqual(inspection.health.identity, inspection.configuration.identity)

        let data = try JSONEncoder().encode(inspection)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual((object["configuration"] as? [String: Any])?["capabilities"] as? [String], [
            "checkHealth",
            "identifyNetwork",
            "loadProviderConfiguration"
        ])
        XCTAssertEqual((object["connection"] as? [String: Any])?["status"] as? String, "connected")
        XCTAssertEqual((object["health"] as? [String: Any])?["status"] as? String, "healthy")
    }

    func testChainProviderStatusInspectionRequiresHealthCapabilityBeforeInspection() async throws {
        let provider = try StaticChainProvider(
            identity: try sampleChainProviderIdentity(),
            capabilities: [.loadProviderConfiguration, .identifyNetwork],
            observedNetwork: "maroo-testnet",
            healthStatus: .healthy
        )

        do {
            _ = try await MeshChainProviderStatusInspectionModule(provider: provider)
                .inspectStatus(checkedAt: "2026-05-31T00:00:00Z")
            XCTFail("Expected status inspection to require health capability")
        } catch {
            XCTAssertEqual(error as? MeshKitValidationError, .unsupportedCapability)
        }
    }

    func testChainProviderTransactionLookupSerializesProviderNeutralProofReference() async throws {
        let identity = try MeshChainProviderIdentity(
            providerName: "AgentOS-Demo",
            networkIdentity: "Demo-Testnet",
            chainId: "Demo-Chain-1",
            rpcEndpoint: try XCTUnwrap(URL(string: "https://rpc.agentos.example.invalid")),
            explorerBaseURL: try XCTUnwrap(URL(string: "https://explorer.agentos.example.invalid"))
        )
        let reference = try MeshChainProofReference(
            identity: identity,
            referenceType: .transaction,
            value: "0xabc123"
        )
        let lookup = try MeshChainTransactionLookup(
            identity: identity,
            reference: reference,
            status: .confirmed,
            blockHeight: 123,
            confirmations: 2,
            checkedAt: "2026-05-31T00:00:00Z",
            providerExtensions: [
                "agentos-demo": [
                    "lookupMode": "fixture"
                ]
            ]
        )

        let data = try JSONEncoder().encode(lookup)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])

        XCTAssertEqual((object["identity"] as? [String: Any])?["provider"] as? String, "agentos-demo")
        XCTAssertEqual((object["reference"] as? [String: Any])?["referenceType"] as? String, "transaction")
        XCTAssertEqual((object["reference"] as? [String: Any])?["canonicalReference"] as? String, reference.canonicalReference)
        XCTAssertEqual(object["status"] as? String, "confirmed")
        XCTAssertEqual(object["transactionHash"] as? String, "0xabc123")
        XCTAssertEqual(object["blockHeight"] as? Int, 123)
        XCTAssertEqual(object["confirmations"] as? Int, 2)
        XCTAssertNil(object["maroo"])
    }

    func testChainProviderProofLookupRequiresProofReferenceAndMatchingIdentity() throws {
        let identity = try sampleChainProviderIdentity()
        let transactionReference = try MeshChainProofReference(
            identity: identity,
            referenceType: .transaction,
            value: "0xabc123"
        )

        XCTAssertThrowsError(try MeshChainProofLookup(
            identity: identity,
            reference: transactionReference,
            status: .pending,
            checkedAt: "2026-05-31T00:00:00Z"
        )) { error in
            XCTAssertEqual(error as? MeshKitValidationError, .invalidChainProof("referenceType"))
        }

        let proofReference = try MeshChainProofReference(
            identity: identity,
            referenceType: .proof,
            value: "anchor-ios-grocery-test-001"
        )
        let otherIdentity = try MeshChainProviderIdentity(
            providerName: "other-provider",
            networkIdentity: "other-testnet",
            chainId: "other-chain-1",
            rpcEndpoint: try XCTUnwrap(URL(string: "https://rpc.other.example.invalid")),
            explorerBaseURL: nil
        )

        XCTAssertThrowsError(try MeshChainProofLookup(
            identity: otherIdentity,
            reference: proofReference,
            status: .pending,
            checkedAt: "2026-05-31T00:00:00Z"
        )) { error in
            XCTAssertEqual(error as? MeshKitValidationError, .signatureMismatch("chain proof lookup provider mismatch"))
        }
    }

    func testChainProviderTransactionAndProofLookupRequireAdvertisedCapabilities() async throws {
        let provider = try StaticChainProvider(
            identity: try sampleChainProviderIdentity(),
            capabilities: [.loadProviderConfiguration],
            observedNetwork: "maroo-testnet",
            healthStatus: .degraded
        )
        let transactionReference = try MeshChainProofReference(
            identity: try sampleChainProviderIdentity(),
            referenceType: .transaction,
            value: "0xabc123"
        )
        let proofReference = try MeshChainProofReference(
            identity: try sampleChainProviderIdentity(),
            referenceType: .proof,
            value: "anchor-ios-grocery-test-001"
        )

        do {
            _ = try await provider.lookupTransaction(
                reference: transactionReference,
                checkedAt: "2026-05-31T00:00:00Z"
            )
            XCTFail("Expected transaction lookup to require advertised lookupTransaction capability")
        } catch {
            XCTAssertEqual(error as? MeshKitValidationError, .unsupportedCapability)
        }

        do {
            _ = try await provider.lookupProof(
                reference: proofReference,
                checkedAt: "2026-05-31T00:00:00Z"
            )
            XCTFail("Expected proof lookup to require advertised lookupProof capability")
        } catch {
            XCTAssertEqual(error as? MeshKitValidationError, .unsupportedCapability)
        }
    }

    func testMarooTestnetChainProviderLooksUpTransactionAndProofViaDemoAdapterCapabilities() async throws {
        let provider = try MeshMarooTestnetChainProvider()
        let transactionReference = try MeshChainProofReference(
            identity: provider.identity,
            referenceType: .transaction,
            value: "0xabc123"
        )
        let proofReference = try MeshChainProofReference(
            identity: provider.identity,
            referenceType: .proof,
            value: "maroo-anchor-ios-grocery-test-001"
        )

        let transactionLookup = try await provider.lookupTransaction(
            reference: transactionReference,
            checkedAt: "2026-05-31T00:00:00Z"
        )
        let proofLookup = try await provider.lookupProof(
            reference: proofReference,
            checkedAt: "2026-05-31T00:00:01Z"
        )

        XCTAssertTrue(try provider.loadProviderConfiguration().supports(.lookupTransaction))
        XCTAssertTrue(try provider.loadProviderConfiguration().supports(.lookupProof))
        XCTAssertEqual(transactionLookup.identity.provider, "maroo")
        XCTAssertEqual(transactionLookup.reference, transactionReference)
        XCTAssertEqual(transactionLookup.status, .pending)
        XCTAssertEqual(transactionLookup.transactionHash, "0xabc123")
        XCTAssertEqual(transactionLookup.providerExtensions["maroo"]?["lookupMode"], "configured-demo")
        XCTAssertEqual(proofLookup.identity.provider, "maroo")
        XCTAssertEqual(proofLookup.reference, proofReference)
        XCTAssertEqual(proofLookup.status, .pending)
        XCTAssertEqual(proofLookup.proofType, .requestAnchor)
        XCTAssertEqual(proofLookup.transactionReference?.referenceType, .transaction)
    }

    func testChainProviderHealthRejectsInvalidHealthyContract() throws {
        XCTAssertThrowsError(try MeshChainProviderHealth(
            identity: try sampleChainProviderIdentity(),
            status: .healthy,
            capabilities: [.checkHealth],
            checkedAt: "2026-05-31T00:00:00Z",
            latencyMilliseconds: nil,
            latestBlockHeight: 1
        )) { error in
            XCTAssertEqual(error as? MeshKitValidationError, .invalidChainProviderIdentity("latencyMilliseconds"))
        }

        XCTAssertThrowsError(try MeshChainProviderConnection(
            identity: try sampleChainProviderIdentity(),
            status: .connected,
            capabilities: [.identifyNetwork],
            observedNetwork: "different-testnet",
            checkedAt: "2026-05-31T00:00:00Z"
        )) { error in
            XCTAssertEqual(error as? MeshKitValidationError, .invalidChainProviderIdentity("observedNetwork"))
        }
    }

    func testRequestAnchorMetadataCapturesSignedMCPRequestContract() throws {
        let request = dailyMartRequest(nonce: "nonce-anchor-metadata")
        let metadata = try MeshSignedRequestAnchorMetadata(request: request)

        XCTAssertEqual(metadata.requestId, request.requestId)
        XCTAssertEqual(metadata.nonce, "nonce-anchor-metadata")
        XCTAssertEqual(metadata.callerAppId, "app.hermes-chat")
        XCTAssertEqual(metadata.targetBundleId, "ai.meshkit.sample.dailymart")
        XCTAssertEqual(metadata.capabilityId, "grocery.purchase_essentials")
        XCTAssertEqual(metadata.payloadHash, request.payloadHash)
        XCTAssertEqual(metadata.signature.keyId, "demo-key")
        XCTAssertEqual(metadata.signedRequestHash.algorithm, "sha256")
        XCTAssertEqual(metadata.signedRequestHash.value.count, 64)

        let data = try JSONEncoder().encode(metadata)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(object["requestId"] as? String, request.requestId)
        XCTAssertEqual(object["nonce"] as? String, "nonce-anchor-metadata")
        XCTAssertEqual((object["signature"] as? [String: Any])?["algorithm"] as? String, "Ed25519")
        XCTAssertNotNil(object["signedRequestHash"])

        let decoded = try JSONDecoder().decode(MeshSignedRequestAnchorMetadata.self, from: data)
        XCTAssertEqual(decoded, metadata)
    }

    func testRequestAnchorCanonicalizationBindsCanonicalHashInputToNonceDeterministically() throws {
        let request = MeshRequest(
            requestId: "ios-anchor-canonical-001",
            caller: MeshIdentity(
                appId: "app.hermes-chat",
                installId: "ios-ipad",
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
                "budget_krw": "100",
                "items": "laundry_detergent:1"
            ],
            nonce: "nonce-anchor-canonical-001",
            timestamp: "2026-05-31T00:00:00Z",
            signature: MeshSignature(
                algorithm: "Ed25519",
                keyId: "demo-key",
                value: "signature-anchor-canonical"
            )
        )

        let input = try MeshRequestAnchorCanonicalization.canonicalRequestHashInput(for: request)
        let repeatedInput = try MeshRequestAnchorCanonicalization.canonicalRequestHashInput(for: request)
        let metadata = try MeshSignedRequestAnchorMetadata(request: request)
        let expectedPayloadHash = "b62b8655974f785429e2276c98778b9b61187683a88421a32249039fbf033fd8"
        let expectedSignedRequestHash = "b8d0e455191affd893961f1d39abe5446abfb4adc7f0e0ab62178cd56dff04b3"
        let expectedCanonical = [
            "meshkit-request-anchor/v1",
            "requestId=ios-anchor-canonical-001",
            "nonce=nonce-anchor-canonical-001",
            "timestamp=2026-05-31T00:00:00Z",
            "callerAppId=app.hermes-chat",
            "callerBundleId=ai.meshkit.sample.hermeschat",
            "callerPublicKeyId=demo-key",
            "targetBundleId=ai.meshkit.sample.dailymart",
            "capabilityId=grocery.purchase_essentials",
            "capabilityVersion=1.0",
            "payloadHashAlgorithm=sha256",
            "payloadHashValue=\(expectedPayloadHash)",
            "signatureAlgorithm=Ed25519",
            "signatureKeyId=demo-key",
            "signatureValue=signature-anchor-canonical"
        ].joined(separator: "\n")

        XCTAssertEqual(request.payloadHash.value, expectedPayloadHash)
        XCTAssertEqual(input, repeatedInput)
        XCTAssertEqual(input.version, "meshkit-request-anchor/v1")
        XCTAssertEqual(input.nonce, "nonce-anchor-canonical-001")
        XCTAssertEqual(input.canonicalString, expectedCanonical)
        XCTAssertEqual(input.sha256Hash(), MeshPayloadHash(value: expectedSignedRequestHash))
        XCTAssertEqual(metadata.signedRequestHash, input.sha256Hash())

        let changedNonceRequest = MeshRequest(
            requestId: request.requestId,
            caller: request.caller,
            target: request.target,
            payload: request.payload,
            nonce: "nonce-anchor-canonical-002",
            timestamp: request.timestamp,
            signature: request.signature
        )
        let changedNonceInput = try MeshRequestAnchorCanonicalization.canonicalRequestHashInput(for: changedNonceRequest)

        XCTAssertTrue(changedNonceInput.canonicalString.contains("nonce=nonce-anchor-canonical-002"))
        XCTAssertNotEqual(changedNonceInput.canonicalString, input.canonicalString)
        XCTAssertNotEqual(changedNonceInput.sha256Hash(), input.sha256Hash())
    }

    func testRequestAnchorPayloadBindsPolicyIdAndPolicyHashForSubmission() async throws {
        let provider = try StaticRequestAnchorProvider(
            identity: try sampleChainProviderIdentity(),
            capabilities: [.anchorSignedRequest, .constructExplorerURL],
            status: .submitted
        )
        let metadata = try MeshSignedRequestAnchorMetadata(
            request: dailyMartRequest(nonce: "nonce-anchor-policy-binding")
        )
        let payload = try MeshRequestAnchorPayload(
            metadata: metadata,
            policyId: "policy-hermes-dailymart-okrw-v1",
            policyHash: MeshPayloadHash(value: String(repeating: "f", count: 64))
        )

        let encodedPayload = try JSONEncoder().encode(payload)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: encodedPayload) as? [String: Any])
        XCTAssertEqual(object["version"] as? String, "meshkit-request-anchor/v1")
        XCTAssertEqual(object["policyId"] as? String, "policy-hermes-dailymart-okrw-v1")
        XCTAssertEqual((object["policyHash"] as? [String: Any])?["algorithm"] as? String, "sha256")
        XCTAssertEqual((object["policyHash"] as? [String: Any])?["value"] as? String, String(repeating: "f", count: 64))

        let anchor = try await provider.anchorSignedRequest(
            payload: payload,
            submittedAt: "2026-05-31T00:00:00Z"
        )

        XCTAssertEqual(anchor.payload, payload)
        XCTAssertEqual(anchor.payload?.metadata.signedRequestHash, metadata.signedRequestHash)
        XCTAssertEqual(anchor.payload?.policyId, "policy-hermes-dailymart-okrw-v1")
        XCTAssertEqual(anchor.payload?.policyHash, MeshPayloadHash(value: String(repeating: "f", count: 64)))
        XCTAssertEqual(anchor.identifier.anchorId, "anchor-ios-grocery-test-001")
    }

    func testMarooTestnetRequestAnchorAdapterExposesProviderNeutralCapabilityMetadataAndSubmitsAnchor() async throws {
        let adapter = try MeshMarooTestnetRequestAnchorAdapter(status: .pending)
        let request = dailyMartRequest(nonce: "nonce-maroo-anchor-adapter")
        let policy = try sampleDelegatedSpendingPolicy()
        let submission = try MeshRequestAnchorSubmission(
            request: request,
            policy: policy,
            providerIdentity: adapter.identity,
            submittedAt: "2026-05-31T00:00:00Z"
        )
        let module = MeshRequestAnchorSubmissionModule(provider: adapter)

        let output = try await module.submitOutput(submission, boundTo: request, policy: policy)

        XCTAssertEqual(MeshMarooTestnetRequestAnchorAdapter.adapterId, "maroo-testnet-request-anchor-demo-adapter")
        XCTAssertEqual(adapter.providerMetadata.provider, "maroo")
        XCTAssertEqual(adapter.providerMetadata.network, "maroo-testnet")
        XCTAssertEqual(adapter.providerMetadata.chainId, "maroo-testnet-1")
        XCTAssertEqual(adapter.endpointConfiguration.rpcEndpoint.absoluteString, "https://rpc-testnet.maroo.io")
        XCTAssertEqual(adapter.endpointConfiguration.explorerBaseUrl?.absoluteString, "https://explorer-testnet.maroo.io")
        XCTAssertTrue(adapter.capabilities.contains(.anchorSignedRequest))
        XCTAssertTrue(adapter.capabilities.contains(.lookupRequestAnchorStatus))
        XCTAssertTrue(adapter.capabilities.contains(.constructExplorerURL))
        XCTAssertEqual(output.anchoringReference.identity.metadata, adapter.providerMetadata)
        XCTAssertEqual(output.anchoringReference.anchorId, "maroo-anchor-ios-grocery-test-001")
        XCTAssertEqual(output.requestHash, submission.payload.metadata.signedRequestHash)
        XCTAssertEqual(output.requestNonce, "nonce-maroo-anchor-adapter")
        XCTAssertEqual(output.policyId, policy.policyId)
        XCTAssertEqual(output.policyHash, policy.policyHash)
        XCTAssertEqual(output.status, .pending)
        XCTAssertEqual(output.submittedAt, "2026-05-31T00:00:00Z")
        XCTAssertEqual(
            output.anchoringReference.explorerURL?.absoluteString,
            "https://explorer-testnet.maroo.io/tx/\(try XCTUnwrap(output.anchoringReference.transactionHash))"
        )
    }

    func testRequestAnchorSubmissionBuildsProviderNeutralBoundPayloadAndValidatesBindingFields() throws {
        let request = dailyMartRequest(nonce: "nonce-anchor-submission")
        let policy = try sampleDelegatedSpendingPolicy()
        let providerIdentity = try sampleChainProviderIdentity()

        let submission = try MeshRequestAnchorSubmission(
            request: request,
            policy: policy,
            providerIdentity: providerIdentity,
            submittedAt: "2026-05-31T00:00:00Z"
        )

        XCTAssertEqual(submission.version, "meshkit-request-anchor-submission/v1")
        XCTAssertEqual(submission.providerMetadata.provider, "maroo")
        XCTAssertEqual(submission.providerMetadata.network, "maroo-testnet")
        XCTAssertEqual(submission.providerMetadata.chainId, "maroo-testnet-1")
        XCTAssertEqual(submission.payload.version, "meshkit-request-anchor/v1")
        XCTAssertEqual(submission.payload.metadata.requestId, request.requestId)
        XCTAssertEqual(submission.payload.metadata.nonce, "nonce-anchor-submission")
        XCTAssertEqual(submission.payload.metadata.timestamp, request.timestamp)
        XCTAssertEqual(submission.payload.metadata.callerAppId, request.caller.appId)
        XCTAssertEqual(submission.payload.metadata.callerBundleId, request.caller.bundleId)
        XCTAssertEqual(submission.payload.metadata.targetBundleId, request.target.targetBundleId)
        XCTAssertEqual(submission.payload.metadata.capabilityId, request.target.capabilityId)
        XCTAssertEqual(submission.payload.metadata.payloadHash, request.payloadHash)
        XCTAssertEqual(submission.payload.metadata.signature, request.signature)
        XCTAssertEqual(submission.payload.metadata.signedRequestHash.value.count, 64)
        XCTAssertEqual(submission.payload.policyId, policy.policyId)
        XCTAssertEqual(submission.payload.policyHash, policy.policyHash)
        XCTAssertEqual(submission.submittedAt, "2026-05-31T00:00:00Z")

        try submission.validate(boundTo: request, policy: policy, providerIdentity: providerIdentity)

        let encodedSubmission = try JSONEncoder().encode(submission)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: encodedSubmission) as? [String: Any])
        XCTAssertEqual(object["version"] as? String, "meshkit-request-anchor-submission/v1")
        XCTAssertEqual(object["submittedAt"] as? String, "2026-05-31T00:00:00Z")
        XCTAssertEqual((object["providerMetadata"] as? [String: Any])?["provider"] as? String, "maroo")
        XCTAssertEqual((object["providerMetadata"] as? [String: Any])?["network"] as? String, "maroo-testnet")
        XCTAssertEqual((object["providerMetadata"] as? [String: Any])?["chainId"] as? String, "maroo-testnet-1")
        XCTAssertNil((object["providerMetadata"] as? [String: Any])?["providerName"])

        let payloadObject = try XCTUnwrap(object["payload"] as? [String: Any])
        let metadataObject = try XCTUnwrap(payloadObject["metadata"] as? [String: Any])
        XCTAssertEqual(metadataObject["requestId"] as? String, request.requestId)
        XCTAssertEqual(metadataObject["nonce"] as? String, "nonce-anchor-submission")
        XCTAssertEqual(metadataObject["targetBundleId"] as? String, request.target.targetBundleId)
        XCTAssertEqual(payloadObject["policyId"] as? String, policy.policyId)

        let otherProviderIdentity = try MeshChainProviderIdentity(
            providerName: "mockchain",
            networkIdentity: "local-testnet",
            chainId: "mockchain-local-1",
            rpcEndpoint: try XCTUnwrap(URL(string: "https://rpc.mockchain.example.invalid"))
        )
        XCTAssertThrowsError(
            try submission.validate(boundTo: request, policy: policy, providerIdentity: otherProviderIdentity)
        ) { error in
            XCTAssertEqual(error as? MeshKitValidationError, .signatureMismatch("request anchor provider metadata mismatch"))
        }
    }

    func testRequestAnchorSubmissionModuleSubmitsBoundPayloadThroughDemoAdapter() async throws {
        let request = dailyMartRequest(nonce: "nonce-anchor-submission-module")
        let policy = try sampleDelegatedSpendingPolicy()
        let provider = try MeshDemoRequestAnchorProvider(
            identity: try sampleChainProviderIdentity(),
            capabilities: [.anchorSignedRequest, .constructExplorerURL],
            status: .submitted,
            transactionHash: "0xanchorSubmissionModule001"
        )
        let submission = try MeshRequestAnchorSubmission(
            request: request,
            policy: policy,
            providerIdentity: provider.identity,
            submittedAt: "2026-05-31T00:00:00Z"
        )
        let module = MeshRequestAnchorSubmissionModule(provider: provider)

        let anchor = try await module.submit(submission, boundTo: request, policy: policy)

        XCTAssertEqual(anchor.status, .submitted)
        XCTAssertEqual(anchor.metadata, submission.payload.metadata)
        XCTAssertEqual(anchor.payload, submission.payload)
        XCTAssertEqual(anchor.payload?.metadata.nonce, "nonce-anchor-submission-module")
        XCTAssertEqual(anchor.payload?.policyId, "policy-hermes-dailymart-okrw-v1")
        XCTAssertEqual(anchor.payload?.policyHash, MeshPayloadHash(value: String(repeating: "f", count: 64)))
        XCTAssertEqual(anchor.identifier.identity.metadata, provider.identity.metadata)
        XCTAssertEqual(anchor.identifier.anchorId, "anchor-ios-grocery-test-001")
        XCTAssertEqual(anchor.identifier.transactionHash, "0xanchorSubmissionModule001")
        XCTAssertEqual(
            anchor.identifier.explorerURL?.absoluteString,
            "https://explorer-testnet.example.invalid/tx/0xanchorSubmissionModule001"
        )
        XCTAssertEqual(anchor.submittedAt, "2026-05-31T00:00:00Z")
        XCTAssertEqual(anchor.observedAt, "2026-05-31T00:00:00Z")

        try MeshRequestAnchorSubmissionModule.validate(
            anchor: anchor,
            for: submission,
            providerIdentity: provider.identity
        )
    }

    func testRequestAnchorSubmissionModuleReturnsStableAnchoringReferenceOutput() async throws {
        let request = dailyMartRequest(nonce: "nonce-anchor-output-module")
        let policy = try sampleDelegatedSpendingPolicy()
        let provider = try MeshDemoRequestAnchorProvider(
            identity: try sampleChainProviderIdentity(),
            capabilities: [.anchorSignedRequest, .constructExplorerURL],
            status: .submitted,
            transactionHash: "0xanchorOutputModule001"
        )
        let submission = try MeshRequestAnchorSubmission(
            request: request,
            policy: policy,
            providerIdentity: provider.identity,
            submittedAt: "2026-05-31T00:00:00Z"
        )
        let module = MeshRequestAnchorSubmissionModule(provider: provider)

        let output = try await module.submitOutput(submission, boundTo: request, policy: policy)

        XCTAssertEqual(output.version, "meshkit-request-anchor-output/v1")
        XCTAssertEqual(output.anchoringReference.identity.metadata, provider.identity.metadata)
        XCTAssertEqual(output.anchoringReference.anchorId, "anchor-ios-grocery-test-001")
        XCTAssertEqual(output.anchoringReference.transactionHash, "0xanchorOutputModule001")
        XCTAssertEqual(
            output.anchoringReference.explorerURL?.absoluteString,
            "https://explorer-testnet.example.invalid/tx/0xanchorOutputModule001"
        )
        XCTAssertEqual(output.requestHash, submission.payload.metadata.signedRequestHash)
        XCTAssertEqual(output.requestNonce, "nonce-anchor-output-module")
        XCTAssertEqual(output.requestNonce, submission.payload.metadata.nonce)
        XCTAssertEqual(output.policyId, "policy-hermes-dailymart-okrw-v1")
        XCTAssertEqual(output.policyId, submission.payload.policyId)
        XCTAssertEqual(output.policyHash, MeshPayloadHash(value: String(repeating: "f", count: 64)))
        XCTAssertEqual(output.policyHash, submission.payload.policyHash)
        XCTAssertEqual(output.status, .submitted)
        XCTAssertEqual(output.submittedAt, "2026-05-31T00:00:00Z")
        XCTAssertEqual(output.observedAt, "2026-05-31T00:00:00Z")

        let encodedOutput = try JSONEncoder().encode(output)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: encodedOutput) as? [String: Any])
        XCTAssertEqual(object["version"] as? String, "meshkit-request-anchor-output/v1")
        XCTAssertEqual(object["requestNonce"] as? String, "nonce-anchor-output-module")
        XCTAssertEqual(object["policyId"] as? String, "policy-hermes-dailymart-okrw-v1")
        XCTAssertEqual((object["requestHash"] as? [String: Any])?["value"] as? String, output.requestHash.value)
        XCTAssertEqual((object["policyHash"] as? [String: Any])?["value"] as? String, String(repeating: "f", count: 64))
        XCTAssertEqual((object["anchoringReference"] as? [String: Any])?["anchorId"] as? String, "anchor-ios-grocery-test-001")
    }

    func testRequestAnchorSubmissionOutputValidationRejectsBrokenRequestOrPolicyLinkage() throws {
        let request = dailyMartRequest(nonce: "nonce-anchor-output-validation")
        let policy = try sampleDelegatedSpendingPolicy()
        let payload = try MeshRequestAnchorPayload(
            metadata: MeshSignedRequestAnchorMetadata(request: request),
            policyId: policy.policyId,
            policyHash: policy.policyHash
        )
        let anchor = try MeshRequestAnchor(
            metadata: payload.metadata,
            payload: payload,
            identifier: MeshRequestAnchorIdentifier(
                identity: try sampleChainProviderIdentity(),
                anchorId: "anchor-ios-grocery-test-001",
                transactionHash: "0xanchorOutputValidation001"
            ),
            status: .confirmed,
            submittedAt: "2026-05-31T00:00:00Z",
            observedAt: "2026-05-31T00:00:01Z"
        )

        let validOutput = try MeshRequestAnchorSubmissionOutput(anchor: anchor)
        try MeshRequestAnchorSubmissionOutput.validate(output: validOutput, anchor: anchor)

        let wrongRequestHashOutput = try MeshRequestAnchorSubmissionOutput(
            anchoringReference: validOutput.anchoringReference,
            requestHash: MeshPayloadHash(value: String(repeating: "a", count: 64)),
            requestNonce: validOutput.requestNonce,
            policyId: validOutput.policyId,
            policyHash: validOutput.policyHash,
            status: validOutput.status,
            submittedAt: validOutput.submittedAt,
            observedAt: validOutput.observedAt
        )
        XCTAssertThrowsError(try MeshRequestAnchorSubmissionOutput.validate(output: wrongRequestHashOutput, anchor: anchor)) { error in
            XCTAssertEqual(error as? MeshKitValidationError, .signatureMismatch("request anchor output request linkage mismatch"))
        }

        let wrongPolicyOutput = try MeshRequestAnchorSubmissionOutput(
            anchoringReference: validOutput.anchoringReference,
            requestHash: validOutput.requestHash,
            requestNonce: validOutput.requestNonce,
            policyId: validOutput.policyId,
            policyHash: MeshPayloadHash(value: String(repeating: "b", count: 64)),
            status: validOutput.status,
            submittedAt: validOutput.submittedAt,
            observedAt: validOutput.observedAt
        )
        XCTAssertThrowsError(try MeshRequestAnchorSubmissionOutput.validate(output: wrongPolicyOutput, anchor: anchor)) { error in
            XCTAssertEqual(error as? MeshKitValidationError, .signatureMismatch("request anchor output policy linkage mismatch"))
        }
    }

    func testAgentWalletRecordsSignedMCPRequestAnchorWithoutPaymentOrTransferSubmission() async throws {
        let request = dailyMartRequest(nonce: "nonce-agent-wallet-anchor-record")
        let policy = try sampleDelegatedSpendingPolicy()
        let signingKey = Curve25519.Signing.PrivateKey()
        let wallet = try StaticAgentWallet(
            identity: sampleAgentWalletIdentity(),
            capabilities: [
                .reportWalletAddress,
                .exposeSigningBoundary,
                .signRequestAnchorPayload,
                .validatePolicy
            ],
            spendingLimit: nil,
            anchorSigningKey: signingKey
        )
        let anchorProvider = try MeshDemoRequestAnchorProvider(
            identity: try sampleChainProviderIdentity(),
            capabilities: [.anchorSignedRequest, .constructExplorerURL],
            status: .submitted,
            transactionHash: "0xanchorAgentWalletRecord001"
        )
        let paymentExecutor = RecordingPaymentExecutor(
            identity: try sampleChainProviderIdentity(),
            capabilities: [.executePayment, .executeTransfer, .lookupExecutionStatus]
        )
        let recorder = MeshAgentWalletRequestAnchorRecorder(
            wallet: wallet,
            requestAnchorProvider: anchorProvider
        )

        let record = try await recorder.recordSignedRequestAnchor(
            request: request,
            policy: policy,
            submittedAt: "2026-05-31T00:00:00Z",
            signedAt: "2026-05-31T00:00:00Z"
        )

        XCTAssertEqual(record.walletIdentity, wallet.identity)
        XCTAssertEqual(record.requestNonce, "nonce-agent-wallet-anchor-record")
        XCTAssertEqual(record.requestHash, try MeshRequestAnchorCanonicalization.signedRequestHash(for: request))
        XCTAssertEqual(record.policyId, policy.policyId)
        XCTAssertEqual(record.policyHash, policy.policyHash)
        XCTAssertEqual(record.anchor.payload?.metadata.requestId, request.requestId)
        XCTAssertEqual(record.anchor.payload?.metadata.nonce, "nonce-agent-wallet-anchor-record")
        XCTAssertEqual(record.anchor.payload?.policyId, policy.policyId)
        XCTAssertEqual(record.anchor.payload?.policyHash, policy.policyHash)
        XCTAssertEqual(record.anchor.status, .submitted)
        XCTAssertEqual(record.anchor.identifier.anchorId, "anchor-ios-grocery-test-001")
        XCTAssertEqual(record.anchor.identifier.transactionHash, "0xanchorAgentWalletRecord001")
        XCTAssertEqual(record.walletAnchorSignature.payload.requestAnchorMetadata, record.anchor.metadata)
        XCTAssertEqual(record.walletAnchorSignature.payload.walletAddress, "maroo1dailyMartAgentWallet")

        let signatureData = try XCTUnwrap(Data(base64Encoded: record.walletAnchorSignature.signature.value))
        XCTAssertTrue(
            signingKey.publicKey.isValidSignature(
                signatureData,
                for: try record.walletAnchorSignature.payload.signingInputData()
            )
        )
        XCTAssertEqual(paymentExecutor.executionCallCount, 0)
    }

    func testAgentWalletOKRWPaymentSubmissionPathRequiresValidSignedRequestAnchorBeforeExecution() async throws {
        let request = dailyMartRequest(nonce: "nonce-agent-wallet-payment-boundary", budget: "4900")
        let policy = try sampleDelegatedSpendingPolicy()
        let signingKey = Curve25519.Signing.PrivateKey()
        let wallet = try StaticAgentWallet(
            identity: sampleAgentWalletIdentity(),
            capabilities: [
                .authorizeExecution,
                .reportDelegatedSpendingLimit,
                .signRequestAnchorPayload,
                .validatePolicy
            ],
            spendingLimit: sampleDelegatedSpendingLimit(),
            anchorSigningKey: signingKey,
            delegatedPolicy: policy
        )
        let log = PaymentSubmissionBoundaryLog()
        let anchorProvider = BoundaryRequestAnchorProvider(
            identity: try sampleChainProviderIdentity(),
            capabilities: [.anchorSignedRequest, .constructExplorerURL],
            log: log
        )
        let paymentExecutor = BoundaryPaymentExecutor(
            identity: try sampleChainProviderIdentity(),
            capabilities: [.executePayment],
            log: log
        )
        let submissionPath = MeshAgentWalletPaymentSubmissionPath(
            wallet: wallet,
            requestAnchorProvider: anchorProvider,
            paymentExecutor: paymentExecutor
        )

        let submission = try await submissionPath.submitPayment(
            request: request,
            policy: policy,
            executionId: "exec-agent-wallet-payment-boundary",
            amount: Decimal(4_900),
            currencyCode: "krw",
            tokenSymbol: "okrw",
            recipientAddress: "maroo1dailyMartMerchant",
            paymentId: "pay-agent-wallet-payment-boundary",
            anchorSubmittedAt: "2026-05-31T00:00:00Z",
            anchorSignedAt: "2026-05-31T00:00:00Z",
            authorizationDecidedAt: "2026-05-31T00:00:01Z",
            paymentRequestedAt: "2026-05-31T00:00:02Z",
            paymentSubmittedAt: "2026-05-31T00:00:03Z"
        )

        XCTAssertEqual(log.events, [
            "anchor:anchor-ios-grocery-test-001",
            "payment:anchor-ios-grocery-test-001"
        ])
        XCTAssertEqual(paymentExecutor.executionCallCount, 1)
        XCTAssertEqual(submission.anchorRecord.anchor.status, .confirmed)
        XCTAssertEqual(submission.anchorRecord.anchor.payload?.metadata.nonce, "nonce-agent-wallet-payment-boundary")
        XCTAssertEqual(submission.anchorRecord.anchor.payload?.policyId, policy.policyId)
        XCTAssertEqual(submission.anchorRecord.anchor.payload?.policyHash, policy.policyHash)
        XCTAssertEqual(submission.authorizationDecision.status, .approved)
        XCTAssertEqual(submission.paymentRequest.asset, "OKRW")
        XCTAssertEqual(submission.paymentRequest.requestAnchor, submission.anchorRecord.anchor)
        XCTAssertEqual(submission.paymentRequest.requestHash, submission.anchorRecord.requestHash)
        XCTAssertEqual(submission.paymentResult.status, .pending)
        XCTAssertEqual(submission.paymentResult.requestAnchorIdentifier, submission.anchorRecord.anchor.identifier)
        XCTAssertEqual(submission.paymentResult.signedRequestHash, submission.anchorRecord.requestHash)
    }

    func testAgentWalletOKRWTransferSubmissionPathRequiresValidSignedRequestAnchorBeforeExecution() async throws {
        let request = dailyMartRequest(nonce: "nonce-agent-wallet-transfer-boundary", budget: "4900")
        let policy = try sampleDelegatedSpendingPolicy()
        let signingKey = Curve25519.Signing.PrivateKey()
        let wallet = try StaticAgentWallet(
            identity: sampleAgentWalletIdentity(),
            capabilities: [
                .authorizeExecution,
                .reportDelegatedSpendingLimit,
                .signRequestAnchorPayload,
                .validatePolicy
            ],
            spendingLimit: sampleDelegatedSpendingLimit(),
            anchorSigningKey: signingKey,
            delegatedPolicy: policy
        )
        let log = PaymentSubmissionBoundaryLog()
        let anchorProvider = BoundaryRequestAnchorProvider(
            identity: try sampleChainProviderIdentity(),
            capabilities: [.anchorSignedRequest, .constructExplorerURL],
            log: log
        )
        let transferExecutor = BoundaryPaymentExecutor(
            identity: try sampleChainProviderIdentity(),
            capabilities: [.executeTransfer],
            log: log
        )
        let submissionPath = MeshAgentWalletPaymentSubmissionPath(
            wallet: wallet,
            requestAnchorProvider: anchorProvider,
            paymentExecutor: transferExecutor
        )

        let submission = try await submissionPath.submitTransfer(
            request: request,
            policy: policy,
            executionId: "exec-agent-wallet-transfer-boundary",
            amount: Decimal(4_900),
            currencyCode: "krw",
            tokenSymbol: "okrw",
            recipientAddress: "maroo1dailyMartMerchant",
            paymentId: "xfer-agent-wallet-transfer-boundary",
            anchorSubmittedAt: "2026-05-31T00:01:00Z",
            anchorSignedAt: "2026-05-31T00:01:00Z",
            authorizationDecidedAt: "2026-05-31T00:01:01Z",
            paymentRequestedAt: "2026-05-31T00:01:02Z",
            paymentSubmittedAt: "2026-05-31T00:01:03Z"
        )

        XCTAssertEqual(log.events, [
            "anchor:anchor-ios-grocery-test-001",
            "transfer:anchor-ios-grocery-test-001"
        ])
        XCTAssertEqual(transferExecutor.executionCallCount, 1)
        XCTAssertEqual(submission.paymentRequest.executionRequest.kind, .transfer)
        XCTAssertEqual(submission.anchorRecord.anchor.status, .confirmed)
        XCTAssertEqual(submission.anchorRecord.anchor.payload?.metadata.nonce, "nonce-agent-wallet-transfer-boundary")
        XCTAssertEqual(submission.anchorRecord.anchor.payload?.policyId, policy.policyId)
        XCTAssertEqual(submission.anchorRecord.anchor.payload?.policyHash, policy.policyHash)
        XCTAssertEqual(submission.authorizationDecision.status, .approved)
        XCTAssertEqual(submission.paymentRequest.asset, "OKRW")
        XCTAssertEqual(submission.paymentRequest.requestAnchor, submission.anchorRecord.anchor)
        XCTAssertEqual(submission.paymentRequest.requestHash, submission.anchorRecord.requestHash)
        XCTAssertEqual(submission.paymentResult.status, .pending)
        XCTAssertEqual(submission.paymentResult.kind, .transfer)
        XCTAssertEqual(submission.paymentResult.requestAnchorIdentifier, submission.anchorRecord.anchor.identifier)
        XCTAssertEqual(submission.paymentResult.signedRequestHash, submission.anchorRecord.requestHash)
    }

    func testAgentWalletRejectsPaymentOrTransferExecutionAuthorizationReusingAnchorOnlySignature() async throws {
        for executionKind in [MeshAgentWalletExecutionKind.payment, .transfer] {
            let request = dailyMartRequest(
                nonce: "nonce-agent-wallet-anchor-signature-reuse-\(executionKind.rawValue)",
                budget: "4900"
            )
            let policy = try sampleDelegatedSpendingPolicy()
            let signingKey = Curve25519.Signing.PrivateKey()
            let wallet = try StaticAgentWallet(
                identity: sampleAgentWalletIdentity(),
                capabilities: [
                    .authorizeExecution,
                    .reportDelegatedSpendingLimit,
                    .signRequestAnchorPayload,
                    .validatePolicy
                ],
                spendingLimit: sampleDelegatedSpendingLimit(),
                anchorSigningKey: signingKey,
                delegatedPolicy: policy
            )
            let anchorProvider = try MeshDemoRequestAnchorProvider(
                identity: try sampleChainProviderIdentity(),
                capabilities: [.anchorSignedRequest, .constructExplorerURL],
                status: .confirmed,
                transactionHash: "0xanchorSignatureReuse\(executionKind.rawValue)"
            )
            let recorder = MeshAgentWalletRequestAnchorRecorder(
                wallet: wallet,
                requestAnchorProvider: anchorProvider
            )
            let anchorRecord = try await recorder.recordSignedRequestAnchor(
                request: request,
                policy: policy,
                submittedAt: "2026-05-31T00:03:00Z",
                signedAt: "2026-05-31T00:03:00Z"
            )
            let executionRequest = try MeshAgentWalletExecutionRequest(
                executionId: "exec-anchor-signature-reuse-\(executionKind.rawValue)",
                kind: executionKind,
                requestAnchorMetadata: anchorRecord.anchor.metadata,
                scope: sampleDelegatedSpendingScope(),
                amount: Decimal(4_900),
                currencyCode: "krw",
                tokenSymbol: "okrw",
                recipientAddress: try XCTUnwrap(policy.recipientAddress),
                policyId: policy.policyId,
                policyHash: policy.policyHash
            )
            let reusedAnchorSignatureAsExecutionAuthorization = try MeshAgentWalletExecutionAuthorization(
                walletIdentity: anchorRecord.walletIdentity,
                payload: MeshAgentWalletExecutionAuthorizationPayload(
                    executionRequest: executionRequest,
                    policyId: policy.policyId,
                    policyHash: policy.policyHash,
                    walletAddress: anchorRecord.walletIdentity.walletAddress,
                    signingPurpose: MeshAgentWalletAnchorSigningPayload.signingPurpose
                ),
                signature: anchorRecord.walletAnchorSignature.signature,
                signedAt: anchorRecord.walletAnchorSignature.signedAt
            )
            let authorizationDecision = try MeshAgentWalletAuthorizationDecision(
                authorizationId: "auth-anchor-signature-reuse-\(executionKind.rawValue)",
                walletIdentity: anchorRecord.walletIdentity,
                executionRequest: executionRequest,
                status: .approved,
                approvedAmount: Decimal(4_900),
                decidedAt: "2026-05-31T00:03:01Z",
                executionAuthorization: reusedAnchorSignatureAsExecutionAuthorization
            )
            let executor = RecordingPaymentExecutor(
                identity: try sampleChainProviderIdentity(),
                capabilities: [.executePayment, .executeTransfer]
            )

            XCTAssertThrowsError(try MeshPaymentExecutionRequest(
                paymentId: "pay-anchor-signature-reuse-\(executionKind.rawValue)",
                authorizationDecision: authorizationDecision,
                requestAnchor: anchorRecord.anchor,
                requestedAt: "2026-05-31T00:03:02Z"
            )) { error in
                XCTAssertEqual(
                    error as? MeshKitValidationError,
                    .invalidPaymentExecution("executionAuthorization.signingPurpose")
                )
            }
            XCTAssertEqual(executor.executionCallCount, 0)
        }
    }

    func testAgentWalletTransferSubmissionPathDoesNotExecuteWhenAnchorIsFailed() async throws {
        let request = dailyMartRequest(nonce: "nonce-agent-wallet-transfer-failed-anchor", budget: "4900")
        let policy = try sampleDelegatedSpendingPolicy()
        let signingKey = Curve25519.Signing.PrivateKey()
        let wallet = try StaticAgentWallet(
            identity: sampleAgentWalletIdentity(),
            capabilities: [
                .authorizeExecution,
                .reportDelegatedSpendingLimit,
                .signRequestAnchorPayload,
                .validatePolicy
            ],
            spendingLimit: sampleDelegatedSpendingLimit(),
            anchorSigningKey: signingKey,
            delegatedPolicy: policy
        )
        let anchorProvider = try MeshDemoRequestAnchorProvider(
            identity: try sampleChainProviderIdentity(),
            capabilities: [.anchorSignedRequest, .constructExplorerURL],
            status: .failed,
            transactionHash: "0xanchorFailedTransferBoundary001"
        )
        let transferExecutor = RecordingPaymentExecutor(
            identity: try sampleChainProviderIdentity(),
            capabilities: [.executeTransfer]
        )
        let submissionPath = MeshAgentWalletPaymentSubmissionPath(
            wallet: wallet,
            requestAnchorProvider: anchorProvider,
            paymentExecutor: transferExecutor
        )

        do {
            _ = try await submissionPath.submitTransfer(
                request: request,
                policy: policy,
                executionId: "exec-agent-wallet-transfer-failed-anchor",
                amount: Decimal(4_900),
                currencyCode: "krw",
                tokenSymbol: "okrw",
                recipientAddress: "maroo1dailyMartMerchant",
                paymentId: "xfer-agent-wallet-transfer-failed-anchor",
                anchorSubmittedAt: "2026-05-31T00:02:00Z",
                anchorSignedAt: "2026-05-31T00:02:00Z",
                authorizationDecidedAt: "2026-05-31T00:02:01Z",
                paymentRequestedAt: "2026-05-31T00:02:02Z",
                paymentSubmittedAt: "2026-05-31T00:02:03Z"
            )
            XCTFail("Expected failed request anchor to abort transfer execution")
        } catch {
            XCTAssertEqual(error as? MeshKitValidationError, .invalidPaymentExecution("requestAnchor"))
        }

        XCTAssertEqual(transferExecutor.executionCallCount, 0)
    }

    func testRequestAnchorSubmissionFailureDoesNotExecuteDownstreamPaymentOrTransfer() async throws {
        for executionKind in [MeshAgentWalletExecutionKind.payment, .transfer] {
            let request = dailyMartRequest(
                nonce: "nonce-anchor-submission-failure-\(executionKind.rawValue)",
                budget: "4900"
            )
            let policy = try sampleDelegatedSpendingPolicy()
            let provider = FailingRequestAnchorProvider(
                identity: try sampleChainProviderIdentity(),
                capabilities: [.anchorSignedRequest]
            )
            let submission = try MeshRequestAnchorSubmission(
                request: request,
                policy: policy,
                providerIdentity: provider.identity,
                submittedAt: "2026-05-31T00:00:00Z"
            )
            let executionRequest = try MeshAgentWalletExecutionRequest(
                executionId: "exec-anchor-failure-\(executionKind.rawValue)",
                kind: executionKind,
                requestAnchorMetadata: submission.payload.metadata,
                scope: sampleDelegatedSpendingScope(),
                amount: Decimal(4_900),
                currencyCode: "krw",
                tokenSymbol: "okrw",
                recipientAddress: try XCTUnwrap(policy.recipientAddress),
                policyId: policy.policyId,
                policyHash: policy.policyHash
            )
            let authorizationDecision = try MeshAgentWalletAuthorizationDecision(
                authorizationId: "auth-anchor-failure-\(executionKind.rawValue)",
                walletIdentity: sampleAgentWalletIdentity(),
                executionRequest: executionRequest,
                status: .approved,
                approvedAmount: Decimal(4_900),
                decidedAt: "2026-05-31T00:00:01Z"
            )
            let executor = RecordingPaymentExecutor(
                identity: try sampleChainProviderIdentity(),
                capabilities: [.executePayment, .executeTransfer]
            )
            let module = MeshRequestAnchorSubmissionModule(provider: provider)

            do {
                _ = try await module.submitAndExecute(
                    submission,
                    boundTo: request,
                    policy: policy,
                    authorizationDecision: authorizationDecision,
                    paymentId: "pay-anchor-failure-\(executionKind.rawValue)",
                    requestedAt: "2026-05-31T00:00:02Z",
                    paymentSubmittedAt: "2026-05-31T00:00:03Z",
                    executor: executor
                )
                XCTFail("Expected failed request anchor submission to abort \(executionKind.rawValue) execution")
            } catch {
                XCTAssertEqual(
                    error as? MeshKitValidationError,
                    .invalidChainProviderIdentity("request anchor submission failed")
                )
            }

            XCTAssertEqual(executor.executionCallCount, 0)
        }
    }

    func testRequestAnchorPolicyBindingRejectsPolicyHashMismatch() throws {
        let policy = try sampleDelegatedSpendingPolicy()
        let metadata = try MeshSignedRequestAnchorMetadata(
            request: dailyMartRequest(nonce: "nonce-anchor-policy-hash-mismatch")
        )
        let payload = try MeshRequestAnchorPayload(
            metadata: metadata,
            policyId: policy.policyId,
            policyHash: MeshPayloadHash(value: String(repeating: "a", count: 64))
        )

        XCTAssertThrowsError(try MeshRequestAnchorPolicyBinding.validate(payload: payload, boundPolicy: policy)) { error in
            XCTAssertEqual(error as? MeshKitValidationError, .signatureMismatch("request anchor policy hash mismatch"))
        }
    }

    func testRequestAnchorCanonicalizationRejectsSuppliedNonceMismatchAgainstBoundRequest() throws {
        let request = dailyMartRequest(nonce: "nonce-anchor-bound")
        let validMetadata = try MeshSignedRequestAnchorMetadata(request: request)
        let mismatchedMetadata = try MeshSignedRequestAnchorMetadata(
            requestId: validMetadata.requestId,
            nonce: "nonce-anchor-supplied-mismatch",
            timestamp: validMetadata.timestamp,
            callerAppId: validMetadata.callerAppId,
            callerBundleId: validMetadata.callerBundleId,
            targetBundleId: validMetadata.targetBundleId,
            capabilityId: validMetadata.capabilityId,
            payloadHash: validMetadata.payloadHash,
            signature: validMetadata.signature,
            signedRequestHash: validMetadata.signedRequestHash
        )

        XCTAssertThrowsError(try MeshRequestAnchorCanonicalization.validate(metadata: mismatchedMetadata, boundTo: request)) { error in
            XCTAssertEqual(error as? MeshKitValidationError, .signatureMismatch("request anchor nonce mismatch"))
        }
    }

    func testRequestAnchorIdentifierAndStatusRemainProviderNeutral() throws {
        let identifier = try MeshRequestAnchorIdentifier(
            identity: try sampleChainProviderIdentity(),
            anchorId: "maroo-anchor-001",
            transactionHash: "0xabc123"
        )

        XCTAssertEqual(identifier.identity.provider, "maroo")
        XCTAssertEqual(identifier.identity.network, "maroo-testnet")
        XCTAssertEqual(identifier.anchorId, "maroo-anchor-001")
        XCTAssertEqual(identifier.transactionHash, "0xabc123")
        XCTAssertEqual(identifier.explorerURL?.absoluteString, "https://explorer-testnet.example.invalid/tx/0xabc123")
        XCTAssertEqual(MeshRequestAnchorStatus.allCases.map(\.rawValue), ["submitted", "pending", "confirmed", "failed", "unavailable"])

        XCTAssertThrowsError(try MeshRequestAnchorIdentifier(
            identity: try sampleChainProviderIdentity(),
            anchorId: "bad\nanchor"
        )) { error in
            XCTAssertEqual(error as? MeshKitValidationError, .invalidChainProviderIdentity("anchorId"))
        }
    }

    func testRequestAnchorProviderCapabilityContractAnchorsSignedRequest() async throws {
        let provider = try StaticRequestAnchorProvider(
            identity: try sampleChainProviderIdentity(),
            capabilities: [.anchorSignedRequest, .constructExplorerURL],
            status: .confirmed
        )
        let metadata = try MeshSignedRequestAnchorMetadata(request: dailyMartRequest(nonce: "nonce-anchor-provider"))

        let anchor = try await provider.anchorSignedRequest(
            metadata: metadata,
            submittedAt: "2026-05-31T00:00:00Z"
        )

        XCTAssertEqual(anchor.metadata.requestId, "ios-grocery-test-001")
        XCTAssertEqual(anchor.identifier.identity.provider, "maroo")
        XCTAssertEqual(anchor.identifier.anchorId, "anchor-ios-grocery-test-001")
        XCTAssertEqual(anchor.status, .confirmed)
        XCTAssertEqual(anchor.submittedAt, "2026-05-31T00:00:00Z")
    }

    func testRequestAnchorFunctionReturnsProviderNeutralIdentifierFromMockAdapter() async throws {
        let provider = try StaticRequestAnchorProvider(
            identity: try sampleChainProviderIdentity(),
            capabilities: [.anchorSignedRequest, .constructExplorerURL],
            status: .submitted
        )
        let metadata = try MeshSignedRequestAnchorMetadata(
            request: dailyMartRequest(nonce: "nonce-anchor-identifier")
        )

        let identifier = try await provider.anchorSignedRequestIdentifier(
            metadata: metadata,
            submittedAt: "2026-05-31T00:00:00Z"
        )

        XCTAssertEqual(identifier.identity.provider, "maroo")
        XCTAssertEqual(identifier.identity.network, "maroo-testnet")
        XCTAssertEqual(identifier.anchorId, "anchor-ios-grocery-test-001")
        XCTAssertEqual(identifier.transactionHash, "0xanchor123")
        XCTAssertEqual(
            identifier.explorerURL?.absoluteString,
            "https://explorer-testnet.example.invalid/tx/0xanchor123"
        )
    }

    func testRequestAnchorStatusLookupReturnsProviderNeutralPendingConfirmedAndFailedStates() async throws {
        for expectedStatus in [MeshRequestAnchorStatus.pending, .confirmed, .failed, .unavailable] {
            let provider = try StaticRequestAnchorProvider(
                identity: try sampleChainProviderIdentity(),
                capabilities: [.lookupRequestAnchorStatus, .constructExplorerURL],
                status: expectedStatus
            )
            let identifier = try MeshRequestAnchorIdentifier(
                identity: try sampleChainProviderIdentity(),
                anchorId: "anchor-status-\(expectedStatus.rawValue)",
                transactionHash: "0xstatus\(expectedStatus.rawValue)"
            )

            let anchor = try await provider.requestAnchorStatus(
                identifier: identifier,
                checkedAt: "2026-05-31T00:00:00Z"
            )
            let statusValue = try await provider.requestAnchorStatusValue(
                identifier: identifier,
                checkedAt: "2026-05-31T00:00:00Z"
            )

            XCTAssertEqual(anchor.identifier, identifier)
            XCTAssertEqual(anchor.identifier.identity.provider, "maroo")
            XCTAssertEqual(anchor.identifier.identity.network, "maroo-testnet")
            XCTAssertEqual(anchor.status, expectedStatus)
            XCTAssertEqual(statusValue, expectedStatus)
            XCTAssertEqual(anchor.observedAt, "2026-05-31T00:00:00Z")
            XCTAssertEqual(
                anchor.identifier.explorerURL?.absoluteString,
                "https://explorer-testnet.example.invalid/tx/0xstatus\(expectedStatus.rawValue)"
            )
        }
    }

    func testRequestAnchorStatusModuleReturnsConfirmedForKnownAnchoringReference() async throws {
        let provider = try StaticRequestAnchorProvider(
            identity: try sampleChainProviderIdentity(),
            capabilities: [.lookupRequestAnchorStatus, .constructExplorerURL],
            status: .confirmed
        )
        let module = MeshRequestAnchorStatusModule(provider: provider)
        let knownReference = try MeshRequestAnchorIdentifier(
            identity: try sampleChainProviderIdentity(),
            anchorId: "anchor-known-confirmed-reference",
            transactionHash: "0xknownconfirmed001"
        )

        let anchor = try await module.lookup(
            identifier: knownReference,
            checkedAt: "2026-05-31T00:00:00Z"
        )
        let status = try await module.status(
            identifier: knownReference,
            checkedAt: "2026-05-31T00:00:00Z"
        )

        XCTAssertEqual(anchor.identifier, knownReference)
        XCTAssertEqual(anchor.status, .confirmed)
        XCTAssertEqual(status, .confirmed)
        XCTAssertEqual(anchor.observedAt, "2026-05-31T00:00:00Z")
    }

    func testRequestAnchorStatusModuleReturnsPendingForKnownAnchoringReference() async throws {
        let provider = try StaticRequestAnchorProvider(
            identity: try sampleChainProviderIdentity(),
            capabilities: [.lookupRequestAnchorStatus, .constructExplorerURL],
            status: .pending
        )
        let module = MeshRequestAnchorStatusModule(provider: provider)
        let knownReference = try MeshRequestAnchorIdentifier(
            identity: try sampleChainProviderIdentity(),
            anchorId: "anchor-known-pending-reference",
            transactionHash: "0xknownpending001"
        )

        let anchor = try await module.lookup(
            identifier: knownReference,
            checkedAt: "2026-05-31T00:00:00Z"
        )
        let status = try await module.status(
            identifier: knownReference,
            checkedAt: "2026-05-31T00:00:00Z"
        )

        XCTAssertEqual(anchor.identifier, knownReference)
        XCTAssertEqual(anchor.status, .pending)
        XCTAssertEqual(status, .pending)
        XCTAssertEqual(anchor.observedAt, "2026-05-31T00:00:00Z")
    }

    func testRequestAnchorStatusModuleReturnsFailedForKnownAnchoringReference() async throws {
        let provider = try StaticRequestAnchorProvider(
            identity: try sampleChainProviderIdentity(),
            capabilities: [.lookupRequestAnchorStatus, .constructExplorerURL],
            status: .failed
        )
        let module = MeshRequestAnchorStatusModule(provider: provider)
        let knownReference = try MeshRequestAnchorIdentifier(
            identity: try sampleChainProviderIdentity(),
            anchorId: "anchor-known-failed-reference",
            transactionHash: "0xknownfailed001"
        )

        let anchor = try await module.lookup(
            identifier: knownReference,
            checkedAt: "2026-05-31T00:00:00Z"
        )
        let status = try await module.status(
            identifier: knownReference,
            checkedAt: "2026-05-31T00:00:00Z"
        )

        XCTAssertEqual(anchor.identifier, knownReference)
        XCTAssertEqual(anchor.status, .failed)
        XCTAssertEqual(status, .failed)
        XCTAssertEqual(anchor.observedAt, "2026-05-31T00:00:00Z")
    }

    func testRequestAnchorStatusModuleReturnsUnknownReferenceResponseForUnrecognizedAnchoringReference() async throws {
        let provider = try StaticRequestAnchorProvider(
            identity: try sampleChainProviderIdentity(),
            capabilities: [.lookupRequestAnchorStatus, .constructExplorerURL],
            status: .pending,
            knownAnchorIds: ["anchor-known-reference"]
        )
        let module = MeshRequestAnchorStatusModule(provider: provider)
        let unknownReference = try MeshRequestAnchorIdentifier(
            identity: try sampleChainProviderIdentity(),
            anchorId: "anchor-unrecognized-reference",
            transactionHash: "0xunknownreference001"
        )

        let response = try await module.lookupResponse(
            identifier: unknownReference,
            checkedAt: "2026-05-31T00:00:00Z"
        )

        XCTAssertEqual(response.outcome, .unknownReference)
        XCTAssertEqual(response.identifier, unknownReference)
        XCTAssertNil(response.anchor)
        XCTAssertEqual(response.checkedAt, "2026-05-31T00:00:00Z")
        XCTAssertEqual(response.message, "unknown anchoring reference")

        do {
            _ = try await module.lookup(
                identifier: unknownReference,
                checkedAt: "2026-05-31T00:00:00Z"
            )
            XCTFail("Expected legacy anchor lookup to reject an unknown anchoring reference")
        } catch {
            XCTAssertEqual(error as? MeshKitValidationError, .requestAnchorReferenceNotFound("anchor-unrecognized-reference"))
        }
    }

    func testRequestAnchorStatusLookupRequiresAdvertisedCapability() async throws {
        let provider = try StaticRequestAnchorProvider(
            identity: try sampleChainProviderIdentity(),
            capabilities: [.anchorSignedRequest],
            status: .pending
        )
        let identifier = try MeshRequestAnchorIdentifier(
            identity: try sampleChainProviderIdentity(),
            anchorId: "anchor-status-unsupported",
            transactionHash: "0xstatusunsupported"
        )

        do {
            _ = try await provider.requestAnchorStatus(
                identifier: identifier,
                checkedAt: "2026-05-31T00:00:00Z"
            )
            XCTFail("Expected request anchor status lookup provider to require lookupRequestAnchorStatus capability")
        } catch {
            XCTAssertEqual(error as? MeshKitValidationError, .unsupportedCapability)
        }
    }

    func testRequestAnchorRequiresSignedRequestAndAdvertisedCapability() async throws {
        let unsigned = MeshRequest(
            requestId: "ios-anchor-unsigned",
            caller: MeshIdentity(
                appId: "app.hermes-chat",
                installId: "ios-sim",
                bundleId: "ai.meshkit.sample.hermeschat",
                publicKeyId: "demo-key"
            ),
            target: MeshCapability(
                targetBundleId: "ai.meshkit.sample.dailymart",
                capabilityId: "grocery.purchase_essentials",
                version: "1.0"
            ),
            payload: ["budget_krw": "100"],
            nonce: "nonce-anchor-unsigned",
            timestamp: ISO8601DateFormatter().string(from: Date()),
            signature: MeshSignature(algorithm: "", keyId: "", value: "")
        )
        XCTAssertThrowsError(try MeshSignedRequestAnchorMetadata(request: unsigned)) { error in
            XCTAssertEqual(error as? MeshKitValidationError, .signatureRequired)
        }

        let provider = try StaticRequestAnchorProvider(
            identity: try sampleChainProviderIdentity(),
            capabilities: [.constructExplorerURL],
            status: .pending
        )
        let metadata = try MeshSignedRequestAnchorMetadata(request: dailyMartRequest(nonce: "nonce-anchor-unsupported"))
        do {
            _ = try await provider.anchorSignedRequest(metadata: metadata, submittedAt: "2026-05-31T00:00:00Z")
            XCTFail("Expected request anchor provider to require anchorSignedRequest capability")
        } catch {
            XCTAssertEqual(error as? MeshKitValidationError, .unsupportedCapability)
        }
    }

    func testSampleGraphFindsNotesAppend() {
        let capability = OpenCapabilityGraph.mintNotesSample.findCapability("notes.append_note")
        XCTAssertEqual(capability?.risk, "write:user_content")
        XCTAssertEqual(capability?.consent, "per_invocation")
        XCTAssertEqual(capability?.inputSchema, ["note_ref", "text"])
    }

    func testMeshRequestCarriesPayloadHashAndRoundTripsThroughURLScheme() throws {
        let request = sampleRequest(nonce: "nonce-roundtrip")
        XCTAssertEqual(request.payloadHash.algorithm, "sha256")
        try MeshTarget.verifyPayloadHash(request)

        let encoded = try request.encodedForURLScheme()
        let decoded = try MeshRequest.decodedFromURLScheme(encoded)
        XCTAssertEqual(decoded, request)
    }

    func testValidatePublicMeshAcceptsTrustedConsentedRequest() throws {
        let cache = MeshReplayCache()
        let request = sampleRequest(nonce: "nonce-public-mesh")
        let audit = try MeshTarget.validatePublicMesh(
            request: request,
            policy: samplePolicy,
            trust: sampleTrust,
            invocationPolicy: MeshInvocationPolicy(
                risk: "write:user_content",
                consent: "per_invocation",
                userApproved: true,
                registrySignatureVerified: true
            ),
            observedCallerBundleId: "ai.meshkit.sample.hermeschat",
            replayCache: cache,
            maxAgeSeconds: 60
        )
        XCTAssertEqual(audit.status, "accepted")
        XCTAssertEqual(audit.capabilityId, "notes.append_note")
    }

    func testReplayIsRejected() throws {
        let cache = MeshReplayCache()
        let request = sampleRequest(nonce: "nonce-replay")
        try MeshTarget.validateSecure(
            request: request,
            policy: samplePolicy,
            trust: sampleTrust,
            observedCallerBundleId: "ai.meshkit.sample.hermeschat",
            replayCache: cache,
            maxAgeSeconds: 60
        )
        XCTAssertThrowsError(try MeshTarget.validateSecure(
            request: request,
            policy: samplePolicy,
            trust: sampleTrust,
            observedCallerBundleId: "ai.meshkit.sample.hermeschat",
            replayCache: cache,
            maxAgeSeconds: 60
        ))
    }

    func testPayloadTamperIsRejected() throws {
        let original = sampleRequest(nonce: "nonce-tamper")
        let tampered = MeshRequest(
            requestId: original.requestId,
            caller: original.caller,
            target: original.target,
            payload: ["note_ref": "ios:mint:demo", "text": "tampered"],
            payloadHash: original.payloadHash,
            nonce: original.nonce,
            timestamp: original.timestamp,
            signature: original.signature
        )
        XCTAssertThrowsError(try MeshTarget.verifyPayloadHash(tampered))
    }

    func testInvalidRequestSignatureIsRejected() throws {
        let cache = MeshReplayCache()
        let request = sampleRequest(nonce: "nonce-bad-signature", signatureValue: Data(repeating: 0, count: 64).base64EncodedString())
        XCTAssertThrowsError(try MeshTarget.validatePublicMesh(
            request: request,
            policy: samplePolicy,
            trust: sampleTrust,
            invocationPolicy: MeshInvocationPolicy(
                risk: "write:user_content",
                consent: "per_invocation",
                userApproved: true,
                registrySignatureVerified: true
            ),
            observedCallerBundleId: "ai.meshkit.sample.hermeschat",
            replayCache: cache,
            maxAgeSeconds: 60
        )) { error in
            XCTAssertEqual(error as? MeshKitValidationError, .signatureMismatch("invalid request signature"))
        }
    }

    func testObservedCallerBundleMismatchIsRejectedBeforeExecution() throws {
        let cache = MeshReplayCache()
        let request = sampleRequest(nonce: "nonce-evil-caller")
        XCTAssertThrowsError(try MeshTarget.validateSecure(
            request: request,
            policy: samplePolicy,
            trust: sampleTrust,
            observedCallerBundleId: "ai.meshkit.sample.evilcaller",
            replayCache: cache,
            maxAgeSeconds: 60
        )) { error in
            XCTAssertEqual(error as? MeshKitValidationError, .observedCallerBundleMismatch)
        }
    }

    func testDailyMartBudgetExceedIsRejected() throws {
        let cache = MeshReplayCache()
        let request = dailyMartRequest(nonce: "nonce-dailymart-overbudget", budget: "500")
        XCTAssertThrowsError(try MeshTarget.validatePublicMesh(
            request: request,
            policy: MeshTargetPolicy(
                allowedCallerAppId: "app.hermes-chat",
                targetBundleId: "ai.meshkit.sample.dailymart",
                capabilityId: "grocery.purchase_essentials"
            ),
            trust: sampleTrust,
            invocationPolicy: MeshInvocationPolicy(
                risk: "spend:money",
                consent: "budgeted_per_invocation",
                userApproved: true,
                registrySignatureVerified: true,
                approvedBudget: Decimal(100)
            ),
            observedCallerBundleId: "ai.meshkit.sample.hermeschat",
            replayCache: cache,
            maxAgeSeconds: 60
        )) { error in
            XCTAssertEqual(error as? MeshKitValidationError, .budgetExceeded)
        }
    }

    func testDailyMartSignedMCPRequestVerifierAcceptsExpectedHermesAgentSigner() throws {
        let verifier = try DailyMartSignedMCPRequestVerifier(expectedHermesAgentSigner: sampleTrust)
        let request = dailyMartRequest(nonce: "nonce-dailymart-signature-ok")

        XCTAssertNoThrow(try verifier.verify(request))
    }

    func testDailyMartSignedMCPRequestVerifierRejectsInvalidAndMissingSignatures() throws {
        let verifier = try DailyMartSignedMCPRequestVerifier(expectedHermesAgentSigner: sampleTrust)
        let invalidSignature = dailyMartRequest(
            nonce: "nonce-dailymart-signature-invalid",
            signatureValue: Data(repeating: 0, count: 64).base64EncodedString()
        )
        XCTAssertThrowsError(try verifier.verify(invalidSignature)) { error in
            XCTAssertEqual(error as? MeshKitValidationError, .signatureMismatch("invalid request signature"))
        }

        let missingSignature = dailyMartRequest(
            nonce: "nonce-dailymart-signature-missing",
            signatureValue: ""
        )
        XCTAssertThrowsError(try verifier.verify(missingSignature)) { error in
            XCTAssertEqual(error as? MeshKitValidationError, .signatureRequired)
        }
    }

    func testDailyMartSignedMCPRequestVerifierRejectsUnexpectedAgentSignerKeyId() throws {
        let verifier = try DailyMartSignedMCPRequestVerifier(expectedHermesAgentSigner: sampleTrust)
        let request = signedDailyMartRequest(
            requestId: "ios-grocery-test-unexpected-signer",
            nonce: "nonce-dailymart-unexpected-signer",
            callerPublicKeyId: "other-agent-key",
            signatureKeyId: "other-agent-key",
            signingKey: Self.signingKey
        )

        XCTAssertThrowsError(try verifier.verify(request)) { error in
            XCTAssertEqual(
                error as? MeshKitValidationError,
                .signatureMismatch("caller publicKeyId must match expected request signer")
            )
        }
    }

    func testDailyMartGraphAndBudgetedSpendValidation() throws {
        let capability = OpenCapabilityGraph.dailyMartSample.findCapability("grocery.purchase_essentials")
        XCTAssertEqual(capability?.risk, "spend:money")
        XCTAssertEqual(capability?.consent, "budgeted_per_invocation")
        XCTAssertEqual(capability?.inputSchema, ["items", "address_ref", "budget_krw"])

        let cache = MeshReplayCache()
        let request = dailyMartRequest(nonce: "nonce-dailymart")
        let audit = try MeshTarget.validatePublicMesh(
            request: request,
            policy: MeshTargetPolicy(
                allowedCallerAppId: "app.hermes-chat",
                targetBundleId: "ai.meshkit.sample.dailymart",
                capabilityId: "grocery.purchase_essentials"
            ),
            trust: sampleTrust,
            invocationPolicy: MeshInvocationPolicy(
                risk: "spend:money",
                consent: "budgeted_per_invocation",
                userApproved: true,
                registrySignatureVerified: true,
                approvedBudget: Decimal(100)
            ),
            observedCallerBundleId: "ai.meshkit.sample.hermeschat",
            replayCache: cache,
            maxAgeSeconds: 60
        )
        XCTAssertEqual(audit.capabilityId, "grocery.purchase_essentials")
        XCTAssertEqual(audit.risk, "spend:money")
    }


    func testProductionTargetOneLineValidatorKeepsSecureDefaultsEasyToAdopt() throws {
        let target = try MeshProductionTarget(
            policy: samplePolicy,
            trust: sampleTrust,
            invocationPolicy: MeshInvocationPolicy(
                risk: "write:user_content",
                consent: "per_invocation",
                userApproved: true,
                registrySignatureVerified: true
            ),
            replayCache: MeshReplayCache()
        )

        let audit = try target.validate(
            sampleRequest(nonce: "nonce-production-target"),
            observedCallerBundleId: "ai.meshkit.sample.hermeschat"
        )

        XCTAssertEqual(audit.status, "accepted")
        XCTAssertEqual(audit.capabilityId, "notes.append_note")
    }

    func testSignedRequestBuilderCreatesVerifiableRequestWithoutManualHashOrSignatureGlue() throws {
        let signer = MeshRequestSigner.ed25519(keyId: "demo-key", privateKey: Self.signingKey)
        let request = try MeshSignedRequestBuilder(
            caller: MeshIdentity(
                appId: "app.hermes-chat",
                installId: "ios-sim",
                bundleId: "ai.meshkit.sample.hermeschat",
                publicKeyId: "demo-key"
            ),
            target: MeshCapability(
                targetBundleId: "ai.meshkit.sample.mintnotes",
                capabilityId: "notes.append_note",
                version: "1.0"
            ),
            signer: signer
        ).makeRequest(
            requestId: "ios-builder-test-001",
            payload: ["note_ref": "ios:mint:demo", "text": "Easy secure adoption."],
            nonce: "nonce-builder",
            timestamp: ISO8601DateFormatter().string(from: Date())
        )

        try MeshTarget.verifyPayloadHash(request)
        try MeshTarget.verifyRequiredSignature(request, trust: sampleTrust)
    }

    func testProductionTargetRejectsIncompleteTrustAtConstruction() throws {
        let unsignedTrust = MeshSenderTrust(
            callerAppId: "app.hermes-chat",
            callerBundleId: "ai.meshkit.sample.hermeschat",
            teamId: "DEVTEAMID"
        )

        XCTAssertThrowsError(try MeshProductionTarget(
            policy: samplePolicy,
            trust: unsignedTrust,
            invocationPolicy: MeshInvocationPolicy(
                risk: "write:user_content",
                consent: "per_invocation",
                userApproved: true,
                registrySignatureVerified: true
            ),
            replayCache: MeshReplayCache()
        )) { error in
            XCTAssertEqual(error as? MeshKitValidationError, .signatureRequired)
        }
    }

    func testProductionTargetRejectsMismatchedTrustAtConstruction() throws {
        let mismatchedTrust = MeshSenderTrust(
            callerAppId: "app.evil",
            callerBundleId: "ai.meshkit.sample.hermeschat",
            teamId: "DEVTEAMID",
            requestSigningAlgorithm: "Ed25519",
            requestSigningKeyId: "demo-key",
            publicKey: Self.signingKey.publicKey.rawRepresentation.base64EncodedString()
        )

        XCTAssertThrowsError(try MeshProductionTarget(
            policy: samplePolicy,
            trust: mismatchedTrust,
            invocationPolicy: MeshInvocationPolicy(
                risk: "write:user_content",
                consent: "per_invocation",
                userApproved: true,
                registrySignatureVerified: true
            ),
            replayCache: MeshReplayCache()
        )) { error in
            XCTAssertEqual(error as? MeshKitValidationError, .signatureMismatch("production target trust callerAppId must match policy allowedCallerAppId"))
        }
    }

    func testProductionSpendTargetRequiresApprovedBudgetAtConstruction() throws {
        XCTAssertThrowsError(try MeshProductionTarget(
            policy: MeshTargetPolicy(
                allowedCallerAppId: "app.hermes-chat",
                targetBundleId: "ai.meshkit.sample.dailymart",
                capabilityId: "grocery.purchase_essentials"
            ),
            trust: sampleTrust,
            invocationPolicy: MeshInvocationPolicy(
                risk: "spend:money",
                consent: "budgeted_per_invocation",
                userApproved: true,
                registrySignatureVerified: true
            ),
            replayCache: MeshReplayCache()
        )) { error in
            XCTAssertEqual(error as? MeshKitValidationError, .signatureMismatch("spend:money production targets require an explicit approved budget"))
        }
    }

    func testProductionTargetRejectsDisabledInvocationPolicyAsKillSwitch() throws {
        XCTAssertThrowsError(try MeshProductionTarget(
            policy: samplePolicy,
            trust: sampleTrust,
            invocationPolicy: MeshInvocationPolicy(
                risk: "write:user_content",
                consent: "per_invocation",
                userApproved: true,
                registrySignatureVerified: true,
                productionEnabled: false,
                killSwitchReason: "incident-response"
            ),
            replayCache: MeshReplayCache()
        )) { error in
            XCTAssertEqual(error as? MeshKitValidationError, .productionDisabled("incident-response"))
        }
    }

    func testSignedRequestBuilderRejectsCallerPublicKeyIdMismatch() throws {
        let signer = MeshRequestSigner.ed25519(keyId: "meshkit-prod-key", privateKey: Self.signingKey)

        XCTAssertThrowsError(try MeshSignedRequestBuilder(
            caller: MeshIdentity(
                appId: "app.hermes-chat",
                installId: "ios-sim",
                bundleId: "ai.meshkit.sample.hermeschat",
                publicKeyId: "different-key"
            ),
            target: MeshCapability(
                targetBundleId: "ai.meshkit.sample.mintnotes",
                capabilityId: "notes.append_note",
                version: "1.0"
            ),
            signer: signer
        ).makeRequest(
            requestId: "ios-builder-mismatch-001",
            payload: ["note_ref": "ios:mint:demo", "text": "Key ids must match."],
            nonce: "nonce-builder-mismatch",
            timestamp: ISO8601DateFormatter().string(from: Date())
        )) { error in
            XCTAssertEqual(error as? MeshKitValidationError, .signatureMismatch("caller publicKeyId must match signer keyId"))
        }
    }

    func testSecurityEnvelopeRejectsDelimiterInjectionInSignedFields() throws {
        let request = MeshRequest(
            requestId: "ios-test-001\nforged",
            caller: MeshIdentity(
                appId: "app.hermes-chat",
                installId: "ios-sim",
                bundleId: "ai.meshkit.sample.hermeschat",
                publicKeyId: "demo-key"
            ),
            target: MeshCapability(
                targetBundleId: "ai.meshkit.sample.mintnotes",
                capabilityId: "notes.append_note",
                version: "1.0"
            ),
            payload: ["note_ref": "ios:mint:demo", "text": "Ship MeshKit iOS demo with OCG discovery."],
            nonce: "nonce-delimiter",
            timestamp: ISO8601DateFormatter().string(from: Date()),
            signature: MeshSignature(algorithm: "Ed25519", keyId: "demo-key", value: "")
        )

        XCTAssertThrowsError(try MeshTarget.validateRequestEnvelope(request)) { error in
            XCTAssertEqual(error as? MeshKitValidationError, .invalidSecurityField("requestId"))
        }
    }

    func testSecurityEnvelopeRejectsMalformedPayloadHashBeforeExecution() throws {
        let request = MeshRequest(
            requestId: "ios-test-001",
            caller: MeshIdentity(
                appId: "app.hermes-chat",
                installId: "ios-sim",
                bundleId: "ai.meshkit.sample.hermeschat",
                publicKeyId: "demo-key"
            ),
            target: MeshCapability(
                targetBundleId: "ai.meshkit.sample.mintnotes",
                capabilityId: "notes.append_note",
                version: "1.0"
            ),
            payload: ["note_ref": "ios:mint:demo", "text": "Ship MeshKit iOS demo with OCG discovery."],
            payloadHash: MeshPayloadHash(value: "not-a-sha256"),
            nonce: "nonce-bad-hash-shape",
            timestamp: ISO8601DateFormatter().string(from: Date()),
            signature: MeshSignature(algorithm: "Ed25519", keyId: "demo-key", value: "")
        )

        XCTAssertThrowsError(try MeshTarget.validateRequestEnvelope(request)) { error in
            XCTAssertEqual(error as? MeshKitValidationError, .invalidSecurityField("payloadHash.value"))
        }
    }

    func testInvokeURLRejectsMalformedSchemeWithoutCrashing() throws {
        XCTAssertThrowsError(try MeshURLRouter.invokeURL(scheme: " not a url ", request: sampleRequest(nonce: "nonce-bad-url")))
    }

    func testSignedTargetReceiptVerifiesAndCorrelatesToPendingRequest() throws {
        let targetKey = Curve25519.Signing.PrivateKey()
        let request = dailyMartRequest(nonce: "nonce-receipt-correlation")
        let receipt = try MeshReceiptSigner.ed25519(
            keyId: "dailymart-receipt-key",
            privateKey: targetKey
        ).makeReceipt(
            receiptId: "receipt-001",
            request: request,
            targetAppId: "app.dailymart",
            targetBundleId: "ai.meshkit.sample.dailymart",
            status: "purchased",
            result: ["order_id": "DM-2026-0509-002", "total_krw": "100"],
            nonce: "receipt-nonce-001",
            timestamp: ISO8601DateFormatter().string(from: Date())
        )

        let store = MeshPendingReceiptStore()
        let token = store.register(request: request, capabilityId: "grocery.purchase_essentials")
        XCTAssertEqual(token, request.requestId)

        let verified = try store.consumeVerified(
            receipt,
            expectedToken: token,
            trust: MeshReceiptTrust(
                targetAppId: "app.dailymart",
                targetBundleId: "ai.meshkit.sample.dailymart",
                receiptSigningAlgorithm: "Ed25519",
                receiptSigningKeyId: "dailymart-receipt-key",
                publicKey: targetKey.publicKey.rawRepresentation.base64EncodedString()
            ),
            maxAgeSeconds: 60
        )

        XCTAssertEqual(verified.status, "purchased")
        XCTAssertEqual(verified.result["order_id"], "DM-2026-0509-002")
        XCTAssertThrowsError(try store.consumeVerified(
            receipt,
            expectedToken: token,
            trust: MeshReceiptTrust(
                targetAppId: "app.dailymart",
                targetBundleId: "ai.meshkit.sample.dailymart",
                receiptSigningAlgorithm: "Ed25519",
                receiptSigningKeyId: "dailymart-receipt-key",
                publicKey: targetKey.publicKey.rawRepresentation.base64EncodedString()
            ),
            maxAgeSeconds: 60
        )) { error in
            XCTAssertEqual(error as? MeshKitValidationError, .replayDetected(token))
        }
    }

    func testSerializedDailyMartReceiptOwnershipMappingIsTargetOwned() throws {
        let targetKey = Curve25519.Signing.PrivateKey()
        let request = dailyMartRequest(nonce: "nonce-receipt-ownership")
        let result = try MeshReceiptOwnershipMapper.targetOwnedResultFields(
            baseResult: ["order_id": "DM-2026-0509-OWN", "total_krw": "100"],
            targetAppId: "app.dailymart",
            targetBundleId: "ai.meshkit.sample.dailymart"
        )
        let receipt = try MeshReceiptSigner.ed25519(
            keyId: "dailymart-receipt-key",
            privateKey: targetKey
        ).makeReceipt(
            receiptId: "receipt-ownership-001",
            request: request,
            targetAppId: "app.dailymart",
            targetBundleId: "ai.meshkit.sample.dailymart",
            status: "purchased",
            result: result,
            nonce: "receipt-ownership-nonce-001",
            timestamp: ISO8601DateFormatter().string(from: Date())
        )

        let decoded = try MeshReceipt.decodedFromURLScheme(receipt.encodedForURLScheme())
        let ownership = try MeshReceiptOwnershipMapper.ownership(ofSerializedReceipt: receipt.encodedForURLScheme())
        let expectedOwner = try MeshReceiptOwnershipMapper.ownerIdentifier(
            targetAppId: "app.dailymart",
            targetBundleId: "ai.meshkit.sample.dailymart"
        )

        XCTAssertEqual(decoded.result["receiptOwner"], expectedOwner)
        XCTAssertEqual(decoded.result["targetReceiptOwner"], expectedOwner)
        XCTAssertEqual(ownership.receiptOwner, expectedOwner)
        XCTAssertEqual(ownership.targetReceiptOwner, expectedOwner)
        XCTAssertEqual(ownership.targetSignatureKeyId, "dailymart-receipt-key")
        XCTAssertTrue(ownership.isTargetOwned)
        XCTAssertNoThrow(try MeshReceiptOwnershipMapper.assertTargetOwned(
            decoded,
            expectedTargetAppId: "app.dailymart",
            expectedTargetBundleId: "ai.meshkit.sample.dailymart"
        ))
        XCTAssertThrowsError(try MeshReceiptOwnershipMapper.assertTargetOwned(
            decoded,
            expectedTargetAppId: "app.hermes-chat",
            expectedTargetBundleId: "ai.meshkit.sample.hermeschat"
        )) { error in
            XCTAssertEqual(error as? MeshKitValidationError, .targetIdentityMismatch)
        }
    }

    func testProviderNeutralReceiptCoreSchemaRejectsMarooSpecificFixtureFields() throws {
        let providerNeutralFixture: [String: Any] = [
            "receiptId": "receipt-schema-fixture-001",
            "requestId": "ios-grocery-schema-fixture-001",
            "capabilityId": "grocery.purchase_essentials",
            "targetAppId": "app.dailymart",
            "targetBundleId": "ai.meshkit.sample.dailymart",
            "requestPayloadHash": [
                "algorithm": "sha256",
                "value": String(repeating: "a", count: 64)
            ],
            "status": "purchased",
            "result": [
                "chainProvider": "maroo",
                "chainNetwork": "maroo-testnet",
                "order_id": "DM-2026-0531-SCHEMA"
            ],
            "nonce": "receipt-schema-fixture-nonce-001",
            "timestamp": "2026-05-31T00:00:00Z",
            "signature": [
                "algorithm": "Ed25519",
                "keyId": "dailymart-receipt-key",
                "value": "placeholder-signature"
            ]
        ]
        let validData = try JSONSerialization.data(withJSONObject: providerNeutralFixture, options: [.sortedKeys])
        XCTAssertNoThrow(try MeshReceipt.validateProviderNeutralCoreSchema(jsonData: validData))

        var marooSpecificFixture = providerNeutralFixture
        marooSpecificFixture["marooReceipt"] = [
            "txHash": "0xprovidercoreleak",
            "rpcEndpoint": "https://rpc-testnet.maroo.io"
        ]
        let invalidData = try JSONSerialization.data(withJSONObject: marooSpecificFixture, options: [.sortedKeys])

        XCTAssertThrowsError(try MeshReceipt.validateProviderNeutralCoreSchema(jsonData: invalidData)) { error in
            XCTAssertEqual(error as? MeshKitValidationError, .invalidSecurityField("receipt.marooReceipt"))
        }
        XCTAssertThrowsError(try MeshReceipt.decodedFromURLScheme(invalidData.base64EncodedString())) { error in
            XCTAssertEqual(error as? MeshKitValidationError, .invalidSecurityField("receipt.marooReceipt"))
        }
    }

    func testReceiptBaseSchemaDocumentsSharedProtocolFieldsAndValidatesCommonInvalidFixtures() throws {
        let schema = MeshReceiptBaseSchema.providerNeutral

        XCTAssertEqual(schema.version, "meshkit-receipt-base-schema/v1")
        XCTAssertEqual(
            Set(schema.requiredRootFields),
            [
                "receiptId",
                "requestId",
                "capabilityId",
                "targetAppId",
                "targetBundleId",
                "requestPayloadHash",
                "status",
                "result",
                "nonce",
                "timestamp",
                "signature"
            ]
        )
        XCTAssertTrue(schema.ownershipResultFields.contains("receiptOwner"))
        XCTAssertTrue(schema.ownershipResultFields.contains("targetReceiptOwner"))
        XCTAssertTrue(schema.anchoringResultFields.contains("requestHash"))
        XCTAssertTrue(schema.anchoringResultFields.contains("requestNonce"))
        XCTAssertTrue(schema.anchoringResultFields.contains("anchoringReference"))
        XCTAssertTrue(schema.paymentOrTransferResultFields.contains("asset"))
        XCTAssertTrue(schema.paymentOrTransferResultFields.contains("amount"))
        XCTAssertTrue(schema.paymentOrTransferResultFields.contains("recipient"))
        XCTAssertTrue(schema.paymentOrTransferResultFields.contains("txHash"))
        XCTAssertTrue(schema.timestampFields.contains("timestamp"))
        XCTAssertTrue(schema.timestampFields.contains("submittedAt"))
        XCTAssertTrue(schema.timestampFields.contains("confirmedAt"))
        XCTAssertTrue(schema.statusDiscriminatorFields.contains("status"))
        XCTAssertTrue(schema.statusDiscriminatorFields.contains("chainStatus"))
        XCTAssertTrue(schema.statusDiscriminatorFields.contains("chainProofType"))
        XCTAssertTrue(schema.statusDiscriminatorFields.contains("presentationState"))

        let validReceipt: [String: Any] = [
            "receiptId": "receipt-base-schema-001",
            "requestId": "ios-grocery-base-schema-001",
            "capabilityId": "grocery.purchase_essentials",
            "targetAppId": "app.dailymart",
            "targetBundleId": "ai.meshkit.sample.dailymart",
            "requestPayloadHash": [
                "algorithm": "sha256",
                "value": String(repeating: "b", count: 64)
            ],
            "status": "purchased",
            "result": [
                "receiptOwner": "app.dailymart#ai.meshkit.sample.dailymart",
                "targetReceiptOwner": "app.dailymart#ai.meshkit.sample.dailymart",
                "requestHash": String(repeating: "c", count: 64),
                "requestNonce": "nonce-ios-grocery-base-schema-001",
                "anchoringReference": "anchor-ios-grocery-base-schema-001",
                "chainStatus": "confirmed",
                "chainProofType": "payment_execution",
                "presentationState": "paid_complete",
                "asset": "OKRW",
                "amount": "100",
                "recipient": "maroo1dailymartrecipient",
                "txHash": "0xabc123",
                "confirmedAt": "2026-05-31T00:00:05Z"
            ],
            "nonce": "receipt-base-schema-nonce-001",
            "timestamp": "2026-05-31T00:00:06Z",
            "signature": [
                "algorithm": "Ed25519",
                "keyId": "dailymart-receipt-key",
                "value": "placeholder-signature"
            ]
        ]
        let validData = try JSONSerialization.data(withJSONObject: validReceipt, options: [.sortedKeys])
        XCTAssertNoThrow(try MeshReceipt.validateProviderNeutralCoreSchema(jsonData: validData))

        var missingRequestId = validReceipt
        missingRequestId.removeValue(forKey: "requestId")
        let missingRequestIdData = try JSONSerialization.data(withJSONObject: missingRequestId, options: [.sortedKeys])
        XCTAssertThrowsError(try MeshReceipt.validateProviderNeutralCoreSchema(jsonData: missingRequestIdData)) { error in
            XCTAssertEqual(error as? MeshKitValidationError, .invalidSecurityField("receipt.requestId"))
        }

        var invalidPayloadHash = validReceipt
        invalidPayloadHash["requestPayloadHash"] = [
            "algorithm": "sha256",
            "value": "not-a-sha256"
        ]
        let invalidPayloadHashData = try JSONSerialization.data(withJSONObject: invalidPayloadHash, options: [.sortedKeys])
        XCTAssertThrowsError(try MeshReceipt.validateProviderNeutralCoreSchema(jsonData: invalidPayloadHashData)) { error in
            XCTAssertEqual(error as? MeshKitValidationError, .invalidSecurityField("receipt.requestPayloadHash.value"))
        }

        var invalidResult = validReceipt
        invalidResult["result"] = [
            "chainStatus": "confirmed",
            "amount": 100
        ]
        let invalidResultData = try JSONSerialization.data(withJSONObject: invalidResult, options: [.sortedKeys])
        XCTAssertThrowsError(try MeshReceipt.validateProviderNeutralCoreSchema(jsonData: invalidResultData)) { error in
            XCTAssertEqual(error as? MeshKitValidationError, .invalidSecurityField("receipt.result[amount]"))
        }
    }

    func testSignedTargetReceiptRejectsTamperedResultAndWrongCorrelationToken() throws {
        let targetKey = Curve25519.Signing.PrivateKey()
        let request = dailyMartRequest(nonce: "nonce-receipt-tamper")
        let receipt = try MeshReceiptSigner.ed25519(
            keyId: "dailymart-receipt-key",
            privateKey: targetKey
        ).makeReceipt(
            receiptId: "receipt-002",
            request: request,
            targetAppId: "app.dailymart",
            targetBundleId: "ai.meshkit.sample.dailymart",
            status: "purchased",
            result: ["order_id": "DM-2026-0509-002", "total_krw": "100"],
            nonce: "receipt-nonce-002",
            timestamp: ISO8601DateFormatter().string(from: Date())
        )
        let tampered = MeshReceipt(
            receiptId: receipt.receiptId,
            requestId: receipt.requestId,
            capabilityId: receipt.capabilityId,
            targetAppId: receipt.targetAppId,
            targetBundleId: receipt.targetBundleId,
            requestPayloadHash: receipt.requestPayloadHash,
            status: receipt.status,
            result: ["order_id": "DM-ATTACK", "total_krw": "1"],
            nonce: receipt.nonce,
            timestamp: receipt.timestamp,
            signature: receipt.signature
        )
        let trust = MeshReceiptTrust(
            targetAppId: "app.dailymart",
            targetBundleId: "ai.meshkit.sample.dailymart",
            receiptSigningAlgorithm: "Ed25519",
            receiptSigningKeyId: "dailymart-receipt-key",
            publicKey: targetKey.publicKey.rawRepresentation.base64EncodedString()
        )

        XCTAssertThrowsError(try MeshReceiptVerifier.verify(tampered, trust: trust, maxAgeSeconds: 60)) { error in
            XCTAssertEqual(error as? MeshKitValidationError, .signatureMismatch("invalid receipt signature"))
        }

        let store = MeshPendingReceiptStore()
        _ = store.register(request: request, capabilityId: "grocery.purchase_essentials")
        XCTAssertThrowsError(try store.consumeVerified(receipt, expectedToken: "wrong-token", trust: trust, maxAgeSeconds: 60)) { error in
            XCTAssertEqual(error as? MeshKitValidationError, .receiptCorrelationMismatch)
        }
    }

    private var samplePolicy: MeshTargetPolicy {
        MeshTargetPolicy(
            allowedCallerAppId: "app.hermes-chat",
            targetBundleId: "ai.meshkit.sample.mintnotes",
            capabilityId: "notes.append_note"
        )
    }

    private func sampleChainProviderIdentity() throws -> MeshChainProviderIdentity {
        try MeshChainProviderIdentity(
            providerName: "maroo",
            networkIdentity: "maroo-testnet",
            chainId: "maroo-testnet-1",
            rpcEndpoint: try XCTUnwrap(URL(string: "https://rpc-testnet.example.invalid")),
            explorerBaseURL: try XCTUnwrap(URL(string: "https://explorer-testnet.example.invalid"))
        )
    }

    private func sampleAgentWalletProviderMetadata() throws -> MeshAgentWalletProviderMetadata {
        try MeshAgentWalletProviderMetadata(
            chainProviderIdentity: sampleChainProviderIdentity(),
            adapterId: "maroo-testnet-demo-adapter"
        )
    }

    private func sampleAgentWalletIdentity() throws -> MeshAgentWalletIdentity {
        try MeshAgentWalletIdentity(
            walletId: "wallet-hermes-dailymart-okrw-v1",
            agentId: "agent.hermes-chat.daily-mart",
            walletAddress: "maroo1dailyMartAgentWallet",
            providerMetadata: sampleAgentWalletProviderMetadata(),
            signingBoundary: .providerSubmission
        )
    }

    private func assertAgentWalletAddressReportingContract(
        _ wallet: some MeshAgentWallet,
        expectedProvider: String,
        expectedNetwork: String,
        expectedChainId: String,
        expectedWalletAddress: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        let configuration = try wallet.loadWalletConfiguration()

        XCTAssertTrue(configuration.supports(.reportWalletAddress), file: file, line: line)
        XCTAssertEqual(configuration.identity.providerMetadata.provider, expectedProvider, file: file, line: line)
        XCTAssertEqual(configuration.identity.providerMetadata.network, expectedNetwork, file: file, line: line)
        XCTAssertEqual(configuration.identity.providerMetadata.chainId, expectedChainId, file: file, line: line)
        XCTAssertEqual(configuration.identity.walletAddress, expectedWalletAddress, file: file, line: line)
        XCTAssertEqual(try wallet.reportWalletAddress(), expectedWalletAddress, file: file, line: line)
    }

    private func sampleDelegatedSpendingScope() throws -> MeshAgentWalletSpendingScope {
        try MeshAgentWalletSpendingScope(
            merchantId: "merchant.dailymart",
            targetBundleId: "ai.meshkit.sample.dailymart",
            capabilityId: "grocery.purchase_essentials",
            consentGrantId: "grant-hermes-dailymart-001"
        )
    }

    private func sampleDelegatedSpendingLimit() throws -> MeshAgentWalletDelegatedSpendingLimit {
        let policy = try sampleDelegatedSpendingPolicy()
        return try MeshAgentWalletDelegatedSpendingLimit(
            limitAmount: Decimal(10_000),
            availableLimit: Decimal(8_500),
            currencyCode: "krw",
            tokenSymbol: "okrw",
            scope: sampleDelegatedSpendingScope(),
            expiresAt: "2026-06-30T00:00:00Z",
            policyMetadata: MeshAgentWalletDelegatedSpendingPolicyMetadata(policy: policy)
        )
    }

    private func sampleDelegatedSpendingPolicy() throws -> MeshAgentWalletDelegatedSpendingPolicy {
        try MeshAgentWalletDelegatedSpendingPolicy(
            policyId: "policy-hermes-dailymart-okrw-v1",
            policyHash: MeshPayloadHash(value: String(repeating: "f", count: 64)),
            consentGrantId: "grant-hermes-dailymart-001",
            merchantScope: "merchant.dailymart",
            capabilityScope: "grocery.purchase_essentials",
            singlePaymentMax: Decimal(5_000),
            sessionTotalLimit: Decimal(10_000),
            remainingLimit: Decimal(10_000),
            expiresAt: "2026-06-30T00:00:00Z",
            asset: "okrw",
            recipientAddress: "maroo1dailyMartMerchant"
        )
    }

    private func sampleDelegatedSpendingPolicyJSONObject() -> [String: Any] {
        [
            "policyId": "policy-hermes-dailymart-okrw-v1",
            "policyHash": [
                "algorithm": "sha256",
                "value": String(repeating: "f", count: 64)
            ],
            "consentGrantId": "grant-hermes-dailymart-001",
            "merchantScope": "merchant.dailymart",
            "capabilityScope": "grocery.purchase_essentials",
            "singlePaymentMax": 5_000,
            "sessionTotalLimit": 10_000,
            "remainingLimit": 10_000,
            "expiresAt": "2026-06-30T00:00:00Z",
            "asset": "OKRW",
            "recipientAddress": "maroo1dailyMartMerchant"
        ]
    }

    private func sampleAgentWalletExecutionRequest(
        executionId: String = "exec-ios-grocery-test-001",
        kind: MeshAgentWalletExecutionKind,
        amount: Decimal,
        nonce: String,
        recipientAddress: String = "maroo1dailyMartMerchant"
    ) throws -> MeshAgentWalletExecutionRequest {
        try MeshAgentWalletExecutionRequest(
            executionId: executionId,
            kind: kind,
            requestAnchorMetadata: MeshSignedRequestAnchorMetadata(
                request: dailyMartRequest(nonce: nonce, budget: "\(amount)")
            ),
            scope: sampleDelegatedSpendingScope(),
            amount: amount,
            currencyCode: "krw",
            tokenSymbol: "okrw",
            recipientAddress: recipientAddress,
            policyId: "policy-hermes-dailymart-okrw-v1",
            policyHash: MeshPayloadHash(value: String(repeating: "f", count: 64))
        )
    }

    private func sampleRequestAnchor(
        metadata: MeshSignedRequestAnchorMetadata,
        status: MeshRequestAnchorStatus
    ) throws -> MeshRequestAnchor {
        try MeshRequestAnchor(
            metadata: metadata,
            identifier: MeshRequestAnchorIdentifier(
                identity: try sampleChainProviderIdentity(),
                anchorId: "anchor-\(metadata.requestId)",
                transactionHash: "0xanchor123"
            ),
            status: status,
            submittedAt: "2026-05-31T00:00:00Z",
            observedAt: "2026-05-31T00:00:00Z"
        )
    }

    private func samplePaymentExecutionRequest(
        executionId: String = "exec-ios-grocery-test-001",
        kind: MeshAgentWalletExecutionKind,
        amount: Decimal,
        nonce: String,
        authorizationStatus: MeshAgentWalletAuthorizationStatus
    ) throws -> MeshPaymentExecutionRequest {
        let executionRequest = try sampleAgentWalletExecutionRequest(
            executionId: executionId,
            kind: kind,
            amount: amount,
            nonce: nonce
        )
        let authorizationDecision = try MeshAgentWalletAuthorizationDecision(
            authorizationId: "auth-\(executionRequest.executionId)",
            walletIdentity: sampleAgentWalletIdentity(),
            executionRequest: executionRequest,
            status: authorizationStatus,
            approvedAmount: authorizationStatus == .approved ? amount : nil,
            reason: authorizationStatus == .denied ? "delegated-limit-exceeded" : nil,
            decidedAt: "2026-05-31T00:00:00Z"
        )
        let anchor = try sampleRequestAnchor(
            metadata: executionRequest.requestAnchorMetadata,
            status: .confirmed
        )
        return try MeshPaymentExecutionRequest(
            paymentId: "pay-ios-grocery-test-001",
            authorizationDecision: authorizationDecision,
            requestAnchor: anchor,
            requestedAt: "2026-05-31T00:00:01Z"
        )
    }

    private static let signingKey = Curve25519.Signing.PrivateKey()

    private var sampleTrust: MeshSenderTrust {
        MeshSenderTrust(
            callerAppId: "app.hermes-chat",
            callerBundleId: "ai.meshkit.sample.hermeschat",
            teamId: "DEVTEAMID",
            requestSigningAlgorithm: "Ed25519",
            requestSigningKeyId: "demo-key",
            publicKey: Self.signingKey.publicKey.rawRepresentation.base64EncodedString()
        )
    }

    private func signed(_ request: MeshRequest) -> MeshRequest {
        let signature = try! Self.signingKey.signature(for: request.signingInputData()).base64EncodedString()
        return MeshRequest(
            requestId: request.requestId,
            caller: request.caller,
            target: request.target,
            payload: request.payload,
            payloadHash: request.payloadHash,
            nonce: request.nonce,
            timestamp: request.timestamp,
            signature: MeshSignature(algorithm: "Ed25519", keyId: "demo-key", value: signature)
        )
    }

    private func sampleRequest(nonce: String, signatureValue: String? = nil) -> MeshRequest {
        let unsigned = MeshRequest(
            requestId: "ios-test-001",
            caller: MeshIdentity(
                appId: "app.hermes-chat",
                installId: "ios-sim",
                bundleId: "ai.meshkit.sample.hermeschat",
                publicKeyId: "demo-key"
            ),
            target: MeshCapability(
                targetBundleId: "ai.meshkit.sample.mintnotes",
                capabilityId: "notes.append_note",
                version: "1.0"
            ),
            payload: ["note_ref": "ios:mint:demo", "text": "Ship MeshKit iOS demo with OCG discovery."],
            nonce: nonce,
            timestamp: ISO8601DateFormatter().string(from: Date()),
            signature: MeshSignature(algorithm: "Ed25519", keyId: "demo-key", value: signatureValue ?? "")
        )
        if signatureValue != nil { return unsigned }
        return signed(unsigned)
    }

    private func dailyMartRequest(nonce: String, budget: String = "100", signatureValue: String? = nil) -> MeshRequest {
        signedDailyMartRequest(
            requestId: "ios-grocery-test-001",
            nonce: nonce,
            budget: budget,
            callerPublicKeyId: "demo-key",
            signatureKeyId: "demo-key",
            signingKey: Self.signingKey,
            signatureValue: signatureValue
        )
    }

    private func signedDailyMartRequest(
        requestId: String,
        nonce: String,
        budget: String = "100",
        callerPublicKeyId: String,
        signatureKeyId: String,
        signingKey: Curve25519.Signing.PrivateKey,
        signatureValue: String? = nil
    ) -> MeshRequest {
        let unsigned = MeshRequest(
            requestId: requestId,
            caller: MeshIdentity(
                appId: "app.hermes-chat",
                installId: "ios-sim",
                bundleId: "ai.meshkit.sample.hermeschat",
                publicKeyId: callerPublicKeyId
            ),
            target: MeshCapability(
                targetBundleId: "ai.meshkit.sample.dailymart",
                capabilityId: "grocery.purchase_essentials",
                version: "1.0"
            ),
            payload: [
                "items": "laundry_detergent:1,toilet_paper:2,bottled_water_2l:6",
                "address_ref": "home.saved",
                "budget_krw": budget,
                "merchantScope": DailyMartDelegatedSpendingPolicy.merchantScope,
                "capabilityScope": DailyMartDelegatedSpendingPolicy.capabilityScope,
                "consentGrantId": DailyMartDelegatedSpendingPolicy.consentGrantId,
                "policyId": DailyMartDelegatedSpendingPolicy.policyId,
                "policyHash": DailyMartDelegatedSpendingPolicy.policyHash.value
            ],
            nonce: nonce,
            timestamp: ISO8601DateFormatter().string(from: Date()),
            signature: MeshSignature(algorithm: "Ed25519", keyId: signatureKeyId, value: signatureValue ?? "")
        )
        guard signatureValue == nil else { return unsigned }
        let signature = try! signingKey.signature(for: unsigned.signingInputData()).base64EncodedString()
        return MeshRequest(
            requestId: unsigned.requestId,
            caller: unsigned.caller,
            target: unsigned.target,
            payload: unsigned.payload,
            payloadHash: unsigned.payloadHash,
            nonce: unsigned.nonce,
            timestamp: unsigned.timestamp,
            signature: MeshSignature(algorithm: "Ed25519", keyId: signatureKeyId, value: signature)
        )
    }
}
