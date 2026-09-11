"""Reference caller: discovers a mini-app's tools, sends one signed MCP
(2026-07-28) `tools/call`, and verifies the target-signed receipt.

Run examples/miniapp_server.py first, then:
    python3 examples/user_agent.py
Exits non-zero unless a correlated, signature-valid receipt comes back —
"the caller accepts completion only from a target-signed receipt".
"""

import base64
import json
import sys
import urllib.request
from datetime import datetime, timezone
from uuid import uuid4

from meshkit import ed25519, mcpv2
from meshkit.models import MeshCapability, MeshIdentity
from meshkit.receipt import MeshReceiptTrust, verify_receipt
from meshkit.request import MeshRequest

BASE_URL = "http://127.0.0.1:8765"

# Demo identity/keys; in the course these come from your team's registered
# caller manifest.
REQUEST_SEED = bytes(range(1, 33))
CALLER = MeshIdentity(
    app_id="app.hermes-chat",
    install_id=f"install-{uuid4().hex[:8]}",
    bundle_id="ai.meshkit.sample.hermeschat",
    public_key_id="hermes-request-ed25519",
)
TARGET_RECEIPT_TRUST = MeshReceiptTrust(
    target_app_id="app.dailymart",
    target_bundle_id="ai.meshkit.sample.dailymart",
    receipt_signing_algorithm="Ed25519",
    receipt_signing_key_id="target-receipt-ed25519",
    public_key_base64=base64.b64encode(
        ed25519.public_key_raw(ed25519.private_key_from_seed(bytes(range(0xA0, 0xC0))))
    ).decode("ascii"),
)


def rpc(body: dict, headers: dict[str, str]) -> dict:
    request = urllib.request.Request(
        BASE_URL, data=json.dumps(body).encode("utf-8"), headers=headers, method="POST"
    )
    with urllib.request.urlopen(request) as response:
        return json.loads(response.read())


def main() -> int:
    # 1. Stateless discovery: no handshake, straight to tools/list.
    tools = rpc(
        {"jsonrpc": "2.0", "id": 1, "method": "tools/list"},
        {"Content-Type": "application/json", "MCP-Protocol-Version": mcpv2.PROTOCOL_VERSION,
         "Mcp-Method": "tools/list"},
    )["result"]["tools"]
    tool = tools[0]
    print(f"discovered tool: {tool['name']}")

    # 2. Build and sign the request.
    request = MeshRequest.create(
        request_id=f"req-{uuid4().hex[:8]}",
        caller=CALLER,
        target=MeshCapability(
            target_bundle_id=TARGET_RECEIPT_TRUST.target_bundle_id,
            capability_id=tool["name"],
            version="1.0",
        ),
        payload={"items": "milk,eggs,bread", "budget_krw": "100"},
        nonce=uuid4().hex,
        timestamp=datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
    ).signed(ed25519.private_key_from_seed(REQUEST_SEED), CALLER.public_key_id)

    # 3. Self-contained signed tools/call.
    response = rpc(
        mcpv2.build_tool_call(request, rpc_id=2, client_name="course-user-agent", client_version="0.1"),
        mcpv2.request_headers(tool["name"]),
    )
    if "error" in response:
        print(f"call denied: {response['error']}")
        return 1

    # 4. Completion is a verified, correlated, target-signed receipt — or nothing.
    receipt = mcpv2.extract_mesh_receipt(response)
    verify_receipt(receipt, TARGET_RECEIPT_TRUST, request=request)
    print(f"verified receipt {receipt.receipt_id}: {receipt.status} {receipt.result}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
