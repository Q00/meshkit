# MeshKit ACP Superapp Protocol

This document defines the local MVP protocol surface for the MeshKit ACP superapp.
It complements the iOS App-to-App MCP trust layer by specifying the web/API
vertical slice that agents use to discover callable apps, remember user
preferences, route paid and unpaid app calls, and inspect settlement records.

## Scope

The MVP is a local single-user web UI plus local API server. It does not require
cloud sync, authentication, production deployment, paid services, or a real
external chain transaction. The deterministic chain path uses
`maroo-testnet/onchain-sim` records so the full workflow can be verified without
external credentials.

## Agent Client Protocol Discovery

Discovery returns Agent Client Protocol (ACP) app-to-app MCP descriptors for the
canonical MeshKit sample apps. The superapp agent treats this as its callable app
directory: every descriptor must contain enough identity, trust, transport,
scheme, capability, and schema information for the client to decide whether a
target can be invoked.

- `HermesChat`: agent surface and planning caller.
- `MintNotes`: non-payment `notes.append_note` target over `app-to-app-url-scheme`.
- `DailyMart`: paid `grocery.purchase_essentials` target over deterministic
  `maroo-testnet/onchain-sim` OKRW proof.

`MintNotes` and `DailyMart` ACP descriptors are loaded from the existing signed
OCG manifests under `ocg/registry/signed/` and verified with
`ocg/registry/jwks/test-registry-jwks.json`. `HermesChat` remains a local
fallback descriptor because the current registry only contains target app
manifests. The local web model preserves the OCG identity in `ocgAppId` while
using stable local superapp ids such as `app.mint-notes` and `app.dailymart`.

API:

```text
GET /api/acp/apps
```

Required fields:

- `schemaVersion`
- `registryMode`
- `registryFiles`
- `registryTrust`
- `appId`
- `ocgAppId`
- `displayName`
- `publisher`
- `acpEndpoint`
- `mcpTransport`
- `bundleId`
- `platform`
- `registrySource`
- `capabilities[].id`
- `capabilities[].risk`
- `capabilities[].consent`
- `capabilities[].requiresPayment`
- `capabilities[].asset`
- `capabilities[].urlScheme`
- `capabilities[].inputSchema`
- `capabilities[].resultSchema`
- `capabilities[].routingHint`
- `registrySignatureVerification.status` for signed registry apps

`routingHint=onchain_payment` is used for paid capabilities. Non-payment
capabilities use `routingHint=offchain_app_call`. The signed MintNotes
descriptor must preserve the callable iOS scheme `mintnotes://mesh/invoke`, and
the signed DailyMart descriptor must preserve `dailymart://mesh/invoke`; these
schemes are part of the agent client invocation contract, not display-only
metadata.

The registry path defaults to `ocg/registry/` and can be redirected with
`MESHKIT_ACP_REGISTRY_DIR`. Signed manifests use
`registryMode=signed-ocg-registry`, `registryTrust.signed=true`, and
`registryTrust.verifiedCount` for the number of verified registry signatures.
When no signed manifests are present, the local API falls back to unsigned
`registryMode=ocg-registry`. When signed manifests are present but malformed or
tampered, the API fails closed with `registryMode=signed-ocg-registry-error` and
reports `registryError`. When the registry cannot be read, it falls back to the
deterministic fixture descriptors and reports `registryMode=fallback-fixture`.

The Swift SDK mirrors this discovery surface through
`OpenCapabilityGraph.acpRegistryDescriptors()`, which projects OCG sample apps
into `AcpAppDescriptor` records with `ocgAppId`, `acpEndpoint`,
`mcpTransport=app-to-app-url-scheme`, `platform=ios-demo`,
`registrySource=meshkit-ios-sample`, and the same routing hints.

## Live LLM Agent Tool-Call Verification

The repository includes a live verifier that talks to an LLM and proves the
superapp agent can use ACP discovery as its tool directory:

```bash
cd server-go
MESHKIT_SUPERAPP_DATA_DIR="$(mktemp -d)" PORT=4173 go run .

cd ..
OPENAI_API_KEY="$OPENAI_API_KEY" \
MESHKIT_SUPERAPP_BASE_URL=http://127.0.0.1:4173 \
node scripts/verify_acp_agent_llm_toolcall.mjs
```

The verifier:

- fetches live `GET /api/acp/apps`
- converts discovered ACP capabilities into LLM tool definitions
- asks the LLM to converse as the MeshKit superapp agent
- requires actual tool calls for `remember_preference`,
  `notes.append_note`, `grocery.purchase_essentials`, and
  `get_settlement_ledger`
- executes those tool calls against `/api/preferences`, `/api/execute`, and
  `/api/settlements`
- feeds tool results back to the LLM and checks the final user-facing answer
  mentions the off-chain note, DailyMart purchase, and on-chain OKRW settlement

## Preference Memory

Preference memory is JSON-compatible and inspired by `~/zep/brain`, without
requiring binary compatibility with that package. The MVP preserves the core
brain concepts that matter for agent behavior:

- young working memory
- durable preference promotion
- long-term promoted memory
- stable `memoryId` identity across reruns and upserts
- importance scoring
- retrieval scoring
- source/provenance metadata
- hippocampus-style consolidation with recalled context stripping, internal
  event filtering, assistant echo filtering, and duplicate filtering

The reference model in `~/zep/brain` separates young-generation working memory
from old-generation long-term memory, promotes stable young memories during
idle consolidation, and treats `memoryId` as an agent-scoped durable identity
that must not be replaced by an overwrite. This MVP maps those principles to a
small local JSON store: accepted events first appear in `workingMemory`, durable
preference events are mirrored into `promotedMemory`, and an upsert of the same
`userId` + `agentId` + `key` updates the value while preserving the existing
memory identity.

Canonical preference keys:

- `payment_proof_policy`: `agent payments use on-chain OKRW proof and non-payment calls stay off-chain`
- `privacy_policy`: `cart/address/user/consent details stay off-chain`

API:

```text
POST /api/preferences
GET /api/preferences?query={text}
```

`POST /api/preferences` returns `preference` when an event enters working or
promoted memory. If the consolidation policy rejects the event, `preference` is
`null` and `droppedPreference.reason` records the filter reason.

Required memory fields:

- `userId`
- `agentId`
- `memoryId`
- `key`
- `value`
- `content`
- `source`
- `importance`
- `createdAt`
- `updatedAt`
- `lastAccessedAt`
- `promotedAt` for durable promoted entries

Memory consolidation fields:

- `filteredEvents`: accepted events after `<memory-context>...</memory-context>`
  removal and policy filtering
- `droppedEvents`: rejected events with reasons such as `internal-event`,
  `internal-reflection-prompt`, `assistant-echo-without-durable-signal`, and
  `duplicate-content`
- `consolidation`: counts for filtered, promoted, and dropped events plus the
  active hippocampus-inspired policy

The local JSON store defaults to `web/.meshkit-data/superapp-store.json` and can
be redirected with `MESHKIT_SUPERAPP_DATA_DIR`. Store writes are serialized per
data directory and committed through an atomic temporary-file rename so
concurrent preference or execution requests do not lose paid/off-chain records.

## Execution Routing

Agents submit app-to-app MCP execution requests to the local API. The router
chooses the transport from the capability contract and amount:

- paid DailyMart `grocery.purchase_essentials`, amount `42`, asset `OKRW`:
  `route=onchain`, `recordType=onchain-sim`, deterministic maroo testnet tx id.
- unpaid MintNotes `notes.append_note`, amount `0`:
  `route=offchain`, `recordType=app-to-app-url-scheme`, no tx id.

Routing invariants:

- payment capabilities require `amount > 0`
- non-payment capabilities require `amount = 0`
- invalid, missing, non-finite, or negative amounts return an error response
- zero-amount on-chain records are excluded from settlement projections

API:

```text
POST /api/execute
```

Required request fields:

- `capabilityId`
- `amount`
- optional `requestId`
- optional `userId`
- optional `agentId`

Required route decision fields:

- `route`
- `transport`
- `appId`
- `capabilityId`
- `requiresPayment`
- `asset`
- `amount`
- `privacyBoundary`
- `recalledPreferences`
- `appliedPolicy.policyId`
- `appliedPolicy.source`
- `appliedPolicy.sourceMemoryIds`
- `appliedPolicy.paymentProof`
- `appliedPolicy.nonPaymentTransport`
- `appliedPolicy.payloadPrivacy`
- `appliedPolicy.chainVisibleFields`
- `appliedPolicy.offchainFields`

The router derives `appliedPolicy` from promoted preference memory. The canonical
`payment_proof_policy` produces `paymentProof=onchain-okrw-proof` for paid agent
calls and `nonPaymentTransport=offchain-app-to-app-mcp` for non-payment calls.
The canonical `privacy_policy` produces `payloadPrivacy=private-payload-offchain`,
so cart, address, user identity, and consent text stay out of chain-visible
fields.

Invalid capability IDs or invalid amounts return an error response and must not
create execution or settlement records.

## Settlement Ledger

The settlement ledger is an on-chain accounting view. It includes only records
whose route is `onchain` or that carry a transaction hash. Off-chain app-to-app
MCP records remain in execution history but are excluded from settlement totals.

API:

```text
GET /api/settlements
```

Required ledger fields:

- `entryId`
- `requestId`
- `appId`
- `capabilityId`
- `provider`
- `network`
- `asset`
- `amount`
- `status`
- `direction`
- `category`
- `counterparty`
- `txHash`
- `explorerUrl`
- `policyHash`
- `signedRequestHash`
- `policyId`
- `paymentProof`
- `payloadPrivacy`
- `policySourceMemoryIds`

The trusted total includes only `confirmed`, `verified`, or `trusted` ledger
entries. The canonical deterministic fixture produces one DailyMart settlement
for `42 OKRW`.

The ledger summary is an accounting projection with:

- `totalDebits`
- `totalCredits`
- `byStatus`
- `byApp`
- `byCategory`
- `byCounterparty`

## Full State Projection

The superapp state endpoint returns one render-ready snapshot for the web UI:

```text
GET /api/superapp-state
```

It includes:

- discovered ACP apps
- preference memory
- route decisions
- execution records
- on-chain settlement ledger

## Verification

Run:

```bash
cd server-go
go test ./...
go test -race ./...

cd web
npm test
```

The test suites cover signed discovery, memory promotion and persistence, paid
and unpaid routing invariants, server API integration, invalid input handling,
trust-path normalization, concurrent JSON store writes, UI control presence, and
this protocol document.
