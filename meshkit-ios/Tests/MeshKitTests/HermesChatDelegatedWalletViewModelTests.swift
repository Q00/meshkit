import XCTest
@testable import MeshKit

final class HermesChatDelegatedWalletViewModelTests: XCTestCase {
    func testMarooDailyMartOKRWWalletViewModelExposesProviderLimitsAssetAndScope() throws {
        let viewModel = try HermesChatDelegatedWalletViewModels.marooTestnetOKRWDailyMartGrocerySession()

        XCTAssertEqual(viewModel.provider, "maroo")
        XCTAssertEqual(viewModel.network, "maroo-testnet")
        XCTAssertEqual(viewModel.chainId, "maroo-testnet-1")
        XCTAssertEqual(viewModel.walletAddress, "maroo1dailyMartAgentWallet")
        XCTAssertEqual(viewModel.asset, "OKRW")
        XCTAssertEqual(viewModel.singlePaymentMax, Decimal(100))
        XCTAssertEqual(viewModel.sessionTotalLimit, Decimal(100))
        XCTAssertEqual(viewModel.remainingLimit, Decimal(100))
        XCTAssertEqual(viewModel.merchantScope, "merchant.dailymart")
        XCTAssertEqual(viewModel.capabilityScope, "grocery.purchase_essentials")
        XCTAssertEqual(viewModel.targetBundleId, "ai.meshkit.sample.dailymart")
        XCTAssertEqual(viewModel.consentGrantId, "grant-hermes-dailymart-001")
        XCTAssertEqual(viewModel.policyId, "policy-hermes-dailymart-okrw-v1")
    }

    func testDelegatedWalletPanelSnapshotRendersAgentOSOCGHeaderAndLimitRows() throws {
        let snapshot = try HermesChatDelegatedWalletViewModels
            .marooTestnetOKRWDailyMartGrocerySession()
            .panelSnapshot

        XCTAssertEqual(snapshot.headerLabel, "AgentOS/OCG delegated wallet")
        XCTAssertEqual(snapshot.providerLine, "maroo testnet")
        XCTAssertEqual(snapshot.sessionLimitLine, "100 OKRW")
        XCTAssertEqual(snapshot.remainingLimitLine, "100 OKRW")
        XCTAssertEqual(snapshot.remainingSessionLimitSummaryLine, "Remaining session limit: 100 OKRW")
        XCTAssertEqual(snapshot.perPaymentMaxLine, "100 OKRW")
        XCTAssertEqual(snapshot.authorizationLine, "OKRW · DailyMart grocery.purchase_essentials")
        XCTAssertEqual(snapshot.assetLine, "OKRW")
        XCTAssertEqual(snapshot.scopeLine, "DailyMart grocery.purchase_essentials")
        XCTAssertEqual(snapshot.scopeStatusLine, "Allowed by saved grant")
        XCTAssertEqual(snapshot.scopePresentation.status, .allowed)
        XCTAssertEqual(snapshot.scopePresentation.rawScopeLine, "merchant.dailymart · grocery.purchase_essentials")
        XCTAssertTrue(snapshot.accessibilityLabel.contains("AgentOS/OCG delegated wallet"))
        XCTAssertTrue(snapshot.accessibilityLabel.contains("provider maroo testnet"))
        XCTAssertTrue(snapshot.accessibilityLabel.contains("total session limit 100 OKRW"))
        XCTAssertTrue(snapshot.accessibilityLabel.contains("remaining session limit 100 OKRW"))
        XCTAssertTrue(snapshot.accessibilityLabel.contains("per payment max 100 OKRW"))
        XCTAssertTrue(snapshot.accessibilityLabel.contains("authorization OKRW · DailyMart grocery.purchase_essentials"))
        XCTAssertTrue(snapshot.accessibilityLabel.contains("asset OKRW"))
        XCTAssertTrue(snapshot.accessibilityLabel.contains("scope DailyMart grocery.purchase_essentials"))
        XCTAssertTrue(snapshot.accessibilityLabel.contains("raw scope merchant.dailymart · grocery.purchase_essentials"))
    }

    func testDelegatedWalletPanelRowsProvideRunnableComponentCoverageForHermesChat() throws {
        let snapshot = try HermesChatDelegatedWalletViewModels
            .marooTestnetOKRWDailyMartGrocerySession()
            .panelSnapshot

        XCTAssertEqual(snapshot.rows, [
            MeshDelegatedWalletPanelRow(label: "Provider", value: "maroo testnet"),
            MeshDelegatedWalletPanelRow(label: "Total session limit", value: "100 OKRW"),
            MeshDelegatedWalletPanelRow(label: "Remaining limit", value: "100 OKRW"),
            MeshDelegatedWalletPanelRow(label: "Per-payment max", value: "100 OKRW"),
            MeshDelegatedWalletPanelRow(label: "Authorization", value: "OKRW · DailyMart grocery.purchase_essentials"),
            MeshDelegatedWalletPanelRow(label: "Asset", value: "OKRW"),
            MeshDelegatedWalletPanelRow(label: "Scope", value: "DailyMart grocery.purchase_essentials"),
            MeshDelegatedWalletPanelRow(label: "Scope status", value: "Allowed by saved grant")
        ])
    }

    func testDelegatedWalletPanelComponentRendersTotalSessionLimitFromPolicyData() throws {
        let policy = try MeshAgentWalletDelegatedSpendingPolicy(
            policyId: "policy-panel-total-limit-v1",
            policyHash: MeshPayloadHash(value: String(repeating: "d", count: 64)),
            consentGrantId: "grant-panel-total-limit-001",
            merchantScope: DailyMartDelegatedSpendingPolicy.merchantScope,
            capabilityScope: DailyMartDelegatedSpendingPolicy.capabilityScope,
            singlePaymentMax: Decimal(75),
            sessionTotalLimit: Decimal(250),
            remainingLimit: Decimal(175),
            expiresAt: "2026-12-31T23:59:59Z",
            asset: "OKRW",
            recipientAddress: "0x000000000000000000000000000000000000d417"
        )
        let wallet = try HermesChatDelegatedWalletViewModels.viewModel(
            providerMetadata: MeshAgentWalletProviderMetadata(
                chainProviderIdentity: MeshMarooTestnetChainProvider().identity,
                adapterId: "maroo-testnet-agent-wallet-adapter"
            ),
            walletAddress: "maroo1dailyMartAgentWallet",
            policy: policy,
            targetBundleId: HermesChatDelegatedWalletViewModels.dailyMartTargetBundleId
        )

        let component = MeshDelegatedWalletPanelComponent(wallet: wallet)

        XCTAssertEqual(component.renderedLines[2], "Total session limit: 250 OKRW")
        XCTAssertEqual(component.renderedPanelLines[1], "Remaining session limit: 175 OKRW")
        XCTAssertTrue(component.renderedLines.contains("Remaining limit: 175 OKRW"))
        XCTAssertTrue(component.renderedPanelLines.contains("Remaining limit: 175 OKRW"))
        XCTAssertTrue(component.renderedLines.contains("Per-payment max: 75 OKRW"))
        XCTAssertTrue(component.renderedPanelLines.contains("Authorization: OKRW · grocery.purchase_essentials"))
        XCTAssertTrue(component.accessibilityLabel.contains("remaining session limit 175 OKRW"))
        XCTAssertTrue(component.accessibilityLabel.contains("total session limit 250 OKRW"))
    }

    func testDelegatedWalletPanelComponentRendersPerPaymentMaxFromPolicyData() throws {
        let policy = try MeshAgentWalletDelegatedSpendingPolicy(
            policyId: "policy-panel-per-payment-max-v1",
            policyHash: MeshPayloadHash(value: String(repeating: "e", count: 64)),
            consentGrantId: "grant-panel-per-payment-max-001",
            merchantScope: DailyMartDelegatedSpendingPolicy.merchantScope,
            capabilityScope: DailyMartDelegatedSpendingPolicy.capabilityScope,
            singlePaymentMax: Decimal(42),
            sessionTotalLimit: Decimal(250),
            remainingLimit: Decimal(175),
            expiresAt: "2026-12-31T23:59:59Z",
            asset: "OKRW",
            recipientAddress: "0x000000000000000000000000000000000000d417"
        )
        let wallet = try HermesChatDelegatedWalletViewModels.viewModel(
            providerMetadata: MeshAgentWalletProviderMetadata(
                chainProviderIdentity: MeshMarooTestnetChainProvider().identity,
                adapterId: "maroo-testnet-agent-wallet-adapter"
            ),
            walletAddress: "maroo1dailyMartAgentWallet",
            policy: policy,
            targetBundleId: HermesChatDelegatedWalletViewModels.dailyMartTargetBundleId
        )

        let component = MeshDelegatedWalletPanelComponent(wallet: wallet)

        XCTAssertEqual(wallet.singlePaymentMax, Decimal(42))
        XCTAssertEqual(wallet.panelSnapshot.perPaymentMaxLine, "42 OKRW")
        XCTAssertTrue(component.renderedLines.contains("Per-payment max: 42 OKRW"))
        XCTAssertTrue(component.renderedPanelLines.contains("Per-payment max: 42 OKRW"))
        XCTAssertTrue(component.accessibilityLabel.contains("per payment max 42 OKRW"))
    }

    func testDelegatedWalletRemainingLimitDecrementsOnlyAfterAcceptedPaymentReceiptsAcrossRequests() throws {
        let initialWallet = try HermesChatDelegatedWalletViewModels.marooTestnetOKRWDailyMartGrocerySession()

        let unchangedAfterPending = try initialWallet.applyingDailyMartReceiptResult([
            "chainProofType": "payment_execution",
            "presentationState": "submitted_not_final",
            "chainStatus": "pending",
            "asset": "OKRW",
            "total_krw": "35"
        ])
        let unchangedAfterPolicyDenied = try unchangedAfterPending.applyingDailyMartReceiptResult([
            "chainProofType": "policy_denial",
            "presentationState": "policy_denied",
            "chainStatus": "failed",
            "asset": "OKRW",
            "total_krw": "35"
        ])
        let firstAccepted = try unchangedAfterPolicyDenied.applyingDailyMartReceiptResult([
            "chainProofType": "payment_execution",
            "presentationState": "paid_complete",
            "chainStatus": "confirmed",
            "asset": "OKRW",
            "total_krw": "35",
            "txHash": "0xokrwConfirmedFirstAccepted"
        ])
        let unchangedAfterFailed = try firstAccepted.applyingDailyMartReceiptResult([
            "chainProofType": "payment_execution",
            "presentationState": "attempted_failed",
            "chainStatus": "failed",
            "asset": "OKRW",
            "total_krw": "40"
        ])
        let secondAccepted = try unchangedAfterFailed.applyingDailyMartReceiptResult([
            "chainProofType": "payment_execution",
            "presentationState": "paid_complete",
            "chainStatus": "confirmed",
            "asset": "OKRW",
            "total_krw": "40",
            "txHash": "0xokrwConfirmedSecondAccepted"
        ])

        XCTAssertEqual(unchangedAfterPending.remainingLimit, Decimal(100))
        XCTAssertEqual(unchangedAfterPolicyDenied.remainingLimit, Decimal(100))
        XCTAssertEqual(firstAccepted.remainingLimit, Decimal(65))
        XCTAssertEqual(unchangedAfterFailed.remainingLimit, Decimal(65))
        XCTAssertEqual(secondAccepted.remainingLimit, Decimal(25))
        XCTAssertEqual(secondAccepted.panelSnapshot.remainingLimitLine, "25 OKRW")
    }

    func testDelegatedWalletReceiptDecrementHandlerDebitsEligibleReceiptOnlyOnce() throws {
        let initialWallet = try HermesChatDelegatedWalletViewModels.marooTestnetOKRWDailyMartGrocerySession()
        let eligibleReceiptResult = [
            "chainProofType": "payment_execution",
            "presentationState": "paid_complete",
            "chainStatus": "confirmed",
            "asset": "OKRW",
            "total_krw": "35",
            "txHash": "0xokrwConfirmedReceipt001"
        ]
        var handler = MeshDelegatedWalletReceiptDecrementHandler()

        let firstResult = try handler.apply(
            receiptId: "receipt-dailymart-confirmed-001",
            receiptResult: eligibleReceiptResult,
            to: initialWallet
        )
        let replayResult = try handler.apply(
            receiptId: "receipt-dailymart-confirmed-001",
            receiptResult: eligibleReceiptResult,
            to: firstResult.wallet
        )

        XCTAssertTrue(firstResult.eligibility.isEligible)
        XCTAssertTrue(firstResult.didDecrement)
        XCTAssertEqual(firstResult.wallet.remainingLimit, Decimal(65))
        XCTAssertEqual(handler.appliedReceiptIds, ["receipt-dailymart-confirmed-001"])
        XCTAssertTrue(replayResult.eligibility.isEligible)
        XCTAssertFalse(replayResult.didDecrement)
        XCTAssertEqual(replayResult.wallet.remainingLimit, Decimal(65))
    }

    func testDelegatedWalletLedgerDecrementsByExtractedConfirmedOKRWReceiptAmount() throws {
        let initialWallet = try HermesChatDelegatedWalletViewModels.marooTestnetOKRWDailyMartGrocerySession()
        let receipt = try confirmedOKRWReceipt(
            receiptId: "receipt-dailymart-confirmed-extracted-amount",
            requestId: "request-dailymart-confirmed-extracted-amount",
            executionId: "exec-dailymart-confirmed-extracted-amount",
            amount: Decimal(42),
            conflictingResultAmount: "99"
        )
        var handler = MeshDelegatedWalletReceiptDecrementHandler()

        let result = try handler.apply(receipt: receipt, to: initialWallet)

        XCTAssertTrue(result.eligibility.isEligible)
        XCTAssertTrue(result.didDecrement)
        XCTAssertEqual(result.extractedConfirmedOKRWAmount?.amount, Decimal(42))
        XCTAssertEqual(result.extractedConfirmedOKRWAmount?.denomination, "OKRW")
        XCTAssertEqual(result.wallet.remainingLimit, Decimal(58))
        XCTAssertEqual(result.wallet.panelSnapshot.remainingLimitLine, "58 OKRW")
        XCTAssertEqual(handler.appliedReceiptIds, ["receipt-dailymart-confirmed-extracted-amount"])
    }

    func testHermesChatNonOKRWExecutionReceiptDoesNotDebitRemainingDelegatedLimit() throws {
        let initialWallet = try HermesChatDelegatedWalletViewModels.marooTestnetOKRWDailyMartGrocerySession()
        let receipt = try okrwReceipt(
            receiptId: "receipt-dailymart-confirmed-usdc-no-debit",
            requestId: "request-dailymart-confirmed-usdc-no-debit",
            executionId: "exec-dailymart-confirmed-usdc-no-debit",
            amount: Decimal(35),
            resultAmount: "35",
            status: .confirmed,
            presentationState: .paidComplete,
            txHash: "0x" + String(repeating: "d", count: 64),
            confirmedAt: "2026-05-31T12:06:30Z",
            asset: "USDC"
        )
        var handler = MeshDelegatedWalletReceiptDecrementHandler()

        let processing = try handler.apply(receipt: receipt, to: initialWallet)

        XCTAssertFalse(processing.eligibility.isEligible)
        XCTAssertEqual(processing.eligibility.reason, .notOKRWReceipt)
        XCTAssertFalse(processing.didDecrement)
        XCTAssertNil(processing.extractedConfirmedOKRWAmount)
        XCTAssertEqual(processing.wallet.remainingLimit, Decimal(100))
        XCTAssertEqual(processing.wallet.panelSnapshot.remainingLimitLine, "100 OKRW")
        XCTAssertTrue(handler.appliedReceiptIds.isEmpty)
    }

    func testHermesChatConfirmedMeshReceiptProcessingIsIdempotentForDelegatedLimitAccounting() throws {
        let initialWallet = try HermesChatDelegatedWalletViewModels.marooTestnetOKRWDailyMartGrocerySession()
        let receipt = try confirmedOKRWReceipt(
            receiptId: "receipt-dailymart-confirmed-replay-idempotent",
            requestId: "request-dailymart-confirmed-replay-idempotent",
            executionId: "exec-dailymart-confirmed-replay-idempotent",
            amount: Decimal(35),
            conflictingResultAmount: "35"
        )
        var handler = MeshDelegatedWalletReceiptDecrementHandler()

        let firstProcessing = try handler.apply(receipt: receipt, to: initialWallet)
        let replayProcessing = try handler.apply(receipt: receipt, to: firstProcessing.wallet)

        XCTAssertTrue(firstProcessing.eligibility.isEligible)
        XCTAssertTrue(firstProcessing.didDecrement)
        XCTAssertEqual(firstProcessing.wallet.remainingLimit, Decimal(65))
        XCTAssertTrue(replayProcessing.eligibility.isEligible)
        XCTAssertFalse(replayProcessing.didDecrement)
        XCTAssertEqual(replayProcessing.receiptId, firstProcessing.receiptId)
        XCTAssertEqual(replayProcessing.extractedConfirmedOKRWAmount, firstProcessing.extractedConfirmedOKRWAmount)
        XCTAssertEqual(replayProcessing.wallet.remainingLimit, Decimal(65))
        XCTAssertEqual(replayProcessing.wallet.panelSnapshot.remainingLimitLine, "65 OKRW")
        XCTAssertEqual(handler.appliedReceiptIds, ["receipt-dailymart-confirmed-replay-idempotent"])
    }

    func testHermesChatPendingMeshReceiptDoesNotDebitRemainingDelegatedLimit() throws {
        let initialWallet = try HermesChatDelegatedWalletViewModels.marooTestnetOKRWDailyMartGrocerySession()
        let receipt = try okrwReceipt(
            receiptId: "receipt-dailymart-pending-no-debit",
            requestId: "request-dailymart-pending-no-debit",
            executionId: "exec-dailymart-pending-no-debit",
            amount: Decimal(35),
            resultAmount: "35",
            status: .pending,
            presentationState: .submittedNotFinal,
            txHash: nil,
            confirmedAt: nil
        )
        var handler = MeshDelegatedWalletReceiptDecrementHandler()

        let processing = try handler.apply(receipt: receipt, to: initialWallet)

        XCTAssertFalse(processing.eligibility.isEligible)
        XCTAssertEqual(processing.eligibility.reason, .notPaymentExecutionReceipt)
        XCTAssertFalse(processing.didDecrement)
        XCTAssertNil(processing.extractedConfirmedOKRWAmount)
        XCTAssertEqual(processing.wallet.remainingLimit, Decimal(100))
        XCTAssertEqual(processing.wallet.panelSnapshot.remainingLimitLine, "100 OKRW")
        XCTAssertTrue(handler.appliedReceiptIds.isEmpty)
    }

    func testHermesChatFailedMeshReceiptDoesNotDebitEvenWhenResultLooksConfirmed() throws {
        let wallet = try HermesChatDelegatedWalletViewModels
            .marooTestnetOKRWDailyMartGrocerySession()
            .applyingAcceptedPayment(amount: Decimal(35))
        let receipt = try okrwReceipt(
            receiptId: "receipt-dailymart-failed-conflicting-result-no-debit",
            requestId: "request-dailymart-failed-conflicting-result-no-debit",
            executionId: "exec-dailymart-failed-conflicting-result-no-debit",
            amount: Decimal(40),
            resultAmount: "40",
            status: .failed,
            presentationState: .attemptedFailed,
            txHash: nil,
            confirmedAt: nil,
            overridingResultFields: [
                "chainStatus": "confirmed",
                "presentationState": "paid_complete"
            ]
        )
        var handler = MeshDelegatedWalletReceiptDecrementHandler()

        let processing = try handler.apply(receipt: receipt, to: wallet)

        XCTAssertFalse(processing.eligibility.isEligible)
        XCTAssertEqual(processing.eligibility.reason, .notConfirmedReceipt)
        XCTAssertFalse(processing.didDecrement)
        XCTAssertNil(processing.extractedConfirmedOKRWAmount)
        XCTAssertEqual(processing.wallet.remainingLimit, Decimal(65))
        XCTAssertEqual(processing.wallet.panelSnapshot.remainingLimitLine, "65 OKRW")
        XCTAssertTrue(handler.appliedReceiptIds.isEmpty)
    }

    func testHermesChatPolicyDeniedMeshReceiptDoesNotDebitEvenWhenResultLooksConfirmed() throws {
        let wallet = try HermesChatDelegatedWalletViewModels
            .marooTestnetOKRWDailyMartGrocerySession()
            .applyingAcceptedPayment(amount: Decimal(35))
        let receipt = try okrwReceipt(
            receiptId: "receipt-dailymart-policy-denied-conflicting-result-no-debit",
            requestId: "request-dailymart-policy-denied-conflicting-result-no-debit",
            executionId: "exec-dailymart-policy-denied-conflicting-result-no-debit",
            amount: Decimal(40),
            resultAmount: "40",
            proofType: .policyDenial,
            status: .failed,
            presentationState: .policyDenied,
            txHash: nil,
            confirmedAt: nil,
            overridingResultFields: [
                "chainProofType": "payment_execution",
                "chainStatus": "confirmed",
                "presentationState": "paid_complete"
            ]
        )
        var handler = MeshDelegatedWalletReceiptDecrementHandler()

        let processing = try handler.apply(receipt: receipt, to: wallet)

        XCTAssertFalse(processing.eligibility.isEligible)
        XCTAssertEqual(processing.eligibility.reason, .notPaymentExecutionReceipt)
        XCTAssertFalse(processing.didDecrement)
        XCTAssertNil(processing.extractedConfirmedOKRWAmount)
        XCTAssertEqual(processing.wallet.remainingLimit, Decimal(65))
        XCTAssertEqual(processing.wallet.panelSnapshot.remainingLimitLine, "65 OKRW")
        XCTAssertTrue(handler.appliedReceiptIds.isEmpty)
    }

    func testDelegatedWalletReceiptDecrementHandlerDoesNotDebitIneligibleReceipts() throws {
        let initialWallet = try HermesChatDelegatedWalletViewModels.marooTestnetOKRWDailyMartGrocerySession()
        var handler = MeshDelegatedWalletReceiptDecrementHandler()
        let ineligibleReceiptResults: [[String: String]] = [
            [
                "chainProofType": "payment_execution",
                "presentationState": "submitted_not_final",
                "chainStatus": "pending",
                "asset": "OKRW",
                "total_krw": "35"
            ],
            [
                "chainProofType": "payment_execution",
                "presentationState": "attempted_failed",
                "chainStatus": "failed",
                "asset": "OKRW",
                "total_krw": "35"
            ],
            [
                "chainProofType": "policy_denial",
                "presentationState": "policy_denied",
                "chainStatus": "failed",
                "asset": "OKRW",
                "total_krw": "35"
            ]
        ]

        var wallet = initialWallet
        for (index, receiptResult) in ineligibleReceiptResults.enumerated() {
            let result = try handler.apply(
                receiptId: "receipt-dailymart-ineligible-\(index)",
                receiptResult: receiptResult,
                to: wallet
            )
            XCTAssertFalse(result.eligibility.isEligible)
            XCTAssertFalse(result.didDecrement)
            XCTAssertEqual(result.wallet.remainingLimit, Decimal(100))
            wallet = result.wallet
        }

        XCTAssertEqual(wallet.remainingLimit, Decimal(100))
        XCTAssertTrue(handler.appliedReceiptIds.isEmpty)
    }

    func testHermesChatReceiptEligibilityClassifierAcceptsOnlyConfirmedOKRWExecutionReceipts() {
        let cases: [(name: String, result: [String: String], expectedEligible: Bool, expectedReason: MeshHermesChatReceiptEligibilityReason)] = [
            (
                "confirmed OKRW execution",
                [
                    "chainProofType": "payment_execution",
                    "chainStatus": "confirmed",
                    "presentationState": "paid_complete",
                    "asset": "OKRW",
                    "txHash": "0xokrwConfirmedEligibility"
                ],
                true,
                .eligibleOKRWConfirmedExecution
            ),
            (
                "pending OKRW execution",
                [
                    "chainProofType": "payment_execution",
                    "chainStatus": "pending",
                    "presentationState": "submitted_not_final",
                    "asset": "OKRW"
                ],
                false,
                .notConfirmedReceipt
            ),
            (
                "failed OKRW execution",
                [
                    "chainProofType": "payment_execution",
                    "chainStatus": "failed",
                    "presentationState": "attempted_failed",
                    "asset": "OKRW"
                ],
                false,
                .notConfirmedReceipt
            ),
            (
                "policy denied OKRW receipt",
                [
                    "chainProofType": "policy_denial",
                    "chainStatus": "failed",
                    "presentationState": "policy_denied",
                    "asset": "OKRW"
                ],
                false,
                .notPaymentExecutionReceipt
            ),
            (
                "confirmed non OKRW execution",
                [
                    "chainProofType": "payment_execution",
                    "chainStatus": "confirmed",
                    "presentationState": "paid_complete",
                    "asset": "USDC"
                ],
                false,
                .notOKRWReceipt
            ),
            (
                "confirmed OKRW execution without transaction receipt",
                [
                    "chainProofType": "payment_execution",
                    "chainStatus": "confirmed",
                    "presentationState": "paid_complete",
                    "asset": "OKRW"
                ],
                false,
                .missingExecutionReceipt
            ),
            (
                "confirmed OKRW non execution",
                [
                    "chainProofType": "request_anchor",
                    "chainStatus": "confirmed",
                    "presentationState": "paid_complete",
                    "asset": "OKRW"
                ],
                false,
                .notPaymentExecutionReceipt
            )
        ]

        for testCase in cases {
            let eligibility = MeshHermesChatReceiptEligibilityClassifier.classify(receiptResult: testCase.result)
            XCTAssertEqual(eligibility.isEligible, testCase.expectedEligible, testCase.name)
            XCTAssertEqual(eligibility.reason, testCase.expectedReason, testCase.name)
            XCTAssertEqual(
                MeshHermesChatReceiptEligibilityClassifier.isEligible(receiptResult: testCase.result),
                testCase.expectedEligible,
                testCase.name
            )
        }
    }

    func testDelegatedWalletDoesNotDecrementForConfirmedOKRWNonExecutionReceipt() throws {
        let wallet = try HermesChatDelegatedWalletViewModels.marooTestnetOKRWDailyMartGrocerySession()

        let unchanged = try wallet.applyingDailyMartReceiptResult([
            "chainProofType": "request_anchor",
            "chainStatus": "confirmed",
            "presentationState": "paid_complete",
            "asset": "OKRW",
            "total_krw": "35"
        ])

        XCTAssertEqual(unchanged.remainingLimit, Decimal(100))
    }

    func testHermesChatConfirmedOKRWResultDoesNotDebitWhenExecutionReceiptIsMissing() throws {
        let wallet = try HermesChatDelegatedWalletViewModels.marooTestnetOKRWDailyMartGrocerySession()
        var handler = MeshDelegatedWalletReceiptDecrementHandler()
        let missingExecutionReceiptResult = [
            "chainProofType": "payment_execution",
            "chainStatus": "confirmed",
            "presentationState": "paid_complete",
            "asset": "OKRW",
            "total_krw": "35",
            "anchoringReference": "anchor-ios-grocery-confirmed-missing-execution-receipt"
        ]

        let unchanged = try wallet.applyingDailyMartReceiptResult(missingExecutionReceiptResult)
        let processing = try handler.apply(
            receiptId: "receipt-dailymart-confirmed-missing-execution-receipt",
            receiptResult: missingExecutionReceiptResult,
            to: wallet
        )

        XCTAssertEqual(unchanged.remainingLimit, Decimal(100))
        XCTAssertFalse(processing.eligibility.isEligible)
        XCTAssertEqual(processing.eligibility.reason, .missingExecutionReceipt)
        XCTAssertFalse(processing.didDecrement)
        XCTAssertEqual(processing.wallet.remainingLimit, Decimal(100))
        XCTAssertEqual(processing.wallet.panelSnapshot.remainingLimitLine, "100 OKRW")
        XCTAssertTrue(handler.appliedReceiptIds.isEmpty)
    }

    func testFailedReceiptProcessingLeavesRemainingLimitUnchangedEvenWithConflictingConfirmedStatus() throws {
        let wallet = try HermesChatDelegatedWalletViewModels
            .marooTestnetOKRWDailyMartGrocerySession()
            .applyingAcceptedPayment(amount: Decimal(35))

        let unchanged = try wallet.applyingDailyMartReceiptResult([
            "chainProofType": "payment_execution",
            "chainStatus": "confirmed",
            "presentationState": "attempted_failed",
            "asset": "OKRW",
            "total_krw": "40",
            "errorCode": "rpc_unavailable",
            "errorMessage": "maroo RPC did not return a transaction receipt"
        ])

        XCTAssertEqual(wallet.remainingLimit, Decimal(65))
        XCTAssertEqual(unchanged.remainingLimit, Decimal(65))
        XCTAssertEqual(unchanged.panelSnapshot.remainingLimitLine, "65 OKRW")
    }

    func testFailedReceiptDisplayStateKeepsRenderedRemainingLimitUnchangedAfterProcessing() throws {
        let wallet = try HermesChatDelegatedWalletViewModels
            .marooTestnetOKRWDailyMartGrocerySession()
            .applyingAcceptedPayment(amount: Decimal(35))
        let beforeFailurePanel = wallet.panelSnapshot

        let displayState = try wallet.dailyMartReceiptDisplayState(
            afterProcessing: [
                "chainProofType": "payment_execution",
                "chainStatus": "failed",
                "presentationState": "attempted_failed",
                "asset": "OKRW",
                "total_krw": "40",
                "errorCode": "rpc_unavailable",
                "errorMessage": "maroo RPC did not return a transaction receipt"
            ],
            fallbackAuditId: "anchor-ios-grocery-failed"
        )

        XCTAssertEqual(displayState.paymentPresentation.kind, .attemptedFailed)
        XCTAssertTrue(displayState.paymentPresentation.isPaymentAttempted)
        XCTAssertFalse(displayState.paymentPresentation.isPaid)
        XCTAssertFalse(displayState.paymentPresentation.isComplete)
        XCTAssertFalse(displayState.paymentPresentation.isPaidComplete)
        XCTAssertTrue(displayState.remainingLimitUnchanged)
        XCTAssertEqual(displayState.processedWallet.remainingLimit, Decimal(65))
        XCTAssertEqual(displayState.processedPanelSnapshot.remainingLimitLine, beforeFailurePanel.remainingLimitLine)
        XCTAssertEqual(displayState.processedPanelSnapshot.remainingSessionLimitSummaryLine, beforeFailurePanel.remainingSessionLimitSummaryLine)
        XCTAssertEqual(displayState.remainingLimitLineAfterProcessing, "65 OKRW")
        XCTAssertEqual(displayState.remainingLimitUnchangedLine, "Remaining session limit unchanged: 65 OKRW")
        XCTAssertTrue(displayState.renderedLines.contains("Payment state: attempted · unpaid · incomplete"))
        XCTAssertTrue(displayState.renderedLines.contains("errorCode: rpc_unavailable"))
        XCTAssertTrue(displayState.renderedLines.contains("errorMessage: maroo RPC did not return a transaction receipt"))
        XCTAssertTrue(displayState.processedPanelSnapshot.accessibilityLabel.contains("remaining session limit 65 OKRW"))
    }

    func testPolicyDeniedReceiptDisplayStatePreservesRemainingDelegatedSpendingLimitValue() throws {
        let wallet = try HermesChatDelegatedWalletViewModels
            .marooTestnetOKRWDailyMartGrocerySession()
            .applyingAcceptedPayment(amount: Decimal(35))
        let beforeDeniedPanel = wallet.panelSnapshot

        let displayState = try wallet.dailyMartReceiptDisplayState(
            afterProcessing: [
                "chainProofType": "policy_denial",
                "presentationState": "policy_denied",
                "chainStatus": "failed",
                "asset": "OKRW",
                "total_krw": "40",
                "errorCode": "wallet_policy_denied",
                "errorMessage": "DailyMart policy blocked this delegated spend"
            ],
            fallbackAuditId: "anchor-ios-grocery-policy-denied"
        )

        XCTAssertEqual(displayState.paymentPresentation.kind, .policyDenied)
        XCTAssertFalse(displayState.paymentPresentation.isPaidComplete)
        XCTAssertTrue(displayState.remainingLimitUnchanged)
        XCTAssertEqual(displayState.originalWallet.remainingLimit, Decimal(65))
        XCTAssertEqual(displayState.processedWallet.remainingLimit, Decimal(65))
        XCTAssertEqual(displayState.processedPanelSnapshot.remainingLimitLine, beforeDeniedPanel.remainingLimitLine)
        XCTAssertEqual(displayState.processedPanelSnapshot.remainingSessionLimitSummaryLine, beforeDeniedPanel.remainingSessionLimitSummaryLine)
        XCTAssertEqual(displayState.remainingLimitLineAfterProcessing, "65 OKRW")
        XCTAssertEqual(displayState.remainingLimitUnchangedLine, "Remaining session limit unchanged: 65 OKRW")
        XCTAssertTrue(displayState.renderedLines.contains("DailyMart returned a target-signed policy-denied receipt"))
        XCTAssertTrue(displayState.renderedLines.contains("wallet_policy_denied · DailyMart policy blocked this delegated spend"))
        XCTAssertTrue(displayState.renderedLines.contains("Remaining session limit unchanged: 65 OKRW"))
    }

    func testConfirmedReceiptDisplayStateRendersUpdatedRemainingDelegatedSpendingLimit() throws {
        let wallet = try HermesChatDelegatedWalletViewModels
            .marooTestnetOKRWDailyMartGrocerySession()

        let displayState = try wallet.dailyMartReceiptDisplayState(
            afterProcessing: [
                "chainProofType": "payment_execution",
                "presentationState": "paid_complete",
                "chainStatus": "confirmed",
                "asset": "OKRW",
                "total_krw": "35",
                "txHash": "0xokrwConfirmedDailyMartReceipt",
                "explorerUrl": "https://explorer-testnet.maroo.io/tx/0xokrwConfirmedDailyMartReceipt"
            ],
            fallbackAuditId: "anchor-ios-grocery-confirmed"
        )

        XCTAssertEqual(displayState.paymentPresentation.kind, .paidComplete)
        XCTAssertTrue(displayState.paymentPresentation.isPaidComplete)
        XCTAssertFalse(displayState.remainingLimitUnchanged)
        XCTAssertEqual(displayState.processedWallet.remainingLimit, Decimal(65))
        XCTAssertEqual(displayState.remainingLimitLineAfterProcessing, "65 OKRW")
        XCTAssertEqual(displayState.remainingLimitAfterProcessingLine, "Remaining session limit: 65 OKRW")
        XCTAssertTrue(displayState.renderedLines.contains("DailyMart background checkout complete"))
        XCTAssertTrue(displayState.renderedLines.contains("Remaining session limit: 65 OKRW"))
        XCTAssertFalse(displayState.renderedLines.contains("Remaining session limit unchanged: 65 OKRW"))
    }

    func testPendingReceiptPresentationRendersBlockedByExternalChainEvidenceBesideSubmittedState() {
        let presentation = MeshDailyMartReceiptPaymentPresentation(receiptResult: [
            "presentationState": "submitted_not_final",
            "chainStatus": "pending",
            "anchoringReference": "anchor-ios-grocery-pending",
            "submittedAt": "2026-05-31T12:00:00Z",
            "externalChainExitCondition": "BlockedByExternalChain",
            "externalChainBlockerType": "payment_confirmation_unavailable",
            "externalChainOperation": "executeOKRWTransfer",
            "externalChainEndpoint": "https://rpc-testnet.maroo.io",
            "externalChainObservedAt": "2026-05-31T12:00:00Z",
            "externalChainMessage": "maroo live OKRW confirmation is unavailable for this demo run"
        ])

        XCTAssertEqual(presentation.kind, .submittedNotFinal)
        XCTAssertFalse(presentation.isPaidComplete)
        XCTAssertEqual(presentation.title, "DailyMart returned a target-signed pending receipt")
        XCTAssertTrue(presentation.body.contains("Submitted, not final"))
        XCTAssertTrue(presentation.body.contains("anchor-ios-grocery-pending"))
        XCTAssertEqual(presentation.pendingSubmittedAtLine, "submittedAt=2026-05-31T12:00:00Z")
        XCTAssertEqual(presentation.pendingAnchoringReferenceLine, "anchoringReference=anchor-ios-grocery-pending")
        XCTAssertTrue(presentation.auditLine.contains("grocery.purchase_essentials.submitted_not_final"))
        XCTAssertTrue(presentation.auditLine.contains("BlockedByExternalChain"))
        XCTAssertTrue(presentation.auditLine.contains("payment_confirmation_unavailable"))
        XCTAssertTrue(presentation.auditLine.contains("executeOKRWTransfer"))
        XCTAssertTrue(presentation.auditLine.contains("no txHash accepted as confirmed fallback"))
        XCTAssertEqual(presentation.externalChainEvidence?.detailLine, "https://rpc-testnet.maroo.io · 2026-05-31T12:00:00Z · maroo live OKRW confirmation is unavailable for this demo run")
        XCTAssertTrue(presentation.renderedLines.contains("submittedAt=2026-05-31T12:00:00Z"))
        XCTAssertTrue(presentation.renderedLines.contains("anchoringReference=anchor-ios-grocery-pending"))
        XCTAssertTrue(presentation.renderedLines.contains("https://rpc-testnet.maroo.io · 2026-05-31T12:00:00Z · maroo live OKRW confirmation is unavailable for this demo run"))
    }

    func testPendingReceiptDisplayStateRendersSubmittedNonFinalWithoutDebitingDelegatedLimit() throws {
        let wallet = try HermesChatDelegatedWalletViewModels
            .marooTestnetOKRWDailyMartGrocerySession()

        let displayState = try wallet.dailyMartReceiptDisplayState(
            afterProcessing: [
                "chainProofType": "payment_execution",
                "presentationState": "submitted_not_final",
                "chainStatus": "pending",
                "asset": "OKRW",
                "total_krw": "35",
                "anchoringReference": "anchor-ios-grocery-pending-render",
                "submittedAt": "2026-05-31T12:00:03Z",
                "externalChainExitCondition": "BlockedByExternalChain",
                "externalChainBlockerType": "payment_confirmation_unavailable",
                "externalChainOperation": "executeOKRWTransfer",
                "externalChainEndpoint": "https://rpc-testnet.maroo.io",
                "externalChainObservedAt": "2026-05-31T12:00:00Z",
                "externalChainMessage": "maroo live OKRW confirmation is unavailable for this demo run"
            ],
            fallbackAuditId: "anchor-ios-grocery-fallback"
        )

        XCTAssertEqual(displayState.paymentPresentation.kind, .submittedNotFinal)
        XCTAssertFalse(displayState.paymentPresentation.isPaidComplete)
        XCTAssertTrue(displayState.remainingLimitUnchanged)
        XCTAssertEqual(displayState.processedWallet.remainingLimit, Decimal(100))
        XCTAssertEqual(displayState.remainingLimitUnchangedLine, "Remaining session limit unchanged: 100 OKRW")
        XCTAssertTrue(displayState.renderedLines.contains("DailyMart returned a target-signed pending receipt"))
        XCTAssertTrue(displayState.renderedLines.contains("Submitted, not final · anchoring reference anchor-ios-grocery-pending-render · no paid order until maroo confirms"))
        XCTAssertTrue(displayState.renderedLines.contains("submittedAt=2026-05-31T12:00:03Z"))
        XCTAssertTrue(displayState.renderedLines.contains("anchoringReference=anchor-ios-grocery-pending-render"))
        XCTAssertTrue(displayState.renderedLines.contains("Remaining session limit unchanged: 100 OKRW"))
        XCTAssertTrue(displayState.renderedLines.joined(separator: "\n").contains("grocery.purchase_essentials.submitted_not_final"))
        XCTAssertTrue(displayState.renderedLines.joined(separator: "\n").contains("BlockedByExternalChain · payment_confirmation_unavailable · executeOKRWTransfer"))
    }

    func testHermesChatOrderStateRecorderDoesNotPersistPaidOrCompleteWhenReceiptIsPending() {
        let pendingReceiptResult = [
            "chainProofType": "payment_execution",
            "presentationState": "submitted_not_final",
            "chainStatus": "pending",
            "status": "complete",
            "asset": "OKRW",
            "total_krw": "35",
            "txHash": "0xnotConfirmedYet",
            "anchoringReference": "anchor-ios-grocery-pending-order-state",
            "submittedAt": "2026-05-31T12:00:09Z"
        ]

        let completeCallbackRecord = MeshHermesChatDailyMartOrderStateRecorder.record(
            receiptResult: pendingReceiptResult,
            callbackStatus: "complete"
        )
        let purchasedCallbackRecord = MeshHermesChatDailyMartOrderStateRecorder.record(
            receiptResult: pendingReceiptResult,
            callbackStatus: "purchased"
        )

        XCTAssertEqual(completeCallbackRecord.kind, .submittedNotFinal)
        XCTAssertEqual(completeCallbackRecord.lastAction, "DailyMart OKRW execution submitted")
        XCTAssertFalse(completeCallbackRecord.persistsPaidStatus)
        XCTAssertFalse(completeCallbackRecord.persistsCompleteStatus)
        XCTAssertEqual(purchasedCallbackRecord.kind, .submittedNotFinal)
        XCTAssertFalse(purchasedCallbackRecord.persistsPaidStatus)
        XCTAssertFalse(purchasedCallbackRecord.persistsCompleteStatus)
    }

    func testHermesChatOrderStateRecorderPersistsPaidCompleteOnlyForConfirmedEligibleReceipt() {
        let record = MeshHermesChatDailyMartOrderStateRecorder.record(
            receiptResult: [
                "chainProofType": "payment_execution",
                "presentationState": "paid_complete",
                "chainStatus": "confirmed",
                "status": "confirmed",
                "asset": "OKRW",
                "total_krw": "35",
                "txHash": "0xokrwConfirmedOrderState"
            ],
            callbackStatus: "complete"
        )

        XCTAssertEqual(record.kind, .paidComplete)
        XCTAssertEqual(record.lastAction, "DailyMart order confirmed")
        XCTAssertTrue(record.persistsPaidStatus)
        XCTAssertTrue(record.persistsCompleteStatus)
    }

    func testPendingReceiptRenderingComponentDisplaysSubmittedAtAndAnchoringReference() throws {
        let wallet = try HermesChatDelegatedWalletViewModels
            .marooTestnetOKRWDailyMartGrocerySession()

        let displayState = try wallet.dailyMartReceiptDisplayState(
            afterProcessing: [
                "chainProofType": "payment_execution",
                "presentationState": "submitted_not_final",
                "chainStatus": "pending",
                "asset": "OKRW",
                "total_krw": "35",
                "submittedAt": "2026-05-31T12:00:07Z",
                "anchoringReference": "maroo-anchor-hermes-pending-render-test"
            ]
        )

        let renderedComponentText = displayState.renderedLines.joined(separator: "\n")

        XCTAssertEqual(displayState.paymentPresentation.kind, .submittedNotFinal)
        XCTAssertFalse(displayState.paymentPresentation.isPaid)
        XCTAssertFalse(displayState.paymentPresentation.isComplete)
        XCTAssertEqual(displayState.paymentPresentation.pendingSubmittedAtLine, "submittedAt=2026-05-31T12:00:07Z")
        XCTAssertEqual(displayState.paymentPresentation.pendingAnchoringReferenceLine, "anchoringReference=maroo-anchor-hermes-pending-render-test")
        XCTAssertTrue(renderedComponentText.contains("submittedAt=2026-05-31T12:00:07Z"))
        XCTAssertTrue(renderedComponentText.contains("anchoringReference=maroo-anchor-hermes-pending-render-test"))
        XCTAssertTrue(renderedComponentText.contains("Remaining session limit unchanged: 100 OKRW"))
    }

    func testFailedReceiptPresentationRendersBlockedByExternalChainEvidenceBesideAttemptedFailedState() {
        let presentation = MeshDailyMartReceiptPaymentPresentation(receiptResult: [
            "presentationState": "attempted_failed",
            "chainStatus": "failed",
            "errorCode": "rpc_unavailable",
            "errorMessage": "maroo RPC did not return a transaction receipt",
            "externalChainExitCondition": "BlockedByExternalChain",
            "externalChainBlockerType": "rpc_unavailable",
            "externalChainOperation": "eth_getTransactionReceipt",
            "externalChainEndpoint": "https://rpc-testnet.maroo.io",
            "externalChainObservedAt": "2026-05-31T12:00:01Z",
            "externalChainMessage": "RPC timed out"
        ])

        XCTAssertEqual(presentation.kind, .attemptedFailed)
        XCTAssertTrue(presentation.isPaymentAttempted)
        XCTAssertFalse(presentation.isPaid)
        XCTAssertFalse(presentation.isComplete)
        XCTAssertFalse(presentation.isPaidComplete)
        XCTAssertEqual(presentation.title, "DailyMart returned a target-signed failed receipt")
        XCTAssertTrue(presentation.body.contains("Attempted, not paid"))
        XCTAssertTrue(presentation.body.contains("rpc_unavailable"))
        XCTAssertEqual(presentation.paymentStateLine, "Payment state: attempted · unpaid · incomplete")
        XCTAssertTrue(presentation.renderedLines.contains("Payment state: attempted · unpaid · incomplete"))
        XCTAssertEqual(presentation.errorCodeLine, "errorCode: rpc_unavailable")
        XCTAssertEqual(presentation.errorMessageLine, "errorMessage: maroo RPC did not return a transaction receipt")
        XCTAssertTrue(presentation.renderedLines.contains("errorCode: rpc_unavailable"))
        XCTAssertTrue(presentation.renderedLines.contains("errorMessage: maroo RPC did not return a transaction receipt"))
        XCTAssertTrue(presentation.auditLine.contains("grocery.purchase_essentials.attempted_failed"))
        XCTAssertTrue(presentation.auditLine.contains("BlockedByExternalChain"))
        XCTAssertTrue(presentation.auditLine.contains("rpc_unavailable"))
        XCTAssertTrue(presentation.auditLine.contains("eth_getTransactionReceipt"))
        XCTAssertTrue(presentation.auditLine.contains("no txHash accepted as confirmed fallback"))
        XCTAssertEqual(presentation.externalChainEvidence?.summaryLine, "BlockedByExternalChain · rpc_unavailable · eth_getTransactionReceipt")
    }

    func testConfirmedReceiptPresentationRendersPaidCompleteForPaymentExecutionProofStatuses() {
        let scenarios: [[String: String]] = [
            [
                "chainProofType": "payment_execution",
                "presentationState": "paid_complete",
                "chainStatus": "confirmed",
                "status": "confirmed",
                "asset": "OKRW",
                "order_id": "DM-2026-0531-render-paid-complete",
                "total_krw": "35"
            ],
            [
                "chainProofType": "payment_execution",
                "chainStatus": "confirmed",
                "status": "confirmed",
                "asset": "OKRW",
                "order_id": "DM-2026-0531-render-confirmed-chain",
                "total_krw": "40"
            ],
            [
                "status": "purchased",
                "order_id": "DM-2026-0531-render-legacy-purchased",
                "total_krw": "45"
            ],
            [
                "status": "complete",
                "order_id": "DM-2026-0531-render-legacy-complete",
                "total_krw": "50"
            ]
        ]

        for receiptResult in scenarios {
            let presentation = MeshDailyMartReceiptPaymentPresentation(receiptResult: receiptResult)

            XCTAssertEqual(presentation.kind, .paidComplete)
            XCTAssertTrue(presentation.isPaidComplete)
            XCTAssertEqual(presentation.title, "DailyMart background checkout complete")
            XCTAssertTrue(presentation.body.contains(receiptResult["order_id"] ?? ""))
            XCTAssertTrue(presentation.auditLine.contains("grocery.purchase_essentials.paid_complete"))
            XCTAssertTrue(presentation.renderedLines.contains(presentation.title))
            XCTAssertTrue(presentation.renderedLines.contains(presentation.body))
            XCTAssertTrue(presentation.renderedLines.contains(presentation.auditLine))
        }
    }

    func testConfirmedReceiptPresentationRendersTxHashInRunnableRenderLines() {
        let presentation = MeshDailyMartReceiptPaymentPresentation(receiptResult: [
            "chainProofType": "payment_execution",
            "presentationState": "paid_complete",
            "chainStatus": "confirmed",
            "status": "confirmed",
            "asset": "OKRW",
            "order_id": "DM-2026-0531-render-confirmed-txhash",
            "total_krw": "55",
            "txHash": "0xokrwHermesRenderConfirmedTxHash"
        ])

        XCTAssertEqual(presentation.kind, .paidComplete)
        XCTAssertTrue(presentation.isPaidComplete)
        XCTAssertTrue(presentation.body.contains("txHash=0xokrwHermesRenderConfirmedTxHash"))
        XCTAssertTrue(presentation.auditLine.contains("txHash=0xokrwHermesRenderConfirmedTxHash"))
        XCTAssertTrue(presentation.renderedLines.joined(separator: "\n").contains("txHash=0xokrwHermesRenderConfirmedTxHash"))
    }

    func testConfirmedReceiptPresentationRendersRunnableExplorerLink() throws {
        let txHash = "0x" + String(repeating: "a", count: 64)
        let explorerUrl = "https://explorer-testnet.maroo.io/tx/\(txHash)"
        let presentation = MeshDailyMartReceiptPaymentPresentation(receiptResult: [
            "chainProofType": "payment_execution",
            "presentationState": "paid_complete",
            "chainStatus": "confirmed",
            "status": "confirmed",
            "asset": "OKRW",
            "order_id": "DM-2026-0531-render-confirmed-explorer-link",
            "total_krw": "55",
            "txHash": txHash,
            "explorerUrl": explorerUrl
        ])

        let renderedURL = try XCTUnwrap(presentation.explorerURL)
        XCTAssertEqual(renderedURL.scheme, "https")
        XCTAssertEqual(renderedURL.host, "explorer-testnet.maroo.io")
        XCTAssertEqual(renderedURL.path, "/tx/\(txHash)")
        XCTAssertEqual(renderedURL.absoluteString, explorerUrl)
        XCTAssertEqual(presentation.explorerLinkTitle, "Open maroo explorer: \(explorerUrl)")
        XCTAssertTrue(presentation.body.contains("explorerUrl=\(explorerUrl)"))
        XCTAssertTrue(presentation.auditLine.contains("explorerUrl=\(explorerUrl)"))
        XCTAssertTrue(presentation.renderedLines.contains("Open maroo explorer: \(explorerUrl)"))

        let runnableLink = try XCTUnwrap(URL(string: renderedURL.absoluteString))
        XCTAssertEqual(runnableLink.absoluteString, explorerUrl)
    }

    func testReceiptPresentationDoesNotRenderExplorerLinkForUnconfirmedReceipt() {
        let presentation = MeshDailyMartReceiptPaymentPresentation(receiptResult: [
            "chainProofType": "payment_execution",
            "presentationState": "submitted_not_final",
            "chainStatus": "pending",
            "status": "pending",
            "asset": "OKRW",
            "explorerUrl": "https://explorer-testnet.maroo.io/tx/0xnotconfirmed"
        ])

        XCTAssertNil(presentation.explorerURL)
        XCTAssertNil(presentation.explorerLinkTitle)
    }

    func testDelegatedWalletRejectsAcceptedPaymentReceiptThatExceedsRemainingSessionLimit() throws {
        let wallet = try HermesChatDelegatedWalletViewModels
            .marooTestnetOKRWDailyMartGrocerySession()
            .applyingAcceptedPayment(amount: Decimal(80))

        XCTAssertThrowsError(try wallet.applyingDailyMartReceiptResult([
            "chainProofType": "payment_execution",
            "presentationState": "paid_complete",
            "chainStatus": "confirmed",
            "asset": "OKRW",
            "total_krw": "30",
            "txHash": "0xokrwConfirmedExceedsRemaining"
        ])) { error in
            XCTAssertEqual(error as? MeshKitValidationError, .invalidAgentWalletIdentity("remainingLimit"))
        }
        XCTAssertEqual(wallet.remainingLimit, Decimal(20))
    }

    func testDelegatedWalletPanelComponentRendersAllowedDailyMartScopeFromProvidedPresentationData() throws {
        let snapshot = try HermesChatDelegatedWalletViewModels
            .marooTestnetOKRWDailyMartGrocerySession()
            .panelSnapshot

        let component = MeshDelegatedWalletPanelComponent(snapshot: snapshot)

        XCTAssertEqual(component.headerLabel, "AgentOS/OCG delegated wallet")
        XCTAssertEqual(component.rows, snapshot.rows)
        XCTAssertTrue(component.rendersAllowedDailyMartEssentialsScope)
        XCTAssertTrue(component.renderedLines.contains("Authorization: OKRW · DailyMart grocery.purchase_essentials"))
        XCTAssertTrue(component.renderedLines.contains("Scope: DailyMart grocery.purchase_essentials"))
        XCTAssertTrue(component.renderedLines.contains("Scope status: Allowed by saved grant"))
        XCTAssertTrue(component.accessibilityLabel.contains("raw scope merchant.dailymart · grocery.purchase_essentials"))
    }

    func testHermesChatDailyMartCallableActionUsesSameScopeAsDelegatedWalletPanel() throws {
        let wallet = try HermesChatDelegatedWalletViewModels.marooTestnetOKRWDailyMartGrocerySession()
        let snapshot = wallet.panelSnapshot
        let action = wallet.callableAppPresentation(appName: "DailyMart")

        XCTAssertEqual(action.subtitle, "maroo testnet OKRW · 100 OKRW limit · grocery.purchase_essentials")
        XCTAssertEqual(action.capabilityScope, DailyMartDelegatedSpendingPolicy.capabilityScope)
        XCTAssertEqual(action.scopePresentation.status, .allowed)
        XCTAssertEqual(action.scopePresentation.label, "DailyMart grocery.purchase_essentials")
        XCTAssertTrue(action.matchesPanelScope(snapshot))
        XCTAssertTrue(action.accessibilityScopeLabel.contains("DailyMart grocery.purchase_essentials"))
        XCTAssertTrue(action.accessibilityScopeLabel.contains("grocery.purchase_essentials"))
    }

    func testCallableActionPresentationRemainsProviderNeutralWhileCarryingWalletScope() throws {
        let policy = try MeshAgentWalletDelegatedSpendingPolicy(
            policyId: "policy-mock-okrw-v2",
            policyHash: MeshPayloadHash(value: String(repeating: "b", count: 64)),
            consentGrantId: "grant-mock-002",
            merchantScope: "merchant.mockmart",
            capabilityScope: "grocery.purchase_essentials",
            singlePaymentMax: Decimal(25),
            sessionTotalLimit: Decimal(60),
            remainingLimit: Decimal(40),
            expiresAt: "2026-12-31T23:59:59Z",
            asset: "OKRW",
            recipientAddress: "mock1merchant"
        )
        let wallet = try HermesChatDelegatedWalletViewModels.viewModel(
            providerMetadata: MeshAgentWalletProviderMetadata(
                provider: "mockchain",
                network: "mock-testnet",
                chainId: "mockchain-testnet-1"
            ),
            walletAddress: "mock1agentwallet",
            policy: policy,
            targetBundleId: "ai.meshkit.sample.dailymart"
        )

        let action = wallet.callableAppPresentation(appName: "MockMart")

        XCTAssertEqual(action.subtitle, "mockchain OKRW · 40 OKRW limit · grocery.purchase_essentials")
        XCTAssertEqual(action.capabilityScope, "grocery.purchase_essentials")
        XCTAssertEqual(action.scopePresentation.status, .unavailable)
        XCTAssertEqual(action.scopePresentation.label, "grocery.purchase_essentials")
        XCTAssertTrue(action.matchesPanelScope(wallet.panelSnapshot))
    }

    func testDelegatedWalletScopePresentationMapsDailyMartAllowedScopeToLabelAndStatus() {
        let presentation = MeshDelegatedWalletScopePresentation(
            merchantScope: "merchant.dailymart",
            capabilityScope: "grocery.purchase_essentials",
            consentGrantId: "grant-hermes-dailymart-001"
        )

        XCTAssertEqual(presentation.label, "DailyMart grocery.purchase_essentials")
        XCTAssertEqual(presentation.status, .allowed)
        XCTAssertEqual(presentation.statusLabel, "Allowed by saved grant")
        XCTAssertEqual(presentation.rawScopeLine, "merchant.dailymart · grocery.purchase_essentials")
    }

    func testDelegatedWalletScopePresentationMarksUnmatchedScopeUnavailable() {
        let presentation = MeshDelegatedWalletScopePresentation(
            merchantScope: "merchant.dailymart",
            capabilityScope: "grocery.refund_order",
            consentGrantId: "grant-hermes-dailymart-001"
        )

        XCTAssertEqual(presentation.label, "grocery.refund_order")
        XCTAssertEqual(presentation.status, .unavailable)
        XCTAssertEqual(presentation.statusLabel, "Not allowed by saved grant")
        XCTAssertEqual(presentation.rawScopeLine, "merchant.dailymart · grocery.refund_order")
    }

    func testDelegatedWalletPolicyFormatterMapsPolicyLimitsAndAssetFields() throws {
        let policy = try MeshAgentWalletDelegatedSpendingPolicy(
            policyId: "policy-formatter-okrw-v1",
            policyHash: MeshPayloadHash(value: String(repeating: "c", count: 64)),
            consentGrantId: "grant-formatter-001",
            merchantScope: "merchant.formattermart",
            capabilityScope: "grocery.purchase_essentials",
            singlePaymentMax: Decimal(35),
            sessionTotalLimit: Decimal(120),
            remainingLimit: Decimal(85),
            expiresAt: "2026-12-31T23:59:59Z",
            asset: "okrw",
            recipientAddress: "formatter1merchant"
        )

        let formatter = try MeshDelegatedWalletPolicyFormatter(policy: policy)

        XCTAssertEqual(formatter.totalSessionLimit, "120 OKRW")
        XCTAssertEqual(formatter.remainingLimit, "85 OKRW")
        XCTAssertEqual(formatter.perPaymentMax, "35 OKRW")
        XCTAssertEqual(formatter.asset, "OKRW")
    }

    func testDelegatedWalletViewModelAcceptsProviderNeutralMetadata() throws {
        let policy = try MeshAgentWalletDelegatedSpendingPolicy(
            policyId: "policy-mock-okrw-v1",
            policyHash: MeshPayloadHash(value: String(repeating: "a", count: 64)),
            consentGrantId: "grant-mock-001",
            merchantScope: "merchant.mockmart",
            capabilityScope: "grocery.purchase_essentials",
            singlePaymentMax: Decimal(50),
            sessionTotalLimit: Decimal(75),
            remainingLimit: Decimal(25),
            expiresAt: "2026-12-31T23:59:59Z",
            asset: "OKRW",
            recipientAddress: "mock1merchant"
        )

        let viewModel = try HermesChatDelegatedWalletViewModels.viewModel(
            providerMetadata: MeshAgentWalletProviderMetadata(
                provider: "mockchain",
                network: "local-testnet",
                chainId: "mockchain-local-1"
            ),
            walletAddress: "mock1agentwallet",
            policy: policy,
            targetBundleId: "ai.meshkit.sample.dailymart"
        )

        XCTAssertEqual(viewModel.provider, "mockchain")
        XCTAssertEqual(viewModel.network, "local-testnet")
        XCTAssertEqual(viewModel.chainId, "mockchain-local-1")
        XCTAssertEqual(viewModel.asset, "OKRW")
        XCTAssertEqual(viewModel.singlePaymentMax, Decimal(50))
        XCTAssertEqual(viewModel.sessionTotalLimit, Decimal(75))
        XCTAssertEqual(viewModel.remainingLimit, Decimal(25))
        XCTAssertEqual(viewModel.merchantScope, "merchant.mockmart")
        XCTAssertEqual(viewModel.capabilityScope, "grocery.purchase_essentials")
    }

    func testDelegatedWalletViewModelRejectsInvalidLimitShape() throws {
        XCTAssertThrowsError(try MeshDelegatedWalletViewModel(
            providerMetadata: MeshAgentWalletProviderMetadata(
                provider: "mockchain",
                network: "local-testnet",
                chainId: "mockchain-local-1"
            ),
            policy: MeshAgentWalletDelegatedSpendingPolicy(
                policyId: "policy-mock-okrw-v1",
                policyHash: MeshPayloadHash(value: String(repeating: "a", count: 64)),
                consentGrantId: "grant-mock-001",
                merchantScope: "merchant.mockmart",
                capabilityScope: "grocery.purchase_essentials",
                singlePaymentMax: Decimal(80),
                sessionTotalLimit: Decimal(75),
                remainingLimit: Decimal(25),
                expiresAt: "2026-12-31T23:59:59Z",
                asset: "OKRW"
            ),
            targetBundleId: "ai.meshkit.sample.dailymart"
        )) { error in
            XCTAssertEqual(error as? MeshKitValidationError, .invalidAgentWalletIdentity("singlePaymentMax"))
        }
    }

    private func confirmedOKRWReceipt(
        receiptId: String,
        requestId: String,
        executionId: String,
        amount: Decimal,
        conflictingResultAmount: String
    ) throws -> MeshReceipt {
        try okrwReceipt(
            receiptId: receiptId,
            requestId: requestId,
            executionId: executionId,
            amount: amount,
            resultAmount: conflictingResultAmount,
            status: .confirmed,
            presentationState: .paidComplete,
            txHash: "0x" + String(repeating: "a", count: 64),
            confirmedAt: "2026-05-31T12:06:30Z"
        )
    }

    private func okrwReceipt(
        receiptId: String,
        requestId: String,
        executionId: String,
        amount: Decimal,
        resultAmount: String,
        proofType: MeshChainProofType? = nil,
        status: MeshChainProofStatus,
        presentationState: MeshChainProofPresentationState,
        txHash: String?,
        confirmedAt: String?,
        asset: String = "OKRW",
        overridingResultFields: [String: String] = [:]
    ) throws -> MeshReceipt {
        let proof = try MeshChainProof(
            provider: "maroo",
            chainId: "maroo-testnet-1",
            network: "maroo-testnet",
            proofType: proofType ?? (status == .pending ? .requestAnchor : .paymentExecution),
            status: status,
            presentationState: presentationState,
            requestHash: MeshPayloadHash(value: String(repeating: "b", count: 64)),
            requestNonce: "nonce-\(executionId)",
            policyId: DailyMartDelegatedSpendingPolicy.policyId,
            policyHash: DailyMartDelegatedSpendingPolicy.policyHash,
            walletAddress: "maroo1dailyMartAgentWallet",
            amount: amount,
            asset: asset,
            recipient: "0x000000000000000000000000000000000000d417",
            anchoringReference: "maroo-anchor-\(executionId)",
            executionAttemptId: "attempt-\(executionId)",
            paymentId: "pay-\(executionId)",
            authorizationId: "auth-\(executionId)",
            executionId: executionId,
            executionKind: .payment,
            anchorTxHash: "0x" + String(repeating: "b", count: 64),
            txHash: txHash,
            explorerUrl: txHash.map { URL(string: "https://explorer-testnet.maroo.io/tx/\($0)")! },
            errorCode: status == .failed ? "payment_execution_failed" : nil,
            errorMessage: status == .failed ? "DailyMart could not complete the OKRW execution" : nil,
            submittedAt: "2026-05-31T12:06:00Z",
            confirmedAt: confirmedAt
        )
        let ownedResult = try MeshReceiptOwnershipMapper.targetOwnedResultFields(
            baseResult: [
                "merchant": "DailyMart",
                "total_krw": resultAmount
            ],
            targetAppId: "app.dailymart",
            targetBundleId: HermesChatDelegatedWalletViewModels.dailyMartTargetBundleId
        )
        let result = try MeshReceiptChainProofSerializer.receiptResultFields(
            baseResult: ownedResult,
            proof: proof
        ).merging(overridingResultFields) { _, new in new }
        return MeshReceipt(
            receiptId: receiptId,
            requestId: requestId,
            capabilityId: DailyMartDelegatedSpendingPolicy.capabilityScope,
            targetAppId: "app.dailymart",
            targetBundleId: HermesChatDelegatedWalletViewModels.dailyMartTargetBundleId,
            requestPayloadHash: MeshPayloadHash(value: String(repeating: "c", count: 64)),
            status: proof.presentationState.rawValue,
            result: result,
            nonce: "receipt-nonce-\(executionId)",
            timestamp: "2026-05-31T12:10:00Z",
            signature: MeshSignature(
                algorithm: "Ed25519",
                keyId: "dailymart-receipt-key",
                value: "receipt-signature"
            )
        )
    }
}
