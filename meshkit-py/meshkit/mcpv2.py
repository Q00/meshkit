"""MeshKit trust layer as an MCP extension, aligned to spec 2026-07-28.

The 2026-07-28 MCP specification made the protocol stateless: no
`initialize`/`initialized` handshake, no `Mcp-Session-Id`; every request is a
self-contained JSON-RPC POST carrying protocol version and client identity in
`_meta`, mirrored by the `MCP-Protocol-Version` / `Mcp-Method` / `Mcp-Name`
HTTP headers, with `server/discover` for on-demand capability discovery.

MeshKit rides on that as a formal extension (reverse-DNS metadata key
`ai.meshkit/trust`):

- One OCG capability = one MCP tool; `Mcp-Name` carries the capability id.
- `tools/call` `params.arguments` carries the business payload (string map),
  and `params._meta["ai.meshkit/trust"]["mesh_request"]` carries the signed
  MeshKit envelope. The target verifies the envelope fail-closed AND checks
  that the envelope payload equals the tool arguments, so a standard MCP
  client cannot smuggle arguments past the signature.
- The tool result carries the target-signed receipt in
  `result._meta["ai.meshkit/trust"]["mesh_receipt"]`.

A plain MCP v2 client can still list and call the tools; the MeshKit
extension is what upgrades a call into a signed, receipted transaction.
"""

from dataclasses import dataclass
from typing import Any

from meshkit.receipt import MeshReceipt
from meshkit.request import MeshRequest
from meshkit.trust import MeshValidationError

PROTOCOL_VERSION = "2026-07-28"
TRUST_META_KEY = "ai.meshkit/trust"
CLIENT_INFO_META_KEY = "io.modelcontextprotocol/clientInfo"

# JSON-RPC invalid params (2026-07-28 folded "resource not found" -32002 into
# the standard -32602).
INVALID_PARAMS = -32602


def request_headers(capability_id: str) -> dict[str, str]:
    return {
        "Content-Type": "application/json",
        "MCP-Protocol-Version": PROTOCOL_VERSION,
        "Mcp-Method": "tools/call",
        "Mcp-Name": capability_id,
    }


def build_tool_call(
    request: MeshRequest,
    rpc_id: int | str,
    client_name: str,
    client_version: str,
) -> dict[str, Any]:
    """Self-contained stateless `tools/call` body for a signed invocation."""
    return {
        "jsonrpc": "2.0",
        "id": rpc_id,
        "method": "tools/call",
        "params": {
            "name": request.target.capability_id,
            "arguments": dict(request.payload),
            "_meta": {
                CLIENT_INFO_META_KEY: {"name": client_name, "version": client_version},
                TRUST_META_KEY: {"mesh_request": request.encoded()},
            },
        },
    }


def extract_mesh_request(body: dict[str, Any], headers: dict[str, str] | None = None) -> MeshRequest:
    """Target-side extraction: decode the envelope and bind it to the call.

    Raises MeshValidationError when the trust extension is missing, the
    envelope disagrees with the tool name/arguments, or (when headers are
    provided) the standardized `Mcp-Method`/`Mcp-Name` headers disagree with
    the body — servers must validate that mirror per the 2026-07-28 spec.
    """
    if body.get("method") != "tools/call":
        raise MeshValidationError("invalid_encoding", "not a tools/call request")
    params = body.get("params")
    if not isinstance(params, dict):
        raise MeshValidationError("invalid_encoding", "tools/call params missing")
    tool_name = params.get("name")
    arguments = params.get("arguments") or {}
    meta = params.get("_meta") or {}
    trust_meta = meta.get(TRUST_META_KEY)
    if not isinstance(trust_meta, dict) or "mesh_request" not in trust_meta:
        raise MeshValidationError(
            "signature_required", f"missing {TRUST_META_KEY} mesh_request extension metadata"
        )

    if headers is not None:
        normalized = {key.lower(): value for key, value in headers.items()}
        header_method = normalized.get("mcp-method")
        if header_method is not None and header_method != "tools/call":
            raise MeshValidationError("invalid_encoding", "Mcp-Method header does not match body")
        header_name = normalized.get("mcp-name")
        if header_name is not None and header_name != tool_name:
            raise MeshValidationError("invalid_encoding", "Mcp-Name header does not match body")

    request = MeshRequest.decoded(trust_meta["mesh_request"])
    if request.target.capability_id != tool_name:
        raise MeshValidationError(
            "unsupported_capability", "envelope capability does not match tool name"
        )
    if not isinstance(arguments, dict) or {
        key: value for key, value in arguments.items()
    } != dict(request.payload):
        raise MeshValidationError(
            "payload_hash_mismatch", "tool arguments do not match the signed envelope payload"
        )
    return request


def build_tool_result(receipt: MeshReceipt, rpc_id: int | str) -> dict[str, Any]:
    return {
        "jsonrpc": "2.0",
        "id": rpc_id,
        "result": {
            "content": [
                {
                    "type": "text",
                    "text": f"{receipt.capability_id}: {receipt.status} (receipt {receipt.receipt_id})",
                }
            ],
            "structuredContent": dict(receipt.result),
            "isError": receipt.status not in ("completed", "pending"),
            "_meta": {TRUST_META_KEY: {"mesh_receipt": receipt.encoded()}},
        },
    }


def extract_mesh_receipt(body: dict[str, Any]) -> MeshReceipt:
    result = body.get("result")
    if not isinstance(result, dict):
        raise MeshValidationError("invalid_encoding", "tools/call result missing")
    meta = result.get("_meta") or {}
    trust_meta = meta.get(TRUST_META_KEY)
    if not isinstance(trust_meta, dict) or "mesh_receipt" not in trust_meta:
        raise MeshValidationError(
            "receipt_correlation_mismatch",
            f"missing {TRUST_META_KEY} mesh_receipt extension metadata",
        )
    return MeshReceipt.decoded(trust_meta["mesh_receipt"])


def build_error(rpc_id: int | str | None, error: MeshValidationError) -> dict[str, Any]:
    return {
        "jsonrpc": "2.0",
        "id": rpc_id,
        "error": {
            "code": INVALID_PARAMS,
            "message": str(error),
            "data": {"meshkit": {"code": error.code}},
        },
    }


@dataclass(frozen=True)
class ToolDescriptor:
    """`tools/list` entry for one OCG capability, with 2026-07-28 cache hints."""

    capability_id: str
    description: str
    input_schema: dict[str, Any]
    ttl_ms: int = 60_000

    def to_tool(self) -> dict[str, Any]:
        return {
            "name": self.capability_id,
            "description": self.description,
            "inputSchema": self.input_schema,
            "_meta": {"ttlMs": self.ttl_ms, "cacheScope": "public"},
        }
