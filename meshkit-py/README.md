# MeshKit Python SDK (course kit)

Python port of the MeshKit app-to-app MCP trust layer, aligned to the MCP
2026-07-28 specification (stateless core). This is the assignment kit for
teams building mini-apps and seller agents on the MeshKit superapp: your
mini-app is a **stateless MCP server**, and MeshKit is the trust extension
that turns a tool call into a signed, receipted transaction.

Wire-compatible with the Swift and Kotlin SDKs — same signing inputs
(`meshkit-request-signing/v1`, `meshkit-target-receipt-signing/v1`), the same
nonce-bound canonical payload hash (`meshkit-payload-hash/v1`), the same
base64 sorted-keys JSON envelopes, Ed25519 with raw public keys. Golden
vectors: `../meshkit-android/vectors/wire-compat.v1.json`.

## The MCP 2026-07-28 mapping

- One OCG capability = one MCP tool (`Mcp-Name` = capability id).
- Every request is a self-contained JSON-RPC POST — no handshake, no
  session. `MCP-Protocol-Version` / `Mcp-Method` / `Mcp-Name` headers mirror
  the body; targets validate the mirror.
- The signed MeshKit envelope rides in
  `params._meta["ai.meshkit/trust"]["mesh_request"]`; the target verifies it
  fail-closed AND checks the envelope payload equals the tool arguments.
- The result carries the target-signed receipt in
  `result._meta["ai.meshkit/trust"]["mesh_receipt"]`; the caller accepts
  completion only from a verified, request-correlated receipt.
- Trust failures return JSON-RPC `-32602` with
  `error.data.meshkit.code` (`budget_exceeded`, `replay_detected`, ...).

## Quick start

```bash
cd meshkit-py
python3 -m pytest tests/ -q                 # 18 tests: vectors + fail-closed + MCP mapping
PYTHONPATH=. python3 examples/miniapp_server.py   # your mini-app (assignment template)
PYTHONPATH=. python3 examples/user_agent.py       # signed call + receipt verification
```

Cross-SDK proof (needs the Swift package):

```bash
scripts/verify_python_wire_compat.sh
```

## Assignment shape

Your team replaces `examples/miniapp_server.py`'s `CAPABILITY` and
`handle_call` with your catalog and seller-agent logic. The trust wrapper
must stay fail-closed — the grader attacks your endpoint with tampered
payloads, replayed nonces, over-budget spends, unsigned requests, and
imposter callers, and every one of `tests/test_trust.py`'s rejection cases
must hold against your live server. Keys are Ed25519: generate a seed, keep
it private, and register the raw public key (base64) in your team's OCG
manifest.
