# MeshKit RN Superapp

React Native client for the MeshKit ACP superapp. The app talks to the Go
server in `server-go` and renders the same product surface on mobile:

- Discovery: signed ACP apps and app-to-app MCP capabilities
- Memory: brain-inspired promoted preferences
- Execution: paid on-chain-sim and unpaid off-chain app calls
- Ledger: on-chain-only settlement accounting

## Run API

```bash
cd ../server-go
MESHKIT_SUPERAPP_DATA_DIR="$(mktemp -d)" PORT=4173 go run .
```

## Run Mobile

```bash
cd mobile-rn
npm install
npm run ios
```

For iOS simulator access to the host machine, use the default API base
`http://127.0.0.1:4173`. On a physical device, set `MESHKIT_SUPERAPP_API_BASE`
at build time or edit `src/config.js` to point at the host LAN address.

## Verify

```bash
npm test
```

The tests use mock fetch responses to verify the client calls the Go API
contract and keeps paid DailyMart executions, unpaid MintNotes executions, and
on-chain-only ledger totals distinct.
