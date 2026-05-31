#!/usr/bin/env python3
from pathlib import Path
import json
import os
import re
import shlex
import subprocess


ROOT = Path(__file__).resolve().parents[1]


def read(rel):
    path = ROOT / rel
    assert path.exists(), f"missing {rel}"
    return path.read_text()


def require(rel, needles):
    text = read(rel)
    for needle in needles:
        assert needle in text, f"{rel} missing {needle}"


def forbid(rel, needles):
    text = read(rel)
    for needle in needles:
        assert needle not in text, f"{rel} must not contain {needle}"


def extract_marked_table(rel, start_marker, end_marker):
    text = read(rel)
    match = re.search(
        rf"<!-- {re.escape(start_marker)} -->(.*?)<!-- {re.escape(end_marker)} -->",
        text,
        re.DOTALL,
    )
    assert match, f"{rel} missing marked table {start_marker}/{end_marker}"
    rows = []
    for line in match.group(1).splitlines():
        stripped = line.strip()
        if not stripped.startswith("|") or "---" in stripped:
            continue
        cells = [cell.strip() for cell in stripped.strip("|").split("|")]
        if cells and cells[0].lower() not in {"schema key", "environment key"}:
            rows.append(cells)
    return rows


def extract_backtick_key(cell):
    match = re.search(r"`([^`]+)`", cell)
    assert match, f"missing backtick key in table cell {cell!r}"
    return match.group(1)


def extract_swift_string_array(rel, property_name):
    text = read(rel)
    match = re.search(
        rf"public static let {re.escape(property_name)} = \[(.*?)\]",
        text,
        re.DOTALL,
    )
    assert match, f"{rel} missing public static let {property_name}"
    return re.findall(r'"([^"]+)"', match.group(1))


def extract_marked_code_block(rel, start_marker, end_marker):
    text = read(rel)
    match = re.search(
        rf"<!-- {re.escape(start_marker)} -->(.*?)<!-- {re.escape(end_marker)} -->",
        text,
        re.DOTALL,
    )
    assert match, f"{rel} missing marked code block {start_marker}/{end_marker}"
    block_match = re.search(r"```bash\n(.*?)\n```", match.group(1), re.DOTALL)
    assert block_match, f"{rel} missing bash code fence inside {start_marker}/{end_marker}"
    commands = []
    pending = ""
    for line in block_match.group(1).splitlines():
        stripped = line.strip()
        if not stripped or stripped.startswith("#"):
            continue
        if stripped.endswith("\\"):
            pending += stripped[:-1].strip() + " "
            continue
        command = (pending + stripped).strip()
        pending = ""
        commands.append(command)
    assert not pending, f"{rel} has unterminated continued command in {start_marker}/{end_marker}"
    return commands


def extract_marked_bullets(rel, start_marker, end_marker):
    text = read(rel)
    match = re.search(
        rf"<!-- {re.escape(start_marker)} -->(.*?)<!-- {re.escape(end_marker)} -->",
        text,
        re.DOTALL,
    )
    assert match, f"{rel} missing marked bullet block {start_marker}/{end_marker}"
    bullets = []
    for line in match.group(1).splitlines():
        stripped = line.strip()
        if stripped.startswith("- "):
            bullets.append(stripped[2:].strip())
    assert bullets, f"{rel} has no bullets in {start_marker}/{end_marker}"
    return bullets


def split_env_prefix(tokens):
    env = {}
    index = 0
    while index < len(tokens) and "=" in tokens[index] and not tokens[index].startswith("-"):
        key, value = tokens[index].split("=", 1)
        assert key, f"invalid empty environment key in command tokens {tokens}"
        env[key] = value
        index += 1
    return env, tokens[index:]


def validate_rpc_payload(payload, expected_method):
    parsed = json.loads(payload)
    assert parsed["jsonrpc"] == "2.0", f"{expected_method} command must use JSON-RPC 2.0"
    assert parsed["method"] == expected_method, f"expected {expected_method}, got {parsed['method']}"
    assert isinstance(parsed["params"], list), f"{expected_method} params must be a list"
    if expected_method in {"eth_blockNumber", "net_version"}:
        assert parsed["params"] == [], f"{expected_method} command must not include params"
    if expected_method == "eth_getCode":
        assert len(parsed["params"]) == 2, "eth_getCode command must include address and block tag"
        assert re.fullmatch(r"0x[a-fA-F0-9]{40}", parsed["params"][0]), "eth_getCode address must be hex"
        assert parsed["params"][1] == "latest", "eth_getCode command must query latest"


def verify_maroo_verification_commands_docs():
    commands = extract_marked_code_block(
        "docs/agentos-trust-layer.md",
        "maroo-verification-commands-start",
        "maroo-verification-commands-end",
    )
    assert len(commands) >= 6, "maroo verification command block must include harness and live probes"

    harness_commands = []
    live_script_commands = []
    curl_methods = set()
    for command in commands:
        tokens = shlex.split(command)
        env, argv = split_env_prefix(tokens)
        assert argv, f"empty command after environment prefix: {command}"
        if argv[:2] == ["python3", "scripts/verify_maroo_testnet_status.py"]:
            if "--demo-adapter-harness" in argv:
                harness_commands.append((env, argv, command))
            else:
                if env:
                    assert "MESHKIT_MAROO_OKRW_CONTRACT_ADDRESS" in env, (
                        "only MESHKIT_MAROO_OKRW_CONTRACT_ADDRESS may prefix live maroo status commands"
                    )
                    assert re.fullmatch(
                        r"0x[a-fA-F0-9]{40}",
                        env["MESHKIT_MAROO_OKRW_CONTRACT_ADDRESS"],
                    ), "documented OKRW contract address must be a 20-byte hex placeholder"
                live_script_commands.append(command)
            continue

        assert argv[0] == "curl", f"unsupported maroo verification command: {command}"
        assert "https://rpc-testnet.maroo.io" in argv, f"curl command must target maroo testnet RPC: {command}"
        assert "--data" in argv, f"curl command must include JSON-RPC payload: {command}"
        payload = argv[argv.index("--data") + 1]
        method = json.loads(payload)["method"]
        validate_rpc_payload(payload, method)
        curl_methods.add(method)

    assert len(harness_commands) >= 2, "maroo docs must include base and OKRW harness commands"
    assert len(live_script_commands) >= 2, "maroo docs must include base and OKRW live status commands"
    assert curl_methods == {"eth_blockNumber", "net_version", "eth_getCode"}, (
        f"maroo curl docs must cover eth_blockNumber, net_version, and eth_getCode; got {curl_methods}"
    )

    for env, argv, command in harness_commands:
        process_env = {**env}
        result = subprocess.run(
            argv,
            cwd=ROOT,
            check=True,
            text=True,
            capture_output=True,
            env=None if not process_env else {**os.environ, **process_env},
        )
        assert "maroo demo adapter command harness passed" in result.stdout, (
            f"harness command did not report success: {command}"
        )

    harness_artifact = ROOT / "artifacts/maroo-testnet/demo-adapter-harness.json"
    assert harness_artifact.exists(), "maroo demo adapter harness did not write its artifact"
    artifact = json.loads(harness_artifact.read_text())
    assert artifact["adapterTestHarness"] is True
    assert artifact["provider"] == "maroo"
    assert artifact["network"] == "maroo-testnet"
    assert set(artifact["validatedJsonRpcMethods"]) == {"eth_blockNumber", "net_version", "eth_getCode"}
    for field in [
        "signedRequestHash",
        "requestNonce",
        "policyId",
        "policyHash",
        "anchoringReference",
        "asset",
        "amount",
        "recipient",
        "status",
        "txHash",
        "explorerUrl",
    ]:
        assert field in artifact["validatedProviderNeutralFields"], (
            f"maroo harness missing provider-neutral field {field}"
        )


def verify_signed_mcp_request_anchoring_docs():
    docs_rel = "docs/agentos-trust-layer.md"
    bullets = extract_marked_bullets(
        docs_rel,
        "signed-mcp-request-anchoring-requirements-start",
        "signed-mcp-request-anchoring-requirements-end",
    )
    joined = "\n".join(bullets)
    required_doc_terms = [
        "MeshRequestAnchorHashInput",
        "MeshSignedRequestAnchorMetadata",
        "MeshRequestAnchorPayload",
        "MeshRequestAnchorProvider.anchorSignedRequest",
        "MeshRequestAnchorIdentifier",
        "MeshSignedMCPRequestAnchoringFields",
        "fresh request id, nonce, signature, signed request hash, anchoring reference",
        "DailyMart target-owned receipt id",
        "request signature, payload hash, nonce freshness, caller trust, policy id, policy hash",
        "cart contents, delivery address references, user identity details, consent text, and chat content must stay off-chain",
        "Hermes/caller keys, wallet keys, provider callbacks, or anchor transaction hashes are not accepted as target completion proof",
    ]
    for term in required_doc_terms:
        assert term in joined, f"signed MCP request anchoring docs missing {term}"

    assert len(bullets) >= 10, "signed MCP request anchoring docs must cover canonicalization, submission, freshness, privacy, and proof boundaries"

    require(
        "meshkit-ios/Sources/MeshKit/MeshRequestAnchor.swift",
        [
            "public struct MeshRequestAnchorHashInput",
            "public struct MeshSignedRequestAnchorMetadata",
            "public struct MeshRequestAnchorPayload",
            "public protocol MeshRequestAnchorProvider",
            "func anchorSignedRequest(",
            "public struct MeshRequestAnchorIdentifier",
            "public struct MeshSignedMCPRequestAnchoringFields",
            "signedMCPRequestHash",
            "requestNonce",
            "policyId",
            "policyHash",
        ],
    )
    require(
        "meshkit-ios/Tests/MeshKitTests/MeshSignedMCPRequestAnchoringFieldsExtractionTests.swift",
        [
            "testExtractsSignedMCPRequestAnchoringFieldsFromSDKAndProviderRequestContexts",
            "testExtractsSignedMCPRequestAnchoringFieldsFromExecutionAndPaymentContexts",
            "testPaymentContextExtractionRejectsMismatchedAnchorPayloadPolicyBinding",
            "MeshSignedMCPRequestAnchoringFields(payload: payload)",
            "MeshSignedMCPRequestAnchoringFields(paymentRequest: tamperedPaymentRequest)",
        ],
    )


def verify_signed_anchor_okrw_transaction_linkage_docs():
    docs_rel = "docs/agentos-trust-layer.md"
    bullets = extract_marked_bullets(
        docs_rel,
        "signed-anchor-okrw-transaction-linkage-start",
        "signed-anchor-okrw-transaction-linkage-end",
    )
    joined = "\n".join(bullets)
    required_doc_terms = [
        "MeshPaymentExecutionRequest",
        "provider callback alone",
        "MeshMarooTestnetExecutionLinkPayload",
        "provider metadata, execution kind, asset, amount, recipient, request id, request nonce",
        "payload hash, signed request hash, anchoring reference, policy id, policy hash",
        "payment id, authorization id, and execution id",
        "MeshMarooTestnetOKRWExecutionTransactionRequest",
        "signed_mcp_request_hash",
        "anchoring_reference",
        "anchor_metadata",
        "asset=OKRW",
        "recipient_address",
        "MeshMarooTestnetOKRWExecutionAnchorMetadata",
        "optional anchor transaction hash",
        "MeshPaymentExecutionReceiptLinkageMapper.map",
        "rejects mismatched request hashes",
        "executionKind=payment",
        "executionKind=transfer",
        "request anchor transaction hash or provider callback is not sufficient payment completion proof",
        "target-owned DailyMart receipt",
    ]
    for term in required_doc_terms:
        assert term in joined, f"signed anchor to OKRW transaction linkage docs missing {term}"

    assert len(bullets) >= 7, "signed anchor to OKRW transaction linkage docs must cover request, adapter, receipt, status, and proof boundaries"

    require(
        "meshkit-ios/Sources/MeshKit/MeshPaymentExecutor.swift",
        [
            "public struct MeshMarooTestnetExecutionLinkPayload",
            "public struct MeshMarooTestnetOKRWExecutionTransactionRequest",
            "public struct MeshMarooTestnetOKRWExecutionAnchorMetadata",
            "public enum MeshMarooTestnetOKRWExecutionSerializer",
            "signedMCPRequestHash",
            "anchoringReference",
            "anchorMetadata",
            "paymentId",
            "authorizationId",
            "executionId",
            "executionKind",
            "asset",
            "recipientAddress",
            "guard anchorMetadata.signedMCPRequestHash == signedMCPRequestHash",
            "anchorMetadata.requestNonce == requestNonce",
            "anchorMetadata.anchoringReference == anchoringReference",
            "anchorMetadata.policyId == policyId",
            "anchorMetadata.policyHash == policyHash",
        ],
    )
    require(
        "meshkit-ios/Sources/MeshKit/MeshChainProof.swift",
        [
            "public enum MeshPaymentExecutionReceiptLinkageMapper",
            "public static func map(",
            "guard paymentResult.signedRequestHash == executionRequest.requestAnchorMetadata.signedRequestHash",
            "throw MeshKitValidationError.invalidChainProof(\"requestHash\")",
            "receiptResultFields[\"requestHash\"] == proof.requestHash.value.lowercased()",
            "receiptResultFields[\"anchoringReference\"] == proof.anchoringReference",
            "receiptResultFields[\"policyId\"] == proof.policyId",
            "receiptResultFields[\"policyHash\"] == proof.policyHash.value.lowercased()",
            "receiptResultFields[\"txHash\"] == proof.txHash",
            "receiptResultFields[\"executionAttemptId\"] == proof.executionAttemptId",
        ],
    )
    require(
        "meshkit-ios/Tests/MeshKitTests/MarooPaymentExecutorAdapterTests.swift",
        [
            "testMarooAdaptersLinkAnchoredSignedMCPRequestToOKRWExecutionRecord",
            "testMarooOKRWExecutionResultMapsIntoReceiptLinkageWithAnchoredRequestFields",
            "testMarooOKRWTransferReceiptLinkagePreservesPolicyMetadata",
            "testMarooOKRWReceiptLinkageRejectsPolicyMetadataDrift",
            "testMarooOKRWReceiptLinkageMapperRejectsMismatchedRequestHash",
            "signedMCPRequestHash",
            "anchoringReference",
            "executionAttemptId",
            "payment_execution",
            "OKRW",
        ],
    )


def verify_target_owned_receipt_ownership_docs():
    docs_rel = "docs/agentos-trust-layer.md"
    bullets = extract_marked_bullets(
        docs_rel,
        "target-owned-receipt-ownership-requirements-start",
        "target-owned-receipt-ownership-requirements-end",
    )
    joined = "\n".join(bullets)
    required_doc_terms = [
        "target-owned MeshKit receipt",
        "not a Hermes/caller-owned receipt, wallet-owned receipt, provider callback, request anchor transaction hash, or maroo chain proof by itself",
        "`receiptOwner` and `targetReceiptOwner`",
        "DailyMart target owner identifier",
        "MeshReceiptOwnershipMapper.ownerIdentifier(targetAppId:targetBundleId:)",
        "`targetAppId` and `targetBundleId` bound to DailyMart",
        "`requestId` and `requestPayloadHash`",
        "MeshReceiptOwnershipMapper.assertTargetOwned",
        "MeshReceiptChainProofSerializer.targetOwnedProof",
        "signed MCP request hash, request nonce, anchoring reference, policy id, and policy hash",
        "Hermes/caller keys must not be accepted as target completion proof",
        "Wallet keys, Agent Wallet Kit callbacks, provider callbacks, anchor transaction hashes, and maroo transaction proofs augment receipt verification only when serialized inside the target-owned DailyMart receipt",
        "Confirmed, pending, failed, and policy-denied presentation states",
        "testSerializedDailyMartReceiptOwnershipMappingIsTargetOwned",
        "testTargetOwnedReceiptChainProofOwnershipRejectsCallerOwnedReceiptFields",
        "testAcceptedAppToAppCallCreatesDailyMartOwnedReceiptNotCallerOwned",
    ]
    for term in required_doc_terms:
        assert term in joined, f"target-owned receipt ownership docs missing {term}"

    assert len(bullets) >= 9, "target-owned receipt ownership docs must cover ownership, trust boundaries, linkage, and status states"

    require(
        "meshkit-ios/Sources/MeshKit/MeshReceipt.swift",
        [
            "public struct MeshReceiptOwnership",
            "public struct MeshReceiptChainProofOwnership",
            "public enum MeshReceiptOwnershipMapper",
            "public static func targetOwnedResultFields",
            "public static func ownership(of receipt: MeshReceipt)",
            "public static func assertTargetOwned",
            "receiptOwnerResultKey",
            "targetReceiptOwnerResultKey",
            "receiptOwner == targetReceiptOwner",
            "ownership.receiptOwner == expectedOwner",
            "ownership.targetReceiptOwner == expectedOwner",
            "public static func targetOwnedProof(",
            "expectedRequest",
            "anchoredRequestLinkage",
        ],
    )
    require(
        "meshkit-ios/Sources/MeshKit/DailyMartTargetReceiptFactory.swift",
        [
            "MeshReceiptOwnershipMapper.targetOwnedResultFields",
            "MeshReceiptOwnershipMapper.assertTargetOwned",
            "targetAppId",
            "targetBundleId",
            "DailyMartTargetReceiptFactory",
            "MeshReceiptChainProofSerializer.receiptResultFields",
        ],
    )
    require(
        "meshkit-ios/Tests/MeshKitTests/MeshKitTests.swift",
        [
            "testSerializedDailyMartReceiptOwnershipMappingIsTargetOwned",
            "testTargetOwnedReceiptChainProofOwnershipRejectsCallerOwnedReceiptFields",
            "testTargetOwnedReceiptChainProofOwnershipBindsProofToSignedRequest",
            "testTargetOwnedReceiptChainProofOwnershipSerializesAnchoredMCPRequestLinkage",
            "receiptOwner",
            "targetReceiptOwner",
            "MeshReceiptOwnershipMapper.assertTargetOwned",
            "MeshReceiptChainProofSerializer.targetOwnedProof",
        ],
    )
    require(
        "meshkit-ios/Tests/MeshKitTests/DailyMartTargetReceiptFactoryTests.swift",
        [
            "testAcceptedAppToAppCallCreatesDailyMartOwnedReceiptNotCallerOwned",
            "testVerifiedFailedExecutionAttemptCreatesFailedDailyMartOwnedReceipt",
            "testPolicyDeniedWalletExecutionCreatesFailedDailyMartOwnedReceipt",
            "receiptOwner",
            "targetReceiptOwner",
            "callerOwner",
            "providerOwner",
            "XCTAssertNotEqual(ownership.receiptOwner, callerOwner)",
            "XCTAssertNotEqual(ownershipProof.ownership.receiptOwner, callerOwner)",
            "MeshReceiptOwnershipMapper.assertTargetOwned",
            "MeshReceiptChainProofSerializer.targetOwnedProof",
        ],
    )


def verify_signed_mcp_request_signature_docs():
    docs_rel = "docs/agentos-trust-layer.md"
    bullets = extract_marked_bullets(
        docs_rel,
        "signed-mcp-request-signature-requirements-start",
        "signed-mcp-request-signature-requirements-end",
    )
    joined = "\n".join(bullets)
    required_doc_terms = [
        "MeshRequest.signingInputData()",
        "meshkit-request-signing/v1",
        "request id, caller app id, caller bundle id, caller public key id",
        "target bundle id, target capability id, target capability version",
        "payload hash algorithm, payload hash value, timestamp, and nonce",
        "MeshSignedMCPRequestVerifier.verify(_:)",
        "target policy, trusted caller app id, trusted caller bundle id",
        "caller public key id, request signature algorithm, request signature key id",
        "payload hash, and cryptographic signature",
        "DailyMartSignedMCPRequestVerifier.verify(_:)",
        "Hermes/agent OCG request signer",
        "must not accept wallet keys, provider callbacks, anchor transaction hashes, or maroo chain proofs",
        "reject tampered payloads",
        "reject requests signed by the wrong signer key id",
        "before nonce reservation, request anchoring, delegated wallet authorization, OKRW payment or transfer execution",
    ]
    for term in required_doc_terms:
        assert term in joined, f"signed MCP request signature docs missing {term}"

    assert len(bullets) >= 6, "signed MCP request signature docs must cover canonical input, trust metadata, rejection cases, and execution ordering"

    require(
        "meshkit-ios/Sources/MeshKit/MeshRequest.swift",
        [
            "public func signingInputData() -> Data",
            "meshkit-request-signing/v1",
            "requestId",
            "caller.appId",
            "caller.bundleId",
            "caller.publicKeyId",
            "target.targetBundleId",
            "target.capabilityId",
            "target.version",
            "payloadHash.algorithm.lowercased()",
            "payloadHash.value.lowercased()",
            "timestamp",
            "nonce",
        ],
    )
    require(
        "meshkit-ios/Sources/MeshKit/MeshSignedRequestVerification.swift",
        [
            "public struct MeshSignedMCPRequestVerifier",
            "public func verify(_ request: MeshRequest) throws",
            "MeshTarget.validate(request, policy: policy)",
            "request.caller.appId != trust.callerAppId",
            "request.caller.bundleId != trust.callerBundleId",
            "request.caller.publicKeyId != expectedKeyId",
            "request.signature.algorithm != expectedAlgorithm",
            "request.signature.keyId != expectedKeyId",
            "MeshTarget.verifyPayloadHash(request)",
            "MeshTarget.verifyRequiredSignature(request, trust: trust)",
            "public struct DailyMartSignedMCPRequestVerifier",
            "expectedHermesAgentSigner",
            "try payloadHashValidator.validate(request)",
            "try verifier.verify(request)",
        ],
    )
    require(
        "meshkit-ios/Tests/MeshKitTests/DailyMartSignedMCPRequestVerifierTests.swift",
        [
            "testDailyMartSignatureVerifierAcceptsExpectedSignerAndCanonicalPayloadHash",
            "testDailyMartSignatureVerifierRejectsTamperedPayload",
            "testDailyMartSignatureVerifierRejectsWrongSigner",
            ".payloadHashMismatch",
            ".signatureMismatch(\"request signing key id mismatch\")",
            "unsigned.signingInputData()",
        ],
    )


def verify_maroo_adapter_config_docs():
    docs_rel = "docs/agentos-trust-layer.md"
    swift_rel = "meshkit-ios/Sources/MeshKit/MeshChainProvider.swift"
    endpoint_rows = extract_marked_table(
        docs_rel,
        "maroo-adapter-config-endpoints-start",
        "maroo-adapter-config-endpoints-end",
    )
    env_rows = extract_marked_table(
        docs_rel,
        "maroo-adapter-config-env-start",
        "maroo-adapter-config-env-end",
    )
    documented_endpoint_keys = [extract_backtick_key(row[0]) for row in endpoint_rows]
    documented_env_keys = [extract_backtick_key(row[0]) for row in env_rows]
    expected_endpoint_keys = extract_swift_string_array(swift_rel, "endpointConfigurationKeys")
    expected_env_keys = (
        extract_swift_string_array(swift_rel, "requiredEnvironmentKeys")
        + extract_swift_string_array(swift_rel, "optionalEnvironmentKeys")
    )
    assert documented_endpoint_keys == expected_endpoint_keys, (
        "docs maroo endpoint config keys must match MeshMarooTestnetAdapterConfigSchema: "
        f"{documented_endpoint_keys} != {expected_endpoint_keys}"
    )
    assert documented_env_keys == expected_env_keys, (
        "docs maroo env keys must match MeshMarooTestnetAdapterConfigSchema: "
        f"{documented_env_keys} != {expected_env_keys}"
    )
    require(
        docs_rel,
        [
            "meshkit-maroo-testnet-adapter-config/v1",
            "MeshMarooTestnetAdapterConfigSchema",
            "MESHKIT_IOS_MAROO_LIVE_TX_HASH",
            "MESHKIT_IOS_MAROO_ANCHOR_TX_HASH",
            "MESHKIT_MAROO_OKRW_CONTRACT_ADDRESS",
        ],
    )


def verify_external_chain_outage_fallback_docs():
    docs_rel = "docs/agentos-trust-layer.md"
    bullets = extract_marked_bullets(
        docs_rel,
        "external-chain-outage-fallback-start",
        "external-chain-outage-fallback-end",
    )
    joined = "\n".join(bullets)
    expected_blockers = [
        "rpc_unavailable",
        "explorer_unavailable",
        "faucet_unavailable",
        "okrw_contract_unavailable",
        "funded_wallet_unavailable",
        "payment_confirmation_unavailable",
        "request_anchor_unavailable",
    ]
    assert len(bullets) == len(expected_blockers), (
        "external-chain outage docs must define exactly one fallback bullet per blocker type"
    )
    for blocker in expected_blockers:
        matches = [bullet for bullet in bullets if bullet.startswith(f"`{blocker}`:")]
        assert len(matches) == 1, f"external-chain outage docs must define one {blocker} trigger"

    required_doc_terms = [
        "MeshMarooTestnetRPCAvailabilityCheck",
        "eth_blockNumber",
        "net_version",
        "https://rpc-testnet.maroo.io",
        "artifacts/maroo-testnet/status.json",
        "failed or pending provider-neutral proof",
        "never synthesizes `txHash`, `explorerUrl`, or `confirmedAt`",
        "MeshMarooTestnetExplorerAvailabilityCheck",
        "https://explorer-testnet.maroo.io",
        "omits runnable explorer links for unconfirmed receipts",
        "submitted-not-final or attempted-failed state",
        "MeshMarooTestnetFaucetAvailabilityCheck",
        "https://faucet.maroo.io",
        "does not debit HermesChat delegated remaining limit",
        "MeshMarooTestnetOKRWContractAvailabilityCheck",
        "eth_getCode OKRW",
        "MESHKIT_MAROO_OKRW_CONTRACT_ADDRESS",
        "does not create confirmed payment proof",
        "cannot prove a funded delegated OKRW wallet",
        "preserves signed MCP request and policy linkage",
        "repeat saved-grant behavior",
        "cannot return a live confirmed OKRW payment or transfer receipt",
        "signed request hash, request nonce, anchoring reference",
        "does not mark HermesChat as paid or complete",
        "MeshRequestAnchorIdentifier",
        "anchoring reference only",
        "target-owned DailyMart receipt evidence",
    ]
    for term in required_doc_terms:
        assert term in joined, f"external-chain outage fallback docs missing {term}"

    presentation_bullets = extract_marked_bullets(
        docs_rel,
        "external-chain-outage-presentation-states-start",
        "external-chain-outage-presentation-states-end",
    )
    assert len(presentation_bullets) == 2, (
        "external-chain outage presentation docs must define pending and failed states"
    )
    expected_presentations = {
        "`pending/submitted_not_final`:": [
            "operator-facing state must expose",
            "BlockedByExternalChain",
            "blockerType",
            "externalChainEndpoint",
            "operation",
            "observedAt",
            "signed request hash",
            "request nonce",
            "anchoring reference",
            "`executionAttemptId`",
            "target-owned DailyMart receipt id",
            "user-facing state must show \"submitted but not final\"",
            "keep delegated remaining limit unchanged",
            "show submittedAt and anchoringReference",
            "never show paid, complete, `txHash`, `explorerUrl`, or `confirmedAt`",
        ],
        "`failed/attempted_failed`:": [
            "operator-facing state must expose",
            "BlockedByExternalChain",
            "blockerType",
            "externalChainEndpoint",
            "operation",
            "observedAt",
            "signed request hash",
            "request nonce",
            "anchoring reference",
            "`executionAttemptId`",
            "`errorCode`",
            "`errorMessage`",
            "target-owned DailyMart receipt id",
            "user-facing state must show \"attempted but not paid\"",
            "keep delegated remaining limit unchanged",
            "show errorCode and errorMessage",
            "never show paid, complete, `txHash`, `explorerUrl`, or `confirmedAt`",
        ],
    }
    for prefix, terms in expected_presentations.items():
        matches = [bullet for bullet in presentation_bullets if bullet.startswith(prefix)]
        assert len(matches) == 1, (
            f"external-chain outage presentation docs must define one {prefix} bullet"
        )
        for term in terms:
            assert term in matches[0], (
                f"external-chain outage presentation docs missing {term} in {prefix}"
            )

    require(
        "meshkit-ios/Sources/MeshKit/MeshChainProvider.swift",
        [
            "public enum MeshExternalChainBlockerType",
            "case rpcUnavailable = \"rpc_unavailable\"",
            "case explorerUnavailable = \"explorer_unavailable\"",
            "case faucetUnavailable = \"faucet_unavailable\"",
            "case okrwContractUnavailable = \"okrw_contract_unavailable\"",
            "case fundedWalletUnavailable = \"funded_wallet_unavailable\"",
            "case paymentConfirmationUnavailable = \"payment_confirmation_unavailable\"",
            "case requestAnchorUnavailable = \"request_anchor_unavailable\"",
            "public struct MeshExternalChainBlockerEvidence",
            "public static let exitCondition = \"BlockedByExternalChain\"",
            "providerExtensionFields",
            "requestHash",
            "requestNonce",
            "anchoringReference",
            "txHash",
            "MeshMarooTestnetRPCAvailabilityCheck",
            "MeshMarooTestnetExplorerAvailabilityCheck",
            "MeshMarooTestnetFaucetAvailabilityCheck",
            "MeshMarooTestnetOKRWContractAvailabilityCheck",
        ],
    )
    require(
        "scripts/verify_maroo_testnet_status.py",
        [
            "EXIT_CONDITION = \"BlockedByExternalChain\"",
            "blocker_evidence",
            "fail_with_blocker(\"rpc_unavailable\"",
            "fail_with_blocker(\"explorer_unavailable\"",
            "fail_with_blocker(\"faucet_unavailable\"",
            "fail_with_blocker(\"okrw_contract_unavailable\"",
            "\"eth_blockNumber\"",
            "\"net_version\"",
            "\"eth_getCode\"",
            "No deterministic fallback hash may be represented as confirmed payment proof.",
            "ARTIFACT_PATH",
        ],
    )
    require(
        "meshkit-ios/Tests/MeshKitTests/MarooRPCAvailabilityBlockerTests.swift",
        [
            "testMarooRPCAvailabilityFailureCreatesBlockedByExternalChainEvidence",
            "testMarooRPCHTTPFailureStatusConvertsToRPCUnavailableEvidence",
            "testMarooRPCTransportFailureConvertsToRPCUnavailableEvidence",
            "testMarooRPCUnusableJSONRPCResultConvertsToRPCUnavailableEvidence",
            "rpc_unavailable",
        ],
    )
    require(
        "meshkit-ios/Tests/MeshKitTests/MarooExplorerAvailabilityBlockerTests.swift",
        [
            "testMarooExplorerAvailabilityFailureCreatesBlockedByExternalChainEvidence",
            "testMarooExplorerHTTPFailureStatusConvertsToExplorerUnavailableEvidence",
            "testMarooExplorerTransportFailureConvertsToExplorerUnavailableEvidence",
            "explorer_unavailable",
        ],
    )
    require(
        "meshkit-ios/Tests/MeshKitTests/MarooFaucetAvailabilityBlockerTests.swift",
        [
            "testMarooFaucetAvailabilityFailureCreatesBlockedByExternalChainEvidence",
            "testMarooFaucetHTTPFailureStatusConvertsToFaucetUnavailableEvidence",
            "testMarooFaucetTransportFailureConvertsToFaucetUnavailableEvidence",
            "faucet_unavailable",
        ],
    )
    require(
        "meshkit-ios/Tests/MeshKitTests/MarooOKRWContractAvailabilityBlockerTests.swift",
        [
            "testMarooOKRWContractAvailabilityFailureCreatesBlockedByExternalChainEvidence",
            "testMarooOKRWContractHTTPFailureStatusConvertsToContractUnavailableEvidence",
            "testMarooOKRWContractTransportFailureConvertsToContractUnavailableEvidence",
            "testMarooOKRWContractEmptyBytecodeConvertsToContractUnavailableEvidence",
            "okrw_contract_unavailable",
        ],
    )
    require(
        "meshkit-ios/Tests/MeshKitTests/MarooPaymentExecutorAdapterTests.swift",
        [
            "testMarooStateMapperUsesExplicitFallbackStatusWhenLiveConfirmationIsUnavailable",
            "testExternallyBlockedPaymentStateMapperNeverConfirmsWithoutLiveExecutionProof",
            "testMarooTestnetPaymentExecutorMapsOKRWContractAvailabilityFailureToExternalChainBlocker",
            "testExternalChainBlockerEvidenceSerializesProviderNeutralTestnetAvailabilityFailure",
            "BlockedByExternalChain",
        ],
    )
    require(
        "meshkit-ios/Tests/MeshKitTests/DailyMartTargetReceiptFactoryTests.swift",
        [
            "testDailyMartReceiptSerializationPreservesBlockedByExternalChainEvidence",
            "externalChainExitCondition",
            "externalChainBlockerType",
            "payment_confirmation_unavailable",
            "XCTAssertNil(decodedReceipt.result[\"txHash\"])",
            "XCTAssertNil(decodedReceipt.result[\"explorerUrl\"])",
        ],
    )
    require(
        "meshkit-ios/Tests/MeshKitTests/HermesChatDelegatedWalletViewModelTests.swift",
        [
            "testFailedReceiptPresentationRendersBlockedByExternalChainEvidenceBesideAttemptedFailedState",
            "testPendingReceiptDisplayStateRendersSubmittedNonFinalWithoutDebitingDelegatedLimit",
            "testReceiptPresentationDoesNotRenderExplorerLinkForUnconfirmedReceipt",
            "BlockedByExternalChain",
            "payment_confirmation_unavailable",
            "rpc_unavailable",
        ],
    )


def verify_external_chain_outage_recovery_guidance_docs():
    docs_rel = "docs/agentos-trust-layer.md"
    bullets = extract_marked_bullets(
        docs_rel,
        "external-chain-outage-recovery-guidance-start",
        "external-chain-outage-recovery-guidance-end",
    )
    expected_steps = [
        "`retry`:",
        "`reconciliation`:",
        "`receipt_finalization`:",
        "`escalation`:",
    ]
    assert len(bullets) == len(expected_steps), (
        "external-chain outage recovery docs must define retry, reconciliation, receipt finalization, and escalation"
    )
    for step in expected_steps:
        matches = [bullet for bullet in bullets if bullet.startswith(step)]
        assert len(matches) == 1, f"external-chain outage recovery docs must define one {step} bullet"

    expected_recovery_terms = {
        "`retry`:": [
            "python3 scripts/verify_maroo_testnet_status.py",
            "MeshRequestAnchorIdentifier",
            "MeshPaymentExecutionResult",
            "original signed request hash",
            "request nonce",
            "anchoring reference",
            "`executionAttemptId`",
            "policy id",
            "policy hash",
            "repeat saved-grant freshness",
            "must never reuse a prior signed MCP request id, nonce, signature, or target-owned receipt",
        ],
        "`reconciliation`:": [
            "maroo RPC",
            "explorer",
            "OKRW contract",
            "wallet evidence",
            "artifacts/maroo-testnet/status.json",
            "pending DailyMart receipt result fields",
            "persisted `BlockedByExternalChain` evidence",
            "recovered `txHash`, `explorerUrl`, or `confirmedAt`",
            "same signed request hash",
            "request nonce",
            "anchoring reference",
            "`executionAttemptId`",
            "asset, amount, and recipient",
        ],
        "`receipt_finalization`:": [
            "confirmed OKRW payment or transfer evidence",
            "fresh target-owned MeshKit receipt",
            "`status=confirmed`",
            "`presentationState=paid_complete`",
            "`chainStatus=confirmed`",
            "`txHash`",
            "`explorerUrl`",
            "`confirmedAt`",
            "HermesChat decrements delegated remaining limit only after this finalized target-owned receipt verifies",
            "pending or failed receipts remain non-final audit records",
        ],
        "`escalation`:": [
            "cannot bind live chain evidence to the signed MCP request",
            "keep the receipt pending or failed",
            "keep delegated remaining limit unchanged",
            "unresolved `BlockedByExternalChain` evidence",
            "blocker type",
            "endpoint",
            "operation",
            "observedAt",
            "signed request hash",
            "request nonce",
            "anchoring reference",
            "`executionAttemptId`",
            "target-owned DailyMart receipt id",
            "maroo status artifact path",
            "instead of fabricating completion proof",
        ],
    }
    for prefix, terms in expected_recovery_terms.items():
        bullet = next(item for item in bullets if item.startswith(prefix))
        for term in terms:
            assert term in bullet, (
                f"external-chain outage recovery docs missing {term} in {prefix}"
            )


verify_maroo_adapter_config_docs()
verify_maroo_verification_commands_docs()
verify_signed_mcp_request_anchoring_docs()
verify_signed_anchor_okrw_transaction_linkage_docs()
verify_target_owned_receipt_ownership_docs()
verify_signed_mcp_request_signature_docs()
verify_external_chain_outage_fallback_docs()
verify_external_chain_outage_recovery_guidance_docs()


require(
    "meshkit-ios/Sources/MeshKit/MeshRequestAnchor.swift",
    [
        "public enum MeshRequestAnchorStatus",
        "case pending",
        "case confirmed",
        "case failed",
        "func requestAnchorStatus(",
        "func requestAnchorStatusValue(",
        "MeshRequestAnchorIdentifier",
    ],
)

for rel in [
    "meshkit-ios/Sources/MeshKit/MeshRequestAnchor.swift",
    "meshkit-ios/Sources/MeshKit/MeshPaymentExecutor.swift",
]:
    forbid(
        rel,
        [
            "address_ref",
            "home.saved",
            "\"items\"",
        ],
    )

require(
    "meshkit-ios/Sources/MeshKit/MeshChainProvider.swift",
    [
        "case anchorSignedRequest",
        "case lookupRequestAnchorStatus",
        "case constructExplorerURL",
        "MeshExternalChainBlockerEvidence",
        "MeshMarooTestnetRPCAvailabilityCheck",
        "MeshMarooTestnetExplorerAvailabilityCheck",
        "MeshMarooTestnetFaucetAvailabilityCheck",
        "MeshMarooTestnetOKRWContractAvailabilityCheck",
        "BlockedByExternalChain",
        "rpc_unavailable",
        "explorer_unavailable",
        "faucet_unavailable",
        "okrw_contract_unavailable",
        "payment_confirmation_unavailable",
    ],
)

require(
    "meshkit-ios/Tests/MeshKitTests/MarooExplorerAvailabilityBlockerTests.swift",
    [
        "MeshMarooTestnetExplorerAvailabilityCheck",
        "BlockedByExternalChain",
        "explorer_unavailable",
        "testMarooExplorerHTTPFailureStatusConvertsToExplorerUnavailableEvidence",
        "testMarooExplorerTransportFailureConvertsToExplorerUnavailableEvidence",
    ],
)

require(
    "meshkit-ios/Tests/MeshKitTests/MarooOKRWContractAvailabilityBlockerTests.swift",
    [
        "MeshMarooTestnetOKRWContractAvailabilityCheck",
        "BlockedByExternalChain",
        "okrw_contract_unavailable",
        "testMarooOKRWContractHTTPFailureStatusConvertsToContractUnavailableEvidence",
        "testMarooOKRWContractEmptyBytecodeConvertsToContractUnavailableEvidence",
    ],
)

require(
    "meshkit-ios/Sources/MeshKit/HermesChatDelegatedWalletViewModel.swift",
    [
        "public struct MeshDelegatedWalletPanelSnapshot",
        "public struct MeshDelegatedWalletPanelRow",
        "public struct MeshDelegatedWalletReceiptDisplayState",
        "dailyMartReceiptDisplayState",
        "paymentPresentation.renderedLines + [remainingLimitUnchangedLine]",
        "pendingSubmittedAtLine",
        "pendingAnchoringReferenceLine",
        "submittedAt=\\(submittedAt)",
        "anchoringReference=\\(anchoringReference)",
        "Payment state: attempted · unpaid · incomplete",
        "Remaining session limit unchanged",
        "AgentOS/OCG delegated wallet",
        "maroo testnet",
        "DailyMart grocery.purchase_essentials",
        "sessionLimitLine",
        "remainingLimitLine",
        "perPaymentMaxLine",
        "authorizationLine",
        "Total session limit",
        "Remaining limit",
        "Per-payment max",
        "Authorization",
        "Asset",
        "rows = [",
        "authorizationLine = \"\\(formatter.asset) · \\(scopePresentation.label)\"",
    ],
)

require(
    "meshkit-ios/Samples/iOSDemo/HermesChat/HermesChatApp.swift",
    [
        "snapshot.headerLabel",
        "snapshot.rows",
        "WalletSummaryRow(label: row.label, value: row.value)",
        "snapshot.accessibilityLabel",
        "DelegatedWalletPanel(snapshot: delegatedWallet.panelSnapshot)",
        ".submittedNotFinal",
        ".policyDenied",
        "displayState?.renderedLines.joined(separator: \"\\n\")",
        "BlockedByExternalChain",
        "no txHash accepted as confirmed fallback",
        "no txHash.",
        "confirmedReceiptExplorerURL",
        "Link(destination: confirmedReceiptExplorerURL)",
        "Open maroo explorer receipt link",
    ],
)

require(
    "meshkit-ios/Tests/MeshKitTests/HermesChatDelegatedWalletViewModelTests.swift",
    [
        "testFailedReceiptDisplayStateKeepsRenderedRemainingLimitUnchangedAfterProcessing",
        "testFailedReceiptPresentationRendersBlockedByExternalChainEvidenceBesideAttemptedFailedState",
        "errorCode: rpc_unavailable",
        "errorMessage: maroo RPC did not return a transaction receipt",
    ],
)

require(
    "meshkit-ios/Samples/iOSDemo/DailyMart/DailyMartApp.swift",
    [
        "https://explorer-testnet.maroo.io/tx/",
        "DailyMartPreExecutionMCPGuard",
        "DailyMartTargetReceiptFactory",
        "MESHKIT_IOS_MAROO_LIVE_TX_HASH",
        "BlockedByExternalChain",
        "status: .pending",
        "presentationState: .submittedNotFinal",
        "--confirmed-receipt-ui-proof",
        "--pending-receipt-ui-proof",
        "--failed-receipt-ui-proof",
        "--policy-denied-receipt-ui-proof",
        "Confirmed provider-neutral chain proof",
        "Pending provider-neutral chain proof",
        "Failed provider-neutral chain proof",
        "Policy-denied provider-neutral chain proof",
        "DailyMartReceiptProofField.confirmedFields",
        "DailyMartReceiptProofField.pendingFields",
        "DailyMartReceiptProofField.failedFields",
        "DailyMartReceiptProofField.policyDeniedFields",
        "meshkit-execution-attempt/v1:pay-pending-ui:auth-pending-ui:exec-pending-ui",
        "0xanchorDailyMartPendingUIReceipt",
        "meshkit-execution-attempt/v1:pay-failed-ui:auth-failed-ui:exec-failed-ui",
        "0xanchorDailyMartFailedUIReceipt",
        "proof_type=payment_execution",
        "Submitted at",
        "Execution kind",
        "Anchor tx hash",
        "Error code",
        "Error message",
        "attempted_failed",
        "policy_denial",
        "policy_denied",
        "wallet_policy_denied",
        "BlockedByExternalChain",
    ],
)

require(
    "meshkit-ios/Samples/iOSDemo/UITests/MeshKitiOSDemoUITests.swift",
    [
        "testDailyMartConfirmedReceiptRendersProviderNeutralChainProofFields",
        "--confirmed-receipt-ui-proof",
        "Confirmed provider-neutral chain proof",
        "payment_execution",
        "paid_complete",
        "confirmed-chain-proof-debug-ui",
        "chain-proof-field-",
        "assertVisibleElement",
        "0xokrwDailyMartConfirmedUIReceipt",
        "testDailyMartPendingReceiptRendersProviderNeutralChainProofFields",
        "--pending-receipt-ui-proof",
        "Pending provider-neutral chain proof",
        "pending-chain-proof-debug-ui",
        "providerNeutralPendingFields",
        "payment_execution",
        "submitted_not_final",
        "ios-grocery-pending-ui-nonce",
        "meshkit-execution-attempt/v1:pay-pending-ui:auth-pending-ui:exec-pending-ui",
        "0xanchorDailyMartPendingUIReceipt",
        "Pending receipt UI must not render a payment txHash field as proof of completion",
        "BlockedByExternalChain",
        "payment_confirmation_unavailable",
        "testDailyMartFailedReceiptRendersProviderNeutralChainProofFields",
        "--failed-receipt-ui-proof",
        "failed-chain-proof-debug-ui",
        "providerNeutralFailedFields",
        "chain-proof-field-\\(schemaName)",
        "Failed provider-neutral chain proof",
        "attempted_failed",
        "ios-grocery-failed-ui-nonce",
        "meshkit-execution-attempt/v1:pay-failed-ui:auth-failed-ui:exec-failed-ui",
        "Execution kind",
        "maroo RPC did not return a transaction receipt",
        "testDailyMartPolicyDeniedReceiptRendersProviderNeutralChainProofFields",
        "--policy-denied-receipt-ui-proof",
        "Policy-denied provider-neutral chain proof",
        "policy-denied-chain-proof-debug-ui",
        "providerNeutralPolicyDeniedFields",
        "chain-proof-field-\\(schemaName)",
        "policy_denial",
        "policy_denied",
        "ios-grocery-policy-denied-ui-nonce",
        "meshkit-execution-attempt/v1:policy-denied-ui:wallet-policy:exec-policy-denied-ui",
        "wallet_policy_denied",
        "policy-single-payment-max-exceeded",
    ],
)

require(
    "meshkit-ios/Sources/MeshKit/DailyMartTargetReceiptFactory.swift",
    [
        "MeshReceiptChainProofSerializer.receiptResultFields",
        "MeshReceiptOwnershipMapper.targetOwnedResultFields",
        "executionAttemptId",
        "policyDenialErrorFields",
        "errorCode",
        "errorMessage",
    ],
)

require(
    "README.md",
    [
        "https://rpc-testnet.maroo.io",
        "https://explorer-testnet.maroo.io",
        "https://faucet.maroo.io",
        "https://agent.maroo.io",
        "python3 scripts/verify_maroo_testnet_status.py",
        "artifacts/maroo-testnet/status.json",
        "No profiles for ai.meshkit.sample.hermeschat",
        "BlockedByExternalChain",
        "Plaintext cart items",
        "eth_blockNumber",
        "net_version",
        "eth_getCode",
        "okrw_contract_unavailable",
    ],
)

require(
    "docs/agentos-trust-layer.md",
    [
        "Provider-neutral chain proof",
        "Provider-Neutral Wallet Interface Contract",
        "Required interface names:",
        "Reference semantics:",
        "On-Chain Wallet Provider Adapter Responsibilities",
        "Required adapter inputs:",
        "Canonical signed MCP request hash, request id, request nonce",
        "Delegated spending policy inputs",
        "Anchor submission inputs",
        "Payment execution inputs",
        "Status lookup inputs",
        "Required adapter outputs:",
        "Provider identity and network identity through `MeshChainProviderIdentity`",
        "Request anchor result through `MeshRequestAnchor`",
        "Wallet result through `MeshAgentWalletIdentity`",
        "Payment result through `MeshPaymentExecutionResult`",
        "Receipt proof output through `MeshChainProofSchema.providerNeutral`",
        "Required adapter error handling:",
        "Map provider failures to provider-neutral errors",
        "anchor_submission_failed",
        "payment_execution_failed",
        "Return pending or failed proof states when confirmation cannot be observed",
        "Preserve policy-denied as `status=failed` plus `presentationState=policy_denied`",
        "Required adapter execution boundaries:",
        "Request signing, nonce freshness, payload hash validation, caller trust validation, and DailyMart target-owned receipt signing stay in MeshKit/App-to-App MCP",
        "DailyMart remains the execution boundary for `grocery.purchase_essentials`",
        "Provider-specific RPC, faucet, explorer, Agent Wallet Kit, OKRW contract, and chain serialization details stay inside the adapter layer",
        "future replaceable adapter path",
        "Agent Wallet Kit Future Adapter Path",
        "The Agent Wallet Kit future adapter path is a provider plugin behind the same MeshKit/OCG contracts used by the MVP maroo testnet adapter",
        "Extension points:",
        "`MeshChainProvider` may load Agent Wallet Kit network metadata",
        "`MeshRequestAnchorProvider` may submit signed request anchors through Agent Wallet Kit APIs",
        "`MeshAgentWallet` may delegate request-anchor signing, execution-authorization signing, wallet address reporting, policy simulation, and authorization submission to Agent Wallet Kit",
        "`MeshPaymentExecutor` may execute OKRW payments or transfers through Agent Wallet Kit",
        "`MeshChainProofSchema.providerNeutral` may carry provider extension fields for Agent Wallet Kit response ids or diagnostic references",
        "Compatibility expectations:",
        "must accept the same canonical signed MCP request hash, request nonce, `policyId`, `policyHash`, asset, amount, recipient, wallet address, and anchoring reference",
        "must preserve DailyMart target-owned receipt signing",
        "must preserve repeat saved-grant behavior",
        "confirmed, pending, failed, and policy-denied outcomes",
        "deterministic fallbacks are never compatible with confirmed payment presentation",
        "MeshChainProvider",
        "MeshRequestAnchorProvider",
        "MeshAgentWallet",
        "MeshPaymentExecutor",
        "MeshChainProofSchema",
        "MeshChainProviderConfiguration",
        "MeshRequestAnchorPayload",
        "MeshSignedRequestAnchorMetadata",
        "MeshRequestAnchorIdentifier",
        "MeshAgentWalletIdentity",
        "MeshAgentWalletConfiguration",
        "MeshPaymentExecutorConfiguration",
        "MeshPaymentExecutionResult",
        "MeshPaymentExecutorCapabilityError",
        "MeshChainProofReference",
        "canonical signed request hash, request nonce, `policyId`, and `policyHash`",
        "anchoring reference, not completion proof",
        "A deterministic fallback hash must never be presented as confirmed OKRW payment proof",
        "MeshChainProofSchema.providerNeutral",
        "meshkit-chain-proof-schema/v1",
        "maroo Testnet Adapter",
        "On-Chain Privacy",
        "https://docs.maroo.io",
        "must not put cart contents",
        "python3 scripts/verify_maroo_testnet_status.py",
        "artifacts/maroo-testnet/status.json",
        "BlockedByExternalChain",
        "eth_blockNumber",
        "net_version",
        "eth_getCode",
        "okrw_contract_unavailable",
    ],
)

require(
    "meshkit-ios/Sources/MeshKit/MeshChainProvider.swift",
    [
        "public protocol MeshChainProvider",
        "var identity: MeshChainProviderIdentity { get }",
        "func loadProviderConfiguration() throws -> MeshChainProviderConfiguration",
        "func identifyNetwork() throws -> MeshChainProviderIdentity",
        "func connect(checkedAt: String) async throws -> MeshChainProviderConnection",
        "func checkHealth(checkedAt: String) async throws -> MeshChainProviderHealth",
        "func lookupTransaction(",
        "func lookupProof(",
        "func explorerURL(transactionHash: String) throws -> URL",
        "func explorerURL(accountAddress: String) throws -> URL",
    ],
)

require(
    "meshkit-ios/Sources/MeshKit/MeshRequestAnchor.swift",
    [
        "public protocol MeshRequestAnchorProvider",
        "func anchorSignedRequest(",
        "payload: MeshRequestAnchorPayload",
        "metadata: MeshSignedRequestAnchorMetadata",
        "func requestAnchorStatus(",
        "func requestAnchorResolutionResponse(",
        "MeshRequestAnchorIdentifier",
    ],
)

require(
    "meshkit-ios/Sources/MeshKit/MeshAgentWallet.swift",
    [
        "public protocol MeshAgentWallet",
        "var identity: MeshAgentWalletIdentity { get }",
        "func loadWalletConfiguration() throws -> MeshAgentWalletConfiguration",
        "func reportWalletAddress() throws -> String",
        "func delegatedSpendingLimit() throws -> MeshAgentWalletDelegatedSpendingLimit",
        "func signingBoundary() throws -> MeshAgentWalletSigningBoundary",
        "func signRequestAnchorPayload(",
        "func signExecutionAuthorizationPayload(",
        "func authorizeExecution(",
    ],
)

require(
    "meshkit-ios/Sources/MeshKit/MeshPaymentExecutor.swift",
    [
        "public protocol MeshPaymentExecutor",
        "func loadPaymentExecutorConfiguration() throws -> MeshPaymentExecutorConfiguration",
        "func executePayment(_ request: MeshPaymentExecutionRequest, submittedAt: String) async throws -> MeshPaymentExecutionResult",
        "func paymentExecutionStatus(paymentId: String, checkedAt: String) async throws -> MeshPaymentExecutionResult",
        "func providerNeutralCapabilityError(",
        "MeshPaymentExecutorCapabilityError.providerNeutral",
    ],
)

require(
    "scripts/verify_maroo_testnet_status.py",
    [
        "https://rpc-testnet.maroo.io",
        "https://explorer-testnet.maroo.io",
        "eth_blockNumber",
        "net_version",
        "artifacts",
        "maroo-testnet",
        "does not prove a funded",
        "BlockedByExternalChain",
        "blockerEvidence",
        "rpc_unavailable",
        "explorer_unavailable",
        "faucet_unavailable",
        "okrw_contract_unavailable",
        "MESHKIT_MAROO_OKRW_CONTRACT_ADDRESS",
        "eth_getCode",
    ],
)

require(
    "scripts/install_ios_device.sh",
    [
        "No Accounts",
        "No profiles for",
        "requires a development team",
        "DeviceSigning",
    ],
)

require(
    "meshkit-ios/Tests/MeshKitTests/MeshKitTests.swift",
    [
        "testRequestAnchorStatusLookupReturnsProviderNeutralPendingConfirmedAndFailedStates",
        "testRequestAnchorStatusModuleReturnsFailedForKnownAnchoringReference",
        "MeshRequestAnchorStatus.pending",
        ".confirmed",
        ".failed",
        "testRequestAnchorStatusLookupRequiresAdvertisedCapability",
        ".lookupRequestAnchorStatus",
    ],
)

require(
    "meshkit-ios/Sources/MeshKit/MeshChainProof.swift",
    [
        "MeshChainProofSchema",
        "meshkit-chain-proof-schema/v1",
        "providerNeutral",
        "confirmedRequiredFields",
        "pendingRequiredFields",
        "failedRequiredFields",
        "policyDeniedRequiredFields",
        "requiredFields(",
        "validateReceiptResultFields",
        "providerExtensions",
    ],
)

require(
    "meshkit-ios/Sources/MeshKit/MeshReceipt.swift",
    [
        "MeshReceiptBaseSchema",
        "meshkit-receipt-base-schema/v1",
        "requiredRootFields",
        "ownershipResultFields",
        "anchoringResultFields",
        "paymentOrTransferResultFields",
        "timestampFields",
        "statusDiscriminatorFields",
        "validateProviderNeutralCoreSchema",
    ],
)

require(
    "docs/agentos-trust-layer.md",
    [
        "Provider-Neutral Base Receipt Schema",
        "`MeshReceiptBaseSchema.providerNeutral`",
        "`meshkit-receipt-base-schema/v1`",
        "`MeshChainProofSchema.providerNeutral.validateReceiptResultFields(_:)`",
        "Confirmed receipt status-specific required result fields",
        "`chainStatus=confirmed`",
        "`chainProofType=payment_execution`",
        "`presentationState=paid_complete`",
        "`txHash`, `explorerUrl`, and `confirmedAt`",
        "must not include failure-only result fields `errorCode` or `errorMessage`",
        "testConfirmedReceiptSchemaValidationRunnableExampleAcceptsDailyMartReceipt",
        "Pending receipt status-specific required result fields",
        "`chainStatus=pending`",
        "`chainProofType=request_anchor`",
        "`chainProofType=payment_execution`",
        "`presentationState=submitted_not_final`",
        "Pending observation proof: `submittedAt`",
        "Pending receipts must not include confirmed-only result fields `txHash`, `explorerUrl`, or `confirmedAt`",
        "testPendingReceiptSchemaValidationRunnableExampleAcceptsDailyMartReceipt",
        "Failed receipt status-specific required result fields",
        "`chainStatus=failed`",
        "`chainProofType=payment_execution`",
        "`presentationState=attempted_failed`",
        "Failure proof: `errorCode` and `errorMessage`",
        "Failed receipts must not include confirmed-only result fields `txHash`, `explorerUrl`, or `confirmedAt`",
        "testFailedReceiptSchemaValidationRunnableExampleAcceptsDailyMartReceipt",
        "Policy-denied receipt status-specific required result fields",
        "`chainProofType=policy_denial`",
        "`presentationState=policy_denied`",
        "Policy denial execution linkage: `executionAttemptId` and `executionId`",
        "Denial proof: `errorCode` and `errorMessage`",
        "testPolicyDeniedReceiptSchemaValidationRunnableExampleAcceptsDailyMartReceipt",
        "Shared identity",
        "Ownership",
        "Anchoring",
        "Payment or transfer linkage",
        "Timestamps",
        "Status discriminators",
    ],
)

require(
    "meshkit-ios/Tests/MeshKitTests/DailyMartTargetReceiptFactoryTests.swift",
    [
        "testChainProofFieldSchemaExposesProviderNeutralConfirmedReceiptContract",
        "testConfirmedReceiptSchemaValidationRunnableExampleAcceptsDailyMartReceipt",
        "testPendingChainProofFieldSchemaExposesProviderNeutralRequestAnchorContract",
        "testPendingReceiptSchemaValidationRunnableExampleAcceptsDailyMartReceipt",
        "testFailedChainProofFieldSchemaExposesProviderNeutralReceiptContract",
        "testPolicyDeniedChainProofFieldSchemaExposesProviderNeutralOntologyFields",
        "testFailedReceiptSchemaValidationRunnableExampleAcceptsDailyMartReceipt",
        "testPolicyDeniedReceiptSchemaValidationRunnableExampleAcceptsDailyMartReceipt",
        "MeshChainProofSchema.providerNeutral",
        "schema.validateReceiptResultFields(receipt.result)",
        "receipt.result.txHash",
        "ontologyRequiredFields",
        "pendingOntologyRequiredFields",
        "failedOntologyRequiredFields",
        "policyDeniedOntologyRequiredFields",
        "confirmedRequiredFields.contains(\"txHash\")",
        "schema.pendingRequiredFields.contains(\"submittedAt\")",
        "missingSubmittedAt.removeValue(forKey: \"submittedAt\")",
        "incorrectlyConfirmedPending[\"txHash\"]",
        "schema.failedRequiredFields.contains(field)",
        "schema.policyDeniedRequiredFields.contains(field)",
        "missingErrorCode.removeValue(forKey: \"errorCode\")",
        "missingExecutionAttemptId.removeValue(forKey: \"executionAttemptId\")",
        "incorrectlyConfirmedFailure[\"txHash\"]",
        "incorrectlyConfirmedPolicyDenial[\"txHash\"]",
    ],
)

require(
    "meshkit-ios/Tests/MeshKitTests/MeshKitTests.swift",
    [
        "testReceiptBaseSchemaDocumentsSharedProtocolFieldsAndValidatesCommonInvalidFixtures",
        "MeshReceiptBaseSchema.providerNeutral",
        "schema.requiredRootFields",
        "schema.ownershipResultFields",
        "schema.anchoringResultFields",
        "schema.paymentOrTransferResultFields",
        "schema.timestampFields",
        "schema.statusDiscriminatorFields",
        "receipt.requestId",
        "receipt.requestPayloadHash.value",
        "receipt.result[amount]",
    ],
)

assert (ROOT / "scripts/install_ios_device.sh").exists(), "missing physical iPad install script"

status = subprocess.run(
    ["git", "status", "--short"],
    cwd=ROOT,
    check=True,
    text=True,
    capture_output=True,
).stdout
assert "xcuserdata" not in status, "xcuserdata must not appear in git status"

print("Mobile E2E runtime proof docs/scripts verification passed")
