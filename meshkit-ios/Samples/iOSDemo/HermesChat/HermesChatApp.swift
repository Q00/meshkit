import CryptoKit
import SwiftUI
import MeshKit

private enum SampleMeshSigningKey {
    // Sample-only key id. Env vars can override this for tests, but the installed
    // demo app needs a stable local key when launched directly from the iPad.
    static let keyId = "sample-ios-ed25519"
    private static let samplePrivateKeyBase64 = "ciDtnehd8FlWERtZE2lzacQc3/LLIJY0CavAcv0THko="
    private static let samplePublicKeyBase64 = "SYRITem/8/4woLf6P3Iec58z4jBtxzEB+g+UXeS8mcU="
    static func publicKeyBase64() throws -> String {
        let raw = ProcessInfo.processInfo.environment["MESHKIT_IOS_DEMO_PUBLIC_KEY_BASE64"] ?? samplePublicKeyBase64
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw MeshKitValidationError.signatureRequired }
        return trimmed
    }
    static func privateKey() throws -> Curve25519.Signing.PrivateKey {
        let raw = ProcessInfo.processInfo.environment["MESHKIT_IOS_DEMO_PRIVATE_KEY_BASE64"] ?? samplePrivateKeyBase64
        guard !raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              let data = Data(base64Encoded: raw), !data.isEmpty else {
            throw MeshKitValidationError.signatureRequired
        }
        return try Curve25519.Signing.PrivateKey(rawRepresentation: data)
    }
}

private enum SampleDailyMartReceiptKey {
    // Demo target receipt trust. Hermes only receives the DailyMart public key; the target private key lives in DailyMart/backend test config.
    static let keyId = "sample-dailymart-receipt-ed25519"
    private static let samplePublicKeyBase64 = "Bauj33zFJH8pAyxeCxrkn9NNjC/dRfPVXn9avxPskyg="
    static func publicKeyBase64() throws -> String {
        let raw = ProcessInfo.processInfo.environment["MESHKIT_IOS_DAILYMART_RECEIPT_PUBLIC_KEY_BASE64"] ?? samplePublicKeyBase64
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw MeshKitValidationError.signatureRequired }
        return trimmed
    }
}

@main
struct HermesChatApp: App {
    @State private var callbackText = "Ready. Ask Mint Notes to save the message."
    @State private var auditTrail = "Open Calling Graph: notes.append_note discovered from MintNotes manifest."
    @State private var lastAction = "Idle"
    @State private var isBackgroundProcessing = false
    @State private var hasUserPrompt = false
    @State private var isAnalyzingOCG = false
    @State private var showCallableApps = false
    @State private var draftMessage = ""
    @State private var didStartDemoScript = false
    @State private var hasDailyMartConsent = false
    @State private var isSavedConsentCall = false
    @State private var showSavedConsentForegroundAlert = false
    @State private var confirmedReceiptExplorerURL: URL?
    @State private var confirmedDailyMartReceiptResult: [String: String]?
    @State private var pendingReceiptTokens: Set<String> = []
    @State private var pendingReceiptStore = MeshPendingReceiptStore()
    @State private var delegatedWallet = try! HermesChatDelegatedWalletViewModels.marooTestnetOKRWDailyMartGrocerySession()
    @State private var delegatedWalletDecrementHandler = MeshDelegatedWalletReceiptDecrementHandler()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            HermesRootView(
                callbackText: callbackText,
                auditTrail: auditTrail,
                lastAction: lastAction,
                isBackgroundProcessing: isBackgroundProcessing,
                hasUserPrompt: hasUserPrompt,
                isAnalyzingOCG: isAnalyzingOCG,
                showCallableApps: showCallableApps,
                delegatedWallet: delegatedWallet,
                confirmedReceiptExplorerURL: confirmedReceiptExplorerURL,
                hasDailyMartConsent: hasDailyMartConsent,
                isSavedConsentCall: isSavedConsentCall,
                showSavedConsentForegroundAlert: $showSavedConsentForegroundAlert,
                draftMessage: $draftMessage,
                submitPrompt: submitPrompt,
                openMintNotes: openMintNotes,
                openDailyMart: openDailyMart,
                prepareDailyMartSavedConsentCall: prepareDailyMartSavedConsentCall,
                confirmDailyMartSavedConsentCall: confirmDailyMartSavedConsentCall,
                openDailyMartSavedConsentReceipt: openDailyMartSavedConsentReceipt,
                saveDailyMartLedgerToMintNotes: saveDailyMartLedgerToMintNotes
            )
            .onAppear { startDemoScriptIfNeeded() }
            .task { await refreshMarooWalletBalanceIfAvailable() }
            .onChange(of: draftMessage) { newValue in
                if !hasUserPrompt && newValue.count > 70 {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.55) {
                        if !hasUserPrompt { submitPrompt(newValue) }
                    }
                }
            }
            .onChange(of: scenePhase) { phase in
                if phase == .active && lastAction == "Waiting for DailyMart approval" {
                    startDailyMartBackgroundProcessing(auditId: "ios-grocery-001")
                }
            }
            .onOpenURL { url in
                guard let receipt = consumeDemoReceipt(from: url) else {
                    isBackgroundProcessing = false
                    lastAction = "Callback rejected"
                    callbackText = "Rejected callback: missing, unsigned, or mismatched receipt proof."
                    auditTrail = "callback.rejected · request token not pending · signed target receipt verification failed"
                    return
                }
                if receipt.capability == "grocery.purchase_essentials" {
                    hasDailyMartConsent = true
                    let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
                    let status = components?.queryItems?.first(where: { $0.name == "status" })?.value ?? "purchased"
                    let auditId = components?.queryItems?.first(where: { $0.name == "audit_id" })?.value ?? receipt.token
                    let orderState = MeshHermesChatDailyMartOrderStateRecorder.record(
                        receiptResult: receipt.result,
                        callbackStatus: status
                    )
                    if status == "processing" {
                        startDailyMartBackgroundProcessing(auditId: auditId)
                    } else if orderState.kind == .policyDenied || orderState.kind == .attemptedFailed {
                        let displayState = try? delegatedWallet.dailyMartReceiptDisplayState(
                            afterProcessing: receipt.result,
                            fallbackAuditId: auditId
                        )
                        let presentation = displayState?.paymentPresentation ?? MeshDailyMartReceiptPaymentPresentation(receiptResult: receipt.result, fallbackAuditId: auditId)
                        confirmedReceiptExplorerURL = nil
                        confirmedDailyMartReceiptResult = nil
                        isBackgroundProcessing = false
                        lastAction = orderState.lastAction
                        let remainingLimitUnchangedLine = displayState?.remainingLimitUnchangedLine
                            ?? "Remaining session limit unchanged: \(delegatedWallet.panelSnapshot.remainingLimitLine)"
                        callbackText = displayState?.renderedLines.joined(separator: "\n")
                            ?? "\(presentation.title)\n\(presentation.body)\n\(remainingLimitUnchangedLine)"
                        auditTrail = "Target-signed receipt accepted: \(presentation.auditLine)\nreceipt_token=\(receipt.token) · token_consumed=true · BlockedByExternalChain evidence rendered when present · no txHash accepted as confirmed fallback · no txHash."
                    } else if orderState.kind == .submittedNotFinal {
                        let displayState = try? delegatedWallet.dailyMartReceiptDisplayState(
                            afterProcessing: receipt.result,
                            fallbackAuditId: auditId
                        )
                        let presentation = displayState?.paymentPresentation ?? MeshDailyMartReceiptPaymentPresentation(receiptResult: receipt.result, fallbackAuditId: auditId)
                        confirmedReceiptExplorerURL = nil
                        confirmedDailyMartReceiptResult = nil
                        isBackgroundProcessing = false
                        lastAction = orderState.lastAction
                        callbackText = displayState?.renderedLines.joined(separator: "\n")
                            ?? "\(presentation.title)\n\(presentation.body)"
                        auditTrail = "Target-signed receipt accepted: \(presentation.auditLine)\nreceipt_token=\(receipt.token) · token_consumed=true · BlockedByExternalChain evidence rendered when present · no txHash accepted as confirmed fallback · no txHash."
                    } else {
                        let decrement = try? receipt.meshReceipt.map {
                            try delegatedWalletDecrementHandler.apply(receipt: $0, to: delegatedWallet)
                        } ?? delegatedWalletDecrementHandler.apply(
                            receiptId: receipt.receiptId,
                            receiptResult: receipt.result,
                            to: delegatedWallet
                        )
                        let presentation = MeshDailyMartReceiptPaymentPresentation(receiptResult: receipt.result, fallbackAuditId: auditId)
                        confirmedReceiptExplorerURL = presentation.explorerURL
                        confirmedDailyMartReceiptResult = receipt.result
                        if let decrement {
                            delegatedWallet = decrement.wallet
                        }
                        isBackgroundProcessing = false
                        lastAction = orderState.lastAction
                        let remainingLine = decrement?.wallet.panelSnapshot.remainingSessionLimitSummaryLine
                            ?? delegatedWallet.panelSnapshot.remainingSessionLimitSummaryLine
                        callbackText = "\(presentation.title)\n\(presentation.body)\n\(remainingLine)"
                        auditTrail = "Target-signed receipt accepted: \(presentation.auditLine)\nreceipt_token=\(receipt.token) · token_consumed=true · requestId/payloadHash/signature verified · wallet_limit_updated=true."
                    }
                } else {
                    isBackgroundProcessing = false
                    let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
                    let noteRef = components?.queryItems?.first(where: { $0.name == "note_ref" })?.value ?? "unknown"
                    let auditId = components?.queryItems?.first(where: { $0.name == "audit_id" })?.value ?? receipt.token
                    lastAction = "Mint Notes ledger saved"
                    callbackText = "Mint Notes saved the DailyMart household ledger.\nNote ref: \(noteRef)\nAudit id: \(auditId)"
                    auditTrail = "notes.append_note callback accepted · receipt_token=\(receipt.token) · token_consumed=true · ledger derived from verified DailyMart paid receipt."
                }
            }
        }
    }

    private struct DemoReceipt {
        let capability: String
        let token: String
        let receiptId: String
        let result: [String: String]
        let meshReceipt: MeshReceipt?
    }

    private func consumeDemoReceipt(from url: URL) -> DemoReceipt? {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let token = components.queryItems?.first(where: { $0.name == "receipt_token" })?.value,
              !token.isEmpty else {
            return nil
        }
        if let encodedReceipt = components.queryItems?.first(where: { $0.name == "mesh_receipt" })?.value {
            do {
                let receipt = try MeshReceipt.decodedFromURLScheme(encodedReceipt)
                let verified = try pendingReceiptStore.consumeVerified(
                    receipt,
                    expectedToken: token,
                    trust: MeshReceiptTrust(
                        targetAppId: "app.dailymart",
                        targetBundleId: "ai.meshkit.sample.dailymart",
                        receiptSigningAlgorithm: "Ed25519",
                        receiptSigningKeyId: SampleDailyMartReceiptKey.keyId,
                        publicKey: try SampleDailyMartReceiptKey.publicKeyBase64()
                    ),
                    maxAgeSeconds: 300
                )
                return DemoReceipt(
                    capability: verified.capabilityId,
                    token: verified.requestId,
                    receiptId: verified.receiptId,
                    result: verified.result,
                    meshReceipt: verified
                )
            } catch {
                return nil
            }
        }
        guard pendingReceiptTokens.contains(token) else { return nil }
        pendingReceiptTokens.remove(token)
        let capability = components.queryItems?.first(where: { $0.name == "capability" })?.value
            ?? (url.absoluteString.contains("grocery.purchase_essentials") ? "grocery.purchase_essentials" : "notes.append_note")
        guard capability == "notes.append_note" else { return nil }
        return DemoReceipt(capability: capability, token: token, receiptId: token, result: [:], meshReceipt: nil)
    }

    private func startDemoScriptIfNeeded() {
        guard !didStartDemoScript else { return }
        didStartDemoScript = true
        if ProcessInfo.processInfo.arguments.contains("--demo-first-order-complete") {
            hasUserPrompt = true
            isAnalyzingOCG = false
            showCallableApps = false
            hasDailyMartConsent = true
            isSavedConsentCall = false
            isBackgroundProcessing = false
            draftMessage = "Buy water, toilet paper, and detergent tonight. Budget 100 KRW. Deliver home."
            lastAction = "DailyMart order confirmed"
            callbackText = "✅ DailyMart background checkout complete\nOrder DM-2026-0509-001 · Total ₩100 · Delivery 7–9 PM"
            auditTrail = "Callback receipt received: grocery.purchase_essentials.purchased\nHermesChat foreground → DailyMart approved → background checkout → receipt. Audit logged with request nonce, payloadHash, replay guard."
            return
        }
        let chunks = [
            "Buy water",
            "Buy water, toilet paper",
            "Buy water, toilet paper, and detergent tonight.",
            "Buy water, toilet paper, and detergent tonight. Budget 100 KRW.",
            "Buy water, toilet paper, and detergent tonight. Budget 100 KRW. Deliver home."
        ]
        for (index, chunk) in chunks.enumerated() {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.1 + Double(index) * 0.55) {
                if !hasUserPrompt { draftMessage = chunk }
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 4.1) {
            if !hasUserPrompt { submitPrompt(chunks.last ?? draftMessage) }
        }
    }

    private func refreshMarooWalletBalanceIfAvailable() async {
        guard let healthURL = MarooDemoWalletBalanceClient.healthURLFromEnvironment() else {
            NSLog("maroo.wallet_balance.health_skipped missing %@", MarooDemoWalletBalanceClient.transferURLKey)
            return
        }
        NSLog("maroo.wallet_balance.health_fetch %@", healthURL.absoluteString)
        do {
            let balance = try await MarooDemoWalletBalanceClient.fetchBalance(from: healthURL)
            await MainActor.run {
                if let updated = try? delegatedWallet.replacingFundedWalletBalance(balance) {
                    delegatedWallet = updated
                    auditTrail = "maroo.wallet_balance.health_ok · live total wallet balance \(NSDecimalNumber(decimal: balance).stringValue) OKRW"
                }
            }
            NSLog("maroo.wallet_balance.health_ok %@", NSDecimalNumber(decimal: balance).stringValue)
        } catch {
            NSLog("maroo.wallet_balance.health_failed %@", error.localizedDescription)
            await MainActor.run {
                if lastAction == "Idle" {
                    callbackText = "Maroo bridge balance unavailable. Check iPad Local Network permission and bridge URL."
                    auditTrail = "maroo.wallet_balance.health_unavailable · total wallet balance hidden until live bridge health succeeds · \(error.localizedDescription)"
                }
            }
        }
    }

    private func submitPrompt(_ message: String) {
        let normalizedMessage = message.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedMessage.isEmpty else { return }
        draftMessage = normalizedMessage
        hasUserPrompt = true
        showCallableApps = false
        isAnalyzingOCG = true
        isBackgroundProcessing = false
        isSavedConsentCall = false
        lastAction = "Analyzing Open Calling Graph"
        callbackText = "🔎 Reading your message\nMapping intent → grocery.purchase_essentials. Checking callable apps, risk tier, budget, and consent requirements."
        auditTrail = "ocg.scan.started · user_intent=grocery · constraints=budget/home_delivery/items"
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
            isAnalyzingOCG = false
            showCallableApps = true
            lastAction = "Callable apps ready"
            callbackText = "Found 2 callable apps. DailyMart can complete grocery.purchase_essentials after user consent."
            auditTrail = "ocg.scan.complete · DailyMart matched · requires_budget_consent=true · callback=meshkit-hermes://callback"
        }
    }

    private func openMintNotes() {
        openMintNotes(
            requestId: "ios-demo-001",
            noteRef: "ios:mint:demo",
            text: "Ship MeshKit iOS demo with OCG discovery."
        )
    }

    private func openMintNotes(requestId: String, noteRef: String, text: String) {
        let capability = OpenCapabilityGraph.mintNotesSample.findCapability("notes.append_note")
        let caller = MeshIdentity(appId: "app.hermes-chat", installId: "ios-sim", bundleId: "ai.meshkit.sample.hermeschat", publicKeyId: SampleMeshSigningKey.keyId)
        let target = MeshCapability(targetBundleId: "ai.meshkit.sample.mintnotes", capabilityId: capability?.id ?? "notes.append_note", version: "1.0")
        do {
            let request = try MeshSignedRequestBuilder(
                caller: caller,
                target: target,
                signer: MeshRequestSigner.ed25519(keyId: SampleMeshSigningKey.keyId, privateKey: try SampleMeshSigningKey.privateKey())
            ).makeRequest(
                requestId: requestId,
                payload: ["text": text, "note_ref": noteRef],
                nonce: requestId + "-nonce-" + UUID().uuidString,
                timestamp: ISO8601DateFormatter().string(from: Date())
            )
            pendingReceiptTokens.insert(requestId)
            lastAction = "Opening Mint Notes"
            let url = try MeshURLRouter.invokeURL(scheme: capability?.urlScheme ?? "mintnotes://mesh/invoke", request: request)
            UIApplication.shared.open(url)
        } catch {
            callbackText = "Failed to encode MeshRequest: \(error)"
        }
    }

    private func saveDailyMartLedgerToMintNotes() {
        guard let result = confirmedDailyMartReceiptResult else {
            callbackText = "DailyMart paid receipt is not available yet. Hermes only writes a ledger after verified payment completion."
            auditTrail = "ledger.save.blocked · missing confirmed DailyMart receipt"
            return
        }
        let orderId = result["order_id"] ?? "DM-unknown"
        let total = result["total_krw"] ?? result["amount"] ?? "100"
        let asset = result["asset"] ?? result["payment_asset"] ?? delegatedWallet.asset
        let txHash = result["txHash"] ?? "unavailable"
        let explorer = result["explorerUrl"] ?? "unavailable"
        let noteRef = "ledger:dailymart:\(orderId)"
        let requestId = "ios-ledger-\(orderId)-\(UUID().uuidString.prefix(8))"
        let text = [
            "DailyMart household ledger",
            "Order: \(orderId)",
            "Category: groceries",
            "Items: laundry detergent x1, toilet paper x2, bottled water 2L x6",
            "Amount: \(total) \(asset)",
            "Payment: maroo testnet OKRW",
            "Tx hash: \(txHash)",
            "Explorer: \(explorer)"
        ].joined(separator: "\n")
        auditTrail = "ocg.scan.complete · MintNotes matched for notes.append_note · ledger source=verified DailyMart receipt · order_id=\(orderId)"
        openMintNotes(requestId: requestId, noteRef: noteRef, text: text)
    }

    private func startDailyMartBackgroundProcessing(auditId: String) {
        guard !isBackgroundProcessing else { return }
        let savedConsentCall = isSavedConsentCall
        isBackgroundProcessing = true
        if !savedConsentCall {
            hasDailyMartConsent = true
        }
        lastAction = savedConsentCall ? "DailyMart saved-consent MCP call running" : "DailyMart background MCP checkout running"
        callbackText = savedConsentCall
            ? "⏳ Saved-consent MCP call running\nNo DailyMart foreground approval. Hermes invokes grocery.purchase_essentials directly using the stored consent grant."
            : "⏳ DailyMart background MCP checkout running\nHermes Chat is foreground. DailyMart MCP is executing in background."
        auditTrail = savedConsentCall
            ? "Background execution started: grocery.purchase_essentials.processing\nconsent_grant=HermesChat→DailyMart→grocery.purchase_essentials · foreground_approval=false · waiting for callback receipt"
            : "Background execution started: grocery.purchase_essentials.processing\naudit_id=\(auditId) · background=true · waiting for callback receipt"
        DispatchQueue.main.asyncAfter(deadline: .now() + 5.5) {
            callbackText = "Still waiting for DailyMart target-signed receipt. No order is marked complete without receipt verification."
            auditTrail = savedConsentCall
                ? "Background execution pending: grocery.purchase_essentials.processing\naudit_id=\(auditId) · saved consent accepted · completion gated on external DailyMart target receipt"
                : "Background execution pending: grocery.purchase_essentials.processing\naudit_id=\(auditId) · completion gated on target-signed receipt callback"
        }
    }

    private func openDailyMart() {
        let capability = OpenCapabilityGraph.dailyMartSample.findCapability("grocery.purchase_essentials")
        do {
            let invocation = try dailyMartInvocationRequestFactory(
                capabilityId: capability?.id ?? "grocery.purchase_essentials"
            ).makePurchaseEssentialsAnchoredInvocation(providerIdentity: MeshMarooTestnetChainProvider().identity)
            let request = invocation.request
            pendingReceiptStore.register(request: request, capabilityId: "grocery.purchase_essentials")
            lastAction = "Waiting for DailyMart approval"
            showCallableApps = false
            isAnalyzingOCG = false
            isSavedConsentCall = false
            auditTrail = "Open Calling Graph selected DailyMart: grocery.purchase_essentials. Request \(request.requestId) signed with fresh nonce/timestamp/payloadHash. anchoring_reference=\(invocation.anchoringReference.anchorId) request_hash=\(invocation.signedRequestHash.value)"
            let url = try MeshURLRouter.invokeURL(scheme: capability?.urlScheme ?? "dailymart://mesh/invoke", request: request)
            UIApplication.shared.open(url)
        } catch {
            lastAction = "DailyMart call blocked"
            callbackText = "Failed to encode DailyMart MeshRequest: \(error)"
            auditTrail = "DailyMart invocation blocked before app switch: \(error)"
        }
    }

    private func prepareDailyMartSavedConsentCall() {
        guard hasDailyMartConsent else {
            callbackText = "DailyMart still needs first foreground approval before saved-consent background calls."
            return
        }
        showSavedConsentForegroundAlert = true
    }

    private func confirmDailyMartSavedConsentCall() {
        showCallableApps = false
        isAnalyzingOCG = false
        isSavedConsentCall = true
        do {
            let invocation = try savedConsentDailyMartInvocation()
            let request = invocation.request
            pendingReceiptStore.register(request: request, capabilityId: "grocery.purchase_essentials")
            auditTrail = "Saved-grant MCP request signed with fresh nonce/timestamp/payloadHash. anchoring_reference=\(invocation.anchoringReference.anchorId) request_hash=\(invocation.signedRequestHash.value)"
            startDailyMartBackgroundProcessing(auditId: request.requestId)
            let capability = OpenCapabilityGraph.dailyMartSample.findCapability("grocery.purchase_essentials")
            let url = try MeshURLRouter.invokeURL(scheme: capability?.urlScheme ?? "dailymart://mesh/invoke", request: request)
            UIApplication.shared.open(url) { opened in
                if !opened {
                    isBackgroundProcessing = false
                    lastAction = "DailyMart saved-consent call blocked"
                    callbackText = "DailyMart could not be opened for the saved-consent MCP request."
                    auditTrail = "DailyMart saved-consent invocation blocked before target dispatch: app_open_failed"
                }
            }
        } catch {
            lastAction = "DailyMart saved-consent call blocked"
            isBackgroundProcessing = false
            callbackText = "Failed to prepare DailyMart saved-consent request: \(error)"
            auditTrail = "DailyMart saved-consent invocation blocked before background call: \(error)"
        }
    }

    private func savedConsentDailyMartInvocation() throws -> HermesDailyMartAnchoredInvocation {
        try dailyMartInvocationRequestFactory(
            capabilityId: "grocery.purchase_essentials",
            requestIdPrefix: "ios-grocery-saved-consent",
            noncePrefix: "ios-grocery-saved-consent-nonce"
        ).makePurchaseEssentialsAnchoredInvocation(providerIdentity: MeshMarooTestnetChainProvider().identity)
    }

    private func dailyMartInvocationRequestFactory(
        capabilityId: String,
        requestIdPrefix: String = "ios-grocery",
        noncePrefix: String = "ios-grocery-nonce"
    ) throws -> HermesDailyMartInvocationRequestFactory {
        try HermesDailyMartInvocationRequestFactory(
            caller: MeshIdentity(
                appId: "app.hermes-chat",
                installId: "ios-device",
                bundleId: "ai.meshkit.sample.hermeschat",
                publicKeyId: SampleMeshSigningKey.keyId
            ),
            target: MeshCapability(
                targetBundleId: "ai.meshkit.sample.dailymart",
                capabilityId: capabilityId,
                version: "1.0"
            ),
            signer: MeshRequestSigner.ed25519(
                keyId: SampleMeshSigningKey.keyId,
                privateKey: try SampleMeshSigningKey.privateKey()
            ),
            requestIdPrefix: requestIdPrefix,
            noncePrefix: noncePrefix
        )
    }

    private func openDailyMartSavedConsentReceipt() {
        lastAction = "DailyMart receipt proof is target-owned"
        callbackText = "Hermes cannot fabricate a DailyMart receipt. Open the DailyMart target proof only after an external target-signed callback has been accepted."
        auditTrail = "order-proof URL side channel removed · completion requires target-owned signed MeshReceipt · caller private key is not accepted as target proof"
    }
}

private enum MarooDemoWalletBalanceClient {
    static let transferURLKey = "MESHKIT_MAROO_OKRW_TRANSFER_BRIDGE_URL"

    static func healthURLFromEnvironment(
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> URL? {
        guard let rawURL = environment[transferURLKey]?.trimmingCharacters(in: .whitespacesAndNewlines),
              !rawURL.isEmpty,
              var components = URLComponents(string: rawURL) else {
            return nil
        }
        components.path = "/health"
        components.query = nil
        components.fragment = nil
        return components.url
    }

    static func fetchBalance(from url: URL) async throws -> Decimal {
        let (data, response) = try await URLSession.shared.data(from: url)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw MeshKitValidationError.invalidAgentWalletIdentity("marooBridgeHealthStatus")
        }
        let payload = try JSONDecoder().decode(HealthResponse.self, from: data)
        guard payload.ok,
              let rawBalance = payload.data.signerBalanceOKRW,
              let balance = Decimal(string: rawBalance),
              balance >= 0 else {
            throw MeshKitValidationError.invalidAgentWalletIdentity("signerBalanceOKRW")
        }
        return balance
    }

    private struct HealthResponse: Decodable {
        let ok: Bool
        let data: HealthData
    }

    private struct HealthData: Decodable {
        let signerBalanceOKRW: String?
    }
}

private struct HermesRootView: View {
    let callbackText: String
    let auditTrail: String
    let lastAction: String
    let isBackgroundProcessing: Bool
    let hasUserPrompt: Bool
    let isAnalyzingOCG: Bool
    let showCallableApps: Bool
    let delegatedWallet: MeshDelegatedWalletViewModel
    let confirmedReceiptExplorerURL: URL?
    let hasDailyMartConsent: Bool
    let isSavedConsentCall: Bool
    @Binding var showSavedConsentForegroundAlert: Bool
    @Binding var draftMessage: String
    let submitPrompt: (String) -> Void
    let openMintNotes: () -> Void
    let openDailyMart: () -> Void
    let prepareDailyMartSavedConsentCall: () -> Void
    let confirmDailyMartSavedConsentCall: () -> Void
    let openDailyMartSavedConsentReceipt: () -> Void
    let saveDailyMartLedgerToMintNotes: () -> Void

    private let bgTop = Color(red: 0.965, green: 0.972, blue: 0.984)
    private let bgBottom = Color(red: 0.940, green: 0.955, blue: 0.980)
    private let incoming = Color.white
    private let outgoing = Color(red: 0.20, green: 0.39, blue: 1.0)
    private let surface = Color.white
    private let purple = Color(red: 0.48, green: 0.33, blue: 1.0)
    private let orange = Color(red: 1.0, green: 0.48, blue: 0.13)

    var body: some View {
        ZStack {
            LinearGradient(colors: [bgTop, bgBottom], startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                chatHeader
                if hasUserPrompt {
                    pinnedDelegatedWalletPanel
                }

                ScrollView(showsIndicators: false) {
                    VStack(spacing: 14) {
                        dayPill

                        if hasUserPrompt {
                            userMessage

                            if isAnalyzingOCG {
                                ocgAnalysisMessage
                            } else {
                                assistantIntroMessage
                            }

                            if showCallableApps {
                                appPickerMessage
                            }

                            if isBackgroundProcessing || isDailyMartReceiptState {
                                backgroundStatusMessage
                                receiptMessage
                            } else if !showCallableApps && !isAnalyzingOCG {
                                compactHubMessage
                            }
                        } else {
                            emptyChatMessage
                        }
                    }
                    .padding(.horizontal, 14)
                    .padding(.top, 10)
                    .padding(.bottom, 18)
                }

                composer
            }
        }
        .alert("Saved consent: no approval screen", isPresented: $showSavedConsentForegroundAlert) {
            Button("Run background MCP call") {
                confirmDailyMartSavedConsentCall()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This second purchase reuses the saved DailyMart consent grant. DailyMart will execute the signed request without showing another approval screen, then return a target-signed receipt.")
        }
    }

    private var chatHeader: some View {
        HStack(spacing: 11) {
            ZStack(alignment: .bottomTrailing) {
                LinearGradient(colors: [purple, orange], startPoint: .topLeading, endPoint: .bottomTrailing)
                    .frame(width: 43, height: 43)
                    .clipShape(Circle())
                Text("H")
                    .font(.system(size: 22, weight: .black, design: .rounded))
                    .foregroundColor(.white)
                Circle()
                    .fill(.green)
                    .frame(width: 11, height: 11)
                    .overlay(Circle().stroke(Color.white, lineWidth: 2))
                    .offset(x: 1, y: 1)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text("Hermes Chat")
                    .font(.system(size: 19, weight: .black, design: .rounded))
                    .foregroundColor(.primary)
                Text("Open Calling Graph · app-to-app MCP")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }
            Spacer()
            Image(systemName: "phone.fill")
                .font(.system(size: 15, weight: .bold))
                .foregroundColor(.secondary)
                .frame(width: 34, height: 34)
                .background(Color.black.opacity(0.05))
                .clipShape(Circle())
            Image(systemName: "ellipsis")
                .font(.system(size: 17, weight: .heavy))
                .foregroundColor(.secondary)
                .frame(width: 34, height: 34)
                .background(Color.black.opacity(0.05))
                .clipShape(Circle())
        }
        .padding(.horizontal, 16)
        .padding(.top, 7)
        .padding(.bottom, 10)
        .background(Color.white.opacity(0.88))
    }

    private var dayPill: some View {
        Text("Today · Open Calling Graph")
            .font(.system(size: 11, weight: .bold))
            .foregroundColor(.secondary)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Color.black.opacity(0.05))
            .clipShape(Capsule())
    }

    private var userMessage: some View {
        HStack(alignment: .bottom, spacing: 8) {
            Spacer(minLength: 44)
            VStack(alignment: .trailing, spacing: 5) {
                Text(draftMessage.isEmpty ? "오늘 저녁 전 생수 · 휴지 · 세제 장봐줘.\n예산 3만원, 집으로 배송." : draftMessage)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundColor(.white)
                    .lineSpacing(3)
                    .padding(.horizontal, 15)
                    .padding(.vertical, 12)
                    .background(outgoing)
                    .clipShape(ChatBubbleShape(isFromUser: true))
                Text("Delivered")
                    .font(.system(size: 10.5, weight: .bold))
                    .foregroundColor(.secondary)
                    .padding(.trailing, 6)
            }
        }
    }

    private var emptyChatMessage: some View {
        VStack(spacing: 18) {
            Spacer(minLength: 95)
            ZStack {
                Circle()
                    .fill(LinearGradient(colors: [purple, orange], startPoint: .topLeading, endPoint: .bottomTrailing))
                    .frame(width: 74, height: 74)
                Text("H")
                    .font(.system(size: 36, weight: .black, design: .rounded))
                    .foregroundColor(.white)
            }
            Text("What should Hermes call?")
                .font(.system(size: 25, weight: .black, design: .rounded))
                .foregroundColor(.primary)
            Text("Hermes starts with a maroo OKRW delegated wallet. DailyMart can spend only inside this signed grant, and Hermes updates the remaining limit only after DailyMart returns a verified target-signed receipt.")
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .lineSpacing(4)
                .padding(.horizontal, 20)
            delegatedWalletIntro
            VStack(alignment: .leading, spacing: 9) {
                StepLine(done: false, text: "1. Type a grocery request")
                StepLine(done: false, text: "2. Hermes signs App2App MCP request")
                StepLine(done: false, text: "3. DailyMart verifies → pays → returns balance")
            }
            .padding(14)
            .background(Color.white)
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            Spacer(minLength: 80)
        }
        .frame(maxWidth: .infinity)
        .accessibilityLabel("Empty chat")
    }

    private var delegatedWalletIntro: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "wallet.pass.fill")
                    .font(.system(size: 15, weight: .black))
                    .foregroundColor(orange)
                Text("maroo OKRW delegated wallet")
                    .font(.system(size: 15, weight: .black, design: .rounded))
                    .foregroundColor(.primary)
            }
            Text("No private key or personal data is sent to DailyMart. The request carries scoped policy fields: merchant, capability, consent grant, amount, and nonce.")
                .font(.system(size: 12.5, weight: .semibold))
                .foregroundColor(.secondary)
                .lineSpacing(3)
            DelegatedWalletPanel(snapshot: delegatedWallet.panelSnapshot)
        }
        .padding(14)
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .accessibilityLabel("maroo OKRW delegated wallet intro")
    }

    private var ocgAnalysisMessage: some View {
        IncomingMessage(avatarTint: orange) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 8) {
                    ProgressView()
                        .tint(orange)
                        .scaleEffect(0.82)
                        .frame(width: 18, height: 18)
                    Text("Open Calling Graph analysis")
                        .font(.system(size: 15.5, weight: .black, design: .rounded))
                        .foregroundColor(.primary)
                }
                Text("메시지에서 intent, 품목, 예산, 배송지, 동의 필요 여부를 추출하고 있어.")
                    .font(.system(size: 14.5, weight: .semibold))
                    .foregroundColor(.secondary)
                    .lineSpacing(3)
                VStack(alignment: .leading, spacing: 8) {
                    StepLine(done: true, text: "intent → grocery.purchase_essentials")
                    StepLine(done: true, text: "constraints → ₩100 · home · essentials")
                    StepLine(done: false, text: "matching callable apps…")
                }
                .padding(12)
                .background(Color.black.opacity(0.045))
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
        }
        .accessibilityLabel("Open Calling Graph analyzing")
    }

    private var assistantIntroMessage: some View {
        IncomingMessage(avatarTint: purple) {
            VStack(alignment: .leading, spacing: 8) {
                Text("분석 완료. DailyMart가 이 요청을 처리할 수 있어. Hermes가 signed App2App MCP request를 만들고, DailyMart가 검증한 뒤 OKRW 결제를 실행해.")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.primary)
                    .lineSpacing(3)
                HStack(spacing: 6) {
                    Chip(text: "\(plainAmount(delegatedWallet.sessionTotalLimit)) \(delegatedWallet.asset)", color: orange)
                    Chip(text: "Home delivery", color: purple)
                    Chip(text: delegatedWallet.provider, color: .green)
                }
            }
        }
    }

    private var appPickerMessage: some View {
        let dailyMartAction = delegatedWallet.callableAppPresentation(appName: "DailyMart")

        return IncomingMessage(avatarTint: orange) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 7) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 13, weight: .black))
                        .foregroundColor(orange)
                    Text("Callable apps")
                        .font(.system(size: 15, weight: .black, design: .rounded))
                        .foregroundColor(.primary)
                }
                Button(action: openDailyMart) {
                    AppActionCard(
                        icon: "cart.fill",
                        title: "DailyMart",
                        subtitle: dailyMartAction.subtitle,
                        color: orange,
                        primary: true
                    )
                }
                .accessibilityLabel("Buy Essentials with DailyMart")

                Button(action: openMintNotes) {
                    AppActionCard(
                        icon: "note.text",
                        title: "Mint Notes",
                        subtitle: "Save note via callable app",
                        color: purple,
                        primary: false
                    )
                }
                .accessibilityLabel("Open Mint Notes via notes.append_note")
            }
        }
    }

    private var compactHubMessage: some View {
        IncomingMessage(avatarTint: purple) {
            VStack(alignment: .leading, spacing: 7) {
                Text("Hermes Hub")
                    .font(.system(size: 15, weight: .black, design: .rounded))
                    .foregroundColor(.primary)
                Text(lastAction == "Idle" ? "Waiting for your app call." : lastAction)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.secondary)
            }
        }
    }

    private var pinnedDelegatedWalletPanel: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 7) {
                Image(systemName: "wallet.pass.fill")
                    .font(.system(size: 12.5, weight: .black))
                    .foregroundColor(orange)
                Text("maroo OKRW delegated wallet")
                    .font(.system(size: 12.5, weight: .black, design: .rounded))
                    .foregroundColor(.primary)
                Spacer(minLength: 8)
                Text(delegatedWallet.panelSnapshot.primaryWalletSummaryLine)
                    .font(.system(size: 11, weight: .black, design: .rounded))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.76)
            }
            DelegatedWalletPanel(snapshot: delegatedWallet.panelSnapshot)
        }
        .padding(.horizontal, 14)
        .padding(.top, 8)
        .padding(.bottom, 10)
        .background(Color.white.opacity(0.88))
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Color.black.opacity(0.06))
                .frame(height: 1)
        }
        .accessibilityLabel("Pinned maroo OKRW delegated wallet")
    }

    private var isDailyMartReceiptState: Bool {
        lastAction.contains("DailyMart OKRW execution")
            || lastAction.contains("DailyMart order confirmed")
            || lastAction.contains("DailyMart policy denied")
    }

    private func plainAmount(_ decimal: Decimal) -> String {
        NSDecimalNumber(decimal: decimal).stringValue
    }

    private var backgroundStatusMessage: some View {
        IncomingMessage(avatarTint: orange) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 8) {
                    if isBackgroundProcessing {
                        ProgressView()
                            .tint(orange)
                            .scaleEffect(0.82)
                            .frame(width: 18, height: 18)
                    } else {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 18, weight: .bold))
                            .foregroundColor(.green)
                    }
                    Text(isBackgroundProcessing ? (isSavedConsentCall ? "DailyMart MCP call running" : "DailyMart MCP is executing") : "DailyMart order confirmed")
                        .font(.system(size: 15.5, weight: .black, design: .rounded))
                        .foregroundColor(.primary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.86)
                        .accessibilityLabel(isBackgroundProcessing ? (isSavedConsentCall ? "DailyMart saved-consent MCP call running" : "DailyMart background MCP checkout running") : "DailyMart order confirmed")
                }

                Text(isBackgroundProcessing ? (isSavedConsentCall ? "Hermes Chat calls DailyMart in the background using the saved consent grant. No DailyMart foreground approval screen." : "Hermes Chat is foreground. DailyMart places the order through a scoped background MCP call.") : "DailyMart finished in the background and returned a callback receipt.")
                    .font(.system(size: 14.5, weight: .semibold))
                    .foregroundColor(.secondary)
                    .lineSpacing(3)

                VStack(alignment: .leading, spacing: 8) {
                    StepLine(done: true, text: isSavedConsentCall ? "Saved consent grant reused" : "Consent granted in DailyMart")
                    StepLine(done: !isBackgroundProcessing, text: isBackgroundProcessing ? (isSavedConsentCall ? "MCP call running off-screen" : "MCP checkout running off-screen") : "Checkout complete")
                    StepLine(done: !isBackgroundProcessing, text: isBackgroundProcessing ? "Waiting for callback receipt" : "Receipt delivered to Hermes")
                }
                .padding(12)
                .background(Color.black.opacity(0.045))
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
        }
    }

    private var receiptMessage: some View {
        IncomingMessage(avatarTint: purple) {
            VStack(alignment: .leading, spacing: 10) {
                Text("Hermes Hub")
                    .font(.system(size: 15, weight: .black, design: .rounded))
                    .foregroundColor(.primary)
                Text(callbackText)
                    .font(.system(size: 14.5, weight: .semibold))
                    .foregroundColor(.primary)
                    .lineSpacing(4)
                if isDailyMartReceiptState {
                    DelegatedWalletPanel(snapshot: delegatedWallet.panelSnapshot)
                }
                Text(auditTrail)
                    .font(.system(size: 11.5, weight: .medium, design: .monospaced))
                    .foregroundColor(.secondary)
                    .lineSpacing(3)
                    .lineLimit(4)

                if let confirmedReceiptExplorerURL {
                    Link(destination: confirmedReceiptExplorerURL) {
                        Label("Open maroo explorer", systemImage: "link.circle.fill")
                            .font(.system(size: 13, weight: .bold))
                    }
                    .accessibilityLabel("Open maroo explorer receipt link")
                    .accessibilityValue(confirmedReceiptExplorerURL.absoluteString)
                }

                if hasDailyMartConsent && !isBackgroundProcessing && lastAction.contains("confirmed") {
                    Button(action: saveDailyMartLedgerToMintNotes) {
                        AppActionCard(
                            icon: "note.text.badge.plus",
                            title: "Save household ledger",
                            subtitle: "Find Mint Notes · notes.append_note",
                            color: purple,
                            primary: true
                        )
                    }
                    .accessibilityLabel("Save DailyMart household ledger to Mint Notes")
                }

                if hasDailyMartConsent && !isBackgroundProcessing && !isSavedConsentCall {
                    Button(action: prepareDailyMartSavedConsentCall) {
                        AppActionCard(
                            icon: "bolt.horizontal.circle.fill",
                            title: "Call DailyMart again",
                            subtitle: "Use saved consent · background MCP call",
                            color: orange,
                            primary: true
                        )
                    }
                    .accessibilityLabel("Call DailyMart again with saved consent")
                }

                if hasDailyMartConsent && !isBackgroundProcessing && isSavedConsentCall && lastAction.contains("confirmed") {
                    Button(action: openDailyMartSavedConsentReceipt) {
                        AppActionCard(
                            icon: "cart.badge.checkmark",
                            title: "Open DailyMart receipt",
                            subtitle: "Show paid order inside target app",
                            color: orange,
                            primary: true
                        )
                    }
                    .accessibilityLabel("Open DailyMart paid receipt")
                }
            }
        }
    }

    private var composer: some View {
        HStack(spacing: 10) {
            Image(systemName: "plus")
                .font(.system(size: 17, weight: .heavy))
                .foregroundColor(.secondary)
                .frame(width: 34, height: 34)
                .background(Color.white)
                .clipShape(Circle())

            HStack(spacing: 8) {
                TextField("Ask Hermes to call an app…", text: $draftMessage)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(.primary)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .onSubmit { submitPrompt(draftMessage) }
                    .accessibilityLabel("Chat message input")
                Spacer(minLength: 4)
                Image(systemName: "waveform")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal, 14)
            .frame(height: 42)
            .background(Color.white)
            .clipShape(Capsule())

            Button(action: { submitPrompt(draftMessage) }) {
                Image(systemName: "arrow.up")
                    .font(.system(size: 17, weight: .black))
                    .foregroundColor(.white)
                    .frame(width: 36, height: 36)
                    .background(draftMessage.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? Color.white.opacity(0.16) : outgoing)
                    .clipShape(Circle())
            }
            .accessibilityLabel("Send chat message")
        }
        .padding(.horizontal, 14)
        .padding(.top, 10)
        .padding(.bottom, 8)
        .background(Color.white.opacity(0.92))
    }
}

private struct IncomingMessage<Content: View>: View {
    let avatarTint: Color
    @ViewBuilder let content: Content

    var body: some View {
        HStack(alignment: .bottom, spacing: 8) {
            ZStack {
                Circle().fill(avatarTint.opacity(0.96)).frame(width: 30, height: 30)
                Text("H")
                    .font(.system(size: 14, weight: .black, design: .rounded))
                    .foregroundColor(.white)
            }
            content
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .background(Color.white)
                .clipShape(ChatBubbleShape(isFromUser: false))
                .frame(maxWidth: 318, alignment: .leading)
            Spacer(minLength: 22)
        }
    }
}

private struct ChatBubbleShape: Shape {
    let isFromUser: Bool

    func path(in rect: CGRect) -> Path {
        let radius: CGFloat = 20
        var corners: UIRectCorner = [.topLeft, .topRight]
        if isFromUser {
            corners.insert(.bottomLeft)
        } else {
            corners.insert(.bottomRight)
        }
        return Path(UIBezierPath(roundedRect: rect, byRoundingCorners: corners, cornerRadii: CGSize(width: radius, height: radius)).cgPath)
    }
}

private struct AppActionCard: View {
    let icon: String
    let title: String
    let subtitle: String
    let color: Color
    let primary: Bool

    var body: some View {
        HStack(spacing: 11) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .black))
                .foregroundColor(.white)
                .frame(width: 38, height: 38)
                .background(color)
                .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: primary ? 16 : 14.5, weight: .black, design: .rounded))
                    .foregroundColor(.primary)
                    .lineLimit(1)
                Text(subtitle)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.secondary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
            }
            Spacer(minLength: 4)
            Image(systemName: primary ? "arrow.up.right.circle.fill" : "chevron.right")
                .font(.system(size: primary ? 22 : 13, weight: .black))
                .foregroundColor(primary ? color : .secondary)
         }
        .padding(11)
        .background(primary ? color.opacity(0.10) : Color.black.opacity(0.035))
        .clipShape(RoundedRectangle(cornerRadius: 17, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 17, style: .continuous)
                .stroke(primary ? color.opacity(0.24) : Color.black.opacity(0.06), lineWidth: 1)
        )
    }
}

private struct StepLine: View {
    let done: Bool
    let text: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: done ? "checkmark.circle.fill" : "circle.dotted")
                .font(.system(size: 13, weight: .bold))
                .foregroundColor(done ? .green : .orange)
            Text(text)
                .font(.system(size: 12.5, weight: .bold))
                .foregroundColor(.secondary)
        }
    }
}

private struct Chip: View {
    let text: String
    let color: Color
    var body: some View {
        Text(text)
            .font(.system(size: 10.5, weight: .black))
            .foregroundColor(.white)
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(color.opacity(0.27))
            .clipShape(Capsule())
    }
}

private struct WalletSummaryRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(label)
                .font(.system(size: 11, weight: .black))
                .foregroundColor(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.82)
                .frame(width: 112, alignment: .leading)
            Text(value)
                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                .foregroundColor(.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
    }
}

private struct DelegatedWalletPanel: View {
    let snapshot: MeshDelegatedWalletPanelSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(snapshot.headerLabel)
                .font(.system(size: 13.5, weight: .black, design: .rounded))
                .foregroundColor(.primary)
            Text(snapshot.primaryWalletSummaryLine)
                .font(.system(size: 12, weight: .black, design: .rounded))
                .foregroundColor(.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.82)
            ForEach(snapshot.rows, id: \.label) { row in
                WalletSummaryRow(label: row.label, value: row.value)
            }
        }
        .padding(12)
        .background(Color.black.opacity(0.045))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .accessibilityLabel(snapshot.accessibilityLabel)
    }
}
