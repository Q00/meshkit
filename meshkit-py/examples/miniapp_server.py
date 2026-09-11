"""Reference MeshKit mini-app: a stateless MCP (2026-07-28) server.

Course assignment template. Standard library only (plus meshkit). One OCG
capability = one MCP tool; every `tools/call` must carry the signed MeshKit
envelope in `_meta["ai.meshkit/trust"]` and returns a target-signed receipt.

Run:
    python3 examples/miniapp_server.py  # listens on 127.0.0.1:8765

Replace CAPABILITY/handle_call with your team's catalog and seller-agent
logic. The trust layer around it must stay fail-closed — the grader attacks
it with tampered payloads, replays, and budget violations.
"""

import base64
import json
import os
from datetime import datetime, timezone
from decimal import Decimal
from http.server import BaseHTTPRequestHandler, HTTPServer
from uuid import uuid4

from meshkit import ed25519, mcpv2
from meshkit.receipt import MeshReceiptSigner
from meshkit.trust import (
    MeshInvocationPolicy,
    MeshSenderTrust,
    MeshTargetPolicy,
    MeshValidationError,
    validate_and_accept,
)

# --- team identity (in the course: keys come from your registered manifest) --
TARGET_APP_ID = "app.dailymart"
TARGET_BUNDLE_ID = "ai.meshkit.sample.dailymart"
RECEIPT_SEED = bytes(range(0xA0, 0xC0))  # demo seed; teams generate their own
RECEIPT_KEY_ID = "target-receipt-ed25519"

# Trusted caller (in the course: loaded from the signed OCG registry).
TRUSTED_CALLER = MeshSenderTrust(
    caller_app_id="app.hermes-chat",
    caller_bundle_id="ai.meshkit.sample.hermeschat",
    request_signing_algorithm="Ed25519",
    request_signing_key_id="hermes-request-ed25519",
    public_key_base64=os.environ.get(
        "MESHKIT_CALLER_PUBKEY", "ebVWLo/mVPlAeLES6KmLp5AfhTrmlb7X4OORC60ElmQ="
    ),
)

CAPABILITY = mcpv2.ToolDescriptor(
    capability_id="grocery.purchase_essentials",
    description="Purchase household essentials within an approved budget (KRW).",
    input_schema={
        "type": "object",
        "required": ["items", "budget_krw"],
        "properties": {
            "items": {"type": "string"},
            "budget_krw": {"type": "string"},
        },
    },
)

POLICY = MeshTargetPolicy(
    allowed_caller_app_id=TRUSTED_CALLER.caller_app_id,
    target_bundle_id=TARGET_BUNDLE_ID,
    capability_id=CAPABILITY.capability_id,
)

# Demo consent: the ₩100 budget gate, pre-approved. A real mini-app captures
# consent from its user before accepting spend:money calls.
INVOCATION_POLICY = MeshInvocationPolicy(
    risk="spend:money",
    consent="budgeted_per_invocation",
    user_approved=True,
    registry_signature_verified=True,
    approved_budget=Decimal(100),
)

_seen_nonces: set[str] = set()


def reserve_nonce(nonce: str) -> bool:
    if nonce in _seen_nonces:
        return False
    _seen_nonces.add(nonce)
    return True


def handle_call(payload: dict[str, str]) -> dict[str, str]:
    """Your business logic / seller agent lives here."""
    return {
        "status": "completed",
        "order_id": f"order-{uuid4().hex[:8]}",
        "purchased_items": payload["items"],
        "total_krw": payload["budget_krw"],
    }


signer = MeshReceiptSigner.from_seed(RECEIPT_KEY_ID, RECEIPT_SEED)


class Handler(BaseHTTPRequestHandler):
    def do_POST(self):
        body = json.loads(self.rfile.read(int(self.headers["Content-Length"] or 0)))
        method = body.get("method")
        rpc_id = body.get("id")
        if method == "server/discover":
            self._reply(
                {
                    "jsonrpc": "2.0",
                    "id": rpc_id,
                    "result": {
                        "protocolVersions": [mcpv2.PROTOCOL_VERSION],
                        "serverInfo": {"name": TARGET_APP_ID, "version": "0.1.0"},
                        "capabilities": {"tools": {}},
                    },
                }
            )
        elif method == "tools/list":
            self._reply(
                {"jsonrpc": "2.0", "id": rpc_id, "result": {"tools": [CAPABILITY.to_tool()]}}
            )
        elif method == "tools/call":
            self._tools_call(body, rpc_id)
        else:
            self._reply(
                {
                    "jsonrpc": "2.0",
                    "id": rpc_id,
                    "error": {"code": -32601, "message": f"method not found: {method}"},
                }
            )

    def _tools_call(self, body, rpc_id):
        try:
            headers = {key: value for key, value in self.headers.items()}
            request = mcpv2.extract_mesh_request(body, headers)
            validate_and_accept(
                request=request,
                policy=POLICY,
                invocation_policy=INVOCATION_POLICY,
                trust=TRUSTED_CALLER,
                reserve_nonce=reserve_nonce,
            )
        except MeshValidationError as error:
            self._reply(mcpv2.build_error(rpc_id, error))
            return
        result = handle_call(request.payload)
        receipt = signer.make_receipt(
            receipt_id=f"rcpt-{uuid4().hex[:8]}",
            request=request,
            target_app_id=TARGET_APP_ID,
            target_bundle_id=TARGET_BUNDLE_ID,
            status=result["status"],
            result=result,
            nonce=uuid4().hex,
            timestamp=datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
        )
        self._reply(mcpv2.build_tool_result(receipt, rpc_id))

    def _reply(self, obj):
        data = json.dumps(obj).encode("utf-8")
        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)

    def log_message(self, format, *args):
        pass


def main():
    port = int(os.environ.get("PORT", "8765"))
    public_key = base64.b64encode(
        ed25519.public_key_raw(ed25519.private_key_from_seed(RECEIPT_SEED))
    ).decode("ascii")
    print(f"mini-app {TARGET_APP_ID} on 127.0.0.1:{port}")
    print(f"receipt public key (for the registry manifest): {public_key}")
    HTTPServer(("127.0.0.1", port), Handler).serve_forever()


if __name__ == "__main__":
    main()
