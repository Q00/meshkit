# MeshKit Superapp Go Server

Go reference server for the local MeshKit ACP superapp. It implements the same
contract as the original web prototype:

- `GET /api/acp/apps`
- `POST /api/preferences`
- `GET /api/preferences?query=...`
- `POST /api/execute`
- `GET /api/settlements`
- `GET /api/superapp-state`

The server verifies signed OCG registry manifests, persists JSON state in an
isolated local store, routes paid DailyMart calls to deterministic
`maroo-testnet/onchain-sim` records, routes unpaid MintNotes calls off-chain, and
returns an on-chain-only settlement ledger.

## Run

```bash
cd server-go
MESHKIT_SUPERAPP_DATA_DIR="$(mktemp -d)" PORT=4173 go run .
```

The Go server serves the existing static cockpit from `web/src` by default.

## Verify

```bash
cd server-go
go test ./...
go test -race ./...
```

The tests cover signed ACP discovery, preference storage, paid/unpaid execution,
on-chain-only settlement projection, invalid input errors, and concurrent JSON
store writes.
