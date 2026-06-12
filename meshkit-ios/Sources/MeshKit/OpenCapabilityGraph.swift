import Foundation

public enum OcgRisk: String, Codable, Sendable {
    case readOnly = "read_only"
    case writeUserContent = "write:user_content"
    case spendMoney = "spend:money"
    case externalSideEffect = "external_side_effect"
}

public enum OcgConsent: String, Codable, Sendable {
    case perInvocation = "per_invocation"
    case budgetedPerInvocation = "budgeted_per_invocation"
    case rememberForApp = "remember_for_app"
}

public struct OcgCapability: Codable, Equatable, Sendable {
    public let id: String
    public let displayName: String
    public let risk: String
    public let consent: String
    public let urlScheme: String
    public let inputSchema: [String]
    public let resultSchema: [String]
}

public struct OcgApp: Codable, Equatable, Sendable {
    public let appId: String
    public let ocgAppId: String?
    public let displayName: String
    public let bundleId: String
    public let publisher: String
    public let capabilities: [OcgCapability]

    public init(
        appId: String,
        ocgAppId: String? = nil,
        displayName: String,
        bundleId: String,
        publisher: String,
        capabilities: [OcgCapability]
    ) {
        self.appId = appId
        self.ocgAppId = ocgAppId
        self.displayName = displayName
        self.bundleId = bundleId
        self.publisher = publisher
        self.capabilities = capabilities
    }
}

public struct OpenCapabilityGraph: Codable, Equatable, Sendable {
    public let schemaVersion: String
    public let apps: [OcgApp]

    public func findCapability(_ capabilityId: String) -> OcgCapability? {
        apps.flatMap { $0.capabilities }.first { $0.id == capabilityId }
    }

    public func acpRegistryDescriptors() -> [AcpAppDescriptor] {
        apps.map { app in
            let slug = app.appId
                .replacingOccurrences(of: "app.", with: "")
                .lowercased()
            return AcpAppDescriptor(
                schemaVersion: "meshkit-acp-superapp/v1",
                appId: app.appId,
                ocgAppId: app.ocgAppId ?? app.appId,
                displayName: app.displayName,
                publisher: app.publisher,
                acpEndpoint: "acp://\(slug)/apps",
                mcpTransport: "app-to-app-url-scheme",
                bundleId: app.bundleId,
                platform: "ios-demo",
                registrySource: "meshkit-ios-sample",
                capabilities: app.capabilities.map(AcpCapabilityDescriptor.init(ocgCapability:))
            )
        }
    }

    public static let mintNotesSample = OpenCapabilityGraph(
        schemaVersion: "0.1",
        apps: [OcgApp(
            appId: "app.mint-notes",
            ocgAppId: "ai.meshkit.sample.notes",
            displayName: "MintNotes",
            bundleId: "ai.meshkit.sample.mintnotes",
            publisher: "MeshKit Samples",
            capabilities: [OcgCapability(
                id: "notes.append_note",
                displayName: "Append Note",
                risk: "write:user_content",
                consent: "per_invocation",
                urlScheme: "mintnotes://mesh/invoke",
                inputSchema: ["note_ref", "text"],
                resultSchema: ["status", "note_ref", "audit_id"]
            )]
        )]
    )

    public static let dailyMartSample = OpenCapabilityGraph(
        schemaVersion: "0.1",
        apps: [OcgApp(
            appId: "app.dailymart",
            ocgAppId: "ai.meshkit.sample.dailymart",
            displayName: "DailyMart",
            bundleId: "ai.meshkit.sample.dailymart",
            publisher: "MeshKit Samples",
            capabilities: [OcgCapability(
                id: "grocery.purchase_essentials",
                displayName: "Purchase Essentials",
                risk: "spend:money",
                consent: "budgeted_per_invocation",
                urlScheme: "dailymart://mesh/invoke",
                inputSchema: ["items", "address_ref", "budget_krw"],
                resultSchema: ["status", "order_id", "total_krw", "audit_id"]
            )]
        )]
    )
}

public struct AcpCapabilityDescriptor: Codable, Equatable, Sendable {
    public let id: String
    public let displayName: String
    public let risk: String
    public let consent: String
    public let requiresPayment: Bool
    public let asset: String?
    public let urlScheme: String
    public let inputSchema: [String]
    public let resultSchema: [String]
    public let routingHint: String

    public init(ocgCapability: OcgCapability) {
        let requiresPayment = ocgCapability.risk == OcgRisk.spendMoney.rawValue
        self.id = ocgCapability.id
        self.displayName = ocgCapability.displayName
        self.risk = ocgCapability.risk
        self.consent = ocgCapability.consent
        self.requiresPayment = requiresPayment
        self.asset = requiresPayment ? "OKRW" : nil
        self.urlScheme = ocgCapability.urlScheme
        self.inputSchema = ocgCapability.inputSchema
        self.resultSchema = ocgCapability.resultSchema
        self.routingHint = requiresPayment ? "onchain_payment" : "offchain_app_call"
    }
}

public struct AcpAppDescriptor: Codable, Equatable, Sendable {
    public let schemaVersion: String
    public let appId: String
    public let ocgAppId: String
    public let displayName: String
    public let publisher: String
    public let acpEndpoint: String
    public let mcpTransport: String
    public let bundleId: String
    public let platform: String
    public let registrySource: String
    public let capabilities: [AcpCapabilityDescriptor]
}
