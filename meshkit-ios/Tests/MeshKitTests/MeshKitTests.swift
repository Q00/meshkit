import CryptoKit
import XCTest
@testable import MeshKit

final class MeshKitTests: XCTestCase {
    func testSampleGraphFindsNotesAppend() {
        let capability = OpenCapabilityGraph.mintNotesSample.findCapability("notes.append_note")
        XCTAssertEqual(capability?.risk, "write:user_content")
        XCTAssertEqual(capability?.consent, "per_invocation")
        XCTAssertEqual(capability?.inputSchema, ["note_ref", "text"])
    }

    func testMeshRequestCarriesPayloadHashAndRoundTripsThroughURLScheme() throws {
        let request = sampleRequest(nonce: "nonce-roundtrip")
        XCTAssertEqual(request.payloadHash.algorithm, "sha256")
        try MeshTarget.verifyPayloadHash(request)

        let encoded = try request.encodedForURLScheme()
        let decoded = try MeshRequest.decodedFromURLScheme(encoded)
        XCTAssertEqual(decoded, request)
    }

    func testValidatePublicMeshAcceptsTrustedConsentedRequest() throws {
        let cache = MeshReplayCache()
        let request = sampleRequest(nonce: "nonce-public-mesh")
        let audit = try MeshTarget.validatePublicMesh(
            request: request,
            policy: samplePolicy,
            trust: sampleTrust,
            invocationPolicy: MeshInvocationPolicy(
                risk: "write:user_content",
                consent: "per_invocation",
                userApproved: true,
                registrySignatureVerified: true
            ),
            observedCallerBundleId: "ai.meshkit.sample.hermeschat",
            replayCache: cache,
            maxAgeSeconds: 60
        )
        XCTAssertEqual(audit.status, "accepted")
        XCTAssertEqual(audit.capabilityId, "notes.append_note")
    }

    func testReplayIsRejected() throws {
        let cache = MeshReplayCache()
        let request = sampleRequest(nonce: "nonce-replay")
        try MeshTarget.validateSecure(
            request: request,
            policy: samplePolicy,
            trust: sampleTrust,
            observedCallerBundleId: "ai.meshkit.sample.hermeschat",
            replayCache: cache,
            maxAgeSeconds: 60
        )
        XCTAssertThrowsError(try MeshTarget.validateSecure(
            request: request,
            policy: samplePolicy,
            trust: sampleTrust,
            observedCallerBundleId: "ai.meshkit.sample.hermeschat",
            replayCache: cache,
            maxAgeSeconds: 60
        ))
    }

    func testPayloadTamperIsRejected() throws {
        let original = sampleRequest(nonce: "nonce-tamper")
        let tampered = MeshRequest(
            requestId: original.requestId,
            caller: original.caller,
            target: original.target,
            payload: ["note_ref": "ios:mint:demo", "text": "tampered"],
            payloadHash: original.payloadHash,
            nonce: original.nonce,
            timestamp: original.timestamp,
            signature: original.signature
        )
        XCTAssertThrowsError(try MeshTarget.verifyPayloadHash(tampered))
    }

    func testInvalidRequestSignatureIsRejected() throws {
        let cache = MeshReplayCache()
        let request = sampleRequest(nonce: "nonce-bad-signature", signatureValue: Data(repeating: 0, count: 64).base64EncodedString())
        XCTAssertThrowsError(try MeshTarget.validatePublicMesh(
            request: request,
            policy: samplePolicy,
            trust: sampleTrust,
            invocationPolicy: MeshInvocationPolicy(
                risk: "write:user_content",
                consent: "per_invocation",
                userApproved: true,
                registrySignatureVerified: true
            ),
            observedCallerBundleId: "ai.meshkit.sample.hermeschat",
            replayCache: cache,
            maxAgeSeconds: 60
        )) { error in
            XCTAssertEqual(error as? MeshKitValidationError, .signatureMismatch("invalid request signature"))
        }
    }

    func testObservedCallerBundleMismatchIsRejectedBeforeExecution() throws {
        let cache = MeshReplayCache()
        let request = sampleRequest(nonce: "nonce-evil-caller")
        XCTAssertThrowsError(try MeshTarget.validateSecure(
            request: request,
            policy: samplePolicy,
            trust: sampleTrust,
            observedCallerBundleId: "ai.meshkit.sample.evilcaller",
            replayCache: cache,
            maxAgeSeconds: 60
        )) { error in
            XCTAssertEqual(error as? MeshKitValidationError, .observedCallerBundleMismatch)
        }
    }

    func testDailyMartBudgetExceedIsRejected() throws {
        let cache = MeshReplayCache()
        let request = dailyMartRequest(nonce: "nonce-dailymart-overbudget", budget: "500")
        XCTAssertThrowsError(try MeshTarget.validatePublicMesh(
            request: request,
            policy: MeshTargetPolicy(
                allowedCallerAppId: "app.hermes-chat",
                targetBundleId: "ai.meshkit.sample.dailymart",
                capabilityId: "grocery.purchase_essentials"
            ),
            trust: sampleTrust,
            invocationPolicy: MeshInvocationPolicy(
                risk: "spend:money",
                consent: "budgeted_per_invocation",
                userApproved: true,
                registrySignatureVerified: true,
                approvedBudget: Decimal(100)
            ),
            observedCallerBundleId: "ai.meshkit.sample.hermeschat",
            replayCache: cache,
            maxAgeSeconds: 60
        )) { error in
            XCTAssertEqual(error as? MeshKitValidationError, .budgetExceeded)
        }
    }

    func testDailyMartGraphAndBudgetedSpendValidation() throws {
        let capability = OpenCapabilityGraph.dailyMartSample.findCapability("grocery.purchase_essentials")
        XCTAssertEqual(capability?.risk, "spend:money")
        XCTAssertEqual(capability?.consent, "budgeted_per_invocation")
        XCTAssertEqual(capability?.inputSchema, ["items", "address_ref", "budget_krw"])

        let cache = MeshReplayCache()
        let request = dailyMartRequest(nonce: "nonce-dailymart")
        let audit = try MeshTarget.validatePublicMesh(
            request: request,
            policy: MeshTargetPolicy(
                allowedCallerAppId: "app.hermes-chat",
                targetBundleId: "ai.meshkit.sample.dailymart",
                capabilityId: "grocery.purchase_essentials"
            ),
            trust: sampleTrust,
            invocationPolicy: MeshInvocationPolicy(
                risk: "spend:money",
                consent: "budgeted_per_invocation",
                userApproved: true,
                registrySignatureVerified: true,
                approvedBudget: Decimal(100)
            ),
            observedCallerBundleId: "ai.meshkit.sample.hermeschat",
            replayCache: cache,
            maxAgeSeconds: 60
        )
        XCTAssertEqual(audit.capabilityId, "grocery.purchase_essentials")
        XCTAssertEqual(audit.risk, "spend:money")
    }


    func testProductionTargetOneLineValidatorKeepsSecureDefaultsEasyToAdopt() throws {
        let target = try MeshProductionTarget(
            policy: samplePolicy,
            trust: sampleTrust,
            invocationPolicy: MeshInvocationPolicy(
                risk: "write:user_content",
                consent: "per_invocation",
                userApproved: true,
                registrySignatureVerified: true
            ),
            replayCache: MeshReplayCache()
        )

        let audit = try target.validate(
            sampleRequest(nonce: "nonce-production-target"),
            observedCallerBundleId: "ai.meshkit.sample.hermeschat"
        )

        XCTAssertEqual(audit.status, "accepted")
        XCTAssertEqual(audit.capabilityId, "notes.append_note")
    }

    func testSignedRequestBuilderCreatesVerifiableRequestWithoutManualHashOrSignatureGlue() throws {
        let signer = MeshRequestSigner.ed25519(keyId: "demo-key", privateKey: Self.signingKey)
        let request = try MeshSignedRequestBuilder(
            caller: MeshIdentity(
                appId: "app.hermes-chat",
                installId: "ios-sim",
                bundleId: "ai.meshkit.sample.hermeschat",
                publicKeyId: "demo-key"
            ),
            target: MeshCapability(
                targetBundleId: "ai.meshkit.sample.mintnotes",
                capabilityId: "notes.append_note",
                version: "1.0"
            ),
            signer: signer
        ).makeRequest(
            requestId: "ios-builder-test-001",
            payload: ["note_ref": "ios:mint:demo", "text": "Easy secure adoption."],
            nonce: "nonce-builder",
            timestamp: ISO8601DateFormatter().string(from: Date())
        )

        try MeshTarget.verifyPayloadHash(request)
        try MeshTarget.verifyRequiredSignature(request, trust: sampleTrust)
    }

    func testProductionTargetRejectsIncompleteTrustAtConstruction() throws {
        let unsignedTrust = MeshSenderTrust(
            callerAppId: "app.hermes-chat",
            callerBundleId: "ai.meshkit.sample.hermeschat",
            teamId: "DEVTEAMID"
        )

        XCTAssertThrowsError(try MeshProductionTarget(
            policy: samplePolicy,
            trust: unsignedTrust,
            invocationPolicy: MeshInvocationPolicy(
                risk: "write:user_content",
                consent: "per_invocation",
                userApproved: true,
                registrySignatureVerified: true
            ),
            replayCache: MeshReplayCache()
        )) { error in
            XCTAssertEqual(error as? MeshKitValidationError, .signatureRequired)
        }
    }

    func testProductionTargetRejectsMismatchedTrustAtConstruction() throws {
        let mismatchedTrust = MeshSenderTrust(
            callerAppId: "app.evil",
            callerBundleId: "ai.meshkit.sample.hermeschat",
            teamId: "DEVTEAMID",
            requestSigningAlgorithm: "Ed25519",
            requestSigningKeyId: "demo-key",
            publicKey: Self.signingKey.publicKey.rawRepresentation.base64EncodedString()
        )

        XCTAssertThrowsError(try MeshProductionTarget(
            policy: samplePolicy,
            trust: mismatchedTrust,
            invocationPolicy: MeshInvocationPolicy(
                risk: "write:user_content",
                consent: "per_invocation",
                userApproved: true,
                registrySignatureVerified: true
            ),
            replayCache: MeshReplayCache()
        )) { error in
            XCTAssertEqual(error as? MeshKitValidationError, .signatureMismatch("production target trust callerAppId must match policy allowedCallerAppId"))
        }
    }

    func testProductionSpendTargetRequiresApprovedBudgetAtConstruction() throws {
        XCTAssertThrowsError(try MeshProductionTarget(
            policy: MeshTargetPolicy(
                allowedCallerAppId: "app.hermes-chat",
                targetBundleId: "ai.meshkit.sample.dailymart",
                capabilityId: "grocery.purchase_essentials"
            ),
            trust: sampleTrust,
            invocationPolicy: MeshInvocationPolicy(
                risk: "spend:money",
                consent: "budgeted_per_invocation",
                userApproved: true,
                registrySignatureVerified: true
            ),
            replayCache: MeshReplayCache()
        )) { error in
            XCTAssertEqual(error as? MeshKitValidationError, .signatureMismatch("spend:money production targets require an explicit approved budget"))
        }
    }

    func testProductionTargetRejectsDisabledInvocationPolicyAsKillSwitch() throws {
        XCTAssertThrowsError(try MeshProductionTarget(
            policy: samplePolicy,
            trust: sampleTrust,
            invocationPolicy: MeshInvocationPolicy(
                risk: "write:user_content",
                consent: "per_invocation",
                userApproved: true,
                registrySignatureVerified: true,
                productionEnabled: false,
                killSwitchReason: "incident-response"
            ),
            replayCache: MeshReplayCache()
        )) { error in
            XCTAssertEqual(error as? MeshKitValidationError, .productionDisabled("incident-response"))
        }
    }

    func testSignedRequestBuilderRejectsCallerPublicKeyIdMismatch() throws {
        let signer = MeshRequestSigner.ed25519(keyId: "meshkit-prod-key", privateKey: Self.signingKey)

        XCTAssertThrowsError(try MeshSignedRequestBuilder(
            caller: MeshIdentity(
                appId: "app.hermes-chat",
                installId: "ios-sim",
                bundleId: "ai.meshkit.sample.hermeschat",
                publicKeyId: "different-key"
            ),
            target: MeshCapability(
                targetBundleId: "ai.meshkit.sample.mintnotes",
                capabilityId: "notes.append_note",
                version: "1.0"
            ),
            signer: signer
        ).makeRequest(
            requestId: "ios-builder-mismatch-001",
            payload: ["note_ref": "ios:mint:demo", "text": "Key ids must match."],
            nonce: "nonce-builder-mismatch",
            timestamp: ISO8601DateFormatter().string(from: Date())
        )) { error in
            XCTAssertEqual(error as? MeshKitValidationError, .signatureMismatch("caller publicKeyId must match signer keyId"))
        }
    }

    func testSecurityEnvelopeRejectsDelimiterInjectionInSignedFields() throws {
        let request = MeshRequest(
            requestId: "ios-test-001\nforged",
            caller: MeshIdentity(
                appId: "app.hermes-chat",
                installId: "ios-sim",
                bundleId: "ai.meshkit.sample.hermeschat",
                publicKeyId: "demo-key"
            ),
            target: MeshCapability(
                targetBundleId: "ai.meshkit.sample.mintnotes",
                capabilityId: "notes.append_note",
                version: "1.0"
            ),
            payload: ["note_ref": "ios:mint:demo", "text": "Ship MeshKit iOS demo with OCG discovery."],
            nonce: "nonce-delimiter",
            timestamp: ISO8601DateFormatter().string(from: Date()),
            signature: MeshSignature(algorithm: "Ed25519", keyId: "demo-key", value: "")
        )

        XCTAssertThrowsError(try MeshTarget.validateRequestEnvelope(request)) { error in
            XCTAssertEqual(error as? MeshKitValidationError, .invalidSecurityField("requestId"))
        }
    }

    func testSecurityEnvelopeRejectsMalformedPayloadHashBeforeExecution() throws {
        let request = MeshRequest(
            requestId: "ios-test-001",
            caller: MeshIdentity(
                appId: "app.hermes-chat",
                installId: "ios-sim",
                bundleId: "ai.meshkit.sample.hermeschat",
                publicKeyId: "demo-key"
            ),
            target: MeshCapability(
                targetBundleId: "ai.meshkit.sample.mintnotes",
                capabilityId: "notes.append_note",
                version: "1.0"
            ),
            payload: ["note_ref": "ios:mint:demo", "text": "Ship MeshKit iOS demo with OCG discovery."],
            payloadHash: MeshPayloadHash(value: "not-a-sha256"),
            nonce: "nonce-bad-hash-shape",
            timestamp: ISO8601DateFormatter().string(from: Date()),
            signature: MeshSignature(algorithm: "Ed25519", keyId: "demo-key", value: "")
        )

        XCTAssertThrowsError(try MeshTarget.validateRequestEnvelope(request)) { error in
            XCTAssertEqual(error as? MeshKitValidationError, .invalidSecurityField("payloadHash.value"))
        }
    }

    func testInvokeURLRejectsMalformedSchemeWithoutCrashing() throws {
        XCTAssertThrowsError(try MeshURLRouter.invokeURL(scheme: " not a url ", request: sampleRequest(nonce: "nonce-bad-url")))
    }

    func testSignedTargetReceiptVerifiesAndCorrelatesToPendingRequest() throws {
        let targetKey = Curve25519.Signing.PrivateKey()
        let request = dailyMartRequest(nonce: "nonce-receipt-correlation")
        let receipt = try MeshReceiptSigner.ed25519(
            keyId: "dailymart-receipt-key",
            privateKey: targetKey
        ).makeReceipt(
            receiptId: "receipt-001",
            request: request,
            targetAppId: "app.dailymart",
            targetBundleId: "ai.meshkit.sample.dailymart",
            status: "purchased",
            result: ["order_id": "DM-2026-0509-002", "total_krw": "100"],
            nonce: "receipt-nonce-001",
            timestamp: ISO8601DateFormatter().string(from: Date())
        )

        let store = MeshPendingReceiptStore()
        let token = store.register(request: request, capabilityId: "grocery.purchase_essentials")
        XCTAssertEqual(token, request.requestId)

        let verified = try store.consumeVerified(
            receipt,
            expectedToken: token,
            trust: MeshReceiptTrust(
                targetAppId: "app.dailymart",
                targetBundleId: "ai.meshkit.sample.dailymart",
                receiptSigningAlgorithm: "Ed25519",
                receiptSigningKeyId: "dailymart-receipt-key",
                publicKey: targetKey.publicKey.rawRepresentation.base64EncodedString()
            ),
            maxAgeSeconds: 60
        )

        XCTAssertEqual(verified.status, "purchased")
        XCTAssertEqual(verified.result["order_id"], "DM-2026-0509-002")
        XCTAssertThrowsError(try store.consumeVerified(
            receipt,
            expectedToken: token,
            trust: MeshReceiptTrust(
                targetAppId: "app.dailymart",
                targetBundleId: "ai.meshkit.sample.dailymart",
                receiptSigningAlgorithm: "Ed25519",
                receiptSigningKeyId: "dailymart-receipt-key",
                publicKey: targetKey.publicKey.rawRepresentation.base64EncodedString()
            ),
            maxAgeSeconds: 60
        )) { error in
            XCTAssertEqual(error as? MeshKitValidationError, .replayDetected(token))
        }
    }

    func testSignedTargetReceiptRejectsTamperedResultAndWrongCorrelationToken() throws {
        let targetKey = Curve25519.Signing.PrivateKey()
        let request = dailyMartRequest(nonce: "nonce-receipt-tamper")
        let receipt = try MeshReceiptSigner.ed25519(
            keyId: "dailymart-receipt-key",
            privateKey: targetKey
        ).makeReceipt(
            receiptId: "receipt-002",
            request: request,
            targetAppId: "app.dailymart",
            targetBundleId: "ai.meshkit.sample.dailymart",
            status: "purchased",
            result: ["order_id": "DM-2026-0509-002", "total_krw": "100"],
            nonce: "receipt-nonce-002",
            timestamp: ISO8601DateFormatter().string(from: Date())
        )
        let tampered = MeshReceipt(
            receiptId: receipt.receiptId,
            requestId: receipt.requestId,
            capabilityId: receipt.capabilityId,
            targetAppId: receipt.targetAppId,
            targetBundleId: receipt.targetBundleId,
            requestPayloadHash: receipt.requestPayloadHash,
            status: receipt.status,
            result: ["order_id": "DM-ATTACK", "total_krw": "1"],
            nonce: receipt.nonce,
            timestamp: receipt.timestamp,
            signature: receipt.signature
        )
        let trust = MeshReceiptTrust(
            targetAppId: "app.dailymart",
            targetBundleId: "ai.meshkit.sample.dailymart",
            receiptSigningAlgorithm: "Ed25519",
            receiptSigningKeyId: "dailymart-receipt-key",
            publicKey: targetKey.publicKey.rawRepresentation.base64EncodedString()
        )

        XCTAssertThrowsError(try MeshReceiptVerifier.verify(tampered, trust: trust, maxAgeSeconds: 60)) { error in
            XCTAssertEqual(error as? MeshKitValidationError, .signatureMismatch("invalid receipt signature"))
        }

        let store = MeshPendingReceiptStore()
        _ = store.register(request: request, capabilityId: "grocery.purchase_essentials")
        XCTAssertThrowsError(try store.consumeVerified(receipt, expectedToken: "wrong-token", trust: trust, maxAgeSeconds: 60)) { error in
            XCTAssertEqual(error as? MeshKitValidationError, .receiptCorrelationMismatch)
        }
    }

    private var samplePolicy: MeshTargetPolicy {
        MeshTargetPolicy(
            allowedCallerAppId: "app.hermes-chat",
            targetBundleId: "ai.meshkit.sample.mintnotes",
            capabilityId: "notes.append_note"
        )
    }

    private static let signingKey = Curve25519.Signing.PrivateKey()

    private var sampleTrust: MeshSenderTrust {
        MeshSenderTrust(
            callerAppId: "app.hermes-chat",
            callerBundleId: "ai.meshkit.sample.hermeschat",
            teamId: "DEVTEAMID",
            requestSigningAlgorithm: "Ed25519",
            requestSigningKeyId: "demo-key",
            publicKey: Self.signingKey.publicKey.rawRepresentation.base64EncodedString()
        )
    }

    private func signed(_ request: MeshRequest) -> MeshRequest {
        let signature = try! Self.signingKey.signature(for: request.signingInputData()).base64EncodedString()
        return MeshRequest(
            requestId: request.requestId,
            caller: request.caller,
            target: request.target,
            payload: request.payload,
            payloadHash: request.payloadHash,
            nonce: request.nonce,
            timestamp: request.timestamp,
            signature: MeshSignature(algorithm: "Ed25519", keyId: "demo-key", value: signature)
        )
    }

    private func sampleRequest(nonce: String, signatureValue: String? = nil) -> MeshRequest {
        let unsigned = MeshRequest(
            requestId: "ios-test-001",
            caller: MeshIdentity(
                appId: "app.hermes-chat",
                installId: "ios-sim",
                bundleId: "ai.meshkit.sample.hermeschat",
                publicKeyId: "demo-key"
            ),
            target: MeshCapability(
                targetBundleId: "ai.meshkit.sample.mintnotes",
                capabilityId: "notes.append_note",
                version: "1.0"
            ),
            payload: ["note_ref": "ios:mint:demo", "text": "Ship MeshKit iOS demo with OCG discovery."],
            nonce: nonce,
            timestamp: ISO8601DateFormatter().string(from: Date()),
            signature: MeshSignature(algorithm: "Ed25519", keyId: "demo-key", value: signatureValue ?? "")
        )
        if signatureValue != nil { return unsigned }
        return signed(unsigned)
    }

    private func dailyMartRequest(nonce: String, budget: String = "100") -> MeshRequest {
        let unsigned = MeshRequest(
            requestId: "ios-grocery-test-001",
            caller: MeshIdentity(
                appId: "app.hermes-chat",
                installId: "ios-sim",
                bundleId: "ai.meshkit.sample.hermeschat",
                publicKeyId: "demo-key"
            ),
            target: MeshCapability(
                targetBundleId: "ai.meshkit.sample.dailymart",
                capabilityId: "grocery.purchase_essentials",
                version: "1.0"
            ),
            payload: [
                "items": "laundry_detergent:1,toilet_paper:2,bottled_water_2l:6",
                "address_ref": "home.saved",
                "budget_krw": budget
            ],
            nonce: nonce,
            timestamp: ISO8601DateFormatter().string(from: Date()),
            signature: MeshSignature(algorithm: "Ed25519", keyId: "demo-key", value: "")
        )
        return signed(unsigned)
    }
}
