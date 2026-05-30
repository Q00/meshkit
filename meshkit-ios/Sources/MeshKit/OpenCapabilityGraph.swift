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
    public let displayName: String
    public let bundleId: String
    public let publisher: String
    public let capabilities: [OcgCapability]
}

public struct OpenCapabilityGraph: Codable, Equatable, Sendable {
    public let schemaVersion: String
    public let apps: [OcgApp]

    public func findCapability(_ capabilityId: String) -> OcgCapability? {
        apps.flatMap { $0.capabilities }.first { $0.id == capabilityId }
    }

    public static let mintNotesSample = OpenCapabilityGraph(
        schemaVersion: "0.1",
        apps: [OcgApp(
            appId: "app.mint-notes",
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
            appId: "app.daily-mart",
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
