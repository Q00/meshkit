import XCTest
@testable import MeshKit

final class MeshAgentWalletIdentityMetadataTests: XCTestCase {
    func testIdentityMetadataExposesProviderNeutralDelegatedWalletFields() throws {
        let providerMetadata = try MeshAgentWalletProviderMetadata(
            provider: "ExampleChain",
            network: "SandboxNet",
            chainId: "example-chain-1",
            rpcEndpoint: URL(string: "HTTPS://RPC.EXAMPLE.TEST/")!,
            explorerBaseUrl: URL(string: "HTTPS://EXPLORER.EXAMPLE.TEST/")!,
            adapterId: "example-agent-wallet-adapter"
        )
        let identity = try MeshAgentWalletIdentity(
            walletId: "wallet-example-delegated-001",
            agentId: "agent.hermes-chat.daily-mart",
            walletAddress: "example1delegatedwallet",
            providerMetadata: providerMetadata,
            signingBoundary: .externalWalletApp
        )
        let configuration = try MeshAgentWalletConfiguration(
            identity: identity,
            capabilities: [
                .reportWalletAddress,
                .exposeSigningBoundary,
                .validatePolicy,
                .reportDelegatedSpendingLimit
            ]
        )

        let metadata = try MeshAgentWalletIdentityMetadata(configuration: configuration)

        XCTAssertEqual(metadata.walletId, "wallet-example-delegated-001")
        XCTAssertEqual(metadata.agentId, "agent.hermes-chat.daily-mart")
        XCTAssertEqual(metadata.walletAddress, "example1delegatedwallet")
        XCTAssertEqual(metadata.provider, "examplechain")
        XCTAssertEqual(metadata.network, "sandboxnet")
        XCTAssertEqual(metadata.chainId, "example-chain-1")
        XCTAssertEqual(metadata.rpcEndpoint?.absoluteString, "https://rpc.example.test")
        XCTAssertEqual(metadata.explorerBaseUrl?.absoluteString, "https://explorer.example.test")
        XCTAssertEqual(metadata.adapterId, "example-agent-wallet-adapter")
        XCTAssertEqual(metadata.signingBoundary, .externalWalletApp)
        XCTAssertEqual(
            metadata.capabilities,
            [
                .exposeSigningBoundary,
                .reportDelegatedSpendingLimit,
                .reportWalletAddress,
                .validatePolicy
            ].sorted()
        )
    }

    func testAgentWalletInterfaceExposesIdentityMetadataWithoutProviderSpecificCoreFields() throws {
        let wallet: any MeshAgentWallet = try MeshMarooAgentWalletAdapter(
            chainProviderIdentity: MeshMarooTestnetChainProvider().identity,
            walletId: "wallet-hermes-dailymart-okrw-v1",
            agentId: "agent.hermes-chat.daily-mart",
            walletAddress: "maroo1dailyMartAgentWallet"
        )

        let metadata = try wallet.delegatedWalletIdentityMetadata()

        XCTAssertEqual(metadata.walletId, "wallet-hermes-dailymart-okrw-v1")
        XCTAssertEqual(metadata.agentId, "agent.hermes-chat.daily-mart")
        XCTAssertEqual(metadata.walletAddress, "maroo1dailyMartAgentWallet")
        XCTAssertEqual(metadata.provider, "maroo")
        XCTAssertEqual(metadata.network, "maroo-testnet")
        XCTAssertEqual(metadata.chainId, "maroo-testnet-1")
        XCTAssertEqual(metadata.rpcEndpoint?.absoluteString, "https://rpc-testnet.maroo.io")
        XCTAssertEqual(metadata.explorerBaseUrl?.absoluteString, "https://explorer-testnet.maroo.io")
        XCTAssertEqual(metadata.adapterId, "maroo-testnet-agent-wallet-adapter")
        XCTAssertEqual(metadata.signingBoundary, .providerSubmission)
        XCTAssertEqual(metadata.capabilities, [.exposeSigningBoundary, .reportWalletAddress])
    }

    func testIdentityMetadataRejectsMissingDelegatedWalletIdentityAndCapabilities() throws {
        XCTAssertThrowsError(
            try MeshAgentWalletIdentity(
                walletId: "",
                agentId: "agent.hermes-chat.daily-mart",
                walletAddress: "example1delegatedwallet",
                providerMetadata: MeshAgentWalletProviderMetadata(
                    provider: "examplechain",
                    network: "sandboxnet",
                    chainId: "example-chain-1"
                ),
                signingBoundary: .localSignature
            )
        ) { error in
            XCTAssertEqual(
                error.localizedDescription,
                MeshKitValidationError.invalidAgentWalletIdentity("walletId").localizedDescription
            )
        }

        let identity = try MeshAgentWalletIdentity(
            walletId: "wallet-example-delegated-001",
            agentId: "agent.hermes-chat.daily-mart",
            walletAddress: "example1delegatedwallet",
            providerMetadata: MeshAgentWalletProviderMetadata(
                provider: "examplechain",
                network: "sandboxnet",
                chainId: "example-chain-1"
            ),
            signingBoundary: .localSignature
        )

        XCTAssertThrowsError(try MeshAgentWalletIdentityMetadata(identity: identity, capabilities: [])) { error in
            XCTAssertEqual(error.localizedDescription, MeshKitValidationError.unsupportedCapability.localizedDescription)
        }
    }
}
