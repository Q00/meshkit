import XCTest
@testable import MeshKit

final class MeshAgentWalletAddressReportingModuleTests: XCTestCase {
    func testReportsConfiguredWalletAddressThroughProviderNeutralModule() throws {
        let wallet = try StaticAddressReportingWallet(reportedAddress: "maroo1dailyMartAgentWallet")
        let module = MeshAgentWalletAddressReportingModule(wallet: wallet)

        let report = try module.reportWalletAddress()

        XCTAssertEqual(report.walletId, "wallet-hermes-dailymart-okrw-v1")
        XCTAssertEqual(report.agentId, "agent.hermes-chat.daily-mart")
        XCTAssertEqual(report.walletAddress, "maroo1dailyMartAgentWallet")
        XCTAssertEqual(report.provider, "maroo")
        XCTAssertEqual(report.network, "maroo-testnet")
        XCTAssertEqual(report.chainId, "maroo-testnet-1")
        XCTAssertEqual(report.adapterId, "maroo-testnet-agent-wallet-adapter")
        XCTAssertEqual(report.signingBoundary, .providerSubmission)
    }

    func testRejectsMissingWalletAddressFromAdapterReport() throws {
        let wallet = try StaticAddressReportingWallet(reportedAddress: "")
        let module = MeshAgentWalletAddressReportingModule(wallet: wallet)

        XCTAssertThrowsError(try module.reportWalletAddress()) { error in
            XCTAssertEqual(error as? MeshKitValidationError, .invalidAgentWalletIdentity("walletAddress"))
        }
    }

    func testRejectsMalformedWalletAddressFromAdapterReport() throws {
        let wallet = try StaticAddressReportingWallet(reportedAddress: "maroo1dailyMart\nAgentWallet")
        let module = MeshAgentWalletAddressReportingModule(wallet: wallet)

        XCTAssertThrowsError(try module.reportWalletAddress()) { error in
            XCTAssertEqual(error as? MeshKitValidationError, .invalidAgentWalletIdentity("walletAddress"))
        }
    }

    private struct StaticAddressReportingWallet: MeshAgentWallet {
        let identity: MeshAgentWalletIdentity
        let capabilities: [MeshAgentWalletCapability]
        let reportedAddress: String

        init(
            reportedAddress: String,
            capabilities: [MeshAgentWalletCapability] = [.reportWalletAddress]
        ) throws {
            self.identity = try MeshAgentWalletIdentity(
                walletId: "wallet-hermes-dailymart-okrw-v1",
                agentId: "agent.hermes-chat.daily-mart",
                walletAddress: "maroo1dailyMartAgentWallet",
                providerMetadata: MeshAgentWalletProviderMetadata(
                    provider: "maroo",
                    network: "maroo-testnet",
                    chainId: "maroo-testnet-1",
                    adapterId: "maroo-testnet-agent-wallet-adapter"
                ),
                signingBoundary: .providerSubmission
            )
            self.capabilities = capabilities
            self.reportedAddress = reportedAddress
        }

        func loadWalletConfiguration() throws -> MeshAgentWalletConfiguration {
            try MeshAgentWalletConfiguration(identity: identity, capabilities: capabilities)
        }

        func reportWalletAddress() throws -> String {
            reportedAddress
        }

        func delegatedSpendingLimit() throws -> MeshAgentWalletDelegatedSpendingLimit {
            throw MeshKitValidationError.unsupportedCapability
        }

        func signingBoundary() throws -> MeshAgentWalletSigningBoundary {
            throw MeshKitValidationError.unsupportedCapability
        }

        func signRequestAnchorPayload(
            _ payload: MeshAgentWalletAnchorSigningPayload,
            signedAt: String
        ) throws -> MeshAgentWalletAnchorSignature {
            throw MeshKitValidationError.unsupportedCapability
        }

        func signExecutionAuthorizationPayload(
            _ payload: MeshAgentWalletExecutionAuthorizationPayload,
            signedAt: String
        ) throws -> MeshAgentWalletExecutionAuthorization {
            throw MeshKitValidationError.unsupportedCapability
        }

        func authorizeExecution(
            _ request: MeshAgentWalletExecutionRequest,
            decidedAt: String
        ) throws -> MeshAgentWalletAuthorizationDecision {
            throw MeshKitValidationError.unsupportedCapability
        }
    }
}
