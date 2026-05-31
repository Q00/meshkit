import Foundation

public enum MeshRequestAnchorProviderWiring {
    public static func resolveRequestAnchorProvider(
        chainProviderIdentity identity: MeshChainProviderIdentity,
        capabilities: [MeshChainProviderCapability] = MeshMarooTestnetRequestAnchorAdapter.defaultCapabilities,
        status: MeshRequestAnchorStatus = .submitted,
        transactionHash: String? = nil,
        message: String? = nil,
        submissionClient: (any MeshMarooTestnetRequestAnchorSubmissionClient)? = nil
    ) throws -> any MeshRequestAnchorProvider {
        let marooIdentity = try MeshMarooTestnetChainProvider().identity
        guard identity.metadata == marooIdentity.metadata else {
            throw MeshKitValidationError.invalidChainProviderIdentity("requestAnchorProvider")
        }

        let chainProvider = try MeshMarooTestnetChainProvider(
            rpcEndpoint: identity.rpcEndpoint,
            explorerBaseURL: identity.explorerBaseURL ?? MeshMarooTestnetChainProvider.defaultExplorerBaseURL,
            capabilities: capabilities
        )
        return try MeshMarooTestnetRequestAnchorAdapter(
            chainProvider: chainProvider,
            capabilities: capabilities,
            status: status,
            transactionHash: transactionHash,
            message: message,
            submissionClient: submissionClient
        )
    }
}
