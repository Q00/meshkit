# AgentOS Trust Layer

MeshKit is the seed of an AgentOS trust layer: an app call graph where each participating app can verify, consent, execute, and prove what happened.

## Layers

1. **Open Calling Graph**
   - App capability manifests.
   - Risk class and consent policy.
   - Verification keys and callback metadata.

2. **App-to-App MCP envelope**
   - Canonical request signing.
   - Payload hash, nonce, timestamp, caller identity, target capability, and signature.
   - Deterministic validation before target business logic.

3. **Target app execution boundary**
   - The target app owns user consent.
   - The target app validates budget and replay policy.
   - The target app executes its own handler.

4. **Receipt and audit layer**
   - Target-signed receipt.
   - Caller-side receipt verification.
   - Optional blockchain anchoring for registry state, revocation, and receipt hashes.
   - `MeshReceiptBaseSchema.providerNeutral` exposes the runnable `meshkit-receipt-base-schema/v1` contract for the root receipt envelope and shared result-field families.

5. **Provider-neutral chain proof**
   - `ChainProvider`, `RequestAnchor`, `AgentWallet`, `PaymentExecutor`, and `ChainProof` stay provider-neutral.
   - `MeshChainProofSchema.providerNeutral` exposes the runnable `meshkit-chain-proof-schema/v1` field contract for confirmed DailyMart receipts, pending request-anchor proofs, failed payment proofs, and explicit policy-denied proofs.
   - Policy-denied proofs use provider-neutral fields: `proofType=policy_denial`, `status=failed`, `presentationState=policy_denied`, request hash, request nonce, policy id, policy hash, wallet address, amount, asset, recipient, anchoring reference, execution attempt id, execution id, error code, and error message. They do not require `txHash`, `explorerUrl`, `confirmedAt`, `paymentId`, or `authorizationId`.
   - The maroo testnet adapter is the demo provider for request anchoring and OKRW payment or transfer execution.
   - DailyMart receipts serialize `proofType`, `status`, `presentationState`, request hash, request nonce, policy id, policy hash, anchoring reference, execution attempt identity, tx hash, explorer URL, and status-specific error fields without maroo-specific core receipt fields.

## Signed MCP Request Anchoring

The signed App-to-App MCP request is the trust object that DailyMart validates before policy checks, request anchoring, wallet authorization, OKRW execution, or receipt creation. Anchoring records a provider-neutral commitment to that already-signed request; it augments request signing and target-owned receipt verification, but it never replaces either one.

## Signed MCP Request Signature Requirements

DailyMart accepts an App-to-App MCP request only when the request is signed by the Hermes/agent request signer advertised through OCG trust metadata. The signature is checked over the canonical MeshKit request signing input, not over provider callback data, wallet authorization data, or maroo transaction proof.

The runnable documentation check `python3 scripts/verify_mobile_e2e_runtime_docs.py` parses the following requirements and verifies that the SDK verifier and Swift signature tests cover them.

<!-- signed-mcp-request-signature-requirements-start -->
- `MeshRequest.signingInputData()` must use `meshkit-request-signing/v1` and include request id, caller app id, caller bundle id, caller public key id, target bundle id, target capability id, target capability version, payload hash algorithm, payload hash value, timestamp, and nonce.
- `MeshSignedMCPRequestVerifier.verify(_:)` must validate target policy, trusted caller app id, trusted caller bundle id, caller public key id, request signature algorithm, request signature key id, payload hash, and cryptographic signature before DailyMart executes business logic.
- `DailyMartSignedMCPRequestVerifier.verify(_:)` must use the Hermes/agent OCG request signer and must not accept wallet keys, provider callbacks, anchor transaction hashes, or maroo chain proofs as request signature proof.
- DailyMart must reject tampered payloads whose canonical payload hash no longer matches the signed request payload hash.
- DailyMart must reject requests signed by the wrong signer key id or by a key that does not match the OCG trust metadata.
- Signature verification must happen before nonce reservation, request anchoring, delegated wallet authorization, OKRW payment or transfer execution, and target-owned receipt creation.
<!-- signed-mcp-request-signature-requirements-end -->

The runnable documentation check `python3 scripts/verify_mobile_e2e_runtime_docs.py` parses the following requirements and verifies the SDK names that implement them are present.

<!-- signed-mcp-request-anchoring-requirements-start -->
- `MeshRequestAnchorHashInput` canonicalizes the signed MCP request using request id, request nonce, timestamp, caller identity, target capability, payload hash, and signature fields.
- `MeshSignedRequestAnchorMetadata` carries the canonical signed request hash, request id, request nonce, target capability, caller identity, signature key id, signature algorithm, and signature value into anchoring.
- `MeshRequestAnchorPayload` binds `MeshSignedRequestAnchorMetadata` to `policyId` and `policyHash` before provider submission.
- `MeshRequestAnchorProvider.anchorSignedRequest(payload:metadata:submittedAt:)` submits only the provider-neutral anchor payload and metadata; maroo remains a demo adapter behind that protocol.
- `MeshRequestAnchorIdentifier` is an anchoring reference for submitted, pending, confirmed, failed, or unavailable anchor state, not payment completion proof and not a DailyMart completion receipt.
- `MeshSignedMCPRequestAnchoringFields` exposes the same signed request hash, request nonce, policy id, and policy hash from anchor, wallet execution, and payment execution contexts so OKRW execution is linked to the anchored request.
- Each repeat saved-grant tap must create a fresh request id, nonce, signature, signed request hash, anchoring reference, execution attempt id, and DailyMart target-owned receipt id.
- DailyMart must verify request signature, payload hash, nonce freshness, caller trust, policy id, policy hash, merchant scope, capability scope, and consent grant before anchoring or payment execution.
- On-chain anchor data must be limited to hash and reference material such as signed request hash, request nonce, policy id, policy hash, anchoring reference, status, tx hash, and explorer URL; cart contents, delivery address references, user identity details, consent text, and chat content must stay off-chain.
- Target-owned DailyMart MeshKit receipts remain the completion proof; Hermes/caller keys, wallet keys, provider callbacks, or anchor transaction hashes are not accepted as target completion proof.
<!-- signed-mcp-request-anchoring-requirements-end -->

## Signed Anchor To OKRW Transaction Linkage

The runnable documentation check `python3 scripts/verify_mobile_e2e_runtime_docs.py` parses the following requirements and verifies that the SDK and maroo adapter tests document the transaction linkage boundary.

<!-- signed-anchor-okrw-transaction-linkage-start -->
- DailyMart links OKRW payment or transfer execution to the anchored signed MCP request through `MeshPaymentExecutionRequest`, not through a provider callback alone.
- `MeshMarooTestnetExecutionLinkPayload` carries provider metadata, execution kind, asset, amount, recipient, request id, request nonce, payload hash, signed request hash, anchoring reference, policy id, policy hash, payment id, authorization id, and execution id into the maroo adapter boundary.
- `MeshMarooTestnetOKRWExecutionTransactionRequest` serializes the OKRW transaction request with `signed_mcp_request_hash`, `anchoring_reference`, `anchor_metadata`, `payment_id`, `authorization_id`, `execution_id`, `execution_kind`, `asset=OKRW`, `amount`, and `recipient_address`.
- `MeshMarooTestnetOKRWExecutionAnchorMetadata` must match the signed MCP request hash, request nonce, anchoring reference, optional anchor transaction hash, policy id, and policy hash before OKRW execution is treated as linked.
- `MeshPaymentExecutionReceiptLinkageMapper.map` rejects mismatched request hashes and maps successful, pending, or failed OKRW execution results into receipt fields containing request hash, request nonce, policy id, policy hash, anchoring reference, execution attempt id, transaction hash only when present, and execution kind.
- OKRW payment and OKRW transfer share the same signed-request linkage requirements; `executionKind=payment` or `executionKind=transfer` changes the operation type but not the anchored trust object.
- A request anchor transaction hash or provider callback is not sufficient payment completion proof; confirmed paid-complete presentation still requires a target-owned DailyMart receipt with provider-neutral confirmed payment execution proof.
<!-- signed-anchor-okrw-transaction-linkage-end -->

## Provider-Neutral Base Receipt Schema

Every DailyMart completion proof is a target-owned MeshKit receipt first; chain anchoring and payment proof fields are linked into that receipt rather than replacing it. The SDK publishes the base contract as `MeshReceiptBaseSchema.providerNeutral` with version `meshkit-receipt-base-schema/v1`, and the runnable validator is `MeshReceipt.validateProviderNeutralCoreSchema(jsonData:)`.

The runnable documentation check `python3 scripts/verify_mobile_e2e_runtime_docs.py` parses the following ownership requirements and verifies that SDK tests enforce them.

<!-- target-owned-receipt-ownership-requirements-start -->
- DailyMart completion proof must be a target-owned MeshKit receipt, not a Hermes/caller-owned receipt, wallet-owned receipt, provider callback, request anchor transaction hash, or maroo chain proof by itself.
- DailyMart receipts must set both `receiptOwner` and `targetReceiptOwner` to the DailyMart target owner identifier produced by `MeshReceiptOwnershipMapper.ownerIdentifier(targetAppId:targetBundleId:)`.
- The receipt root identity must keep `targetAppId` and `targetBundleId` bound to DailyMart, while request correlation remains in `requestId` and `requestPayloadHash`.
- Target ownership is verified through `MeshReceiptOwnershipMapper.assertTargetOwned` before a chain proof can be accepted as DailyMart completion proof.
- `MeshReceiptChainProofSerializer.targetOwnedProof` must bind target ownership to the signed MCP request hash, request nonce, anchoring reference, policy id, and policy hash.
- HermesChat may verify the DailyMart target-owned receipt, but Hermes/caller keys must not be accepted as target completion proof.
- Wallet keys, Agent Wallet Kit callbacks, provider callbacks, anchor transaction hashes, and maroo transaction proofs augment receipt verification only when serialized inside the target-owned DailyMart receipt.
- Confirmed, pending, failed, and policy-denied presentation states must all preserve the same DailyMart target-owned receipt ownership requirement.
- The runnable Swift coverage includes `testSerializedDailyMartReceiptOwnershipMappingIsTargetOwned`, `testTargetOwnedReceiptChainProofOwnershipRejectsCallerOwnedReceiptFields`, and `testAcceptedAppToAppCallCreatesDailyMartOwnedReceiptNotCallerOwned`.
<!-- target-owned-receipt-ownership-requirements-end -->

Required root fields:

- Shared identity: `receiptId`, `requestId`, `capabilityId`, `targetAppId`, and `targetBundleId`.
- Request correlation: `requestPayloadHash` with `algorithm=sha256` and a 64-character hex `value`.
- Ownership and result envelope: `result`, whose string fields may include `receiptOwner` and `targetReceiptOwner`; DailyMart receipts must set both to the DailyMart target owner identifier.
- Target receipt security: `nonce`, `timestamp`, and `signature` with `algorithm`, `keyId`, and `value`.
- Status discriminator: root `status`; chain-aware receipts also include provider-neutral result fields `chainStatus`, `chainProofType`, and `presentationState`.

Shared provider-neutral result-field families:

- Ownership: `receiptOwner`, `targetReceiptOwner`.
- Anchoring: `requestHash`, `requestNonce`, `anchoringReference`.
- Payment or transfer linkage: `chainProvider`, `chainNetwork`, `chainId`, `asset`, `amount`, `recipient`, `paymentId`, `authorizationId`, `executionId`, `executionAttemptId`, `txHash`, and `explorerUrl`.
- Timestamps: root `timestamp`, plus status-specific `submittedAt` and `confirmedAt` result fields.
- Status discriminators: root `status`, plus `chainStatus`, `chainProofType`, and `presentationState`.

Confirmed DailyMart payment execution receipts are valid only when the root receipt envelope satisfies `MeshReceiptBaseSchema.providerNeutral` and the result fields satisfy `MeshChainProofSchema.providerNeutral.validateReceiptResultFields(_:)` for `chainStatus=confirmed`, `chainProofType=payment_execution`, and `presentationState=paid_complete`.

Confirmed receipt status-specific required result fields:

- Provider and network: `chainProvider`, `chainId`, and `chainNetwork`.
- Status contract: `chainProofType=payment_execution`, `chainStatus=confirmed`, and `presentationState=paid_complete`.
- Signed request and delegated policy linkage: `requestHash`, `requestNonce`, `policyId`, `policyHash`, `walletAddress`, `amount`, `asset`, `recipient`, and `anchoringReference`.
- Confirmed payment proof: `txHash`, `explorerUrl`, and `confirmedAt`.

Confirmed receipts must not include failure-only result fields `errorCode` or `errorMessage`. `submittedAt`, `paymentId`, `authorizationId`, `executionId`, `executionAttemptId`, `executionKind`, and `anchorTxHash` remain provider-neutral linkage fields and may be present, but a confirmed receipt is not accepted as paid or complete without the confirmed payment proof fields above. The runnable example validation test is `testConfirmedReceiptSchemaValidationRunnableExampleAcceptsDailyMartReceipt`.

Pending DailyMart receipts are valid only when the root receipt envelope satisfies `MeshReceiptBaseSchema.providerNeutral` and the result fields satisfy `MeshChainProofSchema.providerNeutral.validateReceiptResultFields(_:)` for `chainStatus=pending`, `chainProofType=request_anchor` or `chainProofType=payment_execution`, and `presentationState=submitted_not_final`.

Pending receipt status-specific required result fields:

- Provider and network: `chainProvider`, `chainId`, and `chainNetwork`.
- Status contract: `chainStatus=pending`, `presentationState=submitted_not_final`, and `chainProofType=request_anchor` for an anchored request that is not final or `chainProofType=payment_execution` for a submitted payment attempt that is not final.
- Signed request and delegated policy linkage: `requestHash`, `requestNonce`, `policyId`, `policyHash`, `walletAddress`, `amount`, `asset`, `recipient`, and `anchoringReference`.
- Pending observation proof: `submittedAt`.

Pending receipts must not include confirmed-only result fields `txHash`, `explorerUrl`, or `confirmedAt`, and they must not include failure-only result fields `errorCode` or `errorMessage`. `paymentId`, `authorizationId`, `executionId`, `executionAttemptId`, `executionKind`, and `anchorTxHash` remain provider-neutral linkage fields and may be present, but a pending receipt is presented as submitted and not final until a later target-owned DailyMart receipt carries confirmed or failed status. The runnable example validation test is `testPendingReceiptSchemaValidationRunnableExampleAcceptsDailyMartReceipt`.

Failed DailyMart payment execution receipts are valid only when the root receipt envelope satisfies `MeshReceiptBaseSchema.providerNeutral` and the result fields satisfy `MeshChainProofSchema.providerNeutral.validateReceiptResultFields(_:)` for `chainStatus=failed`, `chainProofType=payment_execution`, and `presentationState=attempted_failed`.

Failed receipt status-specific required result fields:

- Provider and network: `chainProvider`, `chainId`, and `chainNetwork`.
- Status contract: `chainProofType=payment_execution`, `chainStatus=failed`, and `presentationState=attempted_failed`.
- Signed request and delegated policy linkage: `requestHash`, `requestNonce`, `policyId`, `policyHash`, `walletAddress`, `amount`, `asset`, `recipient`, and `anchoringReference`.
- Failure proof: `errorCode` and `errorMessage`.

Failed receipts must not include confirmed-only result fields `txHash`, `explorerUrl`, or `confirmedAt`. `submittedAt`, `paymentId`, `authorizationId`, `executionId`, `executionAttemptId`, `executionKind`, and `anchorTxHash` remain provider-neutral linkage fields and may be present, but a failed receipt is presented as attempted and not paid or complete. The runnable example validation test is `testFailedReceiptSchemaValidationRunnableExampleAcceptsDailyMartReceipt`.

Policy-denied DailyMart receipts are valid only when the root receipt envelope satisfies `MeshReceiptBaseSchema.providerNeutral` and the result fields satisfy `MeshChainProofSchema.providerNeutral.validateReceiptResultFields(_:)` for `chainStatus=failed`, `chainProofType=policy_denial`, and `presentationState=policy_denied`.

Policy-denied receipt status-specific required result fields:

- Provider and network: `chainProvider`, `chainId`, and `chainNetwork`.
- Status contract: `chainProofType=policy_denial`, `chainStatus=failed`, and `presentationState=policy_denied`.
- Signed request and delegated policy linkage: `requestHash`, `requestNonce`, `policyId`, `policyHash`, `walletAddress`, `amount`, `asset`, `recipient`, and `anchoringReference`.
- Policy denial execution linkage: `executionAttemptId` and `executionId`.
- Denial proof: `errorCode` and `errorMessage`.

Policy-denied receipts must not include confirmed-only result fields `txHash`, `explorerUrl`, or `confirmedAt`, and they must not require payment-only identifiers `paymentId` or `authorizationId` because payment execution is not called after policy denial. Policy denial is not a fourth chain status; it is `chainStatus=failed` with `chainProofType=policy_denial` and `presentationState=policy_denied`. The runnable example validation test is `testPolicyDeniedReceiptSchemaValidationRunnableExampleAcceptsDailyMartReceipt`.

The base schema deliberately excludes provider-specific root fields such as maroo RPC metadata, OKRW contract configuration, or adapter response blobs. Provider-specific diagnostics belong in the encoded `MeshChainProof.providerExtensions` payload or in provider-neutral blocker evidence fields when external chain dependencies are unavailable.

## maroo Testnet Adapter

Demo configuration:

Schema: `meshkit-maroo-testnet-adapter-config/v1`.

<!-- maroo-adapter-config-endpoints-start -->
| schema key | value |
| --- | --- |
| `rpcEndpoint` | `https://rpc-testnet.maroo.io` |
| `explorerBaseURL` | `https://explorer-testnet.maroo.io` |
| `faucetURL` | `https://faucet.maroo.io` |
| `agentWalletKitBaseURL` | `https://agent.maroo.io` |
| `docsURL` | `https://docs.maroo.io` |
<!-- maroo-adapter-config-endpoints-end -->

Required and optional runtime environment variables:

<!-- maroo-adapter-config-env-start -->
| environment key | required for | notes |
| --- | --- | --- |
| `MESHKIT_IOS_MAROO_LIVE_TX_HASH` | confirmed OKRW payment receipt proof | DailyMart uses this only when a real maroo testnet transaction hash is available; deterministic fallback hashes must not be presented as confirmed payment proof. |
| `MESHKIT_IOS_MAROO_ANCHOR_TX_HASH` | optional request-anchor explorer link | DailyMart may attach this to the anchoring reference when a live anchor transaction exists. |
| `MESHKIT_MAROO_OKRW_CONTRACT_ADDRESS` | optional OKRW contract availability probe | `scripts/verify_maroo_testnet_status.py` uses this for `eth_getCode`; when absent, endpoint availability can still be checked. |
<!-- maroo-adapter-config-env-end -->

The runnable docs check `python3 scripts/verify_mobile_e2e_runtime_docs.py` parses these tables and verifies the documented keys match `MeshMarooTestnetAdapterConfigSchema`.

### maroo Verification Commands

These commands are the protocol-doc source of truth for the demo adapter verification path. The first two run against the deterministic MeshKit demo adapter test harness and are safe for local CI because they do not contact public maroo endpoints. The remaining commands are the live pre-demo probes for public maroo testnet availability; the docs test extracts this block, executes the harness commands, and validates the live command shapes against the same adapter contract.

<!-- maroo-verification-commands-start -->
```bash
python3 scripts/verify_maroo_testnet_status.py --demo-adapter-harness
python3 scripts/verify_maroo_testnet_status.py --demo-adapter-harness --okrw-contract-address 0x0000000000000000000000000000000000000001
python3 scripts/verify_maroo_testnet_status.py
MESHKIT_MAROO_OKRW_CONTRACT_ADDRESS=0x0000000000000000000000000000000000000001 python3 scripts/verify_maroo_testnet_status.py
curl -sS https://rpc-testnet.maroo.io -H 'content-type: application/json' --data '{"jsonrpc":"2.0","id":1,"method":"eth_blockNumber","params":[]}'
curl -sS https://rpc-testnet.maroo.io -H 'content-type: application/json' --data '{"jsonrpc":"2.0","id":2,"method":"net_version","params":[]}'
curl -sS https://rpc-testnet.maroo.io -H 'content-type: application/json' --data '{"jsonrpc":"2.0","id":3,"method":"eth_getCode","params":["0x0000000000000000000000000000000000000001","latest"]}'
```
<!-- maroo-verification-commands-end -->

The harness commands write `artifacts/maroo-testnet/demo-adapter-harness.json` and validate the documented provider, network, JSON-RPC method names, OKRW contract input path, and provider-neutral proof fields used by the maroo demo adapter. The live commands may return `BlockedByExternalChain` evidence when public RPC, explorer, faucet, OKRW contract, wallet funding, or payment confirmation is unavailable; those failures must not be converted into confirmed payment receipts.

Direct maroo Agent Wallet Kit integration is not required for the MVP. The current adapter boundary is intentionally replaceable: future work can swap deterministic/local submission code for Agent Wallet Kit or live RPC execution while preserving MeshKit request signing, policy validation, receipt ownership, and chain proof serialization contracts.

### Agent Wallet Kit Future Adapter Path

The Agent Wallet Kit future adapter path is a provider plugin behind the same MeshKit/OCG contracts used by the MVP maroo testnet adapter. It must not become a MeshKit core protocol requirement, and it must not replace the nonce-based signed MCP request as the trust object.

Extension points:

- `MeshChainProvider` may load Agent Wallet Kit network metadata, health checks, account lookup, and explorer URL construction through provider extension metadata.
- `MeshRequestAnchorProvider` may submit signed request anchors through Agent Wallet Kit APIs, but the adapter input must remain `MeshRequestAnchorPayload` plus `MeshSignedRequestAnchorMetadata`.
- `MeshAgentWallet` may delegate request-anchor signing, execution-authorization signing, wallet address reporting, policy simulation, and authorization submission to Agent Wallet Kit.
- `MeshPaymentExecutor` may execute OKRW payments or transfers through Agent Wallet Kit, live RPC, or another provider backend while returning `MeshPaymentExecutionResult`.
- `MeshChainProofSchema.providerNeutral` may carry provider extension fields for Agent Wallet Kit response ids or diagnostic references, but the DailyMart receipt core fields remain provider-neutral.

Compatibility expectations:

- Agent Wallet Kit integration must accept the same canonical signed MCP request hash, request nonce, `policyId`, `policyHash`, asset, amount, recipient, wallet address, and anchoring reference used by the MVP adapter.
- Agent Wallet Kit integration must preserve DailyMart target-owned receipt signing; Hermes/caller keys, wallet keys, or Agent Wallet Kit completion callbacks are not accepted as DailyMart completion proof.
- Agent Wallet Kit integration must preserve repeat saved-grant behavior: each tap creates a fresh request id, nonce, signature, anchor reference, execution attempt id, and target-owned receipt id.
- Agent Wallet Kit integration must map confirmed, pending, failed, and policy-denied outcomes into the same provider-neutral presentation states and status-specific required fields.
- Agent Wallet Kit integration must keep private cart contents, delivery references, user identity details, consent text, and private payload fields out of chain metadata and receipt core fields.
- Agent Wallet Kit integration must report `BlockedByExternalChain` evidence when its RPC, faucet, explorer, OKRW contract, funded wallet, or confirmation path cannot prove live execution; deterministic fallbacks are never compatible with confirmed payment presentation.

## Provider-Neutral Wallet Interface Contract

MeshKit/OCG models on-chain agent wallet execution through provider-neutral interfaces. Concrete adapters such as maroo testnet must implement these contracts without changing App-to-App MCP trust semantics or adding provider-specific fields to core receipts.

Required interface names:

- `MeshChainProvider`: reports `identity`, `metadata`, and `capabilities`; loads `MeshChainProviderConfiguration`; identifies the network; connects and checks health; looks up transactions and proofs by `MeshChainProofReference`; constructs explorer URLs for transactions, accounts, addresses, and blocks.
- `MeshRequestAnchorProvider`: anchors a signed MCP request from `MeshRequestAnchorPayload` or `MeshSignedRequestAnchorMetadata`; returns a `MeshRequestAnchor` with a `MeshRequestAnchorIdentifier`; reports anchor status; resolves an anchoring reference back to the signed request hash and status.
- `MeshAgentWallet`: reports `MeshAgentWalletIdentity` and supported wallet capabilities; loads `MeshAgentWalletConfiguration`; reports the wallet address; exposes the delegated spending limit; declares the signing boundary; signs request-anchor payloads; signs execution-authorization payloads; authorizes execution requests.
- `MeshPaymentExecutor`: loads `MeshPaymentExecutorConfiguration`; executes payment or transfer requests; returns provider-neutral `MeshPaymentExecutionResult` status; exposes execution-status lookup; maps provider errors into `MeshPaymentExecutorCapabilityError`.
- `MeshChainProofSchema`: publishes the runnable provider-neutral receipt schema as `MeshChainProofSchema.providerNeutral` with required fields for confirmed, pending, failed, and policy-denied receipts.

Reference semantics:

- The signed App-to-App MCP request remains the core trust object. `MeshRequestAnchorProvider.anchorSignedRequest` must bind the canonical signed request hash, request nonce, `policyId`, and `policyHash` before DailyMart execution is treated as eligible.
- `MeshRequestAnchorIdentifier` is an anchoring reference, not completion proof. It can show submitted, pending, confirmed, or failed anchoring state, and it can be linked from HermesChat or DailyMart debug UI.
- `MeshAgentWallet.delegatedSpendingLimit`, `MeshAgentWallet.authorizeExecution`, and spend accounting enforce the delegated policy before payment execution. Policy-denied results produce target-owned DailyMart receipts with `proofType=policy_denial`.
- `MeshPaymentExecutor.executePayment` and `MeshPaymentExecutor.paymentExecutionStatus` bind asset, amount, recipient, request hash, execution status, tx hash, and provider-neutral errors to the anchored request. A deterministic fallback hash must never be presented as confirmed OKRW payment proof.
- `MeshChainProofReference` and `MeshChainProofSchema.providerNeutral` connect signed request anchoring, payment execution, and target-owned receipt verification while keeping maroo-specific RPC, faucet, explorer, and Agent Wallet Kit details in the adapter layer.

## On-Chain Wallet Provider Adapter Responsibilities

Provider adapters are replaceable implementation modules behind the MeshKit/OCG contracts. maroo testnet is the demo adapter; it must not change the MeshKit trust model, receipt ownership model, or provider-neutral schema names.

Required adapter inputs:

- Canonical signed MCP request hash, request id, request nonce, target capability, caller identity, and DailyMart target identity.
- Delegated spending policy inputs: `policyId`, `policyHash`, asset, amount, recipient, per-payment maximum, remaining session limit, allowed scope, and expiry window.
- Anchor submission inputs: `MeshRequestAnchorPayload`, `MeshSignedRequestAnchorMetadata`, wallet address, provider/network configuration, and optional provider extension metadata that does not include private payload fields.
- Payment execution inputs: `MeshPaymentExecutionRequest`, execution attempt id, authorization id, payment id, asset such as OKRW, amount, recipient address, anchoring reference, and signed request linkage.
- Status lookup inputs: anchoring reference, transaction hash when present, payment id, execution id, and checked-at timestamp.

Required adapter outputs:

- Provider identity and network identity through `MeshChainProviderIdentity`, including provider name, network name, chain id, RPC endpoint, and explorer URL construction.
- Request anchor result through `MeshRequestAnchor`, including anchoring reference, request hash, request nonce, provider-neutral status, submitted-at timestamp, and any anchor transaction reference returned by the provider.
- Wallet result through `MeshAgentWalletIdentity`, wallet address reporting, delegated spending limit reporting, request-anchor signature, execution-authorization signature, and policy authorization decision.
- Payment result through `MeshPaymentExecutionResult`, including provider-neutral status, payment id, execution id, execution attempt id, submitted-at or confirmed-at timestamps, transaction hash and explorer URL only when the provider returns real chain evidence, and provider-neutral error fields when execution is pending or failed.
- Receipt proof output through `MeshChainProofSchema.providerNeutral`, serialized into a DailyMart target-owned MeshKit receipt for confirmed, pending, failed, and policy-denied presentation states.

Required adapter error handling:

- Map provider failures to provider-neutral errors such as `rpc_unavailable`, `explorer_unavailable`, `faucet_unavailable`, `okrw_contract_unavailable`, `funded_wallet_unavailable`, `payment_confirmation_unavailable`, `anchor_submission_failed`, `payment_execution_failed`, and `wallet_policy_denied`.
- Return pending or failed proof states when confirmation cannot be observed; do not synthesize a confirmed transaction hash, explorer URL, or completion timestamp.
- Preserve policy-denied as `status=failed` plus `presentationState=policy_denied` and `proofType=policy_denial`; do not call payment execution after policy denial.
- Attach `BlockedByExternalChain` evidence when maroo testnet, RPC, faucet, explorer, OKRW contract availability, or live wallet funding blocks confirmation.
- Keep raw provider messages in error fields only when they do not expose private request payloads, user identity details, cart contents, delivery references, or consent text.

Required adapter execution boundaries:

- Request signing, nonce freshness, payload hash validation, caller trust validation, and DailyMart target-owned receipt signing stay in MeshKit/App-to-App MCP; chain anchoring augments those checks and never replaces them.
- DailyMart remains the execution boundary for `grocery.purchase_essentials`; Hermes/caller signatures and wallet signatures are not accepted as target completion proof.
- Spend policy validation happens before payment execution, and confirmed spend accounting is applied only after a confirmed provider-neutral payment proof.
- Provider-specific RPC, faucet, explorer, Agent Wallet Kit, OKRW contract, and chain serialization details stay inside the adapter layer or provider extension fields, not core MeshKit receipt fields.
- Direct maroo Agent Wallet Kit integration is a future replaceable adapter path; the MVP adapter may use deterministic request construction, RPC probing, or configured live transaction references while preserving the same provider-neutral inputs and outputs.

## On-Chain Privacy

The chain is an audit rail, not a plaintext data store. MeshKit may anchor request and policy commitments, but must not put cart contents, delivery address references, user identity, consent text, chat content, or private request payload fields on-chain. The on-chain linkage should be limited to hash and reference material such as signed MCP request hash, request nonce, policy id, policy hash, anchoring reference, status, tx hash, and explorer URL.

If maroo testnet, faucet, RPC, explorer, or OKRW contract availability blocks live confirmation, the demo must document `BlockedByExternalChain` evidence and must not represent deterministic fallback hashes as confirmed payment proof. Evidence uses provider-neutral blocker types such as `rpc_unavailable`, `explorer_unavailable`, `faucet_unavailable`, `okrw_contract_unavailable`, `funded_wallet_unavailable`, and `payment_confirmation_unavailable`, with endpoint, operation, observed time, message, and signed request linkage when available.

Before a live demo, verify public maroo testnet availability with `python3 scripts/verify_maroo_testnet_status.py` or direct JSON-RPC `eth_blockNumber`, `net_version`, and configured OKRW `eth_getCode` calls against `https://rpc-testnet.maroo.io`. The script writes `artifacts/maroo-testnet/status.json` and converts RPC, explorer, faucet, and configured OKRW contract availability failures at `https://rpc-testnet.maroo.io`, `https://explorer-testnet.maroo.io`, and `https://faucet.maroo.io` into `BlockedByExternalChain` evidence such as `rpc_unavailable`, `explorer_unavailable`, `faucet_unavailable`, or `okrw_contract_unavailable`. Reachable RPC, explorer, and faucet endpoints prove public dependency availability only; they do not by themselves prove that the demo has a funded OKRW wallet, a live OKRW contract call, or a confirmed payment transaction.

## External Chain Outage Detection And Fallback

The runnable documentation check `python3 scripts/verify_mobile_e2e_runtime_docs.py` parses the following outage matrix and verifies that every documented trigger and fallback path is represented by the SDK evidence model, maroo status script, receipt serialization tests, and HermesChat presentation tests.

<!-- external-chain-outage-fallback-start -->
- `rpc_unavailable`: detected by `MeshMarooTestnetRPCAvailabilityCheck`, `eth_blockNumber`, `net_version`, or JSON-RPC transport failure against `https://rpc-testnet.maroo.io`; fallback writes `BlockedByExternalChain` evidence to `artifacts/maroo-testnet/status.json`, returns failed or pending provider-neutral proof, keeps DailyMart receipt target-owned, and never synthesizes `txHash`, `explorerUrl`, or `confirmedAt`.
- `explorer_unavailable`: detected by `MeshMarooTestnetExplorerAvailabilityCheck` or explorer HEAD failure against `https://explorer-testnet.maroo.io`; fallback records `BlockedByExternalChain` with `externalChainEndpoint`, omits runnable explorer links for unconfirmed receipts, and presents submitted-not-final or attempted-failed state until a later target-owned receipt has confirmed chain proof.
- `faucet_unavailable`: detected by `MeshMarooTestnetFaucetAvailabilityCheck` or faucet HEAD failure against `https://faucet.maroo.io`; fallback records `BlockedByExternalChain`, treats funding as unavailable for live demo readiness, and does not debit HermesChat delegated remaining limit.
- `okrw_contract_unavailable`: detected by `MeshMarooTestnetOKRWContractAvailabilityCheck` or `eth_getCode OKRW` returning empty, malformed, or unavailable bytecode for `MESHKIT_MAROO_OKRW_CONTRACT_ADDRESS`; fallback records `BlockedByExternalChain`, returns failed OKRW execution proof with provider-neutral error fields, and does not create confirmed payment proof.
- `funded_wallet_unavailable`: detected when Agent Wallet Kit, live RPC, or demo preflight cannot prove a funded delegated OKRW wallet; fallback records `BlockedByExternalChain`, returns pending or failed payment execution evidence, preserves signed MCP request and policy linkage, and leaves repeat saved-grant behavior available for a fresh later attempt.
- `payment_confirmation_unavailable`: detected when submission exists but maroo testnet cannot return a live confirmed OKRW payment or transfer receipt; fallback records `BlockedByExternalChain` with signed request hash, request nonce, anchoring reference, and observed operation, presents attempted-failed or submitted-not-final state, and does not mark HermesChat as paid or complete.
- `request_anchor_unavailable`: detected when a signed MCP request anchor submission or status lookup cannot prove submitted, pending, confirmed, or failed provider state; fallback keeps `MeshRequestAnchorIdentifier` as an anchoring reference only, blocks downstream confirmed-payment presentation, and returns target-owned DailyMart receipt evidence rather than accepting anchor data as completion proof.
<!-- external-chain-outage-fallback-end -->

During external-chain outages, the receipt presentation state is part of the protocol contract rather than demo copy. Operators need enough evidence to decide whether the dependency is blocked or a payment attempt failed; users need clear payment state without false completion.

<!-- external-chain-outage-presentation-states-start -->
- `pending/submitted_not_final`: operator-facing state must expose `BlockedByExternalChain`, `blockerType`, `externalChainEndpoint`, `operation`, `observedAt`, signed request hash, request nonce, anchoring reference, `executionAttemptId`, and target-owned DailyMart receipt id; user-facing state must show "submitted but not final", keep delegated remaining limit unchanged, show submittedAt and anchoringReference, and never show paid, complete, `txHash`, `explorerUrl`, or `confirmedAt`.
- `failed/attempted_failed`: operator-facing state must expose `BlockedByExternalChain`, `blockerType`, `externalChainEndpoint`, `operation`, `observedAt`, signed request hash, request nonce, anchoring reference, `executionAttemptId`, `errorCode`, `errorMessage`, and target-owned DailyMart receipt id; user-facing state must show "attempted but not paid", keep delegated remaining limit unchanged, show errorCode and errorMessage, and never show paid, complete, `txHash`, `explorerUrl`, or `confirmedAt`.
<!-- external-chain-outage-presentation-states-end -->

After an external-chain outage resolves, recovery is a target-owned reconciliation process. DailyMart may retry status lookup or payment execution only from the persisted signed MCP request linkage; HermesChat may display the recovered state only after a new or updated target-owned DailyMart MeshKit receipt verifies.

<!-- external-chain-outage-recovery-guidance-start -->
- `retry`: rerun `python3 scripts/verify_maroo_testnet_status.py` first, then retry the blocked `MeshRequestAnchorIdentifier` or `MeshPaymentExecutionResult` lookup with the original signed request hash, request nonce, anchoring reference, `executionAttemptId`, policy id, and policy hash; every retry must preserve repeat saved-grant freshness for any new user tap and must never reuse a prior signed MCP request id, nonce, signature, or target-owned receipt.
- `reconciliation`: compare maroo RPC, explorer, OKRW contract, and wallet evidence against `artifacts/maroo-testnet/status.json`, the pending DailyMart receipt result fields, and the persisted `BlockedByExternalChain` evidence; reconciliation must bind any recovered `txHash`, `explorerUrl`, or `confirmedAt` to the same signed request hash, request nonce, anchoring reference, `executionAttemptId`, policy id, policy hash, asset, amount, and recipient before status can move from submitted-not-final or attempted-failed.
- `receipt_finalization`: when maroo returns confirmed OKRW payment or transfer evidence, DailyMart issues a fresh target-owned MeshKit receipt with `status=confirmed`, `presentationState=paid_complete`, `chainStatus=confirmed`, `txHash`, `explorerUrl`, `confirmedAt`, and the recovered request anchoring fields; HermesChat decrements delegated remaining limit only after this finalized target-owned receipt verifies, and pending or failed receipts remain non-final audit records.
- `escalation`: if retry and reconciliation cannot bind live chain evidence to the signed MCP request, keep the receipt pending or failed, keep delegated remaining limit unchanged, append the unresolved `BlockedByExternalChain` evidence, and escalate with blocker type, endpoint, operation, observedAt, signed request hash, request nonce, anchoring reference, `executionAttemptId`, target-owned DailyMart receipt id, and the maroo status artifact path instead of fabricating completion proof.
<!-- external-chain-outage-recovery-guidance-end -->

## iPad proof path

The iPad proof starts with a small but complete flow:

```text
HermesChat
  -> OCG discovery
  -> DailyMart foreground consent with ₩100 limit
  -> HermesChat foreground background-MCP progress
  -> DailyMart target-signed receipt
  -> HermesChat verified completion
```

## Production boundary

Physical-device proof is a preview milestone. Production requires persistent registry operations, key rotation, revocation, status reporting, and a public audit/control-plane path.
