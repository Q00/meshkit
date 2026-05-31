import CryptoKit
import SwiftUI
import MeshKit


private enum HermesRequestSigningTrust {
    private static let samplePublicKeyBase64 = "SYRITem/8/4woLf6P3Iec58z4jBtxzEB+g+UXeS8mcU="

    static func publicKeyBase64() throws -> String {
        let raw = ProcessInfo.processInfo.environment["MESHKIT_IOS_DEMO_PUBLIC_KEY_BASE64"] ?? samplePublicKeyBase64
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw MeshKitValidationError.signatureRequired }
        return trimmed
    }

    static func dailyMartVerifier() throws -> DailyMartSignedMCPRequestVerifier {
        try DailyMartSignedMCPRequestVerifier(
            expectedHermesAgentSigner: MeshSenderTrust(
                callerAppId: "app.hermes-chat",
                callerBundleId: "ai.meshkit.sample.hermeschat",
                teamId: "DEVTEAMID",
                requestSigningAlgorithm: "Ed25519",
                requestSigningKeyId: "sample-ios-ed25519",
                publicKey: try publicKeyBase64()
            )
        )
    }

    static func dailyMartPreExecutionGuard(
        freshnessStore: DailyMartRequestNonceFreshnessStore
    ) throws -> DailyMartPreExecutionMCPGuard {
        try DailyMartPreExecutionMCPGuard(
            expectedHermesAgentSigner: MeshSenderTrust(
                callerAppId: "app.hermes-chat",
                callerBundleId: "ai.meshkit.sample.hermeschat",
                teamId: "DEVTEAMID",
                requestSigningAlgorithm: "Ed25519",
                requestSigningKeyId: "sample-ios-ed25519",
                publicKey: try publicKeyBase64()
            ),
            freshnessStore: freshnessStore,
            walletPolicyGuard: try DailyMartPreExecutionWalletPolicyGuard()
        )
    }
}

private enum DailyMartReceiptSigningKey {
    static let keyId = "sample-dailymart-receipt-ed25519"
    private static let samplePrivateKeyBase64 = "LaXmm9S12JqU7R/y9sufJiShgajyWCkyFeGazh4qhb0="

    static func privateKey() throws -> Curve25519.Signing.PrivateKey {
        let raw = ProcessInfo.processInfo.environment["MESHKIT_IOS_DAILYMART_RECEIPT_PRIVATE_KEY_BASE64"] ?? samplePrivateKeyBase64
        guard !raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
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
    @State private var receiptChainProofTitle = "Confirmed provider-neutral chain proof"
    @State private var receiptChainProofAccessibilityPrefix = "Confirmed chain proof"
    @State private var receiptChainProofFields: [DailyMartReceiptProofField] = []
    @State private var request: MeshRequest?
    @State private var isProcessing = false
    @State private var didCompleteOrder = false
    private let replayCache = MeshReplayCache()
    private let preExecutionFreshnessStore = DailyMartRequestNonceFreshnessStore()

    var body: some Scene {
        WindowGroup {
            DailyMartRootView(
                incoming: incoming,
                order: order,
                orderId: orderId,
                orderSource: orderSource,
                auditTrail: auditTrail,
                receiptChainProofTitle: receiptChainProofTitle,
                receiptChainProofAccessibilityPrefix: receiptChainProofAccessibilityPrefix,
                receiptChainProofFields: receiptChainProofFields,
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
        if ProcessInfo.processInfo.arguments.contains("--confirmed-receipt-ui-proof") {
            showConfirmedReceiptUIProof()
            return
        }
        if ProcessInfo.processInfo.arguments.contains("--pending-receipt-ui-proof") {
            showPendingReceiptUIProof()
            return
        }
        if ProcessInfo.processInfo.arguments.contains("--failed-receipt-ui-proof") {
            showFailedReceiptUIProof()
            return
        }
        if ProcessInfo.processInfo.arguments.contains("--policy-denied-receipt-ui-proof") {
            showPolicyDeniedReceiptUIProof()
            return
        }
        if ProcessInfo.processInfo.arguments.contains("--demo-received-request") {
            request = demoMeshRequest(requestId: "ios-grocery-001")
            orderId = "DM-2026-0509-001"
            orderSource = "foreground consent grant"
            receiptChainProofFields = []
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
            let chainStatus = receipt.result["chainStatus"] ?? "pending"
            let callbackStatus = chainStatus == "confirmed" ? "purchased" : "submitted"
            openHermesCallback(status: callbackStatus, requestId: savedConsentRequest.requestId, encodedReceipt: encoded)
            request = nil
            isProcessing = false
            didCompleteOrder = chainStatus == "confirmed"
            orderId = "DM-2026-0509-002"
            orderSource = "saved-consent background MCP"
            if didCompleteOrder {
                incoming = "Target-owned signed confirmed receipt emitted · saved-consent background MCP · approval_screen=false"
                order = "Order DM-2026-0509-002 — 주문 완료\n• 세탁세제 × 1\n• 화장지 × 2\n• 생수 2L × 6\nTotal: ₩100\nDelivery: 오늘 19:00–21:00"
                auditTrail = "grocery.purchase_essentials.executed\nrequest_id=\(receipt.requestId)\nbackground=true\nsource=saved-consent background MCP\napproval_screen=false\nmesh_receipt_signed=true\nchain_status=confirmed\ntx_hash=\(receipt.result["txHash"] ?? "")"
                receiptChainProofTitle = "Confirmed provider-neutral chain proof"
                receiptChainProofAccessibilityPrefix = "Confirmed chain proof"
                receiptChainProofFields = DailyMartReceiptProofField.confirmedFields(from: receipt.result)
            } else {
                incoming = "Target-owned pending receipt emitted · maroo live confirmation blocked · approval_screen=false"
                order = "OKRW execution submitted. No order is marked paid until maroo returns a live confirmed txHash."
                auditTrail = "grocery.purchase_essentials.blocked\nreason=BlockedByExternalChain\nrequest_id=\(receipt.requestId)\nbackground=true\nsource=saved-consent background MCP\napproval_screen=false\nmesh_receipt_signed=true\nchain_status=\(chainStatus)\nanchoring_reference=\(receipt.result["anchoringReference"] ?? "")"
                receiptChainProofTitle = "Pending provider-neutral chain proof"
                receiptChainProofAccessibilityPrefix = "Pending chain proof"
                receiptChainProofFields = DailyMartReceiptProofField.pendingFields(from: receipt.result)
            }
        } catch {
            request = nil
            isProcessing = false
            didCompleteOrder = false
            orderId = "DM-2026-0509-002"
            orderSource = "saved-consent background MCP"
            receiptChainProofFields = []
            incoming = "Saved-consent proof blocked: DailyMart receipt signing key unavailable."
            order = "No order marked complete without a target-signed MeshReceipt."
            auditTrail = "grocery.purchase_essentials.blocked\nreason=missing_target_receipt_signature\nerror=\(error)"
        }
    }

    private func showConfirmedReceiptUIProof() {
        let requestHash = String(repeating: "a", count: 64)
        let policyHash = DailyMartDelegatedSpendingPolicy.policyHash.value
        let result = [
            "chainProvider": "maroo",
            "chainId": "maroo-testnet-1",
            "chainNetwork": "maroo-testnet",
            "chainProofType": "payment_execution",
            "chainStatus": "confirmed",
            "presentationState": "paid_complete",
            "requestHash": requestHash,
            "requestNonce": "ios-grocery-confirmed-ui-nonce",
            "policyId": DailyMartDelegatedSpendingPolicy.policyId,
            "policyHash": policyHash,
            "walletAddress": "maroo1dailyMartAgentWallet",
            "amount": "100",
            "asset": DailyMartDelegatedSpendingPolicy.asset,
            "recipient": DailyMartDelegatedSpendingPolicy.recipientAddress,
            "anchoringReference": "request-anchor-sha256-\(requestHash)",
            "txHash": "0xokrwDailyMartConfirmedUIReceipt",
            "explorerUrl": "https://explorer-testnet.maroo.io/tx/0xokrwDailyMartConfirmedUIReceipt",
            "confirmedAt": "2026-05-31T12:00:00Z",
            "providerExtensions": "none"
        ]
        request = nil
        isProcessing = false
        didCompleteOrder = true
        orderId = "DM-2026-0509-UI"
        orderSource = "confirmed receipt UI test"
        incoming = "Target-owned signed confirmed receipt accepted · provider-neutral proof rendered"
        order = "Order DM-2026-0509-UI — confirmed\nTotal: ₩100\nDelivery: 오늘 19:00–21:00"
        auditTrail = "grocery.purchase_essentials.executed\nrequest_id=ios-grocery-confirmed-ui\nmesh_receipt_signed=true\nchain_status=confirmed\ntx_hash=0xokrwDailyMartConfirmedUIReceipt"
        receiptChainProofTitle = "Confirmed provider-neutral chain proof"
        receiptChainProofAccessibilityPrefix = "Confirmed chain proof"
        receiptChainProofFields = DailyMartReceiptProofField.confirmedFields(from: result)
    }

    private func showPendingReceiptUIProof() {
        let requestHash = String(repeating: "b", count: 64)
        let policyHash = DailyMartDelegatedSpendingPolicy.policyHash.value
        let result = [
            "chainProvider": "maroo",
            "chainId": "maroo-testnet-1",
            "chainNetwork": "maroo-testnet",
            "chainProofType": "payment_execution",
            "chainStatus": "pending",
            "presentationState": "submitted_not_final",
            "requestHash": requestHash,
            "requestNonce": "ios-grocery-pending-ui-nonce",
            "policyId": DailyMartDelegatedSpendingPolicy.policyId,
            "policyHash": policyHash,
            "walletAddress": "maroo1dailyMartAgentWallet",
            "amount": "100",
            "asset": DailyMartDelegatedSpendingPolicy.asset,
            "recipient": DailyMartDelegatedSpendingPolicy.recipientAddress,
            "anchoringReference": "request-anchor-sha256-\(requestHash)",
            "executionAttemptId": "meshkit-execution-attempt/v1:pay-pending-ui:auth-pending-ui:exec-pending-ui",
            "paymentId": "pay-pending-ui",
            "authorizationId": "auth-pending-ui",
            "executionId": "exec-pending-ui",
            "executionKind": "payment",
            "anchorTxHash": "0xanchorDailyMartPendingUIReceipt",
            "submittedAt": "2026-05-31T12:05:00Z",
            "externalChainExitCondition": "BlockedByExternalChain",
            "externalChainBlockerType": "payment_confirmation_unavailable",
            "externalChainOperation": "executeOKRWTransfer",
            "externalChainEndpoint": "https://rpc-testnet.maroo.io",
            "externalChainMessage": "maroo live OKRW confirmation is unavailable for this demo run"
        ]
        request = nil
        isProcessing = false
        didCompleteOrder = false
        orderId = "DM-2026-0509-PENDING"
        orderSource = "pending receipt UI test"
        incoming = "Target-owned pending receipt accepted · request anchored · awaiting OKRW confirmation"
        order = "OKRW execution submitted. No order is marked paid until maroo returns a live confirmed txHash."
        auditTrail = "grocery.purchase_essentials.submitted\nrequest_id=ios-grocery-pending-ui\nmesh_receipt_signed=true\nchain_status=pending\npresentation_state=submitted_not_final\nproof_type=payment_execution\nanchoring_reference=request-anchor-sha256-\(requestHash)\nexecution_attempt_id=meshkit-execution-attempt/v1:pay-pending-ui:auth-pending-ui:exec-pending-ui\nexternal_chain_exit_condition=BlockedByExternalChain\nno_tx_hash=true"
        receiptChainProofTitle = "Pending provider-neutral chain proof"
        receiptChainProofAccessibilityPrefix = "Pending chain proof"
        receiptChainProofFields = DailyMartReceiptProofField.pendingFields(from: result)
    }

    private func showFailedReceiptUIProof() {
        let requestHash = String(repeating: "c", count: 64)
        let policyHash = DailyMartDelegatedSpendingPolicy.policyHash.value
        let result = [
            "chainProvider": "maroo",
            "chainId": "maroo-testnet-1",
            "chainNetwork": "maroo-testnet",
            "chainProofType": "payment_execution",
            "chainStatus": "failed",
            "presentationState": "attempted_failed",
            "requestHash": requestHash,
            "requestNonce": "ios-grocery-failed-ui-nonce",
            "policyId": DailyMartDelegatedSpendingPolicy.policyId,
            "policyHash": policyHash,
            "walletAddress": "maroo1dailyMartAgentWallet",
            "amount": "100",
            "asset": DailyMartDelegatedSpendingPolicy.asset,
            "recipient": DailyMartDelegatedSpendingPolicy.recipientAddress,
            "anchoringReference": "request-anchor-sha256-\(requestHash)",
            "executionAttemptId": "meshkit-execution-attempt/v1:pay-failed-ui:auth-failed-ui:exec-failed-ui",
            "paymentId": "pay-failed-ui",
            "authorizationId": "auth-failed-ui",
            "executionId": "exec-failed-ui",
            "executionKind": "payment",
            "anchorTxHash": "0xanchorDailyMartFailedUIReceipt",
            "errorCode": "payment_confirmation_unavailable",
            "errorMessage": "maroo RPC did not return a transaction receipt",
            "externalChainExitCondition": "BlockedByExternalChain",
            "externalChainBlockerType": "payment_confirmation_unavailable",
            "externalChainOperation": "executeOKRWTransfer",
            "externalChainEndpoint": "https://rpc-testnet.maroo.io",
            "externalChainMessage": "maroo RPC did not return a transaction receipt"
        ]
        request = nil
        isProcessing = false
        didCompleteOrder = false
        orderId = "DM-2026-0509-FAILED"
        orderSource = "failed receipt UI test"
        incoming = "Target-owned failed receipt accepted · OKRW execution attempted · no paid order state"
        order = "OKRW execution attempted but not paid. DailyMart does not mark the order complete without a confirmed txHash."
        auditTrail = "grocery.purchase_essentials.failed\nrequest_id=ios-grocery-failed-ui\nmesh_receipt_signed=true\nchain_status=failed\npresentation_state=attempted_failed\nanchoring_reference=request-anchor-sha256-\(requestHash)\nerrorCode=payment_confirmation_unavailable\nerrorMessage=maroo RPC did not return a transaction receipt\nno_tx_hash=true"
        receiptChainProofTitle = "Failed provider-neutral chain proof"
        receiptChainProofAccessibilityPrefix = "Failed chain proof"
        receiptChainProofFields = DailyMartReceiptProofField.failedFields(from: result)
    }

    private func showPolicyDeniedReceiptUIProof() {
        let requestHash = String(repeating: "d", count: 64)
        let policyHash = DailyMartDelegatedSpendingPolicy.policyHash.value
        let result = [
            "chainProvider": "maroo",
            "chainId": "maroo-testnet-1",
            "chainNetwork": "maroo-testnet",
            "chainProofType": "policy_denial",
            "chainStatus": "failed",
            "presentationState": "policy_denied",
            "requestHash": requestHash,
            "requestNonce": "ios-grocery-policy-denied-ui-nonce",
            "policyId": DailyMartDelegatedSpendingPolicy.policyId,
            "policyHash": policyHash,
            "walletAddress": "maroo1dailyMartAgentWallet",
            "amount": "250",
            "asset": DailyMartDelegatedSpendingPolicy.asset,
            "recipient": DailyMartDelegatedSpendingPolicy.recipientAddress,
            "anchoringReference": "request-anchor-sha256-\(requestHash)",
            "executionAttemptId": "meshkit-execution-attempt/v1:policy-denied-ui:wallet-policy:exec-policy-denied-ui",
            "executionId": "exec-policy-denied-ui",
            "errorCode": "wallet_policy_denied",
            "errorMessage": "policy-single-payment-max-exceeded"
        ]
        request = nil
        isProcessing = false
        didCompleteOrder = false
        orderId = "DM-2026-0509-POLICY-DENIED"
        orderSource = "policy-denied receipt UI test"
        incoming = "Target-owned policy-denied receipt accepted · delegated wallet policy blocked execution"
        order = "DailyMart policy denied this delegated spend. No OKRW execution started and no order is marked paid."
        auditTrail = "grocery.purchase_essentials.policy_denied\nrequest_id=ios-grocery-policy-denied-ui\nmesh_receipt_signed=true\nchain_status=failed\npresentation_state=policy_denied\nproof_type=policy_denial\nanchoring_reference=request-anchor-sha256-\(requestHash)\nexecution_started=false\nerrorCode=wallet_policy_denied\nerrorMessage=policy-single-payment-max-exceeded\nno_tx_hash=true"
        receiptChainProofTitle = "Policy-denied provider-neutral chain proof"
        receiptChainProofAccessibilityPrefix = "Policy-denied chain proof"
        receiptChainProofFields = DailyMartReceiptProofField.policyDeniedFields(from: result)
    }

    private func demoMeshRequest(requestId: String) -> MeshRequest {
        MeshRequest(
            requestId: requestId,
            caller: MeshIdentity(appId: "app.hermes-chat", installId: "ios-sim", bundleId: "ai.meshkit.sample.hermeschat", publicKeyId: "sample-ios-ed25519"),
            target: MeshCapability(targetBundleId: "ai.meshkit.sample.dailymart", capabilityId: "grocery.purchase_essentials", version: "1.0"),
            payload: [
                "items": "laundry_detergent:1,toilet_paper:2,bottled_water_2l:6",
                "address_ref": "home.saved",
                "budget_krw": "100",
                "merchantScope": DailyMartDelegatedSpendingPolicy.merchantScope,
                "capabilityScope": DailyMartDelegatedSpendingPolicy.capabilityScope,
                "consentGrantId": DailyMartDelegatedSpendingPolicy.consentGrantId,
                "walletSessionId": DailyMartDelegatedSpendingPolicy.walletSessionId,
                "principalId": DailyMartDelegatedSpendingPolicy.principalId,
                "policyId": DailyMartDelegatedSpendingPolicy.policyId,
                "policyHash": DailyMartDelegatedSpendingPolicy.policyHash.value
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
            let accepted = try HermesRequestSigningTrust
                .dailyMartPreExecutionGuard(freshnessStore: preExecutionFreshnessStore)
                .acceptForWalletExecution(decoded)
            request = decoded
            orderId = "DM-2026-0509-001"
            orderSource = "foreground consent grant"
            didCompleteOrder = false
            isProcessing = false
            order = "No order yet."
            auditTrail = "Consent and execution history will appear here."
            incoming = "Pre-execution guard passed · nonce \(accepted.nonce) · OKRW ₩\(accepted.executionRequest.amount) · available ₩\(accepted.availableLimitBeforeExecution)"
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
            do {
                let gate = try requireWalletPolicyApproval(for: request)
                isProcessing = true
                order = "Consent granted. Hermes may place this order once in the background."
                orderId = "DM-2026-0509-001"
                orderSource = "foreground consent grant"
                didCompleteOrder = false
                auditTrail = "wallet_policy_gate=\(gate.policyEvaluation.status.rawValue)\nscope_consent_gate=\(gate.scopeConsent.status.rawValue)\nrequest_id=\(request.requestId)\nmerchant_scope=\(gate.scopeConsent.merchantScope)\ncapability_scope=\(gate.scopeConsent.capabilityScope)\nconsent_grant_id=\(gate.scopeConsent.consentGrantId)\navailable_limit_okrw=\(gate.availableLimitBeforeExecution)\norder_placed=false"
            } catch {
                isProcessing = false
                didCompleteOrder = false
                order = "Policy denied before purchase: \(error)"
                auditTrail = policyDeniedAuditTrail(for: request, error: error)
            }
            return
        }
        isProcessing = true
        order = "Consent granted. Hermes may place this order once in the background."
        auditTrail = "consent.granted → intent.pending\nscope=purchase,address,wallet_budget · max_budget=100 · one_time=true"
        Task { @MainActor in
            await executeApprovedOKRWPurchase(request)
        }
    }

    @MainActor
    private func executeApprovedOKRWPurchase(_ request: MeshRequest) async {
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
            let gate = try requireWalletPolicyApproval(for: request)
            let orchestrationResult = try await dailyMartOKRWOrchestrator().execute(
                request: request,
                executionKind: .payment,
                anchorSubmittedAt: ISO8601DateFormatter().string(from: Date()),
                authorizationDecidedAt: ISO8601DateFormatter().string(from: Date()),
                paymentRequestedAt: ISO8601DateFormatter().string(from: Date()),
                paymentSubmittedAt: ISO8601DateFormatter().string(from: Date())
            )
            if orchestrationResult.presentationState == .policyDenied ||
                orchestrationResult.presentationState == .validationDenied {
                let reason = orchestrationResult.denialReason ?? "pre-execution-denied"
                let receipt = try signedPolicyDeniedReceipt(for: request, reason: reason)
                let encodedReceipt = try receipt.encodedForURLScheme()
                isProcessing = false
                didCompleteOrder = false
                order = "DailyMart policy denied this delegated spend. No OKRW execution started and no order is marked paid."
                auditTrail = "wallet_policy_gate=denied\nrequest_id=\(request.requestId)\nexecution_started=false\nmesh_receipt_signed=true\nstatus=failed\nproof_type=\(receipt.result["chainProofType"] ?? "")\npresentation_state=\(receipt.result["presentationState"] ?? "")\nerrorCode=\(receipt.result["errorCode"] ?? "")\nerrorMessage=\(receipt.result["errorMessage"] ?? "")"
                openHermesCallback(status: "failed", requestId: request.requestId, encodedReceipt: encodedReceipt)
                return
            }
            let receipt = try signedReceipt(
                for: request,
                orchestrationResult: orchestrationResult,
                orderId: "DM-2026-0509-001"
            )
            let encodedReceipt = try receipt.encodedForURLScheme()
            let callbackStatus = receipt.result["chainStatus"] == "confirmed" ? "purchased" : "submitted"
            orderId = "DM-2026-0509-001"
            orderSource = "foreground consent grant"
            didCompleteOrder = receipt.result["chainStatus"] == "confirmed"
            isProcessing = true
            if didCompleteOrder {
                incoming = "Target-owned signed OKRW receipt emitted · foreground consent grant"
                order = "Order DM-2026-0509-001 — 주문 완료\n• 세탁세제 × 1\n• 화장지 × 2\n• 생수 2L × 6\nTotal: ₩100\nDelivery: 오늘 19:00–21:00"
                receiptChainProofTitle = "Confirmed provider-neutral chain proof"
                receiptChainProofAccessibilityPrefix = "Confirmed chain proof"
                receiptChainProofFields = DailyMartReceiptProofField.confirmedFields(from: receipt.result)
            } else {
                incoming = "Target-owned signed OKRW receipt emitted · awaiting maroo confirmation"
                order = "OKRW execution submitted. No order is marked paid until maroo returns a live confirmed txHash."
                receiptChainProofTitle = "Pending provider-neutral chain proof"
                receiptChainProofAccessibilityPrefix = "Pending chain proof"
                receiptChainProofFields = DailyMartReceiptProofField.pendingFields(from: receipt.result)
            }
            auditTrail = "wallet_policy_gate=\(gate.policyEvaluation.status.rawValue)\nscope_consent_gate=\(gate.scopeConsent.status.rawValue)\nrequest_id=\(audit.requestId)\nmerchant_scope=\(gate.scopeConsent.merchantScope)\ncapability_scope=\(gate.scopeConsent.capabilityScope)\nconsent_grant_id=\(gate.scopeConsent.consentGrantId)\navailable_limit_okrw=\(gate.availableLimitBeforeExecution)\nmesh_receipt_signed=true\nchain_status=\(receipt.result["chainStatus"] ?? "pending")\npresentation_state=\(receipt.result["presentationState"] ?? "submitted_not_final")\nasset=\(receipt.result["asset"] ?? DailyMartDelegatedSpendingPolicy.asset)"
            openHermesCallback(status: callbackStatus, requestId: request.requestId, encodedReceipt: encodedReceipt)
        } catch {
            isProcessing = false
            didCompleteOrder = false
            order = "Policy denied before purchase: \(error)"
            auditTrail = policyDeniedAuditTrail(for: request, error: error)
        }
    }

    private func policyDeniedAuditTrail(for request: MeshRequest, error: Error) -> String {
        let reason = "\(error)"
        do {
            let receipt = try signedPolicyDeniedReceipt(for: request, reason: reason)
            let encoded = try receipt.encodedForURLScheme()
            openHermesCallback(status: "failed", requestId: request.requestId, encodedReceipt: encoded)
            return "wallet_policy_gate=denied\nrequest_id=\(request.requestId)\nexecution_started=false\nmesh_receipt_signed=true\nstatus=failed\nproof_type=\(receipt.result["chainProofType"] ?? "")\npresentation_state=\(receipt.result["presentationState"] ?? "")\nerrorCode=\(receipt.result["errorCode"] ?? "")\nerrorMessage=\(receipt.result["errorMessage"] ?? "")\nerror=\(reason)"
        } catch {
            return "wallet_policy_gate=denied\nrequest_id=\(request.requestId)\nexecution_started=false\nmesh_receipt_signed=false\nerror=\(reason)\nreceipt_error=\(error)"
        }
    }

    private func dailyMartOKRWOrchestrator() throws -> DailyMartGuardOrchestrator {
        try DailyMartGuardOrchestrator(
            signedRequestGuard: HermesRequestSigningTrust.dailyMartPreExecutionGuard(
                freshnessStore: DailyMartRequestNonceFreshnessStore()
            ),
            walletPolicyGuard: try DailyMartPreExecutionWalletPolicyGuard(),
            requestAnchorProvider: try MeshMarooTestnetRequestAnchorAdapter(status: .submitted),
            paymentExecutor: try MeshMarooTestnetPaymentExecutorAdapter()
        )
    }

    private func signedReceipt(for request: MeshRequest, orderId: String) throws -> MeshReceipt {
        let policyVerification = try verifyDelegatedSpendingPolicy(for: request)
        let chainProof = try dailyMartChainProof(for: request, orderId: orderId, policyVerification: policyVerification)
        let baseResult = [
            "order_id": orderId,
            "total_krw": "100",
            "payment_asset": DailyMartDelegatedSpendingPolicy.asset,
            "policy_verification": policyVerification.status.rawValue
        ]
        return try DailyMartTargetReceiptFactory(
            signer: MeshReceiptSigner.ed25519(
                keyId: DailyMartReceiptSigningKey.keyId,
                privateKey: DailyMartReceiptSigningKey.privateKey()
            )
        ).makeAcceptedCallReceipt(
            request: request,
            status: chainProof.status == .confirmed ? "purchased" : "submitted",
            baseResult: baseResult,
            chainProof: chainProof,
            timestamp: ISO8601DateFormatter().string(from: Date())
        )
    }

    private func signedReceipt(
        for request: MeshRequest,
        orchestrationResult: DailyMartGuardOrchestrationResult,
        orderId: String
    ) throws -> MeshReceipt {
        try DailyMartTargetReceiptFactory(
            signer: MeshReceiptSigner.ed25519(
                keyId: DailyMartReceiptSigningKey.keyId,
                privateKey: DailyMartReceiptSigningKey.privateKey()
            )
        ).makeVerifiedWalletExecutionReceipt(
            request: request,
            orchestrationResult: orchestrationResult,
            walletAddress: "maroo1dailyMartAgentWallet",
            baseResult: [
                "order_id": orderId,
                "total_krw": "100",
                "payment_asset": DailyMartDelegatedSpendingPolicy.asset,
                "policy_verification": MeshDelegatedSpendingPolicyVerificationStatus.approved.rawValue
            ],
            timestamp: ISO8601DateFormatter().string(from: Date())
        )
    }

    private func signedPolicyDeniedReceipt(for request: MeshRequest, reason: String) throws -> MeshReceipt {
        let policyGuard = try DailyMartPreExecutionWalletPolicyGuard()
        let executionRequest = try policyGuard.makeExecutionRequest(
            from: request,
            executionKind: .payment,
            executionId: "exec-\(request.requestId)"
        )
        let providerIdentity = try MeshMarooTestnetChainProvider().identity
        let anchoringReference = try MeshRequestAnchorCanonicalization.anchoringReference(
            for: request,
            providerIdentity: providerIdentity
        )
        return try DailyMartTargetReceiptFactory(
            signer: MeshReceiptSigner.ed25519(
                keyId: DailyMartReceiptSigningKey.keyId,
                privateKey: DailyMartReceiptSigningKey.privateKey()
            )
        ).makePolicyDeniedWalletExecutionReceipt(
            request: request,
            executionRequest: executionRequest,
            providerIdentity: providerIdentity,
            walletAddress: "maroo1dailyMartAgentWallet",
            anchoringReference: anchoringReference.anchorId,
            denialReason: reason,
            baseResult: [
                "order_id": orderId,
                "total_krw": request.payload["budget_krw"] ?? "100",
                "payment_asset": DailyMartDelegatedSpendingPolicy.asset,
                "errorCode": "wallet_policy_denied",
                "errorMessage": reason
            ],
            timestamp: ISO8601DateFormatter().string(from: Date())
        )
    }

    private func dailyMartChainProof(
        for request: MeshRequest,
        orderId: String,
        policyVerification: MeshDelegatedSpendingPolicyVerificationResult
    ) throws -> MeshChainProof {
        let observedAt = ISO8601DateFormatter().string(from: Date())
        let anchoringReference = try dailyMartAnchoringReference(for: request)
        guard let liveTxHash = ProcessInfo.processInfo.environment["MESHKIT_IOS_MAROO_LIVE_TX_HASH"],
              !liveTxHash.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            let blockerEvidence = try MeshExternalChainBlockerEvidence(
                blockerType: .paymentConfirmationUnavailable,
                identity: MeshMarooTestnetChainProvider().identity,
                endpoint: URL(string: "https://rpc-testnet.maroo.io"),
                operation: "executeOKRWTransfer",
                observedAt: observedAt,
                message: "maroo live OKRW confirmation is unavailable for this demo run",
                requestHash: MeshRequestAnchorCanonicalization.signedRequestHash(for: request),
                requestNonce: request.nonce,
                anchoringReference: anchoringReference.anchorId
            )
            return try MeshChainProof(
                provider: "maroo",
                chainId: "maroo-testnet-1",
                network: "maroo-testnet",
                proofType: .requestAnchor,
                status: .pending,
                presentationState: .submittedNotFinal,
                requestHash: MeshRequestAnchorCanonicalization.signedRequestHash(for: request),
                requestNonce: request.nonce,
                policyId: policyVerification.policyId,
                policyHash: policyVerification.policyHash,
                walletAddress: "maroo1dailyMartAgentWallet",
                amount: Decimal(100),
                asset: DailyMartDelegatedSpendingPolicy.asset,
                recipient: DailyMartDelegatedSpendingPolicy.recipientAddress,
                anchoringReference: anchoringReference.anchorId,
                submittedAt: observedAt,
                providerExtensions: ["maroo": blockerEvidence.providerExtensionFields]
            )
        }
        let anchorTxHash = ProcessInfo.processInfo.environment["MESHKIT_IOS_MAROO_ANCHOR_TX_HASH"]
        return try MeshChainProof(
            provider: "maroo",
            chainId: "maroo-testnet-1",
            network: "maroo-testnet",
            proofType: .paymentExecution,
            status: .confirmed,
            presentationState: .paidComplete,
            requestHash: MeshRequestAnchorCanonicalization.signedRequestHash(for: request),
            requestNonce: request.nonce,
            policyId: policyVerification.policyId,
            policyHash: policyVerification.policyHash,
            walletAddress: "maroo1dailyMartAgentWallet",
            amount: Decimal(100),
            asset: DailyMartDelegatedSpendingPolicy.asset,
            recipient: DailyMartDelegatedSpendingPolicy.recipientAddress,
            anchoringReference: anchoringReference.anchorId,
            anchorTxHash: anchorTxHash,
            txHash: liveTxHash,
            explorerUrl: URL(string: "https://explorer-testnet.maroo.io/tx/\(liveTxHash)"),
            submittedAt: observedAt,
            confirmedAt: observedAt
        )
    }

    private func dailyMartAnchoringReference(for request: MeshRequest) throws -> MeshRequestAnchorIdentifier {
        try MeshRequestAnchorCanonicalization.anchoringReference(
            for: request,
            providerIdentity: MeshMarooTestnetChainProvider().identity
        )
    }

    private func verifyDelegatedSpendingPolicy(for request: MeshRequest) throws -> MeshDelegatedSpendingPolicyVerificationResult {
        let result = try DailyMartDelegatedSpendingPolicy.verifyRequest(
            request,
            verifiedAt: ISO8601DateFormatter().string(from: Date())
        )
        guard result.status == .approved else {
            throw MeshKitValidationError.invalidAgentWalletIdentity(result.reason ?? "policy-verification")
        }
        return result
    }

    private func requireWalletPolicyApproval(for request: MeshRequest) throws -> DailyMartPreExecutionWalletPolicyGuardResult {
        try DailyMartPreExecutionWalletPolicyGuard().evaluate(
            request,
            executionKind: .payment,
            executionId: "exec-\(request.requestId)",
            verifiedAt: ISO8601DateFormatter().string(from: Date())
        )
    }

    private func urlEscape(_ value: String) -> String {
        value.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? value
    }

    private func openHermesCallback(status: String, requestId: String, encodedReceipt: String) {
        var components = URLComponents()
        components.scheme = "meshkit-hermes"
        components.host = "callback"
        components.queryItems = [
            URLQueryItem(name: "status", value: status),
            URLQueryItem(name: "receipt_token", value: requestId),
            URLQueryItem(name: "mesh_receipt", value: encodedReceipt)
        ]
        guard let callback = components.url else {
            auditTrail = "\(auditTrail)\ncallback_url_error=badURL"
            return
        }
        UIApplication.shared.open(callback)
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
    let receiptChainProofTitle: String
    let receiptChainProofAccessibilityPrefix: String
    let receiptChainProofFields: [DailyMartReceiptProofField]
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
                        receiptProofCard
                        basketCard
                        auditCard
                    } else if isProcessing {
                        approvalProcessingCard
                        receiptProofCard
                        basketCard
                        auditCard
                    } else {
                        requestCard
                        receiptProofCard
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

    @ViewBuilder
    private var receiptProofCard: some View {
        if !receiptChainProofFields.isEmpty {
            AppCard {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 10) {
                        IconBadge(systemName: "link.badge.plus", color: Color(red: 0.13, green: 0.32, blue: 0.78))
                        VStack(alignment: .leading, spacing: 3) {
                            Text(receiptChainProofTitle)
                                .font(.system(size: 18, weight: .black, design: .rounded))
                                .foregroundColor(.primary)
                                .lineLimit(1)
                                .minimumScaleFactor(0.78)
                            Text("Target-owned DailyMart MeshReceipt")
                                .font(.system(size: 12.5, weight: .semibold))
                                .foregroundColor(.secondary)
                        }
                    }
                    VStack(spacing: 8) {
                        ForEach(receiptChainProofFields) { field in
                            ProofRow(label: field.label, value: field.value)
                                .accessibilityLabel("\(receiptChainProofAccessibilityPrefix) \(field.schemaName): \(field.value)")
                                .accessibilityIdentifier("chain-proof-field-\(field.schemaName)")
                        }
                    }
                    .padding(12)
                    .background(Color(red: 0.13, green: 0.32, blue: 0.78).opacity(0.07))
                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                }
                .accessibilityElement(children: .contain)
                .accessibilityLabel("\(receiptChainProofTitle) fields")
                .accessibilityIdentifier("\(receiptChainProofAccessibilityPrefix.lowercased().replacingOccurrences(of: " ", with: "-"))-debug-ui")
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

private struct DailyMartReceiptProofField: Identifiable, Equatable {
    let schemaName: String
    let label: String
    let value: String

    var id: String { schemaName }

    static func confirmedFields(from result: [String: String]) -> [DailyMartReceiptProofField] {
        [
            field("provider", "Provider", result["chainProvider"]),
            field("chainId", "Chain ID", result["chainId"]),
            field("network", "Network", result["chainNetwork"]),
            field("proofType", "Proof type", result["chainProofType"]),
            field("status", "Status", result["chainStatus"]),
            field("presentationState", "Presentation", result["presentationState"]),
            field("requestHash", "Request hash", result["requestHash"]),
            field("requestNonce", "Request nonce", result["requestNonce"]),
            field("policyId", "Policy ID", result["policyId"]),
            field("policyHash", "Policy hash", result["policyHash"]),
            field("walletAddress", "Wallet", result["walletAddress"]),
            field("amount", "Amount", result["amount"]),
            field("asset", "Asset", result["asset"]),
            field("recipient", "Recipient", result["recipient"]),
            field("anchoringReference", "Anchor", result["anchoringReference"]),
            field("txHash", "Tx hash", result["txHash"]),
            field("explorerUrl", "Explorer", result["explorerUrl"]),
            field("confirmedAt", "Confirmed at", result["confirmedAt"]),
            field("providerExtensions", "Provider extensions", result["providerExtensions"] ?? "none")
        ]
    }

    static func pendingFields(from result: [String: String]) -> [DailyMartReceiptProofField] {
        [
            field("provider", "Provider", result["chainProvider"]),
            field("chainId", "Chain ID", result["chainId"]),
            field("network", "Network", result["chainNetwork"]),
            field("proofType", "Proof type", result["chainProofType"]),
            field("status", "Status", result["chainStatus"]),
            field("presentationState", "Presentation", result["presentationState"]),
            field("requestHash", "Request hash", result["requestHash"]),
            field("requestNonce", "Request nonce", result["requestNonce"]),
            field("policyId", "Policy ID", result["policyId"]),
            field("policyHash", "Policy hash", result["policyHash"]),
            field("walletAddress", "Wallet", result["walletAddress"]),
            field("amount", "Amount", result["amount"]),
            field("asset", "Asset", result["asset"]),
            field("recipient", "Recipient", result["recipient"]),
            field("anchoringReference", "Anchor", result["anchoringReference"]),
            field("executionAttemptId", "Execution attempt", result["executionAttemptId"]),
            field("paymentId", "Payment ID", result["paymentId"]),
            field("authorizationId", "Authorization ID", result["authorizationId"]),
            field("executionId", "Execution ID", result["executionId"]),
            field("executionKind", "Execution kind", result["executionKind"]),
            field("anchorTxHash", "Anchor tx hash", result["anchorTxHash"]),
            field("submittedAt", "Submitted at", result["submittedAt"]),
            field("externalChainExitCondition", "External chain", result["externalChainExitCondition"]),
            field("externalChainBlockerType", "Blocker type", result["externalChainBlockerType"]),
            field("externalChainOperation", "Operation", result["externalChainOperation"]),
            field("externalChainEndpoint", "Endpoint", result["externalChainEndpoint"]),
            field("externalChainMessage", "Message", result["externalChainMessage"])
        ]
    }

    static func failedFields(from result: [String: String]) -> [DailyMartReceiptProofField] {
        [
            field("provider", "Provider", result["chainProvider"]),
            field("chainId", "Chain ID", result["chainId"]),
            field("network", "Network", result["chainNetwork"]),
            field("proofType", "Proof type", result["chainProofType"]),
            field("status", "Status", result["chainStatus"]),
            field("presentationState", "Presentation", result["presentationState"]),
            field("requestHash", "Request hash", result["requestHash"]),
            field("requestNonce", "Request nonce", result["requestNonce"]),
            field("policyId", "Policy ID", result["policyId"]),
            field("policyHash", "Policy hash", result["policyHash"]),
            field("walletAddress", "Wallet", result["walletAddress"]),
            field("amount", "Amount", result["amount"]),
            field("asset", "Asset", result["asset"]),
            field("recipient", "Recipient", result["recipient"]),
            field("anchoringReference", "Anchor", result["anchoringReference"]),
            field("executionAttemptId", "Execution attempt", result["executionAttemptId"]),
            field("paymentId", "Payment ID", result["paymentId"]),
            field("authorizationId", "Authorization ID", result["authorizationId"]),
            field("executionId", "Execution ID", result["executionId"]),
            field("executionKind", "Execution kind", result["executionKind"]),
            field("anchorTxHash", "Anchor tx hash", result["anchorTxHash"]),
            field("errorCode", "Error code", result["errorCode"]),
            field("errorMessage", "Error message", result["errorMessage"]),
            field("externalChainExitCondition", "External chain", result["externalChainExitCondition"]),
            field("externalChainBlockerType", "Blocker type", result["externalChainBlockerType"]),
            field("externalChainOperation", "Operation", result["externalChainOperation"]),
            field("externalChainEndpoint", "Endpoint", result["externalChainEndpoint"]),
            field("externalChainMessage", "Message", result["externalChainMessage"])
        ]
    }

    static func policyDeniedFields(from result: [String: String]) -> [DailyMartReceiptProofField] {
        [
            field("provider", "Provider", result["chainProvider"]),
            field("chainId", "Chain ID", result["chainId"]),
            field("network", "Network", result["chainNetwork"]),
            field("proofType", "Proof type", result["chainProofType"]),
            field("status", "Status", result["chainStatus"]),
            field("presentationState", "Presentation", result["presentationState"]),
            field("requestHash", "Request hash", result["requestHash"]),
            field("requestNonce", "Request nonce", result["requestNonce"]),
            field("policyId", "Policy ID", result["policyId"]),
            field("policyHash", "Policy hash", result["policyHash"]),
            field("walletAddress", "Wallet", result["walletAddress"]),
            field("amount", "Amount", result["amount"]),
            field("asset", "Asset", result["asset"]),
            field("recipient", "Recipient", result["recipient"]),
            field("anchoringReference", "Anchor", result["anchoringReference"]),
            field("executionAttemptId", "Execution attempt", result["executionAttemptId"]),
            field("executionId", "Execution ID", result["executionId"]),
            field("errorCode", "Error code", result["errorCode"]),
            field("errorMessage", "Error message", result["errorMessage"])
        ]
    }

    private static func field(_ schemaName: String, _ label: String, _ value: String?) -> DailyMartReceiptProofField {
        DailyMartReceiptProofField(schemaName: schemaName, label: label, value: value ?? "missing")
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
                .multilineTextAlignment(.trailing)
                .lineLimit(3)
                .minimumScaleFactor(0.72)
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
