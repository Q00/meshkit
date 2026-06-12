# MeshKit ACP Superapp Web

Local single-user MeshKit superapp for ACP discovery, app-to-app MCP routing,
preference memory, on-chain payment proof, and settlement ledger inspection.

The canonical fixture uses the existing MeshKit sample domain:

- `HermesChat` discovers callable apps through an ACP-style registry.
- `MintNotes` handles non-payment `notes.append_note` calls off-chain through app-to-app MCP.
- `DailyMart` handles paid `grocery.purchase_essentials` calls on-chain through deterministic maroo-testnet OKRW proof.
- Preference memory mirrors the `~/zep/brain` hippocampus pattern: young working memory, recalled context stripping, internal/reflection/assistant-echo filtering, duplicate filtering, durable preference promotion, importance scoring, and provenance metadata.
- The settlement ledger shows only on-chain entries and totals confirmed, verified, or trusted records.

## Run

```bash
cd ../server-go
MESHKIT_SUPERAPP_DATA_DIR="$(mktemp -d)" PORT=4173 go run .
```

Open http://localhost:4173. The first screen renders discovered apps, promoted
preferences, on/off-chain routing decisions, and an on-chain settlement ledger.
The UI can also save a preference, execute a MintNotes off-chain app-to-app MCP
request, and execute a DailyMart 42 OKRW on-chain-sim payment request.

The local API exposes:

- `GET /api/superapp-state` for deterministic ACP discovery, memory, routing, and settlement state.
- `GET /api/acp/apps` for ACP-style app-to-app MCP discovery.
- `GET /api/preferences?query={text}` for promoted preference retrieval.
- `POST /api/preferences` to store or update a brain-style preference entry.
- `POST /api/execute` to route an app-to-app MCP request and persist the execution record.
- `GET /api/settlements` for the on-chain-only settlement ledger.
- `GET /api/trust-paths?wallet={walletAccount}&network=maroo-testnet` for live maroo-testnet trust-path scanning.

By default, the local JSON store is written under `web/.meshkit-data/`, which is
ignored by git. Override it with `MESHKIT_SUPERAPP_DATA_DIR=/path/to/data`.
ACP discovery verifies `ocg/registry/signed/*.signed.ocg.json` with the local
test JWKS by default, then falls back to unsigned `ocg/registry/*.ocg.json` if
signed verification is unavailable. Redirect the registry root with
`MESHKIT_ACP_REGISTRY_DIR=/path/to/registry`.

Example deterministic vertical slice:

```bash
curl -X POST http://localhost:4173/api/preferences \
  -H 'content-type: application/json' \
  --data '{"userId":"local-user","agentId":"agent.meshkit-superapp","key":"payment_proof_policy","value":"agent payments use on-chain OKRW proof and non-payment calls stay off-chain","source":"local-demo"}'

curl -X POST http://localhost:4173/api/execute \
  -H 'content-type: application/json' \
  --data '{"capabilityId":"grocery.purchase_essentials","amount":42,"requestId":"req-dailymart-demo"}'

curl -X POST http://localhost:4173/api/execute \
  -H 'content-type: application/json' \
  --data '{"capabilityId":"notes.append_note","amount":0,"requestId":"req-mintnotes-demo"}'

curl http://localhost:4173/api/settlements
```

The bundled server calls the live maroo testnet RPC at `https://rpc-testnet.maroo.io`,
scans recent blocks in the background, filters transactions where `from` or `to`
matches the connected wallet, fetches transaction receipts, and returns those live
records as `TrustPathRecord` objects. API responses are cached so the UI stays
responsive while a scan is in progress. This is intentionally a lightweight RPC scan,
not a production address indexer.

## Verify

```bash
npm test
```

The web tests cover ACP app discovery, hippocampus-style preference promotion and
retrieval, on-chain routing for payment calls, off-chain routing for non-payment
MCP calls, settlement ledger aggregation, the trust-path API URL contract,
TrustPathRecord validation, wallet ownership filtering, and the rule that only
complete `trusted` or `verified` records enter the main graph. The server API
integration test starts the local server with an isolated JSON store and verifies
discovery, preference storage, paid execution, unpaid execution, settlement
projection, and invalid-input errors end to end.

For a reproducible local reset, point the store at a fresh directory:

```bash
cd ../server-go
MESHKIT_SUPERAPP_DATA_DIR="$(mktemp -d)" PORT=4173 go run .
```

The test suite uses the same `MESHKIT_SUPERAPP_DATA_DIR` isolation pattern so
registry, memory, execution, and ledger outputs are recreated from fixtures.
