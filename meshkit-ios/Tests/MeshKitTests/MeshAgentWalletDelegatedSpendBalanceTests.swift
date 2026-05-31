import XCTest
@testable import MeshKit

final class MeshAgentWalletDelegatedSpendBalanceTests: XCTestCase {
    func testAgentWalletCreatesPendingDelegatedSpendReservationWithoutSettlingSpend() throws {
        let policy = try delegatedSpendingPolicy(
            sessionTotalLimit: Decimal(1_000),
            remainingLimit: Decimal(800)
        )
        let request = try executionRequest(
            executionId: "exec-pending-delegated-spend-reservation",
            amount: Decimal(125)
        )
        let accounting = try MeshAgentWalletDelegatedSpendAccounting(policy: policy)
        let wallet = try BalanceReportingAgentWallet(
            limit: delegatedSpendingLimit(for: policy),
            capabilities: [.accountForPendingSpendReservation]
        )

        let reservation = try wallet.reservePendingDelegatedSpend(
            request,
            policy: policy,
            accounting: accounting,
            reservedAt: "2026-05-31T12:00:30Z"
        )

        XCTAssertEqual(reservation.walletIdentity, wallet.identity)
        XCTAssertEqual(reservation.reservedAmount, Decimal(125))
        XCTAssertEqual(reservation.balanceBeforeReservation.priorSettledDebitAmount, Decimal(200))
        XCTAssertEqual(reservation.balanceBeforeReservation.recordedSettledDebitAmount, Decimal(0))
        XCTAssertEqual(reservation.balanceBeforeReservation.availableBalanceAmount, Decimal(800))
        XCTAssertEqual(reservation.accounting.pendingReservedAmount, Decimal(125))
        XCTAssertEqual(reservation.accounting.confirmedSpendAmount, Decimal(0))
        XCTAssertEqual(reservation.accounting.records.last?.status, .pendingReservation)
        XCTAssertEqual(reservation.balanceAfterReservation.pendingReservationAmount, Decimal(125))
        XCTAssertEqual(reservation.balanceAfterReservation.recordedSettledDebitAmount, Decimal(0))
        XCTAssertEqual(reservation.balanceAfterReservation.settledDebitAmount, Decimal(200))
        XCTAssertEqual(reservation.balanceAfterReservation.remainingBalanceAmount, Decimal(800))
        XCTAssertEqual(reservation.balanceAfterReservation.availableBalanceAmount, Decimal(675))
    }

    func testPendingDelegatedSpendReservationRequiresReservationCapability() throws {
        let policy = try delegatedSpendingPolicy(
            sessionTotalLimit: Decimal(1_000),
            remainingLimit: Decimal(800)
        )
        let request = try executionRequest(
            executionId: "exec-pending-delegated-spend-no-capability",
            amount: Decimal(125)
        )
        let wallet = try BalanceReportingAgentWallet(limit: delegatedSpendingLimit(for: policy))

        XCTAssertThrowsError(try wallet.reservePendingDelegatedSpend(
            request,
            policy: policy,
            accounting: MeshAgentWalletDelegatedSpendAccounting(policy: policy),
            reservedAt: "2026-05-31T12:00:45Z"
        )) { error in
            XCTAssertEqual(error as? MeshKitValidationError, .unsupportedCapability)
        }
    }

    func testAgentWalletAppliesSuccessfulDelegatedSpendDebitAndReducesAvailableBalance() throws {
        let policy = try delegatedSpendingPolicy(
            sessionTotalLimit: Decimal(1_000),
            remainingLimit: Decimal(800)
        )
        let request = try executionRequest(
            executionId: "exec-successful-delegated-spend-debit",
            amount: Decimal(125)
        )
        let accounting = try MeshAgentWalletDelegatedSpendAccounting(policy: policy)
        let wallet = try BalanceReportingAgentWallet(
            limit: delegatedSpendingLimit(for: policy),
            capabilities: [.accountForConfirmedSpend]
        )

        let debit = try wallet.applySuccessfulDelegatedSpendDebit(
            request,
            policy: policy,
            accounting: accounting,
            debitedAt: "2026-05-31T12:01:00Z"
        )

        XCTAssertEqual(debit.walletIdentity, wallet.identity)
        XCTAssertEqual(debit.debitedAmount, Decimal(125))
        XCTAssertEqual(debit.balanceBeforeDebit.priorSettledDebitAmount, Decimal(200))
        XCTAssertEqual(debit.balanceBeforeDebit.recordedSettledDebitAmount, Decimal(0))
        XCTAssertEqual(debit.balanceBeforeDebit.availableBalanceAmount, Decimal(800))
        XCTAssertEqual(debit.accounting.confirmedSpendAmount, Decimal(125))
        XCTAssertEqual(debit.accounting.records.last?.status, .confirmed)
        XCTAssertEqual(debit.balanceAfterDebit.recordedSettledDebitAmount, Decimal(125))
        XCTAssertEqual(debit.balanceAfterDebit.settledDebitAmount, Decimal(325))
        XCTAssertEqual(debit.balanceAfterDebit.remainingBalanceAmount, Decimal(675))
        XCTAssertEqual(debit.balanceAfterDebit.availableBalanceAmount, Decimal(675))
    }

    func testSuccessfulDelegatedSpendDebitRequiresAccountingCapability() throws {
        let policy = try delegatedSpendingPolicy(
            sessionTotalLimit: Decimal(1_000),
            remainingLimit: Decimal(800)
        )
        let request = try executionRequest(
            executionId: "exec-successful-delegated-spend-no-capability",
            amount: Decimal(125)
        )
        let wallet = try BalanceReportingAgentWallet(limit: delegatedSpendingLimit(for: policy))

        XCTAssertThrowsError(try wallet.applySuccessfulDelegatedSpendDebit(
            request,
            policy: policy,
            accounting: MeshAgentWalletDelegatedSpendAccounting(policy: policy),
            debitedAt: "2026-05-31T12:02:00Z"
        )) { error in
            XCTAssertEqual(error as? MeshKitValidationError, .unsupportedCapability)
        }
    }

    func testAgentWalletDeniesReservationWhenDelegatedSpendExceedsAvailableLimitWithoutChangingAccounting() throws {
        let policy = try delegatedSpendingPolicy(
            sessionTotalLimit: Decimal(1_000),
            remainingLimit: Decimal(800)
        )
        let accounting = try MeshAgentWalletDelegatedSpendAccounting(
            policy: policy,
            records: [
                accountingRecord(
                    executionId: "exec-existing-confirmed-debit",
                    amount: Decimal(100),
                    status: .confirmed
                ),
                accountingRecord(
                    executionId: "exec-existing-pending-reservation",
                    amount: Decimal(350),
                    status: .pendingReservation
                )
            ]
        )
        let wallet = try BalanceReportingAgentWallet(
            limit: delegatedSpendingLimit(for: policy),
            capabilities: [.accountForPendingSpendReservation]
        )
        let request = try executionRequest(
            executionId: "exec-over-available-reservation-denied",
            amount: Decimal(400)
        )

        XCTAssertEqual(accounting.availableLimit, Decimal(350))
        XCTAssertThrowsError(try wallet.reservePendingDelegatedSpend(
            request,
            policy: policy,
            accounting: accounting,
            reservedAt: "2026-05-31T12:01:30Z"
        )) { error in
            XCTAssertEqual(error as? MeshKitValidationError, .invalidAgentWalletIdentity("availableLimit"))
        }

        XCTAssertEqual(accounting.pendingReservedAmount, Decimal(350))
        XCTAssertEqual(accounting.confirmedSpendAmount, Decimal(100))
        XCTAssertEqual(accounting.availableLimit, Decimal(350))
        XCTAssertEqual(accounting.records.count, 2)
        XCTAssertNil(accounting.records.first { $0.executionId == request.executionId })
    }

    func testAgentWalletDeniesConfirmedDebitWhenDelegatedSpendExceedsAvailableLimitWithoutChangingAccounting() throws {
        let policy = try delegatedSpendingPolicy(
            sessionTotalLimit: Decimal(1_000),
            remainingLimit: Decimal(800)
        )
        let accounting = try MeshAgentWalletDelegatedSpendAccounting(
            policy: policy,
            records: [
                accountingRecord(
                    executionId: "exec-existing-confirmed-debit-before-denied-debit",
                    amount: Decimal(100),
                    status: .confirmed
                ),
                accountingRecord(
                    executionId: "exec-existing-pending-reservation-before-denied-debit",
                    amount: Decimal(350),
                    status: .pendingReservation
                )
            ]
        )
        let wallet = try BalanceReportingAgentWallet(
            limit: delegatedSpendingLimit(for: policy),
            capabilities: [.accountForConfirmedSpend]
        )
        let request = try executionRequest(
            executionId: "exec-over-available-debit-denied",
            amount: Decimal(400)
        )

        XCTAssertEqual(accounting.availableLimit, Decimal(350))
        XCTAssertThrowsError(try wallet.applySuccessfulDelegatedSpendDebit(
            request,
            policy: policy,
            accounting: accounting,
            debitedAt: "2026-05-31T12:01:45Z"
        )) { error in
            XCTAssertEqual(error as? MeshKitValidationError, .invalidAgentWalletIdentity("availableLimit"))
        }

        XCTAssertEqual(accounting.pendingReservedAmount, Decimal(350))
        XCTAssertEqual(accounting.confirmedSpendAmount, Decimal(100))
        XCTAssertEqual(accounting.availableLimit, Decimal(350))
        XCTAssertEqual(accounting.records.count, 2)
        XCTAssertNil(accounting.records.first { $0.executionId == request.executionId })
    }

    func testAgentWalletReleasesFailedDelegatedSpendReservationAndRestoresAvailableBalance() throws {
        let policy = try delegatedSpendingPolicy(
            sessionTotalLimit: Decimal(1_000),
            remainingLimit: Decimal(800)
        )
        let request = try executionRequest(
            executionId: "exec-failed-delegated-spend-release",
            amount: Decimal(125)
        )
        let wallet = try BalanceReportingAgentWallet(
            limit: delegatedSpendingLimit(for: policy),
            capabilities: [.accountForPendingSpendReservation]
        )
        let reservation = try wallet.reservePendingDelegatedSpend(
            request,
            policy: policy,
            accounting: MeshAgentWalletDelegatedSpendAccounting(policy: policy),
            reservedAt: "2026-05-31T12:02:30Z"
        )

        let release = try wallet.releaseFailedDelegatedSpendReservation(
            request,
            policy: policy,
            accounting: reservation.accounting,
            releasedAt: "2026-05-31T12:02:45Z",
            reason: "provider-execution-failed"
        )

        XCTAssertEqual(release.walletIdentity, wallet.identity)
        XCTAssertEqual(release.releasedAmount, Decimal(125))
        XCTAssertEqual(release.reason, "provider-execution-failed")
        XCTAssertEqual(release.balanceBeforeRelease.pendingReservationAmount, Decimal(125))
        XCTAssertEqual(release.balanceBeforeRelease.availableBalanceAmount, Decimal(675))
        XCTAssertEqual(release.accounting.pendingReservedAmount, Decimal(0))
        XCTAssertEqual(release.accounting.confirmedSpendAmount, Decimal(0))
        XCTAssertEqual(release.accounting.failedAttemptAmount, Decimal(125))
        XCTAssertEqual(release.accounting.records.last?.status, .failed)
        XCTAssertEqual(release.accounting.records.last?.reason, "provider-execution-failed")
        XCTAssertEqual(release.balanceAfterRelease.pendingReservationAmount, Decimal(0))
        XCTAssertEqual(release.balanceAfterRelease.recordedSettledDebitAmount, Decimal(0))
        XCTAssertEqual(release.balanceAfterRelease.settledDebitAmount, Decimal(200))
        XCTAssertEqual(release.balanceAfterRelease.remainingBalanceAmount, Decimal(800))
        XCTAssertEqual(release.balanceAfterRelease.availableBalanceAmount, Decimal(800))
        XCTAssertGreaterThan(
            release.balanceAfterRelease.availableBalanceAmount,
            release.balanceBeforeRelease.availableBalanceAmount
        )
    }

    func testFailedDelegatedSpendReservationReleaseRequiresReservationCapability() throws {
        let policy = try delegatedSpendingPolicy(
            sessionTotalLimit: Decimal(1_000),
            remainingLimit: Decimal(800)
        )
        let request = try executionRequest(
            executionId: "exec-failed-delegated-spend-release-no-capability",
            amount: Decimal(125)
        )
        let wallet = try BalanceReportingAgentWallet(limit: delegatedSpendingLimit(for: policy))

        XCTAssertThrowsError(try wallet.releaseFailedDelegatedSpendReservation(
            request,
            policy: policy,
            accounting: MeshAgentWalletDelegatedSpendAccounting(policy: policy),
            releasedAt: "2026-05-31T12:02:50Z",
            reason: "provider-execution-failed"
        )) { error in
            XCTAssertEqual(error as? MeshKitValidationError, .unsupportedCapability)
        }
    }

    func testConfirmedSpendDebitIsIdempotentForSameExecutionId() throws {
        let policy = try delegatedSpendingPolicy(
            sessionTotalLimit: Decimal(1_000),
            remainingLimit: Decimal(800)
        )
        let request = try executionRequest(
            executionId: "exec-successful-delegated-spend-idempotent",
            amount: Decimal(125)
        )
        let wallet = try BalanceReportingAgentWallet(
            limit: delegatedSpendingLimit(for: policy),
            capabilities: [.accountForConfirmedSpend]
        )
        let firstDebit = try wallet.applySuccessfulDelegatedSpendDebit(
            request,
            policy: policy,
            accounting: MeshAgentWalletDelegatedSpendAccounting(policy: policy),
            debitedAt: "2026-05-31T12:03:00Z"
        )

        let secondDebit = try wallet.applySuccessfulDelegatedSpendDebit(
            request,
            policy: policy,
            accounting: firstDebit.accounting,
            debitedAt: "2026-05-31T12:04:00Z"
        )

        XCTAssertEqual(secondDebit.accounting.confirmedSpendAmount, Decimal(125))
        XCTAssertEqual(secondDebit.accounting.records.count, firstDebit.accounting.records.count)
        XCTAssertEqual(secondDebit.balanceAfterDebit.availableBalanceAmount, Decimal(675))
    }

    func testAgentWalletCalculatesAvailableDelegatedSpendBalanceFromLimitDebitsAndReservations() throws {
        let policy = try delegatedSpendingPolicy(
            sessionTotalLimit: Decimal(1_000),
            remainingLimit: Decimal(800)
        )
        let accounting = try MeshAgentWalletDelegatedSpendAccounting(
            policy: policy,
            records: [
                accountingRecord(
                    executionId: "exec-settled-debit",
                    amount: Decimal(125),
                    status: .confirmed
                ),
                accountingRecord(
                    executionId: "exec-pending-reservation",
                    amount: Decimal(75),
                    status: .pendingReservation
                )
            ]
        )
        let wallet = try BalanceReportingAgentWallet(limit: delegatedSpendingLimit(for: policy))

        let balance = try wallet.availableDelegatedSpendBalance(accounting: accounting)

        XCTAssertEqual(balance.policyId, policy.policyId)
        XCTAssertEqual(balance.configuredLimitAmount, Decimal(1_000))
        XCTAssertEqual(balance.priorSettledDebitAmount, Decimal(200))
        XCTAssertEqual(balance.recordedSettledDebitAmount, Decimal(125))
        XCTAssertEqual(balance.settledDebitAmount, Decimal(325))
        XCTAssertEqual(balance.pendingReservationAmount, Decimal(75))
        XCTAssertEqual(balance.remainingBalanceAmount, Decimal(675))
        XCTAssertEqual(balance.availableBalanceAmount, Decimal(600))
        XCTAssertEqual(balance.asset, "OKRW")
    }

    func testReceiptEligibilityAllowsConfirmedOKRWPaymentForDelegatedLimitDecrement() throws {
        let receipt = try receipt(
            proof: confirmedPaymentProof(kind: .payment, asset: "OKRW", executionId: "exec-eligible-payment")
        )

        let eligibility = try MeshDelegatedSpendReceiptEligibilityEvaluator.evaluate(
            receipt: receipt,
            expectedTargetAppId: "app.dailymart",
            expectedTargetBundleId: "ai.meshkit.sample.dailymart"
        )

        XCTAssertTrue(eligibility.isEligibleForDelegatedLimitDecrement)
        XCTAssertNil(eligibility.reason)
        XCTAssertEqual(eligibility.executionKind, .payment)
        XCTAssertEqual(eligibility.debitAmount, Decimal(125))
        XCTAssertEqual(eligibility.asset, "OKRW")
        XCTAssertEqual(eligibility.transactionHash, "0x" + String(repeating: "a", count: 64))
    }

    func testReceiptEligibilityAllowsConfirmedOKRWTransferForDelegatedLimitDecrement() throws {
        let receipt = try receipt(
            proof: confirmedPaymentProof(kind: .transfer, asset: "OKRW", executionId: "exec-eligible-transfer")
        )

        let eligibility = try MeshDelegatedSpendReceiptEligibilityEvaluator.evaluate(receipt: receipt)

        XCTAssertTrue(eligibility.isEligibleForDelegatedLimitDecrement)
        XCTAssertEqual(eligibility.executionKind, .transfer)
        XCTAssertEqual(eligibility.debitAmount, Decimal(125))
    }

    func testOKRWExecutionAmountExtractorReturnsConfirmedAmountInSpendingLimitDenomination() throws {
        let policy = try delegatedSpendingPolicy(
            sessionTotalLimit: Decimal(1_000),
            remainingLimit: Decimal(800)
        )
        let receipt = try receipt(
            proof: confirmedPaymentProof(kind: .payment, asset: "OKRW", executionId: "exec-okrw-amount")
        )

        let extraction = try MeshDelegatedSpendConfirmedExecutionAmountExtractor.confirmedOKRWAmount(
            from: receipt,
            spendingLimit: delegatedSpendingLimit(for: policy),
            expectedTargetAppId: "app.dailymart",
            expectedTargetBundleId: "ai.meshkit.sample.dailymart"
        )

        let amount = try XCTUnwrap(extraction)
        XCTAssertEqual(amount.amount, Decimal(125))
        XCTAssertEqual(amount.denomination, "OKRW")
        XCTAssertEqual(amount.executionKind, .payment)
        XCTAssertEqual(amount.transactionHash, "0x" + String(repeating: "a", count: 64))
        XCTAssertEqual(amount.anchoringReference, "maroo-anchor-exec-okrw-amount")
        XCTAssertEqual(amount.policyId, policy.policyId)
        XCTAssertEqual(amount.policyHash, policy.policyHash)
        XCTAssertEqual(amount.receiptId, "receipt-exec-okrw-amount")
        XCTAssertEqual(amount.requestId, "request-exec-okrw-amount")
    }

    func testOKRWExecutionAmountExtractorIgnoresIneligibleReceipts() throws {
        let policy = try delegatedSpendingPolicy(
            sessionTotalLimit: Decimal(1_000),
            remainingLimit: Decimal(800)
        )
        let pendingReceipt = try receipt(
            proof: baseProof(
                proofType: .requestAnchor,
                status: .pending,
                presentationState: .submittedNotFinal,
                executionKind: .payment,
                txHash: nil,
                explorerUrl: nil,
                errorCode: nil,
                errorMessage: nil,
                submittedAt: "2026-05-31T12:11:00Z",
                confirmedAt: nil,
                executionId: "exec-okrw-pending-amount"
            )
        )

        let extraction = try MeshDelegatedSpendConfirmedExecutionAmountExtractor.confirmedOKRWAmount(
            from: pendingReceipt,
            spendingLimit: delegatedSpendingLimit(for: policy)
        )

        XCTAssertNil(extraction)
    }

    func testOKRWExecutionAmountExtractorRequiresCanonicalOKRWSpendingLimitDenomination() throws {
        let receipt = try receipt(
            proof: confirmedPaymentProof(kind: .payment, asset: "OKRW", executionId: "exec-okrw-denomination")
        )
        let krwLimit = try MeshAgentWalletDelegatedSpendingLimit(
            limitAmount: Decimal(1_000),
            availableLimit: Decimal(800),
            currencyCode: "KRW",
            scope: MeshAgentWalletSpendingScope(
                merchantId: "merchant.dailymart",
                targetBundleId: "ai.meshkit.sample.dailymart",
                capabilityId: "grocery.purchase_essentials",
                consentGrantId: "grant-hermes-dailymart-001"
            ),
            expiresAt: "2026-06-30T00:00:00Z"
        )

        XCTAssertThrowsError(try MeshDelegatedSpendConfirmedExecutionAmountExtractor.confirmedOKRWAmount(
            from: receipt,
            spendingLimit: krwLimit
        )) { error in
            XCTAssertEqual(error as? MeshKitValidationError, .invalidAgentWalletIdentity("denomination"))
        }
    }

    func testReceiptEligibilityRejectsPendingFailedPolicyDeniedAndNonOKRWReceipts() throws {
        let pendingReceipt = try receipt(
            proof: baseProof(
                proofType: .requestAnchor,
                status: .pending,
                presentationState: .submittedNotFinal,
                executionKind: .payment,
                txHash: nil,
                explorerUrl: nil,
                errorCode: nil,
                errorMessage: nil,
                submittedAt: "2026-05-31T12:07:00Z",
                confirmedAt: nil
            )
        )
        let failedReceipt = try receipt(
            proof: baseProof(
                proofType: .paymentExecution,
                status: .failed,
                presentationState: .attemptedFailed,
                executionKind: .payment,
                txHash: nil,
                explorerUrl: nil,
                errorCode: "payment_execution_failed",
                errorMessage: "provider execution failed",
                submittedAt: "2026-05-31T12:07:30Z",
                confirmedAt: nil
            )
        )
        let policyDeniedReceipt = try receipt(
            proof: baseProof(
                proofType: .policyDenial,
                status: .failed,
                presentationState: .policyDenied,
                executionKind: nil,
                txHash: nil,
                explorerUrl: nil,
                errorCode: "policy_denied",
                errorMessage: "policy denied",
                submittedAt: "2026-05-31T12:08:00Z",
                confirmedAt: nil
            )
        )
        let nonOKRWReceipt = try receipt(
            proof: confirmedPaymentProof(kind: .payment, asset: "KRW", executionId: "exec-non-okrw")
        )

        let pending = try MeshDelegatedSpendReceiptEligibilityEvaluator.evaluate(receipt: pendingReceipt)
        let failed = try MeshDelegatedSpendReceiptEligibilityEvaluator.evaluate(receipt: failedReceipt)
        let denied = try MeshDelegatedSpendReceiptEligibilityEvaluator.evaluate(receipt: policyDeniedReceipt)
        let nonOKRW = try MeshDelegatedSpendReceiptEligibilityEvaluator.evaluate(receipt: nonOKRWReceipt)

        XCTAssertFalse(pending.isEligibleForDelegatedLimitDecrement)
        XCTAssertEqual(pending.reason, .notPaymentExecution)
        XCTAssertNil(pending.debitAmount)
        XCTAssertFalse(failed.isEligibleForDelegatedLimitDecrement)
        XCTAssertEqual(failed.reason, .notConfirmed)
        XCTAssertNil(failed.debitAmount)
        XCTAssertFalse(denied.isEligibleForDelegatedLimitDecrement)
        XCTAssertEqual(denied.reason, .notPaymentExecution)
        XCTAssertNil(denied.debitAmount)
        XCTAssertFalse(nonOKRW.isEligibleForDelegatedLimitDecrement)
        XCTAssertEqual(nonOKRW.reason, .unsupportedAsset)
        XCTAssertNil(nonOKRW.debitAmount)
    }

    func testReceiptEligibilityRejectsConfirmedPaymentExecutionWithoutProviderNeutralExecutionKind() throws {
        let receipt = try receipt(
            proof: baseProof(
                proofType: .paymentExecution,
                status: .confirmed,
                presentationState: .paidComplete,
                executionKind: nil,
                txHash: "0x" + String(repeating: "a", count: 64),
                explorerUrl: URL(string: "https://explorer-testnet.maroo.io/tx/0x\(String(repeating: "a", count: 64))"),
                errorCode: nil,
                errorMessage: nil,
                submittedAt: "2026-05-31T12:09:00Z",
                confirmedAt: "2026-05-31T12:09:30Z"
            )
        )

        let eligibility = try MeshDelegatedSpendReceiptEligibilityEvaluator.evaluate(receipt: receipt)

        XCTAssertFalse(eligibility.isEligibleForDelegatedLimitDecrement)
        XCTAssertEqual(eligibility.reason, .unsupportedExecutionKind)
        XCTAssertNil(eligibility.debitAmount)
    }

    func testDelegatedSpendBalanceRejectsInconsistentAvailableBalance() throws {
        XCTAssertThrowsError(try MeshAgentWalletDelegatedSpendBalance(
            policyId: "policy-hermes-dailymart-okrw-v1",
            configuredLimitAmount: Decimal(1_000),
            priorSettledDebitAmount: Decimal(200),
            recordedSettledDebitAmount: Decimal(125),
            settledDebitAmount: Decimal(325),
            pendingReservationAmount: Decimal(75),
            remainingBalanceAmount: Decimal(675),
            availableBalanceAmount: Decimal(675),
            asset: "OKRW"
        )) { error in
            XCTAssertEqual(error as? MeshKitValidationError, .invalidAgentWalletIdentity("availableBalanceAmount"))
        }
    }

    private func receipt(proof: MeshChainProof) throws -> MeshReceipt {
        let targetAppId = "app.dailymart"
        let targetBundleId = "ai.meshkit.sample.dailymart"
        let ownedResult = try MeshReceiptOwnershipMapper.targetOwnedResultFields(
            baseResult: ["merchant": "DailyMart"],
            targetAppId: targetAppId,
            targetBundleId: targetBundleId
        )
        let result = try MeshReceiptChainProofSerializer.receiptResultFields(
            baseResult: ownedResult,
            proof: proof
        )
        return MeshReceipt(
            receiptId: "receipt-\(proof.executionId ?? proof.anchoringReference)",
            requestId: "request-\(proof.executionId ?? proof.anchoringReference)",
            capabilityId: "grocery.purchase_essentials",
            targetAppId: targetAppId,
            targetBundleId: targetBundleId,
            requestPayloadHash: MeshPayloadHash(value: String(repeating: "c", count: 64)),
            status: proof.presentationState.rawValue,
            result: result,
            nonce: "receipt-nonce-\(proof.executionId ?? proof.anchoringReference)",
            timestamp: "2026-05-31T12:10:00Z",
            signature: MeshSignature(
                algorithm: "Ed25519",
                keyId: "dailymart-receipt-key",
                value: "receipt-signature"
            )
        )
    }

    private func confirmedPaymentProof(
        kind: MeshAgentWalletExecutionKind,
        asset: String,
        executionId: String
    ) throws -> MeshChainProof {
        try baseProof(
            proofType: .paymentExecution,
            status: .confirmed,
            presentationState: .paidComplete,
            executionKind: kind,
            txHash: "0x" + String(repeating: "a", count: 64),
            explorerUrl: URL(string: "https://explorer-testnet.maroo.io/tx/0x\(String(repeating: "a", count: 64))"),
            errorCode: nil,
            errorMessage: nil,
            submittedAt: "2026-05-31T12:06:00Z",
            confirmedAt: "2026-05-31T12:06:30Z",
            asset: asset,
            executionId: executionId
        )
    }

    private func baseProof(
        proofType: MeshChainProofType,
        status: MeshChainProofStatus,
        presentationState: MeshChainProofPresentationState,
        executionKind: MeshAgentWalletExecutionKind?,
        txHash: String?,
        explorerUrl: URL?,
        errorCode: String?,
        errorMessage: String?,
        submittedAt: String?,
        confirmedAt: String?,
        asset: String = "OKRW",
        executionId: String = "exec-receipt-eligibility"
    ) throws -> MeshChainProof {
        try MeshChainProof(
            provider: "maroo",
            chainId: "maroo-testnet-1",
            network: "maroo-testnet",
            proofType: proofType,
            status: status,
            presentationState: presentationState,
            requestHash: MeshPayloadHash(value: String(repeating: "b", count: 64)),
            requestNonce: "nonce-\(executionId)",
            policyId: "policy-hermes-dailymart-okrw-v1",
            policyHash: MeshPayloadHash(value: String(repeating: "f", count: 64)),
            walletAddress: "maroo1DailyMartAgentWallet",
            amount: Decimal(125),
            asset: asset,
            recipient: "0x000000000000000000000000000000000000d417",
            anchoringReference: "maroo-anchor-\(executionId)",
            executionAttemptId: "attempt-\(executionId)",
            paymentId: "pay-\(executionId)",
            authorizationId: "auth-\(executionId)",
            executionId: executionId,
            executionKind: executionKind,
            anchorTxHash: "0x" + String(repeating: "b", count: 64),
            txHash: txHash,
            explorerUrl: explorerUrl,
            errorCode: errorCode,
            errorMessage: errorMessage,
            submittedAt: submittedAt,
            confirmedAt: confirmedAt
        )
    }

    private func delegatedSpendingPolicy(
        sessionTotalLimit: Decimal,
        remainingLimit: Decimal
    ) throws -> MeshAgentWalletDelegatedSpendingPolicy {
        try MeshAgentWalletDelegatedSpendingPolicy(
            policyId: "policy-hermes-dailymart-okrw-v1",
            policyHash: MeshPayloadHash(value: String(repeating: "f", count: 64)),
            consentGrantId: "grant-hermes-dailymart-001",
            merchantScope: "merchant.dailymart",
            capabilityScope: "grocery.purchase_essentials",
            singlePaymentMax: Decimal(500),
            sessionTotalLimit: sessionTotalLimit,
            remainingLimit: remainingLimit,
            startsAt: "2026-05-01T00:00:00Z",
            expiresAt: "2026-06-30T00:00:00Z",
            asset: "OKRW",
            recipientAddress: "0x000000000000000000000000000000000000d417"
        )
    }

    private func delegatedSpendingLimit(
        for policy: MeshAgentWalletDelegatedSpendingPolicy
    ) throws -> MeshAgentWalletDelegatedSpendingLimit {
        try MeshAgentWalletDelegatedSpendingLimit(
            limitAmount: policy.sessionTotalLimit,
            availableLimit: policy.remainingLimit,
            tokenSymbol: policy.asset,
            scope: MeshAgentWalletSpendingScope(
                merchantId: policy.merchantScope,
                targetBundleId: "ai.meshkit.sample.dailymart",
                capabilityId: policy.capabilityScope,
                consentGrantId: policy.consentGrantId
            ),
            expiresAt: policy.expiresAt,
            policyMetadata: MeshAgentWalletDelegatedSpendingPolicyMetadata(policy: policy)
        )
    }

    private func accountingRecord(
        executionId: String,
        amount: Decimal,
        status: MeshAgentWalletExecutionAccountingStatus
    ) throws -> MeshAgentWalletExecutionAccountingRecord {
        try MeshAgentWalletExecutionAccountingRecord(
            executionId: executionId,
            policyId: "policy-hermes-dailymart-okrw-v1",
            requestNonce: "nonce-\(executionId)",
            amount: amount,
            asset: "OKRW",
            status: status,
            recordedAt: "2026-05-31T12:00:00Z"
        )
    }

    private func executionRequest(
        executionId: String,
        amount: Decimal
    ) throws -> MeshAgentWalletExecutionRequest {
        let nonce = "nonce-\(executionId)"
        return try MeshAgentWalletExecutionRequest(
            executionId: executionId,
            kind: .payment,
            requestAnchorMetadata: MeshSignedRequestAnchorMetadata(
                request: signedDailyMartRequest(
                    requestId: "request-\(executionId)",
                    nonce: nonce,
                    budget: "\(amount)"
                )
            ),
            scope: MeshAgentWalletSpendingScope(
                merchantId: "merchant.dailymart",
                targetBundleId: "ai.meshkit.sample.dailymart",
                capabilityId: "grocery.purchase_essentials",
                consentGrantId: "grant-hermes-dailymart-001"
            ),
            amount: amount,
            currencyCode: "KRW",
            tokenSymbol: "OKRW",
            recipientAddress: "0x000000000000000000000000000000000000d417",
            policyId: "policy-hermes-dailymart-okrw-v1",
            policyHash: MeshPayloadHash(value: String(repeating: "f", count: 64))
        )
    }

    private func signedDailyMartRequest(
        requestId: String,
        nonce: String,
        budget: String
    ) -> MeshRequest {
        MeshRequest(
            requestId: requestId,
            caller: MeshIdentity(
                appId: "app.hermes-chat",
                installId: "ios-device",
                bundleId: "ai.meshkit.sample.hermeschat",
                publicKeyId: "sample-ios-ed25519"
            ),
            target: MeshCapability(
                targetBundleId: "ai.meshkit.sample.dailymart",
                capabilityId: "grocery.purchase_essentials",
                version: "1.0"
            ),
            payload: [
                "items": "laundry_detergent:1",
                "address_ref": "home.saved",
                "budget_krw": budget
            ],
            nonce: nonce,
            timestamp: "2026-05-31T12:00:00Z",
            signature: MeshSignature(
                algorithm: "Ed25519",
                keyId: "sample-ios-ed25519",
                value: "signature-\(requestId)"
            )
        )
    }
}

private struct BalanceReportingAgentWallet: MeshAgentWallet {
    let identity: MeshAgentWalletIdentity
    let capabilities: [MeshAgentWalletCapability]
    let limit: MeshAgentWalletDelegatedSpendingLimit

    init(
        limit: MeshAgentWalletDelegatedSpendingLimit,
        capabilities: [MeshAgentWalletCapability] = [.reportDelegatedSpendingLimit]
    ) throws {
        self.identity = try MeshAgentWalletIdentity(
            walletId: "wallet-hermes-dailymart-okrw-v1",
            agentId: "agent.hermes-chat.daily-mart",
            walletAddress: "maroo1DailyMartAgentWallet",
            providerMetadata: MeshAgentWalletProviderMetadata(
                provider: "test-provider",
                network: "testnet",
                chainId: "test-chain",
                adapterId: "test-agent-wallet-adapter"
            ),
            signingBoundary: .providerSubmission
        )
        self.capabilities = capabilities
        self.limit = limit
    }

    func loadWalletConfiguration() throws -> MeshAgentWalletConfiguration {
        try MeshAgentWalletConfiguration(identity: identity, capabilities: capabilities)
    }

    func reportWalletAddress() throws -> String {
        throw MeshKitValidationError.unsupportedCapability
    }

    func delegatedSpendingLimit() throws -> MeshAgentWalletDelegatedSpendingLimit {
        try loadWalletConfiguration().require(.reportDelegatedSpendingLimit)
        return limit
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
