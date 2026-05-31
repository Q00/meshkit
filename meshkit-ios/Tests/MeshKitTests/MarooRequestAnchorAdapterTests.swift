import CryptoKit
import XCTest
#if canImport(FoundationNetworking)
@preconcurrency import FoundationNetworking
#endif
@testable import MeshKit

final class MarooRequestAnchorAdapterTests: XCTestCase {
    private static let signingKey = Curve25519.Signing.PrivateKey()

    func testMarooAdapterExposesProviderNeutralSignedMCPRequestAnchoringCapabilityMetadata() throws {
        let adapter = try MeshMarooTestnetRequestAnchorAdapter(status: .pending)

        let metadata = try adapter.capabilityMetadata

        XCTAssertEqual(metadata.version, MeshRequestAnchorProviderCapabilityMetadata.version)
        XCTAssertEqual(metadata.adapterId, MeshMarooTestnetRequestAnchorAdapter.adapterId)
        XCTAssertEqual(metadata.providerMetadata.provider, "maroo")
        XCTAssertEqual(metadata.providerMetadata.network, "maroo-testnet")
        XCTAssertEqual(metadata.providerMetadata.chainId, "maroo-testnet-1")
        XCTAssertEqual(metadata.endpointConfiguration.rpcEndpoint.absoluteString, "https://rpc-testnet.maroo.io")
        XCTAssertEqual(metadata.endpointConfiguration.explorerBaseURL?.absoluteString, "https://explorer-testnet.maroo.io")
        XCTAssertEqual(metadata.providerInputVersion, MeshRequestAnchorProviderInput.version)
        XCTAssertTrue(metadata.supports(.anchorSignedRequest))
        XCTAssertTrue(metadata.supports(.constructExplorerURL))
        XCTAssertTrue(metadata.supports(.createRequestAnchorReference))
        XCTAssertTrue(metadata.supports(.lookupRequestAnchorStatus))
        XCTAssertTrue(metadata.supports(.resolveRequestAnchorHash))
        XCTAssertFalse(metadata.supports(.lookupProof))
        XCTAssertEqual(
            metadata.requiredAnchoringCapabilities,
            MeshRequestAnchorProviderCapabilityMetadata.requiredAnchoringCapabilities
        )
        XCTAssertNoThrow(try metadata.validate())
    }

    func testMarooAdapterRejectsCapabilityMetadataThatCannotAnchorSignedMCPRequests() throws {
        XCTAssertThrowsError(try MeshMarooTestnetRequestAnchorAdapter(
            capabilities: [.anchorSignedRequest, .loadProviderConfiguration]
        )) { error in
            XCTAssertEqual(error as? MeshKitValidationError, .unsupportedCapability)
        }

        XCTAssertThrowsError(try MeshRequestAnchorProviderCapabilityMetadata(
            adapterId: MeshMarooTestnetRequestAnchorAdapter.adapterId,
            providerIdentity: try MeshMarooTestnetChainProvider().identity,
            capabilities: [.anchorSignedRequest, .constructExplorerURL],
            providerInputVersion: "meshkit-request-anchor-provider-input/v0"
        )) { error in
            XCTAssertEqual(error as? MeshKitValidationError, .invalidChainProviderIdentity("providerInputVersion"))
        }
    }

    func testMarooRequestAnchorAdapterInvokesSubmissionBoundaryWithCanonicalSignedMCPRequest() async throws {
        let client = CapturingMarooRequestAnchorSubmissionClient()
        let adapter = try MeshMarooTestnetRequestAnchorAdapter(submissionClient: client)
        let request = signedDailyMartRequest(
            requestId: "ios-grocery-maroo-boundary-001",
            nonce: "nonce-maroo-boundary-001"
        )
        let payload = try MeshRequestAnchorPayload(
            metadata: MeshSignedRequestAnchorMetadata(request: request),
            policyId: "policy-hermes-dailymart-okrw-v1",
            policyHash: MeshPayloadHash(value: String(repeating: "e", count: 64))
        )

        let anchor = try await adapter.anchorSignedRequest(
            payload: payload,
            submittedAt: "2026-05-31T00:00:03Z"
        )
        let capturedInputs = await client.snapshotInputs()
        let capturedInput = try XCTUnwrap(capturedInputs.first)

        XCTAssertEqual(capturedInputs.count, 1)
        XCTAssertEqual(capturedInput.providerMetadata, adapter.providerMetadata)
        XCTAssertEqual(capturedInput.payload, payload)
        XCTAssertEqual(capturedInput.submittedAt, "2026-05-31T00:00:03Z")
        XCTAssertTrue(capturedInput.canonicalString.contains("requestId=ios-grocery-maroo-boundary-001"))
        XCTAssertTrue(capturedInput.canonicalString.contains("requestNonce=nonce-maroo-boundary-001"))
        XCTAssertTrue(capturedInput.canonicalString.contains("signatureAlgorithm=Ed25519"))
        XCTAssertTrue(capturedInput.canonicalString.contains("signatureKeyId=demo-key"))
        XCTAssertTrue(capturedInput.canonicalString.contains("signatureValue=\(request.signature.value)"))
        XCTAssertTrue(capturedInput.canonicalString.contains("policyId=policy-hermes-dailymart-okrw-v1"))
        XCTAssertTrue(capturedInput.canonicalString.contains("policyHashValue=\(String(repeating: "e", count: 64))"))
        XCTAssertEqual(anchor.identifier.anchorId, "maroo-captured-ios-grocery-maroo-boundary-001")
        XCTAssertEqual(anchor.identifier.transactionHash, "0x" + String(repeating: "1", count: 64))
        XCTAssertEqual(anchor.status, .submitted)
        XCTAssertEqual(anchor.payload, payload)
        XCTAssertEqual(anchor.metadata.signedRequestHash, payload.metadata.signedRequestHash)
    }

    func testMarooRequestAnchorAdapterRejectsSubmissionBoundaryProviderMismatch() async throws {
        let wrongProvider = try MeshChainProviderMetadata(
            provider: "other-provider",
            network: "other-testnet",
            chainId: "other-testnet-1"
        )
        let client = CapturingMarooRequestAnchorSubmissionClient(providerMetadataOverride: wrongProvider)
        let adapter = try MeshMarooTestnetRequestAnchorAdapter(submissionClient: client)
        let payload = try anchorPayload(
            requestId: "ios-grocery-maroo-boundary-mismatch",
            nonce: "nonce-maroo-boundary-mismatch"
        )

        do {
            _ = try await adapter.anchorSignedRequest(
                payload: payload,
                submittedAt: "2026-05-31T00:00:03Z"
            )
            XCTFail("Expected maroo anchor adapter to reject a response from the wrong provider boundary")
        } catch {
            XCTAssertEqual(error as? MeshKitValidationError, .signatureMismatch("request anchor provider metadata mismatch"))
        }

        let capturedInputCount = await client.snapshotInputs().count
        XCTAssertEqual(capturedInputCount, 1)
    }

    func testSubmitAnchorWithMarooAdapterReturnsNormalizedSuccessfulSubmissionOutput() async throws {
        let transactionHash = "0x" + String(repeating: "4", count: 64)
        let client = RawOutcomeMarooRequestAnchorSubmissionClient(
            providerOutcome: "success",
            transactionHash: transactionHash
        )
        let adapter = try MeshMarooTestnetRequestAnchorAdapter(submissionClient: client)
        let payload = try anchorPayload(
            requestId: "ios-grocery-maroo-submit-output-success",
            nonce: "nonce-maroo-submit-output-success"
        )
        let input = try MeshRequestAnchorSubmitInput(
            payload: payload,
            providerIdentity: adapter.identity,
            submittedAt: "2026-05-31T00:00:04Z"
        )

        let output = try await MeshRequestAnchorSubmissionModule(provider: adapter).submitAnchor(input)

        XCTAssertEqual(output.version, MeshRequestAnchorSubmissionOutput.version)
        XCTAssertEqual(output.anchoringReference.identity.metadata, adapter.providerMetadata)
        XCTAssertEqual(output.anchoringReference.anchorId, "maroo-raw-ios-grocery-maroo-submit-output-success")
        XCTAssertEqual(output.anchoringReference.transactionHash, transactionHash)
        XCTAssertEqual(
            output.anchoringReference.explorerURL?.absoluteString,
            "https://explorer-testnet.maroo.io/tx/\(transactionHash)"
        )
        XCTAssertEqual(output.requestHash, payload.metadata.signedRequestHash)
        XCTAssertEqual(output.requestNonce, payload.metadata.nonce)
        XCTAssertEqual(output.policyId, payload.policyId)
        XCTAssertEqual(output.policyHash, payload.policyHash)
        XCTAssertEqual(output.status, .confirmed)
        XCTAssertEqual(output.submittedAt, input.submittedAt)
        XCTAssertEqual(output.observedAt, input.submittedAt)
        XCTAssertNil(output.message)
    }

    func testSubmitAnchorWithMarooAdapterReturnsNormalizedFailureSubmissionOutput() async throws {
        let client = RawOutcomeMarooRequestAnchorSubmissionClient(providerOutcome: "rpc_error")
        let adapter = try MeshMarooTestnetRequestAnchorAdapter(submissionClient: client)
        let payload = try anchorPayload(
            requestId: "ios-grocery-maroo-submit-output-failure",
            nonce: "nonce-maroo-submit-output-failure"
        )
        let input = try MeshRequestAnchorSubmitInput(
            payload: payload,
            providerIdentity: adapter.identity,
            submittedAt: "2026-05-31T00:00:05Z"
        )

        let output = try await MeshRequestAnchorSubmissionModule(provider: adapter).submitAnchor(input)

        XCTAssertEqual(output.version, MeshRequestAnchorSubmissionOutput.version)
        XCTAssertEqual(output.anchoringReference.identity.metadata, adapter.providerMetadata)
        XCTAssertEqual(output.anchoringReference.anchorId, "maroo-raw-ios-grocery-maroo-submit-output-failure")
        XCTAssertNil(output.anchoringReference.transactionHash)
        XCTAssertNil(output.anchoringReference.explorerURL)
        XCTAssertEqual(output.requestHash, payload.metadata.signedRequestHash)
        XCTAssertEqual(output.requestNonce, payload.metadata.nonce)
        XCTAssertEqual(output.policyId, payload.policyId)
        XCTAssertEqual(output.policyHash, payload.policyHash)
        XCTAssertEqual(output.status, .failed)
        XCTAssertEqual(output.submittedAt, input.submittedAt)
        XCTAssertEqual(output.observedAt, input.submittedAt)
        XCTAssertEqual(output.message, "maroo testnet request anchor submission failed")
    }

    func testSubmitAnchorWithMarooAdapterReturnsNormalizedPendingSubmissionOutput() async throws {
        let client = RawOutcomeMarooRequestAnchorSubmissionClient(providerOutcome: "awaiting_confirmation")
        let adapter = try MeshMarooTestnetRequestAnchorAdapter(submissionClient: client)
        let payload = try anchorPayload(
            requestId: "ios-grocery-maroo-submit-output-pending",
            nonce: "nonce-maroo-submit-output-pending"
        )
        let input = try MeshRequestAnchorSubmitInput(
            payload: payload,
            providerIdentity: adapter.identity,
            submittedAt: "2026-05-31T00:00:06Z"
        )

        let output = try await MeshRequestAnchorSubmissionModule(provider: adapter).submitAnchor(input)
        let response = try await client.snapshotResponse()
        let mapping = try XCTUnwrap(response.resultMapping)

        XCTAssertEqual(mapping.providerOutcome, .pending)
        XCTAssertEqual(mapping.anchorStatus, .pending)
        XCTAssertEqual(output.version, MeshRequestAnchorSubmissionOutput.version)
        XCTAssertEqual(output.anchoringReference.identity.metadata, adapter.providerMetadata)
        XCTAssertEqual(output.anchoringReference.anchorId, "maroo-raw-ios-grocery-maroo-submit-output-pending")
        XCTAssertNil(output.anchoringReference.transactionHash)
        XCTAssertNil(output.anchoringReference.explorerURL)
        XCTAssertEqual(output.requestHash, payload.metadata.signedRequestHash)
        XCTAssertEqual(output.requestNonce, payload.metadata.nonce)
        XCTAssertEqual(output.policyId, payload.policyId)
        XCTAssertEqual(output.policyHash, payload.policyHash)
        XCTAssertEqual(output.status, .pending)
        XCTAssertEqual(output.submittedAt, input.submittedAt)
        XCTAssertEqual(output.observedAt, input.submittedAt)
        XCTAssertNil(output.message)
    }

    func testMarooRequestAnchorProviderInputCanonicalizesSignedMCPRequestAndPolicyBinding() async throws {
        let adapter = try MeshMarooTestnetRequestAnchorAdapter(status: .pending)
        let request = signedDailyMartRequest(
            requestId: "ios-grocery-maroo-anchor-canonical-001",
            nonce: "nonce-maroo-anchor-canonical-001"
        )
        let requestMetadata = try MeshSignedRequestAnchorMetadata(request: request)
        let metadata = try MeshSignedRequestAnchorMetadata(
            requestId: requestMetadata.requestId,
            nonce: requestMetadata.nonce,
            timestamp: requestMetadata.timestamp,
            callerAppId: requestMetadata.callerAppId,
            callerBundleId: requestMetadata.callerBundleId,
            targetBundleId: requestMetadata.targetBundleId,
            capabilityId: requestMetadata.capabilityId,
            payloadHash: MeshPayloadHash(
                algorithm: "SHA256",
                value: requestMetadata.payloadHash.value.uppercased()
            ),
            signature: requestMetadata.signature,
            signedRequestHash: MeshPayloadHash(
                algorithm: "SHA256",
                value: requestMetadata.signedRequestHash.value.uppercased()
            )
        )
        let payload = try MeshRequestAnchorPayload(
            metadata: metadata,
            policyId: "policy-hermes-dailymart-okrw-v1",
            policyHash: MeshPayloadHash(algorithm: "SHA256", value: String(repeating: "F", count: 64))
        )

        let input = try MeshRequestAnchorProviderInput(
            payload: payload,
            providerIdentity: adapter.identity,
            submittedAt: "2026-05-31T00:00:02Z"
        )
        let anchor = try await adapter.anchorSignedRequest(
            payload: payload,
            submittedAt: "2026-05-31T00:00:02Z"
        )

        XCTAssertEqual(input.version, "meshkit-request-anchor-provider-input/v1")
        XCTAssertEqual(input.providerMetadata.provider, "maroo")
        XCTAssertEqual(input.providerMetadata.network, "maroo-testnet")
        XCTAssertTrue(input.canonicalString.contains("requestNonce=nonce-maroo-anchor-canonical-001"))
        XCTAssertTrue(input.canonicalString.contains("signedRequestHashAlgorithm=sha256"))
        XCTAssertTrue(input.canonicalString.contains("signedRequestHashValue=\(requestMetadata.signedRequestHash.value)"))
        XCTAssertTrue(input.canonicalString.contains("payloadHashValue=\(requestMetadata.payloadHash.value)"))
        XCTAssertTrue(input.canonicalString.contains("signatureAlgorithm=\(requestMetadata.signature.algorithm)"))
        XCTAssertTrue(input.canonicalString.contains("signatureKeyId=\(requestMetadata.signature.keyId)"))
        XCTAssertTrue(input.canonicalString.contains("signatureValue=\(requestMetadata.signature.value)"))
        XCTAssertTrue(input.canonicalString.contains("policyHashValue=\(String(repeating: "f", count: 64))"))
        XCTAssertEqual(input.sha256Hash().algorithm, "sha256")
        XCTAssertEqual(input.sha256Hash().value.count, 64)

        XCTAssertEqual(anchor.payload, payload)
        XCTAssertEqual(anchor.metadata, metadata)
        XCTAssertEqual(anchor.identifier.identity.metadata, adapter.providerMetadata)
        XCTAssertEqual(anchor.identifier.anchorId, "maroo-anchor-ios-grocery-maroo-anchor-canonical-001")
        XCTAssertEqual(anchor.status, .pending)
        XCTAssertEqual(anchor.submittedAt, "2026-05-31T00:00:02Z")
        XCTAssertEqual(anchor.observedAt, "2026-05-31T00:00:02Z")
        XCTAssertNotNil(anchor.identifier.transactionHash)
        XCTAssertEqual(
            anchor.identifier.explorerURL?.absoluteString,
            "https://explorer-testnet.maroo.io/tx/\(try XCTUnwrap(anchor.identifier.transactionHash))"
        )
    }

    func testMarooRequestAnchorSerializerMapsProviderNeutralInputIntoTransactionRequestSchema() throws {
        let adapter = try MeshMarooTestnetRequestAnchorAdapter(status: .pending)
        let payload = try anchorPayload(
            requestId: "ios-grocery-maroo-serializer-001",
            nonce: "nonce-maroo-serializer-001"
        )
        let input = try MeshRequestAnchorProviderInput(
            payload: payload,
            providerIdentity: adapter.identity,
            submittedAt: "2026-05-31T00:00:02Z"
        )

        let transactionRequest = try MeshMarooTestnetRequestAnchorSerializer.transactionRequest(from: input)

        XCTAssertEqual(transactionRequest.version, "maroo-testnet-request-anchor/v1")
        XCTAssertEqual(transactionRequest.requestType, "meshkit_request_anchor")
        XCTAssertEqual(transactionRequest.provider, "maroo")
        XCTAssertEqual(transactionRequest.network, "maroo-testnet")
        XCTAssertEqual(transactionRequest.chainId, "maroo-testnet-1")
        XCTAssertEqual(transactionRequest.rpcEndpoint.absoluteString, "https://rpc-testnet.maroo.io")
        XCTAssertEqual(transactionRequest.explorerBaseURL?.absoluteString, "https://explorer-testnet.maroo.io")
        XCTAssertEqual(
            transactionRequest.anchorPayloadIdentity,
            "meshkit-request-anchor/v1:ios-grocery-maroo-serializer-001:nonce-maroo-serializer-001:policy-hermes-dailymart-okrw-v1"
        )
        XCTAssertEqual(transactionRequest.targetOwner, "ai.meshkit.sample.dailymart")
        XCTAssertEqual(transactionRequest.delegatedSigner, "app.hermes-chat:ai.meshkit.sample.hermeschat:demo-key")
        XCTAssertEqual(transactionRequest.anchorHash, input.sha256Hash())
        XCTAssertEqual(transactionRequest.requestId, payload.metadata.requestId)
        XCTAssertEqual(transactionRequest.requestNonce, payload.metadata.nonce)
        XCTAssertEqual(transactionRequest.signedMCPRequestHash, payload.metadata.signedRequestHash)
        XCTAssertEqual(transactionRequest.signedMCPRequestSignature, payload.metadata.signature)
        XCTAssertEqual(transactionRequest.policyId, payload.policyId)
        XCTAssertEqual(transactionRequest.policyHash, payload.policyHash)
        XCTAssertEqual(transactionRequest.submittedAt, input.submittedAt)
    }

    func testMarooRequestAnchorSerializerEncodesMarooSchemaKeys() throws {
        let adapter = try MeshMarooTestnetRequestAnchorAdapter(status: .pending)
        let input = try MeshRequestAnchorProviderInput(
            payload: anchorPayload(
                requestId: "ios-grocery-maroo-serializer-json-001",
                nonce: "nonce-maroo-serializer-json-001"
            ),
            providerIdentity: adapter.identity,
            submittedAt: "2026-05-31T00:00:02Z"
        )
        let transactionRequest = try MeshMarooTestnetRequestAnchorSerializer.transactionRequest(from: input)

        let data = try JSONEncoder().encode(transactionRequest)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])

        XCTAssertEqual(object["schema_version"] as? String, "maroo-testnet-request-anchor/v1")
        XCTAssertEqual(object["request_type"] as? String, "meshkit_request_anchor")
        XCTAssertEqual(object["rpc_endpoint"] as? String, "https://rpc-testnet.maroo.io")
        XCTAssertEqual(object["explorer_base_url"] as? String, "https://explorer-testnet.maroo.io")
        XCTAssertEqual(object["anchor_payload_identity"] as? String, transactionRequest.anchorPayloadIdentity)
        XCTAssertEqual(object["target_owner"] as? String, "ai.meshkit.sample.dailymart")
        XCTAssertEqual(object["delegated_signer"] as? String, "app.hermes-chat:ai.meshkit.sample.hermeschat:demo-key")
        XCTAssertEqual(object["request_nonce"] as? String, "nonce-maroo-serializer-json-001")
        XCTAssertEqual(object["policy_id"] as? String, "policy-hermes-dailymart-okrw-v1")
        XCTAssertEqual((object["anchor_hash"] as? [String: Any])?["value"] as? String, input.sha256Hash().value)
        XCTAssertEqual(
            (object["signed_mcp_request_hash"] as? [String: Any])?["value"] as? String,
            input.payload.metadata.signedRequestHash.value
        )
        let signature = try XCTUnwrap(object["signed_mcp_request_signature"] as? [String: Any])
        XCTAssertEqual(signature["algorithm"] as? String, "Ed25519")
        XCTAssertEqual(signature["keyId"] as? String, "demo-key")
        XCTAssertEqual(signature["value"] as? String, input.payload.metadata.signature.value)
        XCTAssertEqual((object["policy_hash"] as? [String: Any])?["value"] as? String, input.payload.policyHash.value)
    }

    func testMarooRequestAnchorTransactionRequestRoundTripsAndValidatesProviderNeutralInputLinkage() throws {
        let adapter = try MeshMarooTestnetRequestAnchorAdapter(status: .pending)
        let input = try MeshRequestAnchorProviderInput(
            payload: anchorPayload(
                requestId: "ios-grocery-maroo-serializer-roundtrip-001",
                nonce: "nonce-maroo-serializer-roundtrip-001"
            ),
            providerIdentity: adapter.identity,
            submittedAt: "2026-05-31T00:00:02Z"
        )
        let transactionRequest = try MeshMarooTestnetRequestAnchorSerializer.transactionRequest(from: input)
        let data = try JSONEncoder().encode(transactionRequest)

        let decoded = try JSONDecoder().decode(MeshMarooTestnetRequestAnchorTransactionRequest.self, from: data)

        XCTAssertEqual(decoded, transactionRequest)
        XCTAssertNoThrow(try decoded.validate(providerInput: input))
    }

    func testMarooRequestAnchorTransactionRequestRejectsMismatchedSerializedPayloadIdentity() throws {
        let adapter = try MeshMarooTestnetRequestAnchorAdapter(status: .pending)
        let input = try MeshRequestAnchorProviderInput(
            payload: anchorPayload(
                requestId: "ios-grocery-maroo-serializer-mismatch-001",
                nonce: "nonce-maroo-serializer-mismatch-001"
            ),
            providerIdentity: adapter.identity,
            submittedAt: "2026-05-31T00:00:02Z"
        )
        let transactionRequest = try MeshMarooTestnetRequestAnchorSerializer.transactionRequest(from: input)
        let data = try JSONEncoder().encode(transactionRequest)
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        object["anchor_payload_identity"] = "meshkit-request-anchor/v1:ios-grocery-maroo-serializer-mismatch-001:wrong-nonce:policy-hermes-dailymart-okrw-v1"
        let invalidData = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])

        XCTAssertThrowsError(try JSONDecoder().decode(MeshMarooTestnetRequestAnchorTransactionRequest.self, from: invalidData)) { error in
            XCTAssertEqual(error as? MeshKitValidationError, .signatureMismatch("maroo request anchor payload identity mismatch"))
        }
    }

    func testMarooRequestAnchorTransactionRequestRejectsProviderInputLinkageMismatch() throws {
        let adapter = try MeshMarooTestnetRequestAnchorAdapter(status: .pending)
        let input = try MeshRequestAnchorProviderInput(
            payload: anchorPayload(
                requestId: "ios-grocery-maroo-serializer-linkage-001",
                nonce: "nonce-maroo-serializer-linkage-001"
            ),
            providerIdentity: adapter.identity,
            submittedAt: "2026-05-31T00:00:02Z"
        )
        let otherInput = try MeshRequestAnchorProviderInput(
            payload: anchorPayload(
                requestId: "ios-grocery-maroo-serializer-linkage-002",
                nonce: "nonce-maroo-serializer-linkage-002"
            ),
            providerIdentity: adapter.identity,
            submittedAt: "2026-05-31T00:00:02Z"
        )
        let transactionRequest = try MeshMarooTestnetRequestAnchorSerializer.transactionRequest(from: input)

        XCTAssertThrowsError(try transactionRequest.validate(providerInput: otherInput)) { error in
            XCTAssertEqual(error as? MeshKitValidationError, .signatureMismatch("maroo request anchor provider input linkage mismatch"))
        }
    }

    func testMarooRequestAnchorSerializerPreservesConfiguredNetworkParameters() throws {
        let chainProvider = try MeshMarooTestnetChainProvider(
            rpcEndpoint: try XCTUnwrap(URL(string: "HTTPS://RPC-Override.Maroo.Example.Invalid/")),
            explorerBaseURL: try XCTUnwrap(URL(string: "HTTPS://Explorer-Override.Maroo.Example.Invalid/"))
        )
        let input = try MeshRequestAnchorProviderInput(
            payload: anchorPayload(
                requestId: "ios-grocery-maroo-serializer-network-001",
                nonce: "nonce-maroo-serializer-network-001"
            ),
            providerIdentity: chainProvider.identity,
            submittedAt: "2026-05-31T00:00:02Z"
        )

        let transactionRequest = try MeshMarooTestnetRequestAnchorSerializer.transactionRequest(from: input)

        XCTAssertEqual(transactionRequest.provider, "maroo")
        XCTAssertEqual(transactionRequest.network, "maroo-testnet")
        XCTAssertEqual(transactionRequest.chainId, "maroo-testnet-1")
        XCTAssertEqual(transactionRequest.rpcEndpoint.absoluteString, "https://rpc-override.maroo.example.invalid")
        XCTAssertEqual(transactionRequest.explorerBaseURL?.absoluteString, "https://explorer-override.maroo.example.invalid")
        XCTAssertNoThrow(try transactionRequest.validate(
            providerMetadata: chainProvider.identity.metadata,
            endpointConfiguration: chainProvider.identity.endpointConfiguration
        ))
    }

    func testMarooRPCRequestAnchorSubmissionClientPostsSerializedPayloadToConfiguredTestnetEndpoint() async throws {
        let transactionHash = "0x" + String(repeating: "8", count: 64)
        let transport = CapturingMarooRequestAnchorHTTPTransport(responseObject: [
            "jsonrpc": "2.0",
            "id": 99,
            "result": [
                "anchor_id": "maroo-rpc-anchor-ios-grocery-maroo-rpc-submit-001",
                "transaction_hash": transactionHash,
                "provider_outcome": "success",
                "observed_at": "2026-05-31T00:00:08Z"
            ]
        ])
        let client = MeshMarooTestnetRPCRequestAnchorSubmissionClient(
            transport: transport,
            requestId: 99
        )
        let adapter = try MeshMarooTestnetRequestAnchorAdapter(submissionClient: client)
        let input = try MeshRequestAnchorProviderInput(
            payload: anchorPayload(
                requestId: "ios-grocery-maroo-rpc-submit-001",
                nonce: "nonce-maroo-rpc-submit-001"
            ),
            providerIdentity: adapter.identity,
            submittedAt: "2026-05-31T00:00:07Z"
        )

        let response = try await client.submitRequestAnchor(input)
        let requests = await transport.snapshotRequests()
        let request = try XCTUnwrap(requests.first)
        let body = try XCTUnwrap(request.httpBody)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
        let params = try XCTUnwrap(object["params"] as? [[String: Any]])
        let submittedPayload = try XCTUnwrap(params.first)

        XCTAssertEqual(request.url?.absoluteString, "https://rpc-testnet.maroo.io")
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.value(forHTTPHeaderField: "content-type"), "application/json")
        XCTAssertEqual(object["jsonrpc"] as? String, "2.0")
        XCTAssertEqual(object["id"] as? Int, 99)
        XCTAssertEqual(object["method"] as? String, "meshkit_submitRequestAnchor")
        XCTAssertEqual(params.count, 1)
        XCTAssertEqual(submittedPayload["schema_version"] as? String, "maroo-testnet-request-anchor/v1")
        XCTAssertEqual(submittedPayload["request_type"] as? String, "meshkit_request_anchor")
        XCTAssertEqual(submittedPayload["rpc_endpoint"] as? String, "https://rpc-testnet.maroo.io")
        XCTAssertEqual(submittedPayload["request_id"] as? String, "ios-grocery-maroo-rpc-submit-001")
        XCTAssertEqual(submittedPayload["request_nonce"] as? String, "nonce-maroo-rpc-submit-001")
        XCTAssertEqual(submittedPayload["policy_id"] as? String, "policy-hermes-dailymart-okrw-v1")
        XCTAssertEqual((submittedPayload["anchor_hash"] as? [String: Any])?["value"] as? String, input.sha256Hash().value)
        XCTAssertEqual(
            (submittedPayload["signed_mcp_request_hash"] as? [String: Any])?["value"] as? String,
            input.payload.metadata.signedRequestHash.value
        )
        XCTAssertEqual(response.providerMetadata, input.providerMetadata)
        XCTAssertEqual(response.anchorId, "maroo-rpc-anchor-ios-grocery-maroo-rpc-submit-001")
        XCTAssertEqual(response.transactionHash, transactionHash)
        XCTAssertEqual(response.status, .confirmed)
        XCTAssertEqual(response.observedAt, "2026-05-31T00:00:08Z")
    }

    func testMarooRPCRequestAnchorSubmissionClientMapsRPCErrorToFailedAnchorWithoutConfirmedTx() async throws {
        let transport = CapturingMarooRequestAnchorHTTPTransport(responseObject: [
            "jsonrpc": "2.0",
            "id": 100,
            "error": [
                "code": -32601,
                "message": "method not found"
            ]
        ])
        let client = MeshMarooTestnetRPCRequestAnchorSubmissionClient(
            transport: transport,
            requestId: 100
        )
        let adapter = try MeshMarooTestnetRequestAnchorAdapter(submissionClient: client)
        let input = try MeshRequestAnchorProviderInput(
            payload: anchorPayload(
                requestId: "ios-grocery-maroo-rpc-error-001",
                nonce: "nonce-maroo-rpc-error-001"
            ),
            providerIdentity: adapter.identity,
            submittedAt: "2026-05-31T00:00:09Z"
        )

        let response = try await client.submitRequestAnchor(input)

        XCTAssertEqual(response.providerMetadata, input.providerMetadata)
        XCTAssertEqual(response.anchorId, "maroo-anchor-ios-grocery-maroo-rpc-error-001")
        XCTAssertNil(response.transactionHash)
        XCTAssertEqual(response.status, .failed)
        XCTAssertEqual(response.providerOutcome, .failure)
        XCTAssertEqual(response.observedAt, input.submittedAt)
        XCTAssertEqual(response.message, "maroo RPC -32601: method not found")
    }

    func testMarooRPCRequestAnchorSuccessResponseNormalizesIntoProviderNeutralAnchorOutput() async throws {
        let transactionHash = "0x" + String(repeating: "9", count: 64)
        let transport = CapturingMarooRequestAnchorHTTPTransport(responseObject: [
            "jsonrpc": "2.0",
            "id": 101,
            "result": [
                "anchor_id": "maroo-rpc-anchor-ios-grocery-maroo-normalized-success-001",
                "tx_hash": transactionHash,
                "transaction_state": "receipt_success",
                "observed_at": "2026-05-31T00:00:11Z"
            ]
        ])
        let client = MeshMarooTestnetRPCRequestAnchorSubmissionClient(
            transport: transport,
            requestId: 101
        )
        let adapter = try MeshMarooTestnetRequestAnchorAdapter(submissionClient: client)
        let payload = try anchorPayload(
            requestId: "ios-grocery-maroo-normalized-success-001",
            nonce: "nonce-maroo-normalized-success-001"
        )
        let input = try MeshRequestAnchorSubmitInput(
            payload: payload,
            providerIdentity: adapter.identity,
            submittedAt: "2026-05-31T00:00:10Z"
        )

        let output = try await MeshRequestAnchorSubmissionModule(provider: adapter).submitAnchor(input)

        XCTAssertEqual(output.anchoringReference.anchorId, "maroo-rpc-anchor-ios-grocery-maroo-normalized-success-001")
        XCTAssertEqual(output.anchoringReference.transactionHash, transactionHash)
        XCTAssertEqual(
            output.anchoringReference.explorerURL?.absoluteString,
            "https://explorer-testnet.maroo.io/tx/\(transactionHash)"
        )
        XCTAssertEqual(output.requestHash, payload.metadata.signedRequestHash)
        XCTAssertEqual(output.requestNonce, payload.metadata.nonce)
        XCTAssertEqual(output.policyId, payload.policyId)
        XCTAssertEqual(output.policyHash, payload.policyHash)
        XCTAssertEqual(output.status, .confirmed)
        XCTAssertEqual(output.submittedAt, input.submittedAt)
        XCTAssertEqual(output.observedAt, "2026-05-31T00:00:11Z")
        XCTAssertNil(output.message)
    }

    func testMarooRPCRequestAnchorFailureResponseNormalizesIntoProviderNeutralAnchorOutput() async throws {
        let transport = CapturingMarooRequestAnchorHTTPTransport(responseObject: [
            "jsonrpc": "2.0",
            "id": 102,
            "result": [
                "anchor_id": "maroo-rpc-anchor-ios-grocery-maroo-normalized-failure-001",
                "anchor_status": "tx_reverted",
                "message": "  RPC reverted\nwhile anchoring  ",
                "observed_at": "2026-05-31T00:00:13Z"
            ]
        ])
        let client = MeshMarooTestnetRPCRequestAnchorSubmissionClient(
            transport: transport,
            requestId: 102
        )
        let adapter = try MeshMarooTestnetRequestAnchorAdapter(submissionClient: client)
        let payload = try anchorPayload(
            requestId: "ios-grocery-maroo-normalized-failure-001",
            nonce: "nonce-maroo-normalized-failure-001"
        )
        let input = try MeshRequestAnchorSubmitInput(
            payload: payload,
            providerIdentity: adapter.identity,
            submittedAt: "2026-05-31T00:00:12Z"
        )

        let output = try await MeshRequestAnchorSubmissionModule(provider: adapter).submitAnchor(input)

        XCTAssertEqual(output.anchoringReference.anchorId, "maroo-rpc-anchor-ios-grocery-maroo-normalized-failure-001")
        XCTAssertNil(output.anchoringReference.transactionHash)
        XCTAssertNil(output.anchoringReference.explorerURL)
        XCTAssertEqual(output.requestHash, payload.metadata.signedRequestHash)
        XCTAssertEqual(output.requestNonce, payload.metadata.nonce)
        XCTAssertEqual(output.policyId, payload.policyId)
        XCTAssertEqual(output.policyHash, payload.policyHash)
        XCTAssertEqual(output.status, .failed)
        XCTAssertEqual(output.submittedAt, input.submittedAt)
        XCTAssertEqual(output.observedAt, "2026-05-31T00:00:13Z")
        XCTAssertEqual(output.message, "RPC reverted while anchoring")
    }

    func testMarooRequestAnchorProviderInputRejectsInvalidSubmissionFieldsBeforeAnchoring() async throws {
        let adapter = try MeshMarooTestnetRequestAnchorAdapter(status: .submitted)
        let payload = try anchorPayload(
            requestId: "ios-grocery-maroo-anchor-invalid-submitted-at",
            nonce: "nonce-maroo-anchor-invalid-submitted-at"
        )

        do {
            _ = try await adapter.anchorSignedRequest(
                payload: payload,
                submittedAt: " 2026-05-31T00:00:02Z "
            )
            XCTFail("Expected maroo anchor adapter to reject non-canonical submittedAt")
        } catch {
            XCTAssertEqual(error as? MeshKitValidationError, .invalidChainProviderIdentity("submittedAt"))
        }
    }

    func testMarooRequestAnchorProviderInputRejectsProviderMetadataMismatch() throws {
        let adapter = try MeshMarooTestnetRequestAnchorAdapter(status: .submitted)
        let payload = try anchorPayload(
            requestId: "ios-grocery-maroo-anchor-provider-mismatch",
            nonce: "nonce-maroo-anchor-provider-mismatch"
        )
        let wrongProviderIdentity = try MeshChainProviderIdentity(
            providerName: "other-provider",
            networkIdentity: "other-testnet",
            chainId: "other-testnet-1",
            rpcEndpoint: try XCTUnwrap(URL(string: "https://rpc.other-provider.example.invalid")),
            explorerBaseURL: try XCTUnwrap(URL(string: "https://explorer.other-provider.example.invalid"))
        )
        let input = try MeshRequestAnchorProviderInput(
            payload: payload,
            providerIdentity: wrongProviderIdentity,
            submittedAt: "2026-05-31T00:00:02Z"
        )

        XCTAssertThrowsError(try input.validate(providerIdentity: adapter.identity)) { error in
            XCTAssertEqual(error as? MeshKitValidationError, .signatureMismatch("request anchor provider metadata mismatch"))
        }
    }

    func testMarooRequestAnchorProviderInputRejectsMalformedPolicyHash() throws {
        let metadata = try MeshSignedRequestAnchorMetadata(
            request: signedDailyMartRequest(
                requestId: "ios-grocery-maroo-anchor-bad-policy-hash",
                nonce: "nonce-maroo-anchor-bad-policy-hash"
            )
        )

        XCTAssertThrowsError(try MeshRequestAnchorPayload(
            metadata: metadata,
            policyId: "policy-hermes-dailymart-okrw-v1",
            policyHash: MeshPayloadHash(value: "not-a-sha256")
        )) { error in
            XCTAssertEqual(error as? MeshKitValidationError, .invalidChainProviderIdentity("policyHash.value"))
        }
    }

    func testMarooRequestAnchorResultMappingNormalizesSuccessPendingFailureAndPolicyDeniedResponses() async throws {
        struct Case {
            let providerOutcome: String
            let expectedOutcome: MeshMarooTestnetRequestAnchorProviderOutcome
            let expectedStatus: MeshRequestAnchorStatus
            let expectedPolicyDenied: Bool
            let transactionHash: String?
            let expectedMessage: String?
        }

        let cases = [
            Case(
                providerOutcome: "success",
                expectedOutcome: .success,
                expectedStatus: .confirmed,
                expectedPolicyDenied: false,
                transactionHash: "0x" + String(repeating: "2", count: 64),
                expectedMessage: nil
            ),
            Case(
                providerOutcome: "awaiting-confirmation",
                expectedOutcome: .pending,
                expectedStatus: .pending,
                expectedPolicyDenied: false,
                transactionHash: nil,
                expectedMessage: nil
            ),
            Case(
                providerOutcome: "rpc_error",
                expectedOutcome: .failure,
                expectedStatus: .failed,
                expectedPolicyDenied: false,
                transactionHash: nil,
                expectedMessage: "maroo testnet request anchor submission failed"
            ),
            Case(
                providerOutcome: "spending_limit_exceeded",
                expectedOutcome: .policyDenied,
                expectedStatus: .failed,
                expectedPolicyDenied: true,
                transactionHash: nil,
                expectedMessage: "maroo testnet request anchor policy denied"
            )
        ]

        for testCase in cases {
            let client = RawOutcomeMarooRequestAnchorSubmissionClient(
                providerOutcome: testCase.providerOutcome,
                transactionHash: testCase.transactionHash
            )
            let adapter = try MeshMarooTestnetRequestAnchorAdapter(submissionClient: client)
            let payload = try anchorPayload(
                requestId: "ios-grocery-maroo-anchor-\(testCase.providerOutcome)",
                nonce: "nonce-maroo-anchor-\(testCase.providerOutcome)"
            )

            let anchor = try await adapter.anchorSignedRequest(
                payload: payload,
                submittedAt: "2026-05-31T00:00:03Z"
            )
            let response = try await client.snapshotResponse()
            let mapping = try XCTUnwrap(response.resultMapping)

            XCTAssertEqual(mapping.providerOutcome, testCase.expectedOutcome)
            XCTAssertEqual(mapping.anchorStatus, testCase.expectedStatus)
            XCTAssertEqual(mapping.isPolicyDenied, testCase.expectedPolicyDenied)
            XCTAssertEqual(response.status, testCase.expectedStatus)
            XCTAssertEqual(anchor.status, testCase.expectedStatus)
            XCTAssertEqual(anchor.message, testCase.expectedMessage)
            XCTAssertEqual(anchor.identifier.transactionHash, testCase.transactionHash)
        }
    }

    func testMarooRequestAnchorResultMappingRejectsPolicyDeniedTransactionHash() throws {
        XCTAssertThrowsError(try MeshMarooTestnetRequestAnchorSubmissionResponse(
            providerMetadata: try MeshMarooTestnetChainProvider().metadata,
            anchorId: "maroo-anchor-policy-denied-with-tx",
            transactionHash: "0x" + String(repeating: "3", count: 64),
            providerOutcome: "policy_denied",
            observedAt: "2026-05-31T00:00:03Z"
        )) { error in
            XCTAssertEqual(error as? MeshKitValidationError, .invalidChainProviderIdentity("transactionHash"))
        }
    }

    func testMarooAdapterResolvesSubmittedDailyMartAppToAppAnchorToSignedRequestHash() async throws {
        let adapter = try MeshMarooTestnetRequestAnchorAdapter(status: .pending)
        let request = signedDailyMartRequest(
            requestId: "ios-grocery-maroo-app-to-app-resolution-001",
            nonce: "nonce-maroo-app-to-app-resolution-001"
        )
        let payload = try MeshRequestAnchorPayload(
            metadata: MeshSignedRequestAnchorMetadata(request: request),
            policyId: DailyMartDelegatedSpendingPolicy.policyId,
            policyHash: DailyMartDelegatedSpendingPolicy.policyHash
        )
        let submittedAnchor = try await adapter.anchorSignedRequest(
            payload: payload,
            submittedAt: "2026-05-31T00:00:06Z"
        )
        let expectedSignedRequestHash = try MeshRequestAnchorCanonicalization.signedRequestHash(for: request)

        let resolved = try await MeshRequestAnchorResolutionModule(provider: adapter).resolveResponse(
            identifier: submittedAnchor.identifier,
            checkedAt: "2026-05-31T00:00:07Z"
        )
        let lookedUpAnchor = try await MeshRequestAnchorStatusModule(provider: adapter).lookup(
            identifier: submittedAnchor.identifier,
            checkedAt: "2026-05-31T00:00:07Z"
        )

        XCTAssertEqual(resolved.outcome, .known)
        XCTAssertEqual(resolved.identifier, submittedAnchor.identifier)
        XCTAssertEqual(resolved.requestHash, expectedSignedRequestHash)
        XCTAssertEqual(resolved.anchorStatus, .pending)
        XCTAssertEqual(lookedUpAnchor.metadata.signedRequestHash, expectedSignedRequestHash)
        XCTAssertEqual(lookedUpAnchor.payload?.metadata.signedRequestHash, expectedSignedRequestHash)
        XCTAssertEqual(lookedUpAnchor.metadata.requestId, request.requestId)
        XCTAssertEqual(lookedUpAnchor.metadata.nonce, request.nonce)
        XCTAssertEqual(lookedUpAnchor.status, .pending)
    }

    private func anchorPayload(requestId: String, nonce: String) throws -> MeshRequestAnchorPayload {
        try MeshRequestAnchorPayload(
            metadata: MeshSignedRequestAnchorMetadata(
                request: signedDailyMartRequest(requestId: requestId, nonce: nonce)
            ),
            policyId: "policy-hermes-dailymart-okrw-v1",
            policyHash: MeshPayloadHash(value: String(repeating: "f", count: 64))
        )
    }

    private func signedDailyMartRequest(requestId: String, nonce: String) -> MeshRequest {
        let unsigned = MeshRequest(
            requestId: requestId,
            caller: MeshIdentity(
                appId: "app.hermes-chat",
                installId: "ios-device",
                bundleId: "ai.meshkit.sample.hermeschat",
                publicKeyId: "demo-key"
            ),
            target: MeshCapability(
                targetBundleId: "ai.meshkit.sample.dailymart",
                capabilityId: "grocery.purchase_essentials",
                version: "1.0"
            ),
            payload: [
                "address_ref": "home.saved",
                "budget_krw": "4900",
                "items": "laundry_detergent:1,toilet_paper:2,bottled_water_2l:6"
            ],
            nonce: nonce,
            timestamp: "2026-05-31T00:00:00Z",
            signature: MeshSignature(algorithm: "Ed25519", keyId: "demo-key", value: "")
        )
        let signature = try! Self.signingKey.signature(for: unsigned.signingInputData()).base64EncodedString()
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

private actor RawOutcomeMarooRequestAnchorSubmissionClient: MeshMarooTestnetRequestAnchorSubmissionClient {
    private let providerOutcome: String
    private let transactionHash: String?
    private var response: MeshMarooTestnetRequestAnchorSubmissionResponse?

    init(providerOutcome: String, transactionHash: String? = nil) {
        self.providerOutcome = providerOutcome
        self.transactionHash = transactionHash
    }

    func submitRequestAnchor(
        _ input: MeshRequestAnchorProviderInput
    ) async throws -> MeshMarooTestnetRequestAnchorSubmissionResponse {
        let response = try MeshMarooTestnetRequestAnchorSubmissionResponse(
            providerMetadata: input.providerMetadata,
            anchorId: "maroo-raw-\(input.payload.metadata.requestId)",
            transactionHash: transactionHash,
            providerOutcome: providerOutcome,
            observedAt: input.submittedAt
        )
        self.response = response
        return response
    }

    func snapshotResponse() throws -> MeshMarooTestnetRequestAnchorSubmissionResponse {
        guard let response else {
            throw MeshKitValidationError.invalidChainProviderIdentity("response")
        }
        return response
    }
}

private actor CapturingMarooRequestAnchorSubmissionClient: MeshMarooTestnetRequestAnchorSubmissionClient {
    private(set) var inputs: [MeshRequestAnchorProviderInput] = []
    private let providerMetadataOverride: MeshChainProviderMetadata?

    init(providerMetadataOverride: MeshChainProviderMetadata? = nil) {
        self.providerMetadataOverride = providerMetadataOverride
    }

    func submitRequestAnchor(
        _ input: MeshRequestAnchorProviderInput
    ) async throws -> MeshMarooTestnetRequestAnchorSubmissionResponse {
        inputs.append(input)
        return try MeshMarooTestnetRequestAnchorSubmissionResponse(
            providerMetadata: providerMetadataOverride ?? input.providerMetadata,
            anchorId: "maroo-captured-\(input.payload.metadata.requestId)",
            transactionHash: "0x" + String(repeating: "1", count: 64),
            status: .submitted,
            observedAt: input.submittedAt
        )
    }

    func snapshotInputs() -> [MeshRequestAnchorProviderInput] {
        inputs
    }
}

private actor CapturingMarooRequestAnchorHTTPTransport: MeshMarooTestnetRequestAnchorHTTPTransport {
    private(set) var requests: [URLRequest] = []
    private let statusCode: Int
    private let responseData: Data

    init(responseObject: [String: Any], statusCode: Int = 200) {
        self.statusCode = statusCode
        self.responseData = try! JSONSerialization.data(withJSONObject: responseObject, options: [.sortedKeys])
    }

    func sendMarooRequestAnchor(
        _ request: URLRequest
    ) async throws -> (Data, HTTPURLResponse) {
        requests.append(request)
        let response = HTTPURLResponse(
            url: try XCTUnwrap(request.url),
            statusCode: statusCode,
            httpVersion: "HTTP/1.1",
            headerFields: ["content-type": "application/json"]
        )
        return (responseData, try XCTUnwrap(response))
    }

    func snapshotRequests() -> [URLRequest] {
        requests
    }
}
