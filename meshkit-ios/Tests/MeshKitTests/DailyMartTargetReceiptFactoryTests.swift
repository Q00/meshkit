import CryptoKit
import XCTest
@testable import MeshKit

final class DailyMartTargetReceiptFactoryTests: XCTestCase {
    private let hermesSigningKey = Curve25519.Signing.PrivateKey()
    private let receiptSigningKey = Curve25519.Signing.PrivateKey()
    private let referenceDate = ISO8601DateFormatter().date(from: "2026-05-31T12:00:00Z")!

    func testAcceptedAppToAppCallCreatesDailyMartOwnedReceiptNotCallerOwned() throws {
        let request = try signedDailyMartRequest()
        let accepted = try dailyMartGuard().acceptForPreExecution(request, now: referenceDate)
        let callerOwner = try MeshReceiptOwnershipMapper.ownerIdentifier(
            targetAppId: request.caller.appId,
            targetBundleId: request.caller.bundleId
        )
        let providerOwner = try MeshReceiptOwnershipMapper.ownerIdentifier(
            targetAppId: "provider.maroo",
            targetBundleId: "maroo-testnet-1"
        )
        let receipt = try DailyMartTargetReceiptFactory(
            signer: MeshReceiptSigner.ed25519(
                keyId: "dailymart-receipt-key",
                privateKey: receiptSigningKey
            )
        ).makeAcceptedCallReceipt(
            receiptId: "DM-2026-0531-AC1-receipt",
            request: accepted,
            status: "purchased",
            baseResult: [
                "order_id": "DM-2026-0531-AC1",
                "total_krw": "100",
                "payment_asset": DailyMartDelegatedSpendingPolicy.asset,
                "policy_verification": MeshDelegatedSpendingPolicyVerificationStatus.approved.rawValue,
                "receiptOwner": callerOwner,
                "targetReceiptOwner": providerOwner
            ],
            nonce: "DM-2026-0531-AC1-receipt-nonce",
            timestamp: "2026-05-31T12:00:05Z"
        )

        let ownership = try MeshReceiptOwnershipMapper.assertTargetOwned(
            receipt,
            expectedTargetAppId: DailyMartTargetReceiptFactory.targetAppId,
            expectedTargetBundleId: DailyMartTargetReceiptFactory.targetBundleId
        )
        let ownershipMetadata = try receipt.targetOwnershipMetadata()
        let decodedOwnershipMetadata = try MeshReceipt.decodedFromURLScheme(
            receipt.encodedForURLScheme()
        ).targetOwnershipMetadata()

        XCTAssertEqual(receipt.requestId, accepted.requestId)
        XCTAssertEqual(ownershipMetadata, ownership)
        XCTAssertEqual(decodedOwnershipMetadata, ownershipMetadata)
        XCTAssertEqual(ownershipMetadata.receiptId, receipt.receiptId)
        XCTAssertEqual(ownershipMetadata.requestId, accepted.requestId)
        XCTAssertEqual(ownershipMetadata.targetAppId, DailyMartTargetReceiptFactory.targetAppId)
        XCTAssertEqual(ownershipMetadata.targetBundleId, DailyMartTargetReceiptFactory.targetBundleId)
        XCTAssertEqual(ownershipMetadata.targetSignatureKeyId, "dailymart-receipt-key")
        XCTAssertEqual(ownership.receiptOwner, "app.dailymart#ai.meshkit.sample.dailymart")
        XCTAssertEqual(ownership.targetReceiptOwner, ownership.receiptOwner)
        XCTAssertEqual(receipt.result["receiptOwner"], ownership.receiptOwner)
        XCTAssertEqual(receipt.result["targetReceiptOwner"], ownership.receiptOwner)
        XCTAssertNotEqual(ownership.receiptOwner, callerOwner)
        XCTAssertNotEqual(ownership.targetReceiptOwner, providerOwner)
        XCTAssertNotEqual(receipt.signature.keyId, request.signature.keyId)
        XCTAssertThrowsError(try MeshReceiptOwnershipMapper.assertTargetOwned(
            receipt,
            expectedTargetAppId: request.caller.appId,
            expectedTargetBundleId: request.caller.bundleId
        )) { error in
            XCTAssertEqual(error as? MeshKitValidationError, .targetIdentityMismatch)
        }
    }

    func testAcceptedAppToAppReceiptIdsAreFreshAcrossRepeatedAcceptedCalls() throws {
        let guardModule = try dailyMartGuard()
        let firstAccepted = try guardModule.acceptForPreExecution(
            signedDailyMartRequest(
                requestId: "ios-grocery-repeat-accepted-1",
                nonce: "nonce-dailymart-repeat-accepted-1",
                timestamp: "2026-05-31T12:00:01Z"
            ),
            now: referenceDate
        )
        let secondAccepted = try guardModule.acceptForPreExecution(
            signedDailyMartRequest(
                requestId: "ios-grocery-repeat-accepted-2",
                nonce: "nonce-dailymart-repeat-accepted-2",
                timestamp: "2026-05-31T12:00:02Z"
            ),
            now: referenceDate
        )
        let factory = DailyMartTargetReceiptFactory(
            signer: MeshReceiptSigner.ed25519(
                keyId: "dailymart-receipt-key",
                privateKey: receiptSigningKey
            )
        )

        let firstReceipt = try factory.makeAcceptedCallReceipt(
            request: firstAccepted,
            status: "purchased",
            baseResult: acceptedReceiptResult(orderId: "DM-2026-0531-repeat-1"),
            timestamp: "2026-05-31T12:00:05Z"
        )
        let secondReceipt = try factory.makeAcceptedCallReceipt(
            request: secondAccepted,
            status: "purchased",
            baseResult: acceptedReceiptResult(orderId: "DM-2026-0531-repeat-2"),
            timestamp: "2026-05-31T12:00:06Z"
        )

        XCTAssertNotEqual(firstReceipt.receiptId, secondReceipt.receiptId)
        XCTAssertEqual(firstReceipt.requestId, firstAccepted.requestId)
        XCTAssertEqual(secondReceipt.requestId, secondAccepted.requestId)
        XCTAssertTrue(firstReceipt.receiptId.hasPrefix("dailymart-\(firstAccepted.requestId)-receipt-"))
        XCTAssertTrue(secondReceipt.receiptId.hasPrefix("dailymart-\(secondAccepted.requestId)-receipt-"))
        XCTAssertNoThrow(try MeshReceiptOwnershipMapper.assertTargetOwned(
            firstReceipt,
            expectedTargetAppId: DailyMartTargetReceiptFactory.targetAppId,
            expectedTargetBundleId: DailyMartTargetReceiptFactory.targetBundleId
        ))
        XCTAssertNoThrow(try MeshReceiptOwnershipMapper.assertTargetOwned(
            secondReceipt,
            expectedTargetAppId: DailyMartTargetReceiptFactory.targetAppId,
            expectedTargetBundleId: DailyMartTargetReceiptFactory.targetBundleId
        ))
    }

    func testChainProofFieldSchemaExposesProviderNeutralConfirmedReceiptContract() throws {
        let schema = MeshChainProofSchema.providerNeutral
        let fieldsByName = Dictionary(uniqueKeysWithValues: schema.fields.map { ($0.name, $0) })
        let ontologyRequiredFields = [
            "provider", "chainId", "network", "proofType", "status", "presentationState",
            "requestHash", "requestNonce", "policyId", "policyHash", "walletAddress",
            "amount", "asset", "recipient", "anchoringReference", "txHash",
            "explorerUrl", "confirmedAt", "providerExtensions"
        ]

        try schema.validate()
        XCTAssertEqual(schema.version, MeshChainProofSchema.version)
        for field in ontologyRequiredFields {
            XCTAssertNotNil(fieldsByName[field], "missing chain proof schema field \(field)")
        }
        XCTAssertEqual(fieldsByName["provider"]?.receiptResultKey, "chainProvider")
        XCTAssertEqual(fieldsByName["network"]?.receiptResultKey, "chainNetwork")
        XCTAssertEqual(fieldsByName["proofType"]?.receiptResultKey, "chainProofType")
        XCTAssertEqual(fieldsByName["status"]?.receiptResultKey, "chainStatus")
        XCTAssertEqual(fieldsByName["txHash"]?.requirement, .confirmedOnly)
        XCTAssertEqual(fieldsByName["explorerUrl"]?.requirement, .confirmedOnly)
        XCTAssertEqual(fieldsByName["confirmedAt"]?.requirement, .confirmedOnly)
        XCTAssertEqual(fieldsByName["providerExtensions"]?.requirement, .optional)
        XCTAssertTrue(schema.confirmedRequiredFields.contains("txHash"))
        XCTAssertTrue(schema.confirmedRequiredFields.contains("explorerUrl"))
        XCTAssertTrue(schema.confirmedRequiredFields.contains("confirmedAt"))

        let encoded = try JSONEncoder().encode(schema)
        let decoded = try JSONDecoder().decode(MeshChainProofSchema.self, from: encoded)
        XCTAssertEqual(decoded, schema)
        XCTAssertFalse(String(data: encoded, encoding: .utf8)?.contains("maroo") ?? true)
    }

    func testConfirmedReceiptSchemaValidationRunnableExampleAcceptsDailyMartReceipt() throws {
        let request = try signedDailyMartRequest(
            requestId: "ios-grocery-confirmed-schema-example",
            nonce: "nonce-confirmed-schema-example",
            timestamp: "2026-05-31T12:00:11Z"
        )
        let accepted = try dailyMartGuard().acceptForPreExecution(request, now: referenceDate)
        let confirmedProof = try MeshChainProof(
            provider: "maroo",
            chainId: "maroo-testnet-1",
            network: "maroo-testnet",
            proofType: .paymentExecution,
            status: .confirmed,
            presentationState: .paidComplete,
            requestHash: MeshRequestAnchorCanonicalization.signedRequestHash(for: accepted),
            requestNonce: accepted.nonce,
            policyId: DailyMartDelegatedSpendingPolicy.policyId,
            policyHash: DailyMartDelegatedSpendingPolicy.policyHash,
            walletAddress: "maroo1DailyMartAgentWallet",
            amount: Decimal(100),
            asset: DailyMartDelegatedSpendingPolicy.asset,
            recipient: "maroo1DailyMartMerchant",
            anchoringReference: "maroo-anchor-confirmed-schema-example",
            executionAttemptId: "meshkit-execution-attempt/v1:pay-confirmed-schema-example:auth-confirmed-schema-example:exec-confirmed-schema-example",
            paymentId: "pay-confirmed-schema-example",
            authorizationId: "auth-confirmed-schema-example",
            executionId: "exec-confirmed-schema-example",
            executionKind: .payment,
            anchorTxHash: "0xanchorConfirmedSchemaExample",
            txHash: "0xokrwConfirmedSchemaExample",
            explorerUrl: try XCTUnwrap(URL(string: "https://explorer-testnet.maroo.io/tx/0xokrwConfirmedSchemaExample")),
            submittedAt: "2026-05-31T12:00:12Z",
            confirmedAt: "2026-05-31T12:00:13Z"
        )
        let receipt = try DailyMartTargetReceiptFactory(
            signer: MeshReceiptSigner.ed25519(
                keyId: "dailymart-receipt-key",
                privateKey: receiptSigningKey
            )
        ).makeAcceptedCallReceipt(
            receiptId: "DM-2026-0531-confirmed-schema-example",
            request: accepted,
            status: "purchased",
            baseResult: acceptedReceiptResult(orderId: "DM-2026-0531-confirmed-schema-example"),
            chainProof: confirmedProof,
            nonce: "DM-2026-0531-confirmed-schema-example-nonce",
            timestamp: "2026-05-31T12:00:14Z"
        )
        let encodedReceiptData = try XCTUnwrap(Data(base64Encoded: receipt.encodedForURLScheme()))
        let schema = MeshChainProofSchema.providerNeutral

        XCTAssertNoThrow(try MeshReceipt.validateProviderNeutralCoreSchema(jsonData: encodedReceiptData))
        XCTAssertNoThrow(try schema.validateReceiptResultFields(receipt.result))
        XCTAssertEqual(
            try schema.requiredFields(
                status: .confirmed,
                proofType: .paymentExecution,
                presentationState: .paidComplete
            ),
            schema.confirmedRequiredFields
        )

        var missingConfirmedPaymentHash = receipt.result
        missingConfirmedPaymentHash.removeValue(forKey: "txHash")
        XCTAssertThrowsError(try schema.validateReceiptResultFields(missingConfirmedPaymentHash)) { error in
            XCTAssertEqual(error as? MeshKitValidationError, .invalidChainProof("receipt.result.txHash"))
        }
    }

    func testPendingChainProofFieldSchemaExposesProviderNeutralRequestAnchorContract() throws {
        let schema = MeshChainProofSchema.providerNeutral
        let fieldsByName = Dictionary(uniqueKeysWithValues: schema.fields.map { ($0.name, $0) })
        let pendingOntologyRequiredFields = [
            "provider", "chainId", "network", "proofType", "status", "presentationState",
            "requestHash", "requestNonce", "policyId", "policyHash", "walletAddress",
            "amount", "asset", "recipient", "anchoringReference", "submittedAt"
        ]

        try schema.validate()
        XCTAssertEqual(schema.version, MeshChainProofSchema.version)
        for field in pendingOntologyRequiredFields {
            XCTAssertNotNil(fieldsByName[field], "missing pending chain proof schema field \(field)")
            XCTAssertTrue(schema.pendingRequiredFields.contains(field), "missing pending required field \(field)")
        }
        XCTAssertEqual(fieldsByName["proofType"]?.receiptResultKey, "chainProofType")
        XCTAssertEqual(fieldsByName["status"]?.receiptResultKey, "chainStatus")
        XCTAssertEqual(fieldsByName["presentationState"]?.receiptResultKey, "presentationState")
        XCTAssertEqual(fieldsByName["requestHash"]?.receiptResultKey, "requestHash")
        XCTAssertEqual(fieldsByName["requestNonce"]?.receiptResultKey, "requestNonce")
        XCTAssertEqual(fieldsByName["anchoringReference"]?.receiptResultKey, "anchoringReference")
        XCTAssertEqual(fieldsByName["submittedAt"]?.receiptResultKey, "submittedAt")
        XCTAssertTrue(schema.pendingRequiredFields.contains("submittedAt"))
        XCTAssertFalse(schema.pendingRequiredFields.contains("txHash"))
        XCTAssertFalse(schema.pendingRequiredFields.contains("explorerUrl"))
        XCTAssertFalse(schema.pendingRequiredFields.contains("confirmedAt"))
        XCTAssertEqual(fieldsByName["txHash"]?.requirement, .confirmedOnly)
        XCTAssertEqual(fieldsByName["explorerUrl"]?.requirement, .confirmedOnly)
        XCTAssertEqual(fieldsByName["confirmedAt"]?.requirement, .confirmedOnly)
        XCTAssertEqual(fieldsByName["providerExtensions"]?.requirement, .optional)

        let encoded = try JSONEncoder().encode(schema)
        let decoded = try JSONDecoder().decode(MeshChainProofSchema.self, from: encoded)
        XCTAssertEqual(decoded.pendingRequiredFields, schema.pendingRequiredFields)
        XCTAssertFalse(String(data: encoded, encoding: .utf8)?.contains("maroo") ?? true)
    }

    func testPendingReceiptSchemaValidationRunnableExampleAcceptsDailyMartReceipt() throws {
        let request = try signedDailyMartRequest(
            requestId: "ios-grocery-pending-schema-example",
            nonce: "nonce-pending-schema-example",
            timestamp: "2026-05-31T12:00:15Z"
        )
        let accepted = try dailyMartGuard().acceptForPreExecution(request, now: referenceDate)
        let pendingProof = try MeshChainProof(
            provider: "maroo",
            chainId: "maroo-testnet-1",
            network: "maroo-testnet",
            proofType: .requestAnchor,
            status: .pending,
            presentationState: .submittedNotFinal,
            requestHash: MeshRequestAnchorCanonicalization.signedRequestHash(for: accepted),
            requestNonce: accepted.nonce,
            policyId: DailyMartDelegatedSpendingPolicy.policyId,
            policyHash: DailyMartDelegatedSpendingPolicy.policyHash,
            walletAddress: "maroo1DailyMartAgentWallet",
            amount: Decimal(100),
            asset: DailyMartDelegatedSpendingPolicy.asset,
            recipient: "maroo1DailyMartMerchant",
            anchoringReference: "maroo-anchor-pending-schema-example",
            executionAttemptId: "meshkit-execution-attempt/v1:pay-pending-schema-example:auth-pending-schema-example:exec-pending-schema-example",
            paymentId: "pay-pending-schema-example",
            authorizationId: "auth-pending-schema-example",
            executionId: "exec-pending-schema-example",
            executionKind: .payment,
            anchorTxHash: "0xanchorPendingSchemaExample",
            submittedAt: "2026-05-31T12:00:16Z"
        )
        let receipt = try DailyMartTargetReceiptFactory(
            signer: MeshReceiptSigner.ed25519(
                keyId: "dailymart-receipt-key",
                privateKey: receiptSigningKey
            )
        ).makeAcceptedCallReceipt(
            receiptId: "DM-2026-0531-pending-schema-example",
            request: accepted,
            status: "pending",
            baseResult: acceptedReceiptResult(orderId: "DM-2026-0531-pending-schema-example"),
            chainProof: pendingProof,
            nonce: "DM-2026-0531-pending-schema-example-nonce",
            timestamp: "2026-05-31T12:00:17Z"
        )
        let encodedReceiptData = try XCTUnwrap(Data(base64Encoded: receipt.encodedForURLScheme()))
        let schema = MeshChainProofSchema.providerNeutral

        XCTAssertNoThrow(try MeshReceipt.validateProviderNeutralCoreSchema(jsonData: encodedReceiptData))
        XCTAssertNoThrow(try schema.validateReceiptResultFields(receipt.result))
        XCTAssertEqual(
            try schema.requiredFields(
                status: .pending,
                proofType: .requestAnchor,
                presentationState: .submittedNotFinal
            ),
            schema.pendingRequiredFields
        )
        XCTAssertEqual(receipt.result["chainStatus"], "pending")
        XCTAssertEqual(receipt.result["chainProofType"], "request_anchor")
        XCTAssertEqual(receipt.result["presentationState"], "submitted_not_final")
        XCTAssertEqual(receipt.result["submittedAt"], "2026-05-31T12:00:16Z")
        XCTAssertNil(receipt.result["txHash"])
        XCTAssertNil(receipt.result["explorerUrl"])
        XCTAssertNil(receipt.result["confirmedAt"])
        XCTAssertNil(receipt.result["errorCode"])
        XCTAssertNil(receipt.result["errorMessage"])

        var missingSubmittedAt = receipt.result
        missingSubmittedAt.removeValue(forKey: "submittedAt")
        XCTAssertThrowsError(try schema.validateReceiptResultFields(missingSubmittedAt)) { error in
            XCTAssertEqual(error as? MeshKitValidationError, .invalidChainProof("receipt.result.submittedAt"))
        }

        var incorrectlyConfirmedPending = receipt.result
        incorrectlyConfirmedPending["txHash"] = "0xmustNotValidateForPendingReceipt"
        XCTAssertThrowsError(try schema.validateReceiptResultFields(incorrectlyConfirmedPending)) { error in
            XCTAssertEqual(error as? MeshKitValidationError, .invalidChainProof("receipt.result.txHash"))
        }
    }

    func testFailedChainProofFieldSchemaExposesProviderNeutralReceiptContract() throws {
        let schema = MeshChainProofSchema.providerNeutral
        let fieldsByName = Dictionary(uniqueKeysWithValues: schema.fields.map { ($0.name, $0) })
        let failedOntologyRequiredFields = [
            "provider", "chainId", "network", "proofType", "status", "presentationState",
            "requestHash", "requestNonce", "policyId", "policyHash", "walletAddress",
            "amount", "asset", "recipient", "anchoringReference", "errorCode", "errorMessage"
        ]

        try schema.validate()
        XCTAssertEqual(schema.version, MeshChainProofSchema.version)
        for field in failedOntologyRequiredFields {
            XCTAssertNotNil(fieldsByName[field], "missing failed chain proof schema field \(field)")
            XCTAssertTrue(schema.failedRequiredFields.contains(field), "missing failed required field \(field)")
        }
        XCTAssertEqual(fieldsByName["proofType"]?.receiptResultKey, "chainProofType")
        XCTAssertEqual(fieldsByName["status"]?.receiptResultKey, "chainStatus")
        XCTAssertEqual(fieldsByName["presentationState"]?.receiptResultKey, "presentationState")
        XCTAssertEqual(fieldsByName["errorCode"]?.receiptResultKey, "errorCode")
        XCTAssertEqual(fieldsByName["errorMessage"]?.receiptResultKey, "errorMessage")
        XCTAssertEqual(fieldsByName["errorCode"]?.requirement, .failureOnly)
        XCTAssertEqual(fieldsByName["errorMessage"]?.requirement, .failureOnly)
        XCTAssertFalse(schema.failedRequiredFields.contains("txHash"))
        XCTAssertFalse(schema.failedRequiredFields.contains("explorerUrl"))
        XCTAssertFalse(schema.failedRequiredFields.contains("confirmedAt"))

        let encoded = try JSONEncoder().encode(schema)
        let decoded = try JSONDecoder().decode(MeshChainProofSchema.self, from: encoded)
        XCTAssertEqual(decoded.failedRequiredFields, schema.failedRequiredFields)
        XCTAssertFalse(String(data: encoded, encoding: .utf8)?.contains("maroo") ?? true)
    }

    func testPolicyDeniedChainProofFieldSchemaExposesProviderNeutralOntologyFields() throws {
        let schema = MeshChainProofSchema.providerNeutral
        let fieldsByName = Dictionary(uniqueKeysWithValues: schema.fields.map { ($0.name, $0) })
        let policyDeniedOntologyRequiredFields = [
            "provider", "chainId", "network", "proofType", "status", "presentationState",
            "requestHash", "requestNonce", "policyId", "policyHash", "walletAddress",
            "amount", "asset", "recipient", "anchoringReference", "executionAttemptId",
            "executionId", "errorCode", "errorMessage"
        ]

        try schema.validate()
        XCTAssertEqual(schema.version, MeshChainProofSchema.version)
        for field in policyDeniedOntologyRequiredFields {
            XCTAssertNotNil(fieldsByName[field], "missing policy-denied chain proof schema field \(field)")
            XCTAssertTrue(
                schema.policyDeniedRequiredFields.contains(field),
                "missing policy-denied required field \(field)"
            )
        }
        XCTAssertEqual(fieldsByName["proofType"]?.receiptResultKey, "chainProofType")
        XCTAssertEqual(fieldsByName["status"]?.receiptResultKey, "chainStatus")
        XCTAssertEqual(fieldsByName["presentationState"]?.receiptResultKey, "presentationState")
        XCTAssertEqual(fieldsByName["executionAttemptId"]?.receiptResultKey, "executionAttemptId")
        XCTAssertEqual(fieldsByName["executionId"]?.receiptResultKey, "executionId")
        XCTAssertEqual(fieldsByName["errorCode"]?.requirement, .failureOnly)
        XCTAssertEqual(fieldsByName["errorMessage"]?.requirement, .failureOnly)
        XCTAssertFalse(schema.policyDeniedRequiredFields.contains("txHash"))
        XCTAssertFalse(schema.policyDeniedRequiredFields.contains("explorerUrl"))
        XCTAssertFalse(schema.policyDeniedRequiredFields.contains("confirmedAt"))
        XCTAssertFalse(schema.policyDeniedRequiredFields.contains("paymentId"))
        XCTAssertFalse(schema.policyDeniedRequiredFields.contains("authorizationId"))

        let encoded = try JSONEncoder().encode(schema)
        let decoded = try JSONDecoder().decode(MeshChainProofSchema.self, from: encoded)
        XCTAssertEqual(decoded.policyDeniedRequiredFields, schema.policyDeniedRequiredFields)
        XCTAssertFalse(String(data: encoded, encoding: .utf8)?.contains("maroo") ?? true)
    }

    func testFailedReceiptSchemaValidationRunnableExampleAcceptsDailyMartReceipt() throws {
        let request = try signedDailyMartRequest(
            requestId: "ios-grocery-failed-schema-example",
            nonce: "nonce-failed-schema-example",
            timestamp: "2026-05-31T12:00:18Z"
        )
        let accepted = try dailyMartGuard().acceptForPreExecution(request, now: referenceDate)
        let paymentRequest = try paymentExecutionRequest(
            for: accepted,
            executionId: "exec-failed-schema-example",
            paymentId: "pay-failed-schema-example",
            authorizationId: "auth-failed-schema-example"
        )
        let paymentResult = try MeshPaymentExecutionResult(
            request: paymentRequest,
            identity: paymentRequest.requestAnchor.identifier.identity,
            status: .failed,
            observedAt: "2026-05-31T12:00:19Z",
            message: "maroo testnet OKRW execution reverted",
            errorPayload: MeshPaymentExecutionErrorPayload(
                code: "okrw_execution_reverted",
                message: "maroo testnet OKRW execution reverted"
            )
        )
        let receipt = try DailyMartTargetReceiptFactory(
            signer: MeshReceiptSigner.ed25519(
                keyId: "dailymart-receipt-key",
                privateKey: receiptSigningKey
            )
        ).makeVerifiedWalletExecutionReceipt(
            receiptId: "DM-2026-0531-failed-schema-example",
            request: accepted,
            paymentResult: paymentResult,
            executionRequest: paymentRequest.executionRequest,
            walletAddress: "maroo1DailyMartAgentWallet",
            baseResult: acceptedReceiptResult(orderId: "DM-2026-0531-failed-schema-example"),
            nonce: "DM-2026-0531-failed-schema-example-nonce",
            timestamp: "2026-05-31T12:00:20Z"
        )
        let encodedReceiptData = try XCTUnwrap(Data(base64Encoded: receipt.encodedForURLScheme()))
        let schema = MeshChainProofSchema.providerNeutral

        XCTAssertNoThrow(try MeshReceipt.validateProviderNeutralCoreSchema(jsonData: encodedReceiptData))
        XCTAssertNoThrow(try schema.validateReceiptResultFields(receipt.result))
        XCTAssertEqual(
            try schema.requiredFields(
                status: .failed,
                proofType: .paymentExecution,
                presentationState: .attemptedFailed
            ),
            schema.failedRequiredFields
        )
        XCTAssertEqual(receipt.result["chainStatus"], "failed")
        XCTAssertEqual(receipt.result["chainProofType"], "payment_execution")
        XCTAssertEqual(receipt.result["presentationState"], "attempted_failed")
        XCTAssertEqual(receipt.result["errorCode"], "okrw_execution_reverted")
        XCTAssertEqual(receipt.result["errorMessage"], "maroo testnet OKRW execution reverted")
        XCTAssertNil(receipt.result["txHash"])
        XCTAssertNil(receipt.result["explorerUrl"])
        XCTAssertNil(receipt.result["confirmedAt"])

        var missingErrorCode = receipt.result
        missingErrorCode.removeValue(forKey: "errorCode")
        XCTAssertThrowsError(try schema.validateReceiptResultFields(missingErrorCode)) { error in
            XCTAssertEqual(error as? MeshKitValidationError, .invalidChainProof("receipt.result.errorCode"))
        }

        var incorrectlyConfirmedFailure = receipt.result
        incorrectlyConfirmedFailure["txHash"] = "0xmustNotValidateForFailedReceipt"
        XCTAssertThrowsError(try schema.validateReceiptResultFields(incorrectlyConfirmedFailure)) { error in
            XCTAssertEqual(error as? MeshKitValidationError, .invalidChainProof("receipt.result.txHash"))
        }
    }

    func testPolicyDeniedReceiptSchemaValidationRunnableExampleAcceptsDailyMartReceipt() throws {
        let request = try signedDailyMartRequest(
            requestId: "ios-grocery-policy-denied-schema-example",
            nonce: "nonce-policy-denied-schema-example",
            timestamp: "2026-05-31T12:00:21Z",
            budgetKRW: "101"
        )
        let accepted = try dailyMartGuard().acceptForPreExecution(request, now: referenceDate)
        let executionId = "exec-policy-denied-schema-example"
        let executionRequest = try DailyMartPreExecutionWalletPolicyGuard().makeExecutionRequest(
            from: accepted,
            executionKind: .payment,
            executionId: executionId
        )
        let providerIdentity = try MeshMarooTestnetChainProvider().identity
        let anchoringReference = try MeshRequestAnchorCanonicalization.anchoringReference(
            for: accepted,
            providerIdentity: providerIdentity
        )
        let receipt = try DailyMartTargetReceiptFactory(
            signer: MeshReceiptSigner.ed25519(
                keyId: "dailymart-receipt-key",
                privateKey: receiptSigningKey
            )
        ).makePolicyDeniedWalletExecutionReceipt(
            receiptId: "DM-2026-0531-policy-denied-schema-example",
            request: accepted,
            executionRequest: executionRequest,
            providerIdentity: providerIdentity,
            walletAddress: "maroo1DailyMartAgentWallet",
            anchoringReference: anchoringReference.anchorId,
            denialReason: "policy-single-payment-max-exceeded",
            baseResult: [
                "order_id": "DM-2026-0531-policy-denied-schema-example",
                "total_krw": "101",
                "payment_asset": DailyMartDelegatedSpendingPolicy.asset,
                "txHash": "0xmustNotSurvivePolicyDeniedSchemaExample"
            ],
            nonce: "DM-2026-0531-policy-denied-schema-example-nonce",
            timestamp: "2026-05-31T12:00:22Z"
        )
        let encodedReceiptData = try XCTUnwrap(Data(base64Encoded: receipt.encodedForURLScheme()))
        let schema = MeshChainProofSchema.providerNeutral

        XCTAssertNoThrow(try MeshReceipt.validateProviderNeutralCoreSchema(jsonData: encodedReceiptData))
        XCTAssertNoThrow(try schema.validateReceiptResultFields(receipt.result))
        XCTAssertEqual(
            try schema.requiredFields(
                status: .failed,
                proofType: .policyDenial,
                presentationState: .policyDenied
            ),
            schema.policyDeniedRequiredFields
        )
        XCTAssertEqual(receipt.result["chainStatus"], "failed")
        XCTAssertEqual(receipt.result["chainProofType"], "policy_denial")
        XCTAssertEqual(receipt.result["presentationState"], "policy_denied")
        XCTAssertEqual(receipt.result["executionAttemptId"], "meshkit-execution-attempt/v1:payment-unavailable:authorization-unavailable:\(executionId)")
        XCTAssertEqual(receipt.result["executionId"], executionId)
        XCTAssertEqual(receipt.result["errorCode"], "policy_denied")
        XCTAssertEqual(receipt.result["errorMessage"], "policy-single-payment-max-exceeded")
        XCTAssertNil(receipt.result["txHash"])
        XCTAssertNil(receipt.result["explorerUrl"])
        XCTAssertNil(receipt.result["confirmedAt"])
        XCTAssertNil(receipt.result["paymentId"])
        XCTAssertNil(receipt.result["authorizationId"])

        var missingExecutionAttemptId = receipt.result
        missingExecutionAttemptId.removeValue(forKey: "executionAttemptId")
        XCTAssertThrowsError(try schema.validateReceiptResultFields(missingExecutionAttemptId)) { error in
            XCTAssertEqual(error as? MeshKitValidationError, .invalidChainProof("receipt.result.executionAttemptId"))
        }

        var incorrectlyConfirmedPolicyDenial = receipt.result
        incorrectlyConfirmedPolicyDenial["txHash"] = "0xmustNotValidateForPolicyDeniedReceipt"
        XCTAssertThrowsError(try schema.validateReceiptResultFields(incorrectlyConfirmedPolicyDenial)) { error in
            XCTAssertEqual(error as? MeshKitValidationError, .invalidChainProof("receipt.result.txHash"))
        }
    }

    func testChainProofSerializerMapsProviderNeutralProofIntoDailyMartReceiptSchema() throws {
        let request = try signedDailyMartRequest(
            requestId: "ios-grocery-dailymart-chain-proof-schema",
            nonce: "nonce-dailymart-chain-proof-schema",
            timestamp: "2026-05-31T12:00:03Z"
        )
        let accepted = try dailyMartGuard().acceptForPreExecution(request, now: referenceDate)
        let proof = try MeshChainProof(
            provider: "maroo",
            chainId: "maroo-testnet-1",
            network: "maroo-testnet",
            proofType: .paymentExecution,
            status: .confirmed,
            presentationState: .paidComplete,
            requestHash: MeshRequestAnchorCanonicalization.signedRequestHash(for: accepted),
            requestNonce: accepted.nonce,
            policyId: DailyMartDelegatedSpendingPolicy.policyId,
            policyHash: DailyMartDelegatedSpendingPolicy.policyHash,
            walletAddress: "maroo1DailyMartAgentWallet",
            amount: Decimal(100),
            asset: DailyMartDelegatedSpendingPolicy.asset,
            recipient: "maroo1DailyMartMerchant",
            anchoringReference: "maroo-anchor-dailymart-chain-proof-schema",
            executionAttemptId: "meshkit-execution-attempt/v1:pay-dailymart-chain-proof-schema:auth-dailymart-chain-proof-schema:exec-dailymart-chain-proof-schema",
            paymentId: "pay-dailymart-chain-proof-schema",
            authorizationId: "auth-dailymart-chain-proof-schema",
            executionId: "exec-dailymart-chain-proof-schema",
            anchorTxHash: "0xanchorDailyMartChainProofSchema",
            txHash: "0xokrwDailyMartChainProofSchema",
            explorerUrl: try XCTUnwrap(URL(string: "https://explorer-testnet.example.invalid/tx/0xokrwDailyMartChainProofSchema")),
            submittedAt: "2026-05-31T12:00:04Z",
            confirmedAt: "2026-05-31T12:00:05Z"
        )

        let receipt = try DailyMartTargetReceiptFactory(
            signer: MeshReceiptSigner.ed25519(
                keyId: "dailymart-receipt-key",
                privateKey: receiptSigningKey
            )
        ).makeAcceptedCallReceipt(
            receiptId: "DM-2026-0531-chain-proof-schema-receipt",
            request: accepted,
            status: "purchased",
            baseResult: acceptedReceiptResult(orderId: "DM-2026-0531-chain-proof-schema"),
            chainProof: proof,
            nonce: "DM-2026-0531-chain-proof-schema-receipt-nonce",
            timestamp: "2026-05-31T12:00:06Z"
        )

        let decodedReceipt = try MeshReceipt.decodedFromURLScheme(receipt.encodedForURLScheme())
        let decodedProof = try MeshReceiptChainProofSerializer.decodeProof(from: decodedReceipt.result)
        let ownershipProof = try MeshReceiptChainProofSerializer.targetOwnedProof(
            in: decodedReceipt,
            expectedTargetAppId: DailyMartTargetReceiptFactory.targetAppId,
            expectedTargetBundleId: DailyMartTargetReceiptFactory.targetBundleId,
            expectedRequest: accepted
        )

        XCTAssertEqual(decodedReceipt.result["receiptOwner"], "app.dailymart#ai.meshkit.sample.dailymart")
        XCTAssertEqual(decodedReceipt.result["targetReceiptOwner"], "app.dailymart#ai.meshkit.sample.dailymart")
        XCTAssertEqual(decodedReceipt.result["chainProofVersion"], MeshReceiptChainProofPayload.version)
        XCTAssertEqual(decodedReceipt.result["chainProofEncoding"], MeshReceiptChainProofSerializer.encodedProofEncoding)
        XCTAssertNotNil(decodedReceipt.result["chainProof"])
        XCTAssertEqual(decodedReceipt.result["chainProvider"], "maroo")
        XCTAssertEqual(decodedReceipt.result["chainId"], "maroo-testnet-1")
        XCTAssertEqual(decodedReceipt.result["chainNetwork"], "maroo-testnet")
        XCTAssertEqual(decodedReceipt.result["chainProofType"], "payment_execution")
        XCTAssertEqual(decodedReceipt.result["chainStatus"], "confirmed")
        XCTAssertEqual(decodedReceipt.result["presentationState"], "paid_complete")
        XCTAssertEqual(decodedReceipt.result["requestHashAlgorithm"], "sha256")
        XCTAssertEqual(decodedReceipt.result["requestHash"], proof.requestHash.value)
        XCTAssertEqual(decodedReceipt.result["requestNonce"], accepted.nonce)
        XCTAssertEqual(decodedReceipt.result["policyId"], DailyMartDelegatedSpendingPolicy.policyId)
        XCTAssertEqual(decodedReceipt.result["policyHashAlgorithm"], "sha256")
        XCTAssertEqual(decodedReceipt.result["policyHash"], DailyMartDelegatedSpendingPolicy.policyHash.value)
        XCTAssertEqual(decodedReceipt.result["walletAddress"], "maroo1DailyMartAgentWallet")
        XCTAssertEqual(decodedReceipt.result["amount"], "100")
        XCTAssertEqual(decodedReceipt.result["asset"], "OKRW")
        XCTAssertEqual(decodedReceipt.result["recipient"], "maroo1DailyMartMerchant")
        XCTAssertEqual(decodedReceipt.result["anchoringReference"], "maroo-anchor-dailymart-chain-proof-schema")
        XCTAssertEqual(
            decodedReceipt.result["executionAttemptId"],
            "meshkit-execution-attempt/v1:pay-dailymart-chain-proof-schema:auth-dailymart-chain-proof-schema:exec-dailymart-chain-proof-schema"
        )
        XCTAssertEqual(decodedReceipt.result["paymentId"], "pay-dailymart-chain-proof-schema")
        XCTAssertEqual(decodedReceipt.result["authorizationId"], "auth-dailymart-chain-proof-schema")
        XCTAssertEqual(decodedReceipt.result["executionId"], "exec-dailymart-chain-proof-schema")
        XCTAssertEqual(decodedReceipt.result["anchorTxHash"], "0xanchorDailyMartChainProofSchema")
        XCTAssertEqual(decodedReceipt.result["txHash"], "0xokrwDailyMartChainProofSchema")
        XCTAssertEqual(decodedReceipt.result["explorerUrl"], "https://explorer-testnet.example.invalid/tx/0xokrwDailyMartChainProofSchema")
        XCTAssertEqual(decodedReceipt.result["submittedAt"], "2026-05-31T12:00:04Z")
        XCTAssertEqual(decodedReceipt.result["confirmedAt"], "2026-05-31T12:00:05Z")
        XCTAssertEqual(decodedProof, proof)
        XCTAssertEqual(ownershipProof.proof, proof)
        XCTAssertEqual(ownershipProof.transactionReference?.value, "0xokrwDailyMartChainProofSchema")
    }

    func testVerifiedConfirmedExecutionAttemptCreatesConfirmedDailyMartReceipt() throws {
        let request = try signedDailyMartRequest(
            requestId: "ios-grocery-dailymart-confirmed-execution-receipt",
            nonce: "nonce-dailymart-confirmed-execution-receipt",
            timestamp: "2026-05-31T12:00:04Z"
        )
        let accepted = try dailyMartGuard().acceptForPreExecution(request, now: referenceDate)
        let paymentRequest = try paymentExecutionRequest(
            for: accepted,
            executionId: "exec-dailymart-confirmed-execution-receipt",
            paymentId: "pay-dailymart-confirmed-execution-receipt",
            authorizationId: "auth-dailymart-confirmed-execution-receipt"
        )
        let paymentResult = try MeshPaymentExecutionResult(
            request: paymentRequest,
            identity: paymentRequest.requestAnchor.identifier.identity,
            status: .confirmed,
            transactionHash: "0xokrwDailyMartConfirmedExecutionReceipt",
            explorerURL: try XCTUnwrap(URL(string: "https://explorer-testnet.maroo.io/tx/0xokrwDailyMartConfirmedExecutionReceipt")),
            observedAt: "2026-05-31T12:00:07Z"
        )

        let receipt = try DailyMartTargetReceiptFactory(
            signer: MeshReceiptSigner.ed25519(
                keyId: "dailymart-receipt-key",
                privateKey: receiptSigningKey
            )
        ).makeVerifiedWalletExecutionReceipt(
            receiptId: "DM-2026-0531-confirmed-execution-receipt",
            request: accepted,
            paymentResult: paymentResult,
            executionRequest: paymentRequest.executionRequest,
            walletAddress: "maroo1DailyMartAgentWallet",
            baseResult: acceptedReceiptResult(orderId: "DM-2026-0531-confirmed-execution-receipt"),
            nonce: "DM-2026-0531-confirmed-execution-receipt-nonce",
            timestamp: "2026-05-31T12:00:08Z"
        )
        let ownershipProof = try MeshReceiptChainProofSerializer.targetOwnedProof(
            in: receipt,
            expectedTargetAppId: DailyMartTargetReceiptFactory.targetAppId,
            expectedTargetBundleId: DailyMartTargetReceiptFactory.targetBundleId,
            expectedRequest: accepted
        )

        XCTAssertEqual(receipt.status, "confirmed")
        XCTAssertEqual(receipt.result["chainProofType"], "payment_execution")
        XCTAssertEqual(receipt.result["chainStatus"], "confirmed")
        XCTAssertEqual(receipt.result["presentationState"], "paid_complete")
        XCTAssertEqual(receipt.result["policy_verification"], MeshDelegatedSpendingPolicyVerificationStatus.approved.rawValue)
        XCTAssertEqual(receipt.result["requestHash"], paymentRequest.requestHash.value)
        XCTAssertEqual(receipt.result["requestNonce"], accepted.nonce)
        XCTAssertEqual(receipt.result["anchoringReference"], paymentRequest.requestAnchor.identifier.anchorId)
        XCTAssertEqual(receipt.result["anchorTxHash"], "0xanchorDailyMartConfirmedExecutionReceipt")
        XCTAssertEqual(receipt.result["txHash"], "0xokrwDailyMartConfirmedExecutionReceipt")
        XCTAssertEqual(receipt.result["confirmedAt"], "2026-05-31T12:00:07Z")
        XCTAssertEqual(
            receipt.result["executionAttemptId"],
            "meshkit-execution-attempt/v1:pay-dailymart-confirmed-execution-receipt:auth-dailymart-confirmed-execution-receipt:exec-dailymart-confirmed-execution-receipt"
        )
        XCTAssertEqual(ownershipProof.proof.status, .confirmed)
        XCTAssertEqual(ownershipProof.proof.presentationState, .paidComplete)
        XCTAssertEqual(ownershipProof.transactionReference?.value, "0xokrwDailyMartConfirmedExecutionReceipt")
    }

    func testVerifiedFailedExecutionAttemptCreatesFailedDailyMartOwnedReceipt() throws {
        let request = try signedDailyMartRequest(
            requestId: "ios-grocery-dailymart-failed-execution-receipt",
            nonce: "nonce-dailymart-failed-execution-receipt",
            timestamp: "2026-05-31T12:00:05Z"
        )
        let accepted = try dailyMartGuard().acceptForPreExecution(request, now: referenceDate)
        let paymentRequest = try paymentExecutionRequest(
            for: accepted,
            executionId: "exec-dailymart-failed-execution-receipt",
            paymentId: "pay-dailymart-failed-execution-receipt",
            authorizationId: "auth-dailymart-failed-execution-receipt"
        )
        let paymentResult = try MeshPaymentExecutionResult(
            request: paymentRequest,
            identity: paymentRequest.requestAnchor.identifier.identity,
            status: .failed,
            observedAt: "2026-05-31T12:00:08Z",
            message: "maroo testnet OKRW execution reverted",
            errorPayload: MeshPaymentExecutionErrorPayload(
                code: "okrw_execution_reverted",
                message: "maroo testnet OKRW execution reverted"
            )
        )

        let receipt = try DailyMartTargetReceiptFactory(
            signer: MeshReceiptSigner.ed25519(
                keyId: "dailymart-receipt-key",
                privateKey: receiptSigningKey
            )
        ).makeVerifiedWalletExecutionReceipt(
            receiptId: "DM-2026-0531-failed-execution-receipt",
            request: accepted,
            paymentResult: paymentResult,
            executionRequest: paymentRequest.executionRequest,
            walletAddress: "maroo1DailyMartAgentWallet",
            baseResult: acceptedReceiptResult(orderId: "DM-2026-0531-failed-execution-receipt"),
            nonce: "DM-2026-0531-failed-execution-receipt-nonce",
            timestamp: "2026-05-31T12:00:09Z"
        )
        let ownershipProof = try MeshReceiptChainProofSerializer.targetOwnedProof(
            in: receipt,
            expectedTargetAppId: DailyMartTargetReceiptFactory.targetAppId,
            expectedTargetBundleId: DailyMartTargetReceiptFactory.targetBundleId,
            expectedRequest: accepted
        )

        XCTAssertEqual(receipt.status, "failed")
        XCTAssertEqual(receipt.result["receiptOwner"], "app.dailymart#ai.meshkit.sample.dailymart")
        XCTAssertEqual(receipt.result["targetReceiptOwner"], "app.dailymart#ai.meshkit.sample.dailymart")
        XCTAssertEqual(receipt.result["chainProofType"], "payment_execution")
        XCTAssertEqual(receipt.result["chainStatus"], "failed")
        XCTAssertEqual(receipt.result["presentationState"], "attempted_failed")
        XCTAssertEqual(receipt.result["policy_verification"], MeshDelegatedSpendingPolicyVerificationStatus.approved.rawValue)
        XCTAssertEqual(receipt.result["requestHash"], paymentRequest.requestHash.value)
        XCTAssertEqual(receipt.result["requestNonce"], accepted.nonce)
        XCTAssertEqual(receipt.result["anchoringReference"], paymentRequest.requestAnchor.identifier.anchorId)
        XCTAssertEqual(receipt.result["anchorTxHash"], "0xanchorDailyMartConfirmedExecutionReceipt")
        XCTAssertEqual(receipt.result["errorCode"], "okrw_execution_reverted")
        XCTAssertEqual(receipt.result["errorMessage"], "maroo testnet OKRW execution reverted")
        XCTAssertEqual(receipt.result["submittedAt"], "2026-05-31T12:00:08Z")
        XCTAssertNil(receipt.result["txHash"])
        XCTAssertNil(receipt.result["explorerUrl"])
        XCTAssertNil(receipt.result["confirmedAt"])
        XCTAssertEqual(
            receipt.result["executionAttemptId"],
            "meshkit-execution-attempt/v1:pay-dailymart-failed-execution-receipt:auth-dailymart-failed-execution-receipt:exec-dailymart-failed-execution-receipt"
        )
        XCTAssertEqual(ownershipProof.proof.proofType, .paymentExecution)
        XCTAssertEqual(ownershipProof.proof.status, .failed)
        XCTAssertEqual(ownershipProof.proof.presentationState, .attemptedFailed)
        XCTAssertEqual(ownershipProof.proof.errorCode, "okrw_execution_reverted")
        XCTAssertEqual(ownershipProof.proof.errorMessage, "maroo testnet OKRW execution reverted")
        XCTAssertNil(ownershipProof.transactionReference)
    }

    func testPolicyDeniedWalletExecutionCreatesFailedDailyMartOwnedReceipt() throws {
        let request = try signedDailyMartRequest(
            requestId: "ios-grocery-dailymart-policy-denied-receipt",
            nonce: "nonce-dailymart-policy-denied-receipt",
            timestamp: "2026-05-31T12:00:04Z",
            budgetKRW: "101"
        )
        let accepted = try dailyMartGuard().acceptForPreExecution(request, now: referenceDate)
        let policyGuard = try DailyMartPreExecutionWalletPolicyGuard()

        XCTAssertThrowsError(try policyGuard.evaluate(
            accepted,
            executionKind: .payment,
            executionId: "exec-\(accepted.requestId)",
            verifiedAt: "2026-05-31T12:00:05Z"
        )) { error in
            XCTAssertEqual(
                error as? MeshKitValidationError,
                .invalidAgentWalletIdentity("policy-single-payment-max-exceeded")
            )
        }

        let executionRequest = try policyGuard.makeExecutionRequest(
            from: accepted,
            executionKind: .payment,
            executionId: "exec-\(accepted.requestId)"
        )
        let callerOwner = try MeshReceiptOwnershipMapper.ownerIdentifier(
            targetAppId: accepted.caller.appId,
            targetBundleId: accepted.caller.bundleId
        )
        let providerOwner = try MeshReceiptOwnershipMapper.ownerIdentifier(
            targetAppId: "provider.maroo",
            targetBundleId: "maroo-testnet-1"
        )
        let providerIdentity = try MeshMarooTestnetChainProvider().identity
        let anchoringReference = try MeshRequestAnchorCanonicalization.anchoringReference(
            for: accepted,
            providerIdentity: providerIdentity
        )
        let receipt = try DailyMartTargetReceiptFactory(
            signer: MeshReceiptSigner.ed25519(
                keyId: "dailymart-receipt-key",
                privateKey: receiptSigningKey
            )
        ).makePolicyDeniedWalletExecutionReceipt(
            receiptId: "DM-2026-0531-policy-denied-receipt",
            request: accepted,
            executionRequest: executionRequest,
            providerIdentity: providerIdentity,
            walletAddress: "maroo1DailyMartAgentWallet",
            anchoringReference: anchoringReference.anchorId,
            denialReason: "policy-single-payment-max-exceeded",
            baseResult: [
                "order_id": "DM-2026-0531-policy-denied",
                "total_krw": "101",
                "payment_asset": DailyMartDelegatedSpendingPolicy.asset,
                "txHash": "0xmustNotSurvivePolicyDeniedReceipt",
                "receiptOwner": callerOwner,
                "targetReceiptOwner": providerOwner
            ],
            nonce: "DM-2026-0531-policy-denied-receipt-nonce",
            timestamp: "2026-05-31T12:00:06Z"
        )

        let ownershipProof = try MeshReceiptChainProofSerializer.targetOwnedProof(
            in: receipt,
            expectedTargetAppId: DailyMartTargetReceiptFactory.targetAppId,
            expectedTargetBundleId: DailyMartTargetReceiptFactory.targetBundleId,
            expectedRequest: accepted
        )

        XCTAssertEqual(receipt.status, "failed")
        XCTAssertEqual(receipt.result["receiptOwner"], "app.dailymart#ai.meshkit.sample.dailymart")
        XCTAssertEqual(receipt.result["targetReceiptOwner"], "app.dailymart#ai.meshkit.sample.dailymart")
        XCTAssertEqual(ownershipProof.ownership.receiptOwner, "app.dailymart#ai.meshkit.sample.dailymart")
        XCTAssertEqual(ownershipProof.ownership.targetReceiptOwner, ownershipProof.ownership.receiptOwner)
        XCTAssertNotEqual(ownershipProof.ownership.receiptOwner, callerOwner)
        XCTAssertNotEqual(ownershipProof.ownership.targetReceiptOwner, providerOwner)
        XCTAssertEqual(receipt.result["chainProofType"], "policy_denial")
        XCTAssertEqual(receipt.result["chainStatus"], "failed")
        XCTAssertEqual(receipt.result["presentationState"], "policy_denied")
        XCTAssertEqual(receipt.result["errorCode"], "policy_denied")
        XCTAssertEqual(receipt.result["errorMessage"], "policy-single-payment-max-exceeded")
        XCTAssertEqual(receipt.result["requestNonce"], accepted.nonce)
        XCTAssertEqual(receipt.result["anchoringReference"], anchoringReference.anchorId)
        XCTAssertEqual(
            receipt.result["executionAttemptId"],
            "meshkit-execution-attempt/v1:payment-unavailable:authorization-unavailable:exec-\(accepted.requestId)"
        )
        XCTAssertEqual(receipt.result["executionId"], "exec-\(accepted.requestId)")
        XCTAssertNil(receipt.result["txHash"])
        let decodedReceipt = try MeshReceipt.decodedFromURLScheme(receipt.encodedForURLScheme())
        XCTAssertNil(decodedReceipt.result["txHash"])
        XCTAssertEqual(ownershipProof.proof.proofType, .policyDenial)
        XCTAssertEqual(ownershipProof.proof.status, .failed)
        XCTAssertEqual(ownershipProof.proof.presentationState, .policyDenied)
        XCTAssertNil(ownershipProof.proof.txHash)
    }

    func testPolicyDeniedReceiptUsesDeniedRequestErrorCodeAndMessage() throws {
        let request = try signedDailyMartRequest(
            requestId: "ios-grocery-dailymart-policy-denied-error-fields",
            nonce: "nonce-dailymart-policy-denied-error-fields",
            timestamp: "2026-05-31T12:00:06Z",
            budgetKRW: "101"
        )
        let accepted = try dailyMartGuard().acceptForPreExecution(request, now: referenceDate)
        let policyGuard = try DailyMartPreExecutionWalletPolicyGuard()
        let executionRequest = try policyGuard.makeExecutionRequest(
            from: accepted,
            executionKind: .payment,
            executionId: "exec-\(accepted.requestId)"
        )
        let providerIdentity = try MeshMarooTestnetChainProvider().identity
        let anchoringReference = try MeshRequestAnchorCanonicalization.anchoringReference(
            for: accepted,
            providerIdentity: providerIdentity
        )
        let receipt = try DailyMartTargetReceiptFactory(
            signer: MeshReceiptSigner.ed25519(
                keyId: "dailymart-receipt-key",
                privateKey: receiptSigningKey
            )
        ).makePolicyDeniedWalletExecutionReceipt(
            receiptId: "DM-2026-0531-policy-denied-error-fields",
            request: accepted,
            executionRequest: executionRequest,
            providerIdentity: providerIdentity,
            walletAddress: "maroo1DailyMartAgentWallet",
            anchoringReference: anchoringReference.anchorId,
            denialReason: "fallback-denial-reason",
            baseResult: [
                "order_id": "DM-2026-0531-policy-denied-error-fields",
                "total_krw": "101",
                "payment_asset": DailyMartDelegatedSpendingPolicy.asset,
                "errorCode": "wallet_policy_denied",
                "errorMessage": "policy-single-payment-max-exceeded"
            ],
            errorCode: "fallback_policy_denied",
            nonce: "DM-2026-0531-policy-denied-error-fields-nonce",
            timestamp: "2026-05-31T12:00:07Z"
        )

        let proof = try MeshReceiptChainProofSerializer.decodeProof(from: receipt.result)

        XCTAssertEqual(receipt.status, "failed")
        XCTAssertEqual(receipt.result["chainProofType"], "policy_denial")
        XCTAssertEqual(receipt.result["presentationState"], "policy_denied")
        XCTAssertEqual(receipt.result["errorCode"], "wallet_policy_denied")
        XCTAssertEqual(receipt.result["errorMessage"], "policy-single-payment-max-exceeded")
        XCTAssertEqual(proof.errorCode, "wallet_policy_denied")
        XCTAssertEqual(proof.errorMessage, "policy-single-payment-max-exceeded")
        XCTAssertNil(receipt.result["txHash"])
    }

    func testDailyMartReceiptSerializationOmitsMarooSpecificCoreFields() throws {
        let request = try signedDailyMartRequest(
            requestId: "ios-grocery-dailymart-provider-neutral-receipt",
            nonce: "nonce-dailymart-provider-neutral-receipt",
            timestamp: "2026-05-31T12:00:07Z"
        )
        let accepted = try dailyMartGuard().acceptForPreExecution(request, now: referenceDate)
        let proof = try MeshChainProof(
            provider: "maroo",
            chainId: "maroo-testnet-1",
            network: "maroo-testnet",
            proofType: .paymentExecution,
            status: .confirmed,
            presentationState: .paidComplete,
            requestHash: MeshRequestAnchorCanonicalization.signedRequestHash(for: accepted),
            requestNonce: accepted.nonce,
            policyId: DailyMartDelegatedSpendingPolicy.policyId,
            policyHash: DailyMartDelegatedSpendingPolicy.policyHash,
            walletAddress: "maroo1DailyMartAgentWallet",
            amount: Decimal(100),
            asset: DailyMartDelegatedSpendingPolicy.asset,
            recipient: "maroo1DailyMartMerchant",
            anchoringReference: "maroo-anchor-provider-neutral-receipt",
            anchorTxHash: "0xanchorProviderNeutralReceipt",
            txHash: "0xokrwProviderNeutralReceipt",
            explorerUrl: try XCTUnwrap(URL(string: "https://explorer-testnet.maroo.io/tx/0xokrwProviderNeutralReceipt")),
            submittedAt: "2026-05-31T12:00:08Z",
            confirmedAt: "2026-05-31T12:00:09Z",
            providerExtensions: [
                "maroo": [
                    "adapterId": "maroo-testnet-payment-executor-demo-adapter",
                    "rpcEndpoint": "https://rpc-testnet.maroo.io",
                    "okrwContract": "maroo1okrwcontract001"
                ]
            ]
        )
        let receipt = try DailyMartTargetReceiptFactory(
            signer: MeshReceiptSigner.ed25519(
                keyId: "dailymart-receipt-key",
                privateKey: receiptSigningKey
            )
        ).makeAcceptedCallReceipt(
            receiptId: "DM-2026-0531-provider-neutral-receipt",
            request: accepted,
            status: "purchased",
            baseResult: acceptedReceiptResult(orderId: "DM-2026-0531-provider-neutral-receipt"),
            chainProof: proof,
            nonce: "DM-2026-0531-provider-neutral-receipt-nonce",
            timestamp: "2026-05-31T12:00:10Z"
        )

        let encodedReceiptData = try XCTUnwrap(Data(base64Encoded: receipt.encodedForURLScheme()))
        let receiptObject = try XCTUnwrap(
            JSONSerialization.jsonObject(with: encodedReceiptData) as? [String: Any]
        )
        let rootKeys = Set(receiptObject.keys)
        let providerSpecificCoreKeys: Set<String> = [
            "maroo",
            "marooReceipt",
            "marooMetadata",
            "provider",
            "network",
            "chainId",
            "providerExtensions",
            "rpcEndpoint",
            "okrwContract"
        ]

        XCTAssertEqual(rootKeys, [
            "receiptId",
            "requestId",
            "capabilityId",
            "targetAppId",
            "targetBundleId",
            "requestPayloadHash",
            "status",
            "result",
            "nonce",
            "timestamp",
            "signature"
        ])
        XCTAssertTrue(rootKeys.isDisjoint(with: providerSpecificCoreKeys))
        XCTAssertNoThrow(try MeshReceipt.validateProviderNeutralCoreSchema(jsonData: encodedReceiptData))

        let decodedReceipt = try MeshReceipt.decodedFromURLScheme(receipt.encodedForURLScheme())
        XCTAssertNil(decodedReceipt.result["providerExtensions"])
        XCTAssertNil(decodedReceipt.result["maroo"])
        XCTAssertNil(decodedReceipt.result["marooReceipt"])
        XCTAssertNil(decodedReceipt.result["marooMetadata"])
        XCTAssertNil(decodedReceipt.result["rpcEndpoint"])
        XCTAssertNil(decodedReceipt.result["okrwContract"])
        XCTAssertEqual(decodedReceipt.result["chainProvider"], "maroo")
        XCTAssertEqual(decodedReceipt.result["chainNetwork"], "maroo-testnet")

        let decodedProof = try MeshReceiptChainProofSerializer.decodeProof(from: decodedReceipt.result)
        XCTAssertEqual(decodedProof.providerExtensions["maroo"]?["adapterId"], "maroo-testnet-payment-executor-demo-adapter")
        XCTAssertEqual(decodedProof.providerExtensions["maroo"]?["rpcEndpoint"], "https://rpc-testnet.maroo.io")
        XCTAssertEqual(decodedProof.providerExtensions["maroo"]?["okrwContract"], "maroo1okrwcontract001")

        let encodedProof = try XCTUnwrap(decodedReceipt.result[MeshReceiptChainProofSerializer.encodedProofResultKey])
        let proofPayloadData = try XCTUnwrap(Data(base64Encoded: encodedProof))
        let proofPayloadObject = try XCTUnwrap(
            JSONSerialization.jsonObject(with: proofPayloadData) as? [String: Any]
        )
        let proofObject = try XCTUnwrap(proofPayloadObject["proof"] as? [String: Any])
        let proofProviderExtensions = try XCTUnwrap(proofObject["providerExtensions"] as? [String: Any])
        let marooExtension = try XCTUnwrap(proofProviderExtensions["maroo"] as? [String: Any])
        let proofProviderSpecificCoreKeys: Set<String> = ["adapterId", "rpcEndpoint", "okrwContract"]

        XCTAssertTrue(Set(proofObject.keys).isDisjoint(with: proofProviderSpecificCoreKeys))
        XCTAssertEqual(Set(proofProviderExtensions.keys), ["maroo"])
        XCTAssertEqual(marooExtension["adapterId"] as? String, "maroo-testnet-payment-executor-demo-adapter")
        XCTAssertEqual(marooExtension["rpcEndpoint"] as? String, "https://rpc-testnet.maroo.io")
        XCTAssertEqual(marooExtension["okrwContract"] as? String, "maroo1okrwcontract001")
    }

    func testDailyMartReceiptAttachesOKRWTxHashOnlyForConfirmedExecutionProofs() throws {
        let request = try signedDailyMartRequest(
            requestId: "ios-grocery-dailymart-confirmed-only-txhash",
            nonce: "nonce-dailymart-confirmed-only-txhash",
            timestamp: "2026-05-31T12:00:11Z"
        )
        let accepted = try dailyMartGuard().acceptForPreExecution(request, now: referenceDate)
        let requestHash = try MeshRequestAnchorCanonicalization.signedRequestHash(for: accepted)
        let factory = DailyMartTargetReceiptFactory(
            signer: MeshReceiptSigner.ed25519(
                keyId: "dailymart-receipt-key",
                privateKey: receiptSigningKey
            )
        )

        let confirmedProof = try MeshChainProof(
            provider: "maroo",
            chainId: "maroo-testnet-1",
            network: "maroo-testnet",
            proofType: .paymentExecution,
            status: .confirmed,
            presentationState: .paidComplete,
            requestHash: requestHash,
            requestNonce: accepted.nonce,
            policyId: DailyMartDelegatedSpendingPolicy.policyId,
            policyHash: DailyMartDelegatedSpendingPolicy.policyHash,
            walletAddress: "maroo1DailyMartAgentWallet",
            amount: Decimal(100),
            asset: DailyMartDelegatedSpendingPolicy.asset,
            recipient: "maroo1DailyMartMerchant",
            anchoringReference: "maroo-anchor-confirmed-only-txhash",
            executionAttemptId: "meshkit-execution-attempt/v1:pay-confirmed-only-txhash-confirmed:auth-confirmed-only-txhash-confirmed:exec-confirmed-only-txhash-confirmed",
            paymentId: "pay-confirmed-only-txhash-confirmed",
            authorizationId: "auth-confirmed-only-txhash-confirmed",
            executionId: "exec-confirmed-only-txhash-confirmed",
            anchorTxHash: "0xanchorConfirmedOnlyTxHash",
            txHash: "0xokrwConfirmedOnlyReceiptTx",
            explorerUrl: try XCTUnwrap(URL(string: "https://explorer-testnet.maroo.io/tx/0xokrwConfirmedOnlyReceiptTx")),
            submittedAt: "2026-05-31T12:00:12Z",
            confirmedAt: "2026-05-31T12:00:13Z"
        )
        let pendingProof = try MeshChainProof(
            provider: "maroo",
            chainId: "maroo-testnet-1",
            network: "maroo-testnet",
            proofType: .requestAnchor,
            status: .pending,
            presentationState: .submittedNotFinal,
            requestHash: requestHash,
            requestNonce: accepted.nonce,
            policyId: DailyMartDelegatedSpendingPolicy.policyId,
            policyHash: DailyMartDelegatedSpendingPolicy.policyHash,
            walletAddress: "maroo1DailyMartAgentWallet",
            amount: Decimal(100),
            asset: DailyMartDelegatedSpendingPolicy.asset,
            recipient: "maroo1DailyMartMerchant",
            anchoringReference: "maroo-anchor-pending-no-receipt-txhash",
            executionAttemptId: "meshkit-execution-attempt/v1:pay-confirmed-only-txhash-pending:auth-confirmed-only-txhash-pending:exec-confirmed-only-txhash-pending",
            paymentId: "pay-confirmed-only-txhash-pending",
            authorizationId: "auth-confirmed-only-txhash-pending",
            executionId: "exec-confirmed-only-txhash-pending",
            anchorTxHash: "0xanchorPendingNoReceiptTxHash",
            submittedAt: "2026-05-31T12:00:14Z"
        )
        let failedProof = try MeshChainProof(
            provider: "maroo",
            chainId: "maroo-testnet-1",
            network: "maroo-testnet",
            proofType: .paymentExecution,
            status: .failed,
            presentationState: .attemptedFailed,
            requestHash: requestHash,
            requestNonce: accepted.nonce,
            policyId: DailyMartDelegatedSpendingPolicy.policyId,
            policyHash: DailyMartDelegatedSpendingPolicy.policyHash,
            walletAddress: "maroo1DailyMartAgentWallet",
            amount: Decimal(100),
            asset: DailyMartDelegatedSpendingPolicy.asset,
            recipient: "maroo1DailyMartMerchant",
            anchoringReference: "maroo-anchor-failed-no-receipt-txhash",
            executionAttemptId: "meshkit-execution-attempt/v1:pay-confirmed-only-txhash-failed:auth-confirmed-only-txhash-failed:exec-confirmed-only-txhash-failed",
            paymentId: "pay-confirmed-only-txhash-failed",
            authorizationId: "auth-confirmed-only-txhash-failed",
            executionId: "exec-confirmed-only-txhash-failed",
            anchorTxHash: "0xanchorFailedNoReceiptTxHash",
            errorCode: "payment_execution_failed",
            errorMessage: "maroo testnet execution failed before confirmation",
            submittedAt: "2026-05-31T12:00:15Z"
        )

        let confirmedReceipt = try factory.makeAcceptedCallReceipt(
            receiptId: "DM-2026-0531-confirmed-only-txhash-confirmed",
            request: accepted,
            status: "purchased",
            baseResult: acceptedReceiptResult(orderId: "DM-2026-0531-confirmed-only-txhash-confirmed"),
            chainProof: confirmedProof,
            nonce: "DM-2026-0531-confirmed-only-txhash-confirmed-nonce",
            timestamp: "2026-05-31T12:00:16Z"
        )
        let pendingReceipt = try factory.makeAcceptedCallReceipt(
            receiptId: "DM-2026-0531-confirmed-only-txhash-pending",
            request: accepted,
            status: "pending",
            baseResult: acceptedReceiptResult(orderId: "DM-2026-0531-confirmed-only-txhash-pending")
                .merging(["txHash": "0xmustNotSurvivePendingReceipt"]) { current, _ in current },
            chainProof: pendingProof,
            nonce: "DM-2026-0531-confirmed-only-txhash-pending-nonce",
            timestamp: "2026-05-31T12:00:17Z"
        )
        let failedReceipt = try factory.makeAcceptedCallReceipt(
            receiptId: "DM-2026-0531-confirmed-only-txhash-failed",
            request: accepted,
            status: "failed",
            baseResult: acceptedReceiptResult(orderId: "DM-2026-0531-confirmed-only-txhash-failed")
                .merging(["txHash": "0xmustNotSurviveFailedReceipt"]) { current, _ in current },
            chainProof: failedProof,
            nonce: "DM-2026-0531-confirmed-only-txhash-failed-nonce",
            timestamp: "2026-05-31T12:00:18Z"
        )

        XCTAssertEqual(confirmedReceipt.result["chainStatus"], "confirmed")
        XCTAssertEqual(confirmedReceipt.result["presentationState"], "paid_complete")
        XCTAssertEqual(
            confirmedReceipt.result["executionAttemptId"],
            "meshkit-execution-attempt/v1:pay-confirmed-only-txhash-confirmed:auth-confirmed-only-txhash-confirmed:exec-confirmed-only-txhash-confirmed"
        )
        XCTAssertEqual(confirmedReceipt.result["txHash"], "0xokrwConfirmedOnlyReceiptTx")
        XCTAssertEqual(
            confirmedReceipt.result["explorerUrl"],
            "https://explorer-testnet.maroo.io/tx/0xokrwConfirmedOnlyReceiptTx"
        )

        XCTAssertEqual(pendingReceipt.result["chainStatus"], "pending")
        XCTAssertEqual(pendingReceipt.result["presentationState"], "submitted_not_final")
        XCTAssertEqual(
            pendingReceipt.result["executionAttemptId"],
            "meshkit-execution-attempt/v1:pay-confirmed-only-txhash-pending:auth-confirmed-only-txhash-pending:exec-confirmed-only-txhash-pending"
        )
        XCTAssertNil(pendingReceipt.result["txHash"])
        XCTAssertNil(pendingReceipt.result["explorerUrl"])

        XCTAssertEqual(failedReceipt.result["chainStatus"], "failed")
        XCTAssertEqual(failedReceipt.result["presentationState"], "attempted_failed")
        XCTAssertEqual(
            failedReceipt.result["executionAttemptId"],
            "meshkit-execution-attempt/v1:pay-confirmed-only-txhash-failed:auth-confirmed-only-txhash-failed:exec-confirmed-only-txhash-failed"
        )
        XCTAssertNil(failedReceipt.result["txHash"])
        XCTAssertNil(failedReceipt.result["explorerUrl"])
    }

    func testDailyMartReceiptSerializationPreservesBlockedByExternalChainEvidence() throws {
        let request = try signedDailyMartRequest(
            requestId: "ios-grocery-dailymart-blocked-external-chain-receipt",
            nonce: "nonce-dailymart-blocked-external-chain-receipt",
            timestamp: "2026-05-31T12:00:27Z"
        )
        let accepted = try dailyMartGuard().acceptForPreExecution(request, now: referenceDate)
        let providerIdentity = try MeshMarooTestnetChainProvider().identity
        let requestHash = try MeshRequestAnchorCanonicalization.signedRequestHash(for: accepted)
        let evidence = try MeshExternalChainBlockerEvidence(
            blockerType: .paymentConfirmationUnavailable,
            identity: providerIdentity,
            endpoint: providerIdentity.rpcEndpoint,
            operation: "executePayment",
            observedAt: "2026-05-31T12:00:28Z",
            message: "maroo testnet payment confirmation unavailable",
            requestHash: requestHash,
            requestNonce: accepted.nonce,
            anchoringReference: "maroo-anchor-blocked-external-chain-receipt",
            txHash: "0xanchorBlockedExternalChainReceipt"
        )
        let proof = try MeshChainProof(
            provider: providerIdentity.provider,
            chainId: providerIdentity.chainId,
            network: providerIdentity.network,
            proofType: .paymentExecution,
            status: .failed,
            presentationState: .attemptedFailed,
            requestHash: requestHash,
            requestNonce: accepted.nonce,
            policyId: DailyMartDelegatedSpendingPolicy.policyId,
            policyHash: DailyMartDelegatedSpendingPolicy.policyHash,
            walletAddress: "maroo1DailyMartAgentWallet",
            amount: Decimal(100),
            asset: DailyMartDelegatedSpendingPolicy.asset,
            recipient: "maroo1DailyMartMerchant",
            anchoringReference: "maroo-anchor-blocked-external-chain-receipt",
            executionAttemptId: "meshkit-execution-attempt/v1:pay-blocked-external-chain:auth-blocked-external-chain:exec-blocked-external-chain",
            paymentId: "pay-blocked-external-chain",
            authorizationId: "auth-blocked-external-chain",
            executionId: "exec-blocked-external-chain",
            anchorTxHash: "0xanchorBlockedExternalChainReceipt",
            errorCode: "payment_confirmation_unavailable",
            errorMessage: "maroo testnet payment confirmation unavailable",
            submittedAt: "2026-05-31T12:00:28Z",
            providerExtensions: [
                providerIdentity.provider: evidence.providerExtensionFields
            ]
        )

        let receipt = try DailyMartTargetReceiptFactory(
            signer: MeshReceiptSigner.ed25519(
                keyId: "dailymart-receipt-key",
                privateKey: receiptSigningKey
            )
        ).makeAcceptedCallReceipt(
            receiptId: "DM-2026-0531-blocked-external-chain-receipt",
            request: accepted,
            status: "failed",
            baseResult: acceptedReceiptResult(orderId: "DM-2026-0531-blocked-external-chain-receipt"),
            chainProof: proof,
            nonce: "DM-2026-0531-blocked-external-chain-receipt-nonce",
            timestamp: "2026-05-31T12:00:29Z"
        )
        let decodedReceipt = try MeshReceipt.decodedFromURLScheme(receipt.encodedForURLScheme())
        let decodedProof = try MeshReceiptChainProofSerializer.decodeProof(from: decodedReceipt.result)
        let ownershipProof = try MeshReceiptChainProofSerializer.targetOwnedProof(
            in: decodedReceipt,
            expectedTargetAppId: DailyMartTargetReceiptFactory.targetAppId,
            expectedTargetBundleId: DailyMartTargetReceiptFactory.targetBundleId,
            expectedRequest: accepted
        )

        XCTAssertEqual(decodedReceipt.status, "failed")
        XCTAssertEqual(decodedReceipt.result["chainProofType"], "payment_execution")
        XCTAssertEqual(decodedReceipt.result["chainStatus"], "failed")
        XCTAssertEqual(decodedReceipt.result["presentationState"], "attempted_failed")
        XCTAssertEqual(decodedReceipt.result["externalChainExitCondition"], "BlockedByExternalChain")
        XCTAssertEqual(decodedReceipt.result["externalChainBlockerType"], "payment_confirmation_unavailable")
        XCTAssertEqual(decodedReceipt.result["externalChainOperation"], "executePayment")
        XCTAssertEqual(decodedReceipt.result["externalChainObservedAt"], "2026-05-31T12:00:28Z")
        XCTAssertEqual(decodedReceipt.result["externalChainEndpoint"], "https://rpc-testnet.maroo.io")
        XCTAssertEqual(decodedReceipt.result["externalChainMessage"], "maroo testnet payment confirmation unavailable")
        XCTAssertEqual(decodedReceipt.result["requestHash"], requestHash.value)
        XCTAssertEqual(decodedReceipt.result["requestNonce"], accepted.nonce)
        XCTAssertEqual(decodedReceipt.result["anchoringReference"], "maroo-anchor-blocked-external-chain-receipt")
        XCTAssertEqual(decodedReceipt.result["anchorTxHash"], "0xanchorBlockedExternalChainReceipt")
        XCTAssertNil(decodedReceipt.result["txHash"])
        XCTAssertNil(decodedReceipt.result["explorerUrl"])
        XCTAssertEqual(decodedProof.providerExtensions["maroo"]?["exitCondition"], "BlockedByExternalChain")
        XCTAssertEqual(decodedProof.providerExtensions["maroo"]?["blockerType"], "payment_confirmation_unavailable")
        XCTAssertEqual(decodedProof.providerExtensions["maroo"]?["requestHash"], requestHash.value)
        XCTAssertEqual(decodedProof.providerExtensions["maroo"]?["requestNonce"], accepted.nonce)
        XCTAssertEqual(decodedProof.providerExtensions["maroo"]?["anchoringReference"], "maroo-anchor-blocked-external-chain-receipt")
        XCTAssertEqual(decodedProof.providerExtensions["maroo"]?["txHash"], "0xanchorBlockedExternalChainReceipt")
        XCTAssertEqual(ownershipProof.proof, decodedProof)
        XCTAssertNil(ownershipProof.transactionReference)
    }

    func testDailyMartReceiptCreationRejectsUnverifiedExecutionAttempt() throws {
        let request = try signedDailyMartRequest(
            requestId: "ios-grocery-dailymart-unverified-execution-attempt",
            nonce: "nonce-dailymart-unverified-execution-attempt",
            timestamp: "2026-05-31T12:00:19Z"
        )
        let accepted = try dailyMartGuard().acceptForPreExecution(request, now: referenceDate)
        let factory = DailyMartTargetReceiptFactory(
            signer: MeshReceiptSigner.ed25519(
                keyId: "dailymart-receipt-key",
                privateKey: receiptSigningKey
            )
        )
        let mismatchedProof = try MeshChainProof(
            provider: "maroo",
            chainId: "maroo-testnet-1",
            network: "maroo-testnet",
            proofType: .paymentExecution,
            status: .confirmed,
            presentationState: .paidComplete,
            requestHash: MeshPayloadHash(value: String(repeating: "0", count: 64)),
            requestNonce: accepted.nonce,
            policyId: DailyMartDelegatedSpendingPolicy.policyId,
            policyHash: DailyMartDelegatedSpendingPolicy.policyHash,
            walletAddress: "maroo1DailyMartAgentWallet",
            amount: Decimal(100),
            asset: DailyMartDelegatedSpendingPolicy.asset,
            recipient: "maroo1DailyMartMerchant",
            anchoringReference: "maroo-anchor-unverified-execution-attempt",
            anchorTxHash: "0xanchorUnverifiedExecutionAttempt",
            txHash: "0xokrwUnverifiedExecutionAttempt",
            explorerUrl: try XCTUnwrap(URL(string: "https://explorer-testnet.maroo.io/tx/0xokrwUnverifiedExecutionAttempt")),
            submittedAt: "2026-05-31T12:00:20Z",
            confirmedAt: "2026-05-31T12:00:21Z"
        )

        XCTAssertThrowsError(try factory.makeAcceptedCallReceipt(
            receiptId: "DM-2026-0531-unverified-execution-attempt",
            request: accepted,
            status: "purchased",
            baseResult: acceptedReceiptResult(orderId: "DM-2026-0531-unverified-execution-attempt"),
            chainProof: mismatchedProof,
            nonce: "DM-2026-0531-unverified-execution-attempt-nonce",
            timestamp: "2026-05-31T12:00:22Z"
        )) { error in
            XCTAssertEqual(error as? MeshKitValidationError, .invalidChainProof("requestHash"))
        }
    }

    func testDailyMartReceiptCreationRequiresApprovedPolicyVerificationForExecutionAttempt() throws {
        let request = try signedDailyMartRequest(
            requestId: "ios-grocery-dailymart-unapproved-execution-attempt",
            nonce: "nonce-dailymart-unapproved-execution-attempt",
            timestamp: "2026-05-31T12:00:23Z"
        )
        let accepted = try dailyMartGuard().acceptForPreExecution(request, now: referenceDate)
        let proof = try MeshChainProof(
            provider: "maroo",
            chainId: "maroo-testnet-1",
            network: "maroo-testnet",
            proofType: .requestAnchor,
            status: .pending,
            presentationState: .submittedNotFinal,
            requestHash: MeshRequestAnchorCanonicalization.signedRequestHash(for: accepted),
            requestNonce: accepted.nonce,
            policyId: DailyMartDelegatedSpendingPolicy.policyId,
            policyHash: DailyMartDelegatedSpendingPolicy.policyHash,
            walletAddress: "maroo1DailyMartAgentWallet",
            amount: Decimal(100),
            asset: DailyMartDelegatedSpendingPolicy.asset,
            recipient: "maroo1DailyMartMerchant",
            anchoringReference: "maroo-anchor-unapproved-execution-attempt",
            anchorTxHash: "0xanchorUnapprovedExecutionAttempt",
            submittedAt: "2026-05-31T12:00:24Z"
        )

        XCTAssertThrowsError(try DailyMartTargetReceiptFactory(
            signer: MeshReceiptSigner.ed25519(
                keyId: "dailymart-receipt-key",
                privateKey: receiptSigningKey
            )
        ).makeAcceptedCallReceipt(
            receiptId: "DM-2026-0531-unapproved-execution-attempt",
            request: accepted,
            status: "pending",
            baseResult: [
                "order_id": "DM-2026-0531-unapproved-execution-attempt",
                "total_krw": "100",
                "payment_asset": DailyMartDelegatedSpendingPolicy.asset,
                "policy_verification": MeshDelegatedSpendingPolicyVerificationStatus.denied.rawValue
            ],
            chainProof: proof,
            nonce: "DM-2026-0531-unapproved-execution-attempt-nonce",
            timestamp: "2026-05-31T12:00:25Z"
        )) { error in
            XCTAssertEqual(error as? MeshKitValidationError, .invalidPaymentExecution("policyVerification"))
        }
    }

    private func dailyMartGuard() throws -> DailyMartPreExecutionMCPGuard {
        try DailyMartPreExecutionMCPGuard(
            expectedHermesAgentSigner: MeshSenderTrust(
                callerAppId: "app.hermes-chat",
                callerBundleId: "ai.meshkit.sample.hermeschat",
                teamId: "DEVTEAMID",
                requestSigningAlgorithm: "Ed25519",
                requestSigningKeyId: "demo-key",
                publicKey: hermesSigningKey.publicKey.rawRepresentation.base64EncodedString()
            ),
            freshnessStore: DailyMartRequestNonceFreshnessStore(
                expirationValidator: DailyMartRequestNonceExpirationValidator(maxAgeSeconds: 300)
            )
        )
    }

    private func acceptedReceiptResult(orderId: String) -> [String: String] {
        [
            "order_id": orderId,
            "total_krw": "100",
            "payment_asset": DailyMartDelegatedSpendingPolicy.asset,
            "policy_verification": MeshDelegatedSpendingPolicyVerificationStatus.approved.rawValue
        ]
    }

    private func paymentExecutionRequest(
        for request: MeshRequest,
        executionId: String,
        paymentId: String,
        authorizationId: String
    ) throws -> MeshPaymentExecutionRequest {
        let providerIdentity = try MeshMarooTestnetChainProvider().identity
        let executionRequest = try DailyMartPreExecutionWalletPolicyGuard().makeExecutionRequest(
            from: request,
            executionKind: .payment,
            executionId: executionId
        )
        let metadata = executionRequest.requestAnchorMetadata
        let requestAnchor = try MeshRequestAnchor(
            metadata: metadata,
            payload: MeshRequestAnchorPayload(
                metadata: metadata,
                policyId: DailyMartDelegatedSpendingPolicy.policyId,
                policyHash: DailyMartDelegatedSpendingPolicy.policyHash
            ),
            identifier: MeshRequestAnchorIdentifier(
                identity: providerIdentity,
                anchorId: MeshRequestAnchorCanonicalization.anchoringReference(
                    for: metadata,
                    providerIdentity: providerIdentity
                ).anchorId,
                transactionHash: "0xanchorDailyMartConfirmedExecutionReceipt"
            ),
            status: .confirmed,
            submittedAt: "2026-05-31T12:00:05Z",
            observedAt: "2026-05-31T12:00:06Z"
        )
        let authorizationDecision = try MeshAgentWalletAuthorizationDecision(
            authorizationId: authorizationId,
            walletIdentity: MeshAgentWalletIdentity(
                walletId: "wallet-hermes-dailymart-okrw-v1",
                agentId: DailyMartDelegatedSpendingPolicy.principalId,
                walletAddress: "maroo1DailyMartAgentWallet",
                providerMetadata: MeshAgentWalletProviderMetadata(
                    chainProviderIdentity: providerIdentity,
                    adapterId: "maroo-testnet-agent-wallet-adapter"
                ),
                signingBoundary: .providerSubmission
            ),
            executionRequest: executionRequest,
            status: .approved,
            approvedAmount: executionRequest.amount,
            decidedAt: "2026-05-31T12:00:06Z"
        )
        return try MeshPaymentExecutionRequest(
            paymentId: paymentId,
            authorizationDecision: authorizationDecision,
            requestAnchor: requestAnchor,
            requestedAt: "2026-05-31T12:00:06Z"
        )
    }

    private func signedDailyMartRequest(
        requestId: String = "ios-grocery-accepted-ac1",
        nonce: String = "nonce-dailymart-accepted-ac1",
        timestamp: String = "2026-05-31T12:00:00Z",
        budgetKRW: String = "100"
    ) throws -> MeshRequest {
        let unsigned = MeshRequest(
            requestId: requestId,
            caller: MeshIdentity(
                appId: "app.hermes-chat",
                installId: "ios-device",
                bundleId: "ai.meshkit.sample.hermeschat",
                publicKeyId: "demo-key"
            ),
            target: MeshCapability(
                targetBundleId: DailyMartTargetReceiptFactory.targetBundleId,
                capabilityId: DailyMartDelegatedSpendingPolicy.capabilityScope,
                version: "1.0"
            ),
            payload: [
                "items": "laundry_detergent:1,toilet_paper:2,bottled_water_2l:6",
                "address_ref": "home.saved",
                "budget_krw": budgetKRW,
                "merchantScope": DailyMartDelegatedSpendingPolicy.merchantScope,
                "capabilityScope": DailyMartDelegatedSpendingPolicy.capabilityScope,
                "consentGrantId": DailyMartDelegatedSpendingPolicy.consentGrantId,
                "walletSessionId": DailyMartDelegatedSpendingPolicy.walletSessionId,
                "principalId": DailyMartDelegatedSpendingPolicy.principalId,
                "policyId": DailyMartDelegatedSpendingPolicy.policyId,
                "policyHash": DailyMartDelegatedSpendingPolicy.policyHash.value
            ],
            nonce: nonce,
            timestamp: timestamp,
            signature: MeshSignature(algorithm: "Ed25519", keyId: "demo-key", value: "")
        )
        let signature = try hermesSigningKey.signature(for: unsigned.signingInputData()).base64EncodedString()
        return MeshRequest(
            requestId: unsigned.requestId,
            caller: unsigned.caller,
            target: unsigned.target,
            payload: unsigned.payload,
            payloadHash: unsigned.payloadHash,
            nonce: unsigned.nonce,
            timestamp: unsigned.timestamp,
            signature: MeshSignature(algorithm: "Ed25519", keyId: "demo-key", value: signature)
        )
    }
}
