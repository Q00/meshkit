"""Fail-closed trust-layer tests — these are the seeds of the course grader:
a mini-app that fails any of these must not pass the assignment."""

from dataclasses import replace
from datetime import datetime, timezone
from decimal import Decimal

import pytest

from meshkit import ed25519
from meshkit.models import MeshCapability, MeshIdentity, MeshSignature
from meshkit.request import MeshRequest
from meshkit.trust import (
    MeshInvocationPolicy,
    MeshSenderTrust,
    MeshTargetPolicy,
    MeshValidationError,
    validate_and_accept,
)

REQUEST_SEED = bytes(range(1, 33))
PUBLIC_KEY_B64 = "ebVWLo/mVPlAeLES6KmLp5AfhTrmlb7X4OORC60ElmQ="
NOW = datetime(2026, 8, 24, 9, 0, 0, tzinfo=timezone.utc)

CALLER = MeshIdentity(
    app_id="app.hermes-chat",
    install_id="install-fixed-0001",
    bundle_id="ai.meshkit.sample.hermeschat",
    public_key_id="hermes-request-ed25519",
)
CAPABILITY = MeshCapability(
    target_bundle_id="ai.meshkit.sample.dailymart",
    capability_id="grocery.purchase_essentials",
    version="1.0",
)
POLICY = MeshTargetPolicy(
    allowed_caller_app_id="app.hermes-chat",
    target_bundle_id="ai.meshkit.sample.dailymart",
    capability_id="grocery.purchase_essentials",
)
TRUST = MeshSenderTrust(
    caller_app_id="app.hermes-chat",
    caller_bundle_id="ai.meshkit.sample.hermeschat",
    request_signing_algorithm="Ed25519",
    request_signing_key_id="hermes-request-ed25519",
    public_key_base64=PUBLIC_KEY_B64,
)


def signed_request(payload=None, nonce="nonce-0001"):
    request = MeshRequest.create(
        request_id="req-0001",
        caller=CALLER,
        target=CAPABILITY,
        payload=payload or {"items": "milk", "budget_krw": "100"},
        nonce=nonce,
        timestamp="2026-08-24T09:00:00Z",
    )
    return request.signed(ed25519.private_key_from_seed(REQUEST_SEED), "hermes-request-ed25519")


def invocation_policy(user_approved=True, approved_budget=Decimal(100)):
    return MeshInvocationPolicy(
        risk="spend:money",
        consent="budgeted_per_invocation",
        user_approved=user_approved,
        registry_signature_verified=True,
        approved_budget=approved_budget,
    )


def accept(request, invocation=None, reserve=lambda nonce: True):
    return validate_and_accept(
        request=request,
        policy=POLICY,
        invocation_policy=invocation or invocation_policy(),
        trust=TRUST,
        reserve_nonce=reserve,
        now=NOW,
    )


def expect_code(code, func):
    with pytest.raises(MeshValidationError) as excinfo:
        func()
    assert excinfo.value.code == code


def test_accepts_valid_request():
    event = accept(signed_request())
    assert event["status"] == "accepted"
    assert event["requestId"] == "req-0001"


def test_rejects_tampered_payload():
    request = signed_request()
    tampered = replace(request, payload={**request.payload, "budget_krw": "999999"})
    expect_code("payload_hash_mismatch", lambda: accept(tampered))


def test_rejects_wrong_signer_key():
    request = signed_request()
    wrong = request.signed(ed25519.private_key_from_seed(bytes(range(7, 39))), "hermes-request-ed25519")
    expect_code("signature_mismatch", lambda: accept(wrong))


def test_rejects_unsigned_request():
    request = signed_request()
    unsigned = replace(request, signature=MeshSignature("Ed25519", "", ""))
    expect_code("signature_required", lambda: accept(unsigned))


def test_rejects_replayed_nonce():
    seen = set()

    def reserve(nonce):
        if nonce in seen:
            return False
        seen.add(nonce)
        return True

    accept(signed_request(), reserve=reserve)
    expect_code("replay_detected", lambda: accept(signed_request(), reserve=reserve))


def test_rejects_budget_over_approved():
    request = signed_request(payload={"items": "milk", "budget_krw": "101"})
    expect_code("budget_exceeded", lambda: accept(request))


def test_rejects_spend_without_consent():
    expect_code(
        "consent_required",
        lambda: accept(signed_request(), invocation=invocation_policy(user_approved=False)),
    )


def test_rejects_untrusted_caller():
    request = signed_request()
    imposter = replace(request, caller=replace(request.caller, app_id="app.evil"))
    expect_code("trusted_caller_mismatch", lambda: accept(imposter))


def test_rejects_stale_timestamp():
    request = signed_request()
    expect_code(
        "stale_timestamp",
        lambda: validate_and_accept(
            request=request,
            policy=POLICY,
            invocation_policy=invocation_policy(),
            trust=TRUST,
            reserve_nonce=lambda nonce: True,
            now=datetime(2026, 8, 24, 10, 0, 0, tzinfo=timezone.utc),
        ),
    )
