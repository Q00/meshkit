"""MCP 2026-07-28 mapping: signed envelope in `_meta`, receipt in result."""

from dataclasses import replace
from datetime import datetime, timezone

import pytest

from meshkit import ed25519, mcpv2
from meshkit.models import MeshCapability, MeshIdentity
from meshkit.receipt import MeshReceiptSigner, MeshReceiptTrust, verify_receipt
from meshkit.request import MeshRequest
from meshkit.trust import MeshValidationError

REQUEST_SEED = bytes(range(1, 33))
RECEIPT_SEED = bytes(range(0xA0, 0xC0))


def signed_request():
    request = MeshRequest.create(
        request_id="req-mcp-0001",
        caller=MeshIdentity("app.hermes-chat", "install-1", "ai.meshkit.sample.hermeschat", "k1"),
        target=MeshCapability("ai.meshkit.sample.dailymart", "grocery.purchase_essentials", "1.0"),
        payload={"items": "milk", "budget_krw": "100"},
        nonce="nonce-mcp-0001",
        timestamp="2026-08-24T09:00:00Z",
    )
    return request.signed(ed25519.private_key_from_seed(REQUEST_SEED), "k1")


def test_tool_call_round_trip():
    request = signed_request()
    body = mcpv2.build_tool_call(request, rpc_id=1, client_name="course-agent", client_version="1.0")
    headers = mcpv2.request_headers(request.target.capability_id)

    assert headers["MCP-Protocol-Version"] == "2026-07-28"
    assert headers["Mcp-Name"] == "grocery.purchase_essentials"
    assert body["params"]["arguments"] == request.payload
    assert mcpv2.CLIENT_INFO_META_KEY in body["params"]["_meta"]

    extracted = mcpv2.extract_mesh_request(body, headers)
    assert extracted == request


def test_rejects_arguments_that_disagree_with_envelope():
    request = signed_request()
    body = mcpv2.build_tool_call(request, 1, "course-agent", "1.0")
    body["params"]["arguments"]["budget_krw"] = "999999"
    with pytest.raises(MeshValidationError) as excinfo:
        mcpv2.extract_mesh_request(body)
    assert excinfo.value.code == "payload_hash_mismatch"


def test_rejects_header_body_mismatch():
    request = signed_request()
    body = mcpv2.build_tool_call(request, 1, "course-agent", "1.0")
    headers = mcpv2.request_headers("some.other_tool")
    with pytest.raises(MeshValidationError):
        mcpv2.extract_mesh_request(body, headers)


def test_rejects_missing_trust_extension():
    request = signed_request()
    body = mcpv2.build_tool_call(request, 1, "course-agent", "1.0")
    del body["params"]["_meta"][mcpv2.TRUST_META_KEY]
    with pytest.raises(MeshValidationError) as excinfo:
        mcpv2.extract_mesh_request(body)
    assert excinfo.value.code == "signature_required"


def test_tool_result_carries_verifiable_receipt():
    request = signed_request()
    receipt = MeshReceiptSigner.from_seed("target-k1", RECEIPT_SEED).make_receipt(
        receipt_id="rcpt-mcp-0001",
        request=request,
        target_app_id="app.dailymart",
        target_bundle_id="ai.meshkit.sample.dailymart",
        status="completed",
        result={"status": "completed", "order_id": "order-1"},
        nonce="rcpt-nonce-mcp-0001",
        timestamp="2026-08-24T09:00:05Z",
    )
    body = mcpv2.build_tool_result(receipt, rpc_id=1)
    assert body["result"]["isError"] is False
    assert body["result"]["structuredContent"]["order_id"] == "order-1"

    extracted = mcpv2.extract_mesh_receipt(body)
    seed_public = ed25519.public_key_raw(ed25519.private_key_from_seed(RECEIPT_SEED))
    import base64

    verify_receipt(
        extracted,
        MeshReceiptTrust(
            target_app_id="app.dailymart",
            target_bundle_id="ai.meshkit.sample.dailymart",
            receipt_signing_algorithm="Ed25519",
            receipt_signing_key_id="target-k1",
            public_key_base64=base64.b64encode(seed_public).decode("ascii"),
        ),
        request=request,
        now=datetime(2026, 8, 24, 9, 0, 5, tzinfo=timezone.utc),
    )


def test_error_uses_invalid_params_code():
    body = mcpv2.build_error(7, MeshValidationError("budget_exceeded", "requested spend exceeds approved budget"))
    assert body["error"]["code"] == -32602
    assert body["error"]["data"]["meshkit"]["code"] == "budget_exceeded"
