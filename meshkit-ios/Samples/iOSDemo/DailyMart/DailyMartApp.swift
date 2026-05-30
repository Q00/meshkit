import CryptoKit
import SwiftUI
import MeshKit


private enum HermesRequestSigningTrust {
    static func publicKeyBase64() throws -> String {
        guard let raw = ProcessInfo.processInfo.environment["MESHKIT_IOS_DEMO_PUBLIC_KEY_BASE64"],
              !raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw MeshKitValidationError.signatureRequired
        }
        return raw
    }
}

private enum DailyMartReceiptSigningKey {
    static let keyId = "sample-dailymart-receipt-ed25519"

    static func privateKey() throws -> Curve25519.Signing.PrivateKey {
        guard let raw = ProcessInfo.processInfo.environment["MESHKIT_IOS_DAILYMART_RECEIPT_PRIVATE_KEY_BASE64"],
              let data = Data(base64Encoded: raw), !data.isEmpty else {
            throw MeshKitValidationError.signatureRequired
        }
        return try Curve25519.Signing.PrivateKey(rawRepresentation: data)
    }
}

@main
struct DailyMartApp: App {
    @State private var incoming = "Waiting for grocery.purchase_essentials request from Hermes Chat."
    @State private var order = "No order yet."
    @State private var orderId = "DM-2026-0509-001"
    @State private var orderSource = "saved-consent background MCP"
    @State private var auditTrail = "Consent and execution history will appear here."
    @State private var request: MeshRequest?
    @State private var isProcessing = false
    @State private var didCompleteOrder = false
    private let replayCache = MeshReplayCache()

    var body: some Scene {
        WindowGroup {
            DailyMartRootView(
                incoming: incoming,
                order: order,
                orderId: orderId,
                orderSource: orderSource,
                auditTrail: auditTrail,
                hasRequest: request != nil,
                isProcessing: isProcessing,
                didCompleteOrder: didCompleteOrder,
                approveAndPurchase: approveAndPurchase
            )
            .onOpenURL { url in
                handleIncoming(url)
            }
            .onAppear {
                handleLaunchArgumentsIfNeeded()
            }
        }
    }

    private func handleLaunchArgumentsIfNeeded() {
        if ProcessInfo.processInfo.arguments.contains("--demo-received-request") {
            request = demoMeshRequest(requestId: "ios-grocery-001")
            orderId = "DM-2026-0509-001"
            orderSource = "foreground consent grant"
            didCompleteOrder = false
            isProcessing = false
            order = "No order yet."
            auditTrail = "Consent and execution history will appear here."
            incoming = "Signed request decoded · needs one-time consent · budget ≤ ₩100"
            return
        }
        guard ProcessInfo.processInfo.arguments.contains("--saved-consent-order-proof") else { return }
        do {
            let savedConsentRequest = demoMeshRequest(requestId: "ios-grocery-saved-consent-002")
            let receipt = try signedReceipt(for: savedConsentRequest, orderId: "DM-2026-0509-002")
            let encoded = try receipt.encodedForURLScheme()
            let callback = "meshkit-hermes://callback?status=purchased&receipt_token=\(urlEscape(savedConsentRequest.requestId))&mesh_receipt=\(urlEscape(encoded))"
            UIApplication.shared.open(URL(string: callback)!)
            request = nil
            isProcessing = false
            didCompleteOrder = true
            orderId = "DM-2026-0509-002"
            orderSource = "saved-consent background MCP"
            incoming = "Target-owned signed receipt emitted · saved-consent background MCP · approval_screen=false"
            order = "Order DM-2026-0509-002 — 주문 완료\n• 세탁세제 × 1\n• 화장지 × 2\n• 생수 2L × 6\nTotal: ₩100\nDelivery: 오늘 19:00–21:00"
            auditTrail = "grocery.purchase_essentials.executed\nrequest_id=\(receipt.requestId)\nbackground=true\nsource=saved-consent background MCP\napproval_screen=false\nmesh_receipt_signed=true"
        } catch {
            request = nil
            isProcessing = false
            didCompleteOrder = false
            orderId = "DM-2026-0509-002"
            orderSource = "saved-consent background MCP"
            incoming = "Saved-consent proof blocked: DailyMart receipt signing key unavailable."
            order = "No order marked complete without a target-signed MeshReceipt."
            auditTrail = "grocery.purchase_essentials.blocked\nreason=missing_target_receipt_signature\nerror=\(error)"
        }
    }

    private func demoMeshRequest(requestId: String) -> MeshRequest {
        MeshRequest(
            requestId: requestId,
            caller: MeshIdentity(appId: "app.hermes-chat", installId: "ios-sim", bundleId: "ai.meshkit.sample.hermeschat", publicKeyId: "sample-ios-ed25519"),
            target: MeshCapability(targetBundleId: "ai.meshkit.sample.dailymart", capabilityId: "grocery.purchase_essentials", version: "1.0"),
            payload: [
                "items": "laundry_detergent:1,toilet_paper:2,bottled_water_2l:6",
                "address_ref": "home.saved",
                "budget_krw": "100"
            ],
            nonce: requestId + "-nonce",
            timestamp: ISO8601DateFormatter().string(from: Date()),
            signature: MeshSignature(algorithm: "Ed25519", keyId: "sample-ios-ed25519", value: "demo-simulator-signature")
        )
    }

    private func handleIncoming(_ url: URL) {
        if url.absoluteString.contains("order-proof") {
            incoming = "Rejected unsigned order-proof URL. Signed target receipt required."
            return
        }

        guard let encoded = URLComponents(url: url, resolvingAgainstBaseURL: false)?
            .queryItems?
            .first(where: { $0.name == "mesh_request" })?
            .value else {
            incoming = "Invalid request: missing mesh_request."
            return
        }
        do {
            let decoded = try MeshRequest.decodedFromURLScheme(encoded)
            try MeshTarget.validate(
                decoded,
                policy: MeshTargetPolicy(
                    allowedCallerAppId: "app.hermes-chat",
                    targetBundleId: "ai.meshkit.sample.dailymart",
                    capabilityId: "grocery.purchase_essentials"
                )
            )
            try MeshTarget.verifyPayloadHash(decoded)
            request = decoded
            orderId = "DM-2026-0509-001"
            orderSource = "foreground consent grant"
            didCompleteOrder = false
            isProcessing = false
            order = "No order yet."
            auditTrail = "Consent and execution history will appear here."
            incoming = "Signed request decoded · needs one-time consent · budget ≤ ₩100"
        } catch {
            request = nil
            incoming = "Rejected MeshKit request: \(error)"
        }
    }

    private func approveAndPurchase() {
        guard let request else {
            order = "No valid request to approve."
            return
        }
        if ProcessInfo.processInfo.arguments.contains("--demo-received-request") {
            isProcessing = true
            order = "Consent granted. Hermes may place this order once in the background."
            orderId = "DM-2026-0509-001"
            orderSource = "foreground consent grant"
            didCompleteOrder = false
            auditTrail = "consent.granted → intent.pending\nrequest_id=\(request.requestId)\nscope=purchase,address,wallet_budget · max_budget=100 · one_time=true\norder_placed=false"
            return
        }
        isProcessing = true
        order = "Consent granted. Hermes may place this order once in the background."
        auditTrail = "consent.granted → intent.pending\nscope=purchase,address,wallet_budget · max_budget=100 · one_time=true"
        do {
            let audit = try MeshTarget.validatePublicMesh(
                request: request,
                policy: MeshTargetPolicy(
                    allowedCallerAppId: "app.hermes-chat",
                    targetBundleId: "ai.meshkit.sample.dailymart",
                    capabilityId: "grocery.purchase_essentials"
                ),
                trust: MeshSenderTrust(
                    callerAppId: "app.hermes-chat",
                    callerBundleId: "ai.meshkit.sample.hermeschat",
                    teamId: "DEVTEAMID",
                    requestSigningAlgorithm: "Ed25519",
                    requestSigningKeyId: "sample-ios-ed25519",
                    publicKey: try HermesRequestSigningTrust.publicKeyBase64()
                ),
                invocationPolicy: MeshInvocationPolicy(
                    risk: "spend:money",
                    consent: "budgeted_per_invocation",
                    userApproved: true,
                    registrySignatureVerified: true,
                    approvedBudget: Decimal(100)
                ),
                observedCallerBundleId: "ai.meshkit.sample.hermeschat",
                replayCache: replayCache
            )
            orderId = "DM-2026-0509-001"
            orderSource = "foreground consent grant"
            didCompleteOrder = false
            isProcessing = true
            order = "Consent granted. Hermes may place this order once in the background."
            auditTrail = "consent.granted → intent.pending\nrequest_id=\(audit.requestId)\nscope=purchase,address,wallet_budget · max_budget=100 · one_time=true\norder_placed=false"
            let callback = "meshkit-hermes://callback?status=processing&capability=grocery.purchase_essentials&audit_id=\(urlEscape(audit.requestId))&receipt_token=\(urlEscape(request.requestId))&receipt_sig=demo-signed-consent"
            UIApplication.shared.open(URL(string: callback)!)
        } catch {
            isProcessing = false
            order = "Rejected before purchase: \(error)"
        }
    }

    private func signedReceipt(for request: MeshRequest, orderId: String) throws -> MeshReceipt {
        try MeshReceiptSigner.ed25519(
            keyId: DailyMartReceiptSigningKey.keyId,
            privateKey: DailyMartReceiptSigningKey.privateKey()
        ).makeReceipt(
            receiptId: orderId + "-receipt",
            request: request,
            targetAppId: "app.dailymart",
            targetBundleId: "ai.meshkit.sample.dailymart",
            status: "purchased",
            result: ["order_id": orderId, "total_krw": "100"],
            nonce: orderId + "-receipt-nonce",
            timestamp: ISO8601DateFormatter().string(from: Date())
        )
    }

    private func urlEscape(_ value: String) -> String {
        value.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? value
    }

    private func showSavedConsentOrderProof(_ url: URL) {
        incoming = "Rejected unsigned order proof. Signed target receipt required."
        auditTrail = "order-proof.rejected · no requestId/nonce/payloadHash/signature correlation"
    }
}

private struct DailyMartRootView: View {
    let incoming: String
    let order: String
    let orderId: String
    let orderSource: String
    let auditTrail: String
    let hasRequest: Bool
    let isProcessing: Bool
    let didCompleteOrder: Bool
    let approveAndPurchase: () -> Void
    @State private var showConsentConfirmation = false

    private let background = Color(red: 0.965, green: 0.955, blue: 0.925)
    private let green = Color(red: 0.03, green: 0.42, blue: 0.25)
    private let orange = Color(red: 0.96, green: 0.39, blue: 0.10)

    var body: some View {
        ZStack(alignment: .bottom) {
            background.ignoresSafeArea()
            ScrollView(showsIndicators: false) {
                VStack(spacing: 10) {
                    hero
                    if didCompleteOrder {
                        orderConfirmationCard
                        basketCard
                        auditCard
                    } else if isProcessing {
                        approvalProcessingCard
                        basketCard
                        auditCard
                    } else {
                        requestCard
                        basketCard
                        deliveryCard
                        auditCard
                    }
                    Color.clear.frame(height: didCompleteOrder ? 112 : 98)
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
            }
            if !didCompleteOrder {
                checkoutBar
            }
        }
        .alert("Grant DailyMart consent?", isPresented: $showConsentConfirmation) {
            Button("Grant one-time consent") {
                approveAndPurchase()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Allow Hermes to place this grocery order once via DailyMart background MCP. Limit: ₩100. Order is not placed until the background MCP call runs.")
        }
    }

    private var hero: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("DailyMart")
                        .font(.system(size: 32, weight: .black, design: .rounded))
                        .foregroundColor(.white)
                    Text("Target app • grocery.purchase_essentials")
                        .font(.system(size: 13, weight: .semibold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.78)
                        .foregroundColor(.white.opacity(0.82))
                    Text("Budget consent + signed execution proof")
                        .font(.system(size: 11.5, weight: .bold))
                        .foregroundColor(.white.opacity(0.68))
                }
                Spacer()
                ZStack {
                    Circle().fill(.white.opacity(0.18)).frame(width: 40, height: 40)
                    Text("🛒").font(.system(size: 21))
                }
            }
            HStack(spacing: 8) {
                pill("Home", icon: "house.fill")
                pill("₩100", icon: "creditcard.fill")
                pill("7–9 PM", icon: "clock.fill")
            }
        }
        .padding(18)
        .background(
            LinearGradient(colors: [green, Color(red: 0.07, green: 0.60, blue: 0.35), orange.opacity(0.92)], startPoint: .topLeading, endPoint: .bottomTrailing)
        )
        .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
        .shadow(color: green.opacity(0.25), radius: 24, x: 0, y: 12)
    }

    private func pill(_ title: String, icon: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon).font(.system(size: 11, weight: .bold))
            Text(title)
                .font(.system(size: 12, weight: .bold))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .foregroundColor(.white)
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(.white.opacity(0.18))
        .clipShape(Capsule())
    }

    private var quickState: some View {
        HStack(spacing: 12) {
            MetricTile(title: "Budget", value: "₩100", caption: "per-invocation", tint: orange)
            MetricTile(title: "Risk", value: "Spend", caption: "needs consent", tint: green)
            MetricTile(title: "ETA", value: didCompleteOrder ? "7–9 PM" : "Today", caption: "fresh delivery", tint: Color(red: 0.13, green: 0.32, blue: 0.78))
        }
    }

    private var requestCard: some View {
        AppCard {
            HStack(alignment: .top, spacing: 12) {
                IconBadge(systemName: hasRequest ? "checkmark.shield.fill" : "hourglass", color: hasRequest ? green : .gray)
                VStack(alignment: .leading, spacing: 8) {
                    Text("Review consent request")
                        .font(.system(size: 19, weight: .black, design: .rounded))
                        .lineLimit(1)
                        .minimumScaleFactor(0.78)
                        .foregroundColor(.primary)
                    Text(incoming)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                    if didCompleteOrder {
                        Text("Paid ₩100 · delivery 7–9 PM")
                            .font(.system(size: 13, weight: .heavy))
                            .foregroundColor(green)
                            .lineLimit(1)
                    }
                    Text("One-time limit · no purchase until background MCP")
                        .font(.system(size: 13, weight: .black, design: .rounded))
                        .foregroundColor(orange)
                        .lineLimit(1)
                    VStack(spacing: 10) {
                        GroceryRow(emoji: "🧺", name: "세탁세제", detail: "2.7L", price: "₩12,900")
                        GroceryRow(emoji: "🧻", name: "화장지", detail: "30롤 × 2 packs", price: "₩10,600")
                        GroceryRow(emoji: "💧", name: "생수 2L", detail: "6 bottles", price: "₩6,500")
                    }
                    .padding(.top, 4)
                }
            }
        }
    }

    private var approvalProcessingCard: some View {
        AppCard {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .center, spacing: 12) {
                    ZStack {
                        Circle()
                            .stroke(green.opacity(0.18), lineWidth: 8)
                            .frame(width: 54, height: 54)
                        ProgressView()
                            .tint(green)
                            .scaleEffect(1.08)
                    }
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Consent granted")
                            .font(.system(size: 20, weight: .black, design: .rounded))
                            .foregroundColor(green)
                            .lineLimit(1)
                            .minimumScaleFactor(0.74)
                        Text("Order intent pending")
                            .font(.system(size: 17, weight: .heavy, design: .rounded))
                            .foregroundColor(.primary)
                            .accessibilityLabel("Order intent pending")
                        Text("No order placed yet. Hermes now has one-time permission to call DailyMart MCP in the background.")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(.secondary)
                            .lineLimit(2)
                    }
                    .layoutPriority(1)
                }
                VStack(spacing: 8) {
                    LoadingStep(title: "Consent", detail: "₩100 one-time grant", done: true, tint: green)
                    LoadingStep(title: "Background MCP", detail: "Actual checkout happens off-screen", done: false, tint: orange)
                    LoadingStep(title: "Receipt", detail: "Order proof returns after MCP execution", done: false, tint: Color(red: 0.13, green: 0.32, blue: 0.78))
                }
                .padding(12)
                .background(green.opacity(0.07))
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            }
        }
    }

    private var orderConfirmationCard: some View {
        AppCard {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .top, spacing: 12) {
                    IconBadge(systemName: "checkmark.seal.fill", color: green)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Order placed")
                            .font(.system(size: 26, weight: .black, design: .rounded))
                            .foregroundColor(green)
                            .lineLimit(1)
                            .minimumScaleFactor(0.82)
                            .accessibilityLabel("Order placed")
                        Text("Order \(orderId) confirmed")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                    Text("PAID")
                        .font(.system(size: 10, weight: .black))
                        .foregroundColor(.white)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 6)
                        .background(green)
                        .clipShape(Capsule())
                }
                VStack(spacing: 10) {
                    ProofRow(label: "Order", value: orderId)
                    ProofRow(label: "Total", value: "₩100")
                    ProofRow(label: "Source", value: orderSource)
                    ProofRow(label: "Delivery", value: "오늘 19:00–21:00")
                    ProofRow(label: "Items", value: "세제 1 · 화장지 2 · 생수 6")
                }
                .padding(14)
                .background(green.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            }
        }
    }

    private var basketCard: some View {
        AppCard {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(didCompleteOrder ? "Purchased items" : "Pending basket")
                            .font(.system(size: 22, weight: .black, design: .rounded))
                        Text(didCompleteOrder ? "Order \(orderId)" : "Intent approved only after consent")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                    Text(didCompleteOrder ? "PAID" : "PENDING")
                        .font(.system(size: 11, weight: .black))
                        .foregroundColor(didCompleteOrder ? .white : orange)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(didCompleteOrder ? green : orange.opacity(0.12))
                        .clipShape(Capsule())
                }
                VStack(spacing: 8) {
                    GroceryRow(emoji: "🧺", name: "세탁세제", detail: "2.7L", price: "₩12,900")
                    GroceryRow(emoji: "🧻", name: "화장지", detail: "30롤 × 2 packs", price: "₩10,600")
                    GroceryRow(emoji: "💧", name: "생수 2L", detail: "6 bottles", price: "₩6,500")
                }
                if !didCompleteOrder {
                    Divider()
                    HStack {
                        Text(order)
                            .font(.system(size: 15, weight: .bold))
                            .foregroundColor(.secondary)
                        Spacer()
                        Text("₩100")
                            .font(.system(size: 23, weight: .black, design: .rounded))
                    }
                }
            }
        }
    }

    private var deliveryCard: some View {
        AppCard {
            HStack(spacing: 13) {
                IconBadge(systemName: didCompleteOrder ? "scooter" : "location.fill", color: Color(red: 0.13, green: 0.32, blue: 0.78))
                VStack(alignment: .leading, spacing: 4) {
                    Text(didCompleteOrder ? "Rider assigned" : "Delivery scope")
                        .font(.system(size: 17, weight: .bold))
                    Text(didCompleteOrder ? "Doorstep drop-off · 오늘 19:00–21:00" : "Consent allows DailyMart to resolve address_ref=home.saved once.")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(.secondary)
                }
                Spacer()
            }
        }
    }

    private var auditCard: some View {
        AppCard {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("Consent / execution record")
                        .font(.system(size: 17, weight: .bold))
                    Spacer()
                    Circle().fill(didCompleteOrder ? green : Color.gray.opacity(0.35)).frame(width: 10, height: 10)
                }
                Text(auditTrail)
                    .font(.system(size: didCompleteOrder ? 11 : 12.5, weight: .medium, design: .monospaced))
                    .foregroundColor(.secondary)
                    .lineSpacing(3)
                    .lineLimit(didCompleteOrder ? 3 : 6)
            }
        }
    }

    private var checkoutBar: some View {
        VStack(spacing: 10) {
            if didCompleteOrder {
                HStack(spacing: 12) {
                    Image(systemName: "checkmark.seal.fill")
                        .font(.system(size: 19, weight: .black))
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Order placed · DM-2026-0509-001")
                            .font(.system(size: 16, weight: .heavy))
                        Text("Paid ₩100 · delivery 7–9 PM")
                            .font(.system(size: 12.5, weight: .bold))
                            .opacity(0.82)
                    }
                    Spacer()
                }
                .foregroundColor(.white)
                .padding(.horizontal, 14)
                .padding(.vertical, 16)
                .background(green)
                .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                .shadow(color: green.opacity(0.30), radius: 18, x: 0, y: 10)
                .padding(.horizontal, 20)
                .padding(.bottom, 12)
            } else {
                Button(action: { showConsentConfirmation = true }) {
                    HStack {
                        if isProcessing {
                            ProgressView().tint(.white)
                        } else {
                            Image(systemName: "lock.shield.fill")
                        }
                        Text(isProcessing ? "Consent granted — returning to Hermes…" : "Grant one-time ₩100 consent")
                            .font(.system(size: 16, weight: .heavy))
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.system(size: 14, weight: .black))
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 17)
                    .background(hasRequest ? green : Color.gray)
                    .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                    .shadow(color: green.opacity(hasRequest ? 0.30 : 0), radius: 18, x: 0, y: 10)
                }
                .accessibilityLabel("Grant one-time DailyMart consent")
                .disabled(isProcessing)
                .padding(.horizontal, 20)
                .padding(.bottom, 12)
            }
        }
        .padding(.top, 12)
        .background(.ultraThinMaterial)
    }
}

private struct ProofRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack {
            Text(label)
                .font(.system(size: 12, weight: .bold))
                .foregroundColor(.secondary)
            Spacer()
            Text(value)
                .font(.system(size: 14, weight: .black, design: .rounded))
                .foregroundColor(.primary)
        }
    }
}

private struct AppCard<Content: View>: View {
    @ViewBuilder let content: Content
    var body: some View {
        content
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.white)
            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
            .shadow(color: Color.black.opacity(0.06), radius: 18, x: 0, y: 8)
    }
}

private struct MetricTile: View {
    let title: String
    let value: String
    let caption: String
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.system(size: 11, weight: .bold)).foregroundColor(.secondary)
            Text(value).font(.system(size: 16, weight: .black, design: .rounded)).foregroundColor(tint)
            Text(caption).font(.system(size: 10, weight: .semibold)).foregroundColor(.secondary)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .shadow(color: Color.black.opacity(0.05), radius: 12, x: 0, y: 6)
    }
}

private struct LoadingStep: View {
    let title: String
    let detail: String
    let done: Bool
    let tint: Color

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: done ? "checkmark.circle.fill" : "arrow.triangle.2.circlepath.circle.fill")
                .font(.system(size: 17, weight: .bold))
                .foregroundColor(tint)
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.system(size: 13, weight: .black, design: .rounded))
                    .foregroundColor(.primary)
                Text(detail)
                    .font(.system(size: 11.5, weight: .semibold))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.74)
            }
            Spacer(minLength: 4)
        }
    }
}

private struct GroceryRow: View {
    let emoji: String
    let name: String
    let detail: String
    let price: String

    var body: some View {
        HStack(spacing: 12) {
            Text(emoji)
                .font(.system(size: 23))
                .frame(width: 44, height: 44)
                .background(Color(red: 0.965, green: 0.955, blue: 0.925))
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text(name).font(.system(size: 16, weight: .black, design: .rounded))
                Text(detail).font(.system(size: 12.5, weight: .semibold)).foregroundColor(.secondary)
            }
            .layoutPriority(1)
            Spacer(minLength: 8)
            Text(price)
                .font(.system(size: 14, weight: .black, design: .rounded))
                .lineLimit(1)
                .minimumScaleFactor(0.65)
                .allowsTightening(true)
                .frame(width: 76, alignment: .trailing)
        }
    }
}

private struct IconBadge: View {
    let systemName: String
    let color: Color

    var body: some View {
        Image(systemName: systemName)
            .font(.system(size: 18, weight: .bold))
            .foregroundColor(color)
            .frame(width: 44, height: 44)
            .background(color.opacity(0.12))
            .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
    }
}

private struct StatusChip: View {
    let text: String
    init(_ text: String) { self.text = text }
    var body: some View {
        Text(text)
            .font(.system(size: 11, weight: .bold))
            .foregroundColor(Color(red: 0.03, green: 0.42, blue: 0.25))
            .padding(.horizontal, 9)
            .padding(.vertical, 6)
            .background(Color(red: 0.03, green: 0.42, blue: 0.25).opacity(0.10))
            .clipShape(Capsule())
    }
}
