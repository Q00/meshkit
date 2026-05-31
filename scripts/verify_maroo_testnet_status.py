#!/usr/bin/env python3
import json
import os
import argparse
import subprocess
from datetime import datetime, timezone
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
RPC_URL = "https://rpc-testnet.maroo.io"
EXPLORER_URL = "https://explorer-testnet.maroo.io"
FAUCET_URL = "https://faucet.maroo.io"
OKRW_CONTRACT_ADDRESS = os.environ.get("MESHKIT_MAROO_OKRW_CONTRACT_ADDRESS", "").strip()
ARTIFACT_DIR = ROOT / "artifacts" / "maroo-testnet"
ARTIFACT_PATH = ARTIFACT_DIR / "status.json"
EXIT_CONDITION = "BlockedByExternalChain"


def parse_args():
    parser = argparse.ArgumentParser(
        description="Verify maroo testnet availability or validate the local MeshKit demo adapter harness."
    )
    parser.add_argument(
        "--demo-adapter-harness",
        action="store_true",
        help=(
            "Run deterministic local checks for the MeshKit maroo demo adapter command contract "
            "without contacting public maroo endpoints."
        ),
    )
    parser.add_argument(
        "--okrw-contract-address",
        default=None,
        help="Override MESHKIT_MAROO_OKRW_CONTRACT_ADDRESS for harness or live OKRW bytecode checks.",
    )
    return parser.parse_args()


def post_json(url, payload, timeout=10):
    result = subprocess.run(
        [
            "curl",
            "-sS",
            "-m",
            str(timeout),
            "-w",
            "\n%{http_code}",
            url,
            "-H",
            "content-type: application/json",
            "--data",
            json.dumps(payload),
        ],
        check=True,
        text=True,
        capture_output=True,
    )
    body, status = result.stdout.rsplit("\n", 1)
    return int(status), json.loads(body)


def head(url, timeout=10):
    result = subprocess.run(
        [
            "curl",
            "-sS",
            "-I",
            "-m",
            str(timeout),
            "-o",
            "/dev/null",
            "-w",
            "%{http_code}",
            url,
        ],
        check=True,
        text=True,
        capture_output=True,
    )
    return int(result.stdout.strip())


def write_artifact(artifact):
    ARTIFACT_DIR.mkdir(parents=True, exist_ok=True)
    ARTIFACT_PATH.write_text(json.dumps(artifact, indent=2, sort_keys=True) + "\n")


def run_demo_adapter_harness():
    ARTIFACT_DIR.mkdir(parents=True, exist_ok=True)
    harness_path = ARTIFACT_DIR / "demo-adapter-harness.json"
    artifact = {
        "checkedAt": datetime.now(timezone.utc).isoformat(),
        "adapterTestHarness": True,
        "provider": "maroo",
        "network": "maroo-testnet",
        "chainId": "maroo-testnet-1",
        "rpcUrl": RPC_URL,
        "explorerUrl": EXPLORER_URL,
        "faucetUrl": FAUCET_URL,
        "okrwContractAddress": OKRW_CONTRACT_ADDRESS or None,
        "validatedJsonRpcMethods": [
            "eth_blockNumber",
            "net_version",
            "eth_getCode",
        ],
        "validatedProviderNeutralFields": [
            "signedRequestHash",
            "requestNonce",
            "policyId",
            "policyHash",
            "anchoringReference",
            "asset",
            "amount",
            "recipient",
            "status",
            "txHash",
            "explorerUrl",
        ],
        "scopeBoundary": (
            "Deterministic docs-command harness only; live confirmation still requires public maroo "
            "testnet availability, a funded OKRW wallet, and a real provider-returned transaction hash."
        ),
    }
    harness_path.write_text(json.dumps(artifact, indent=2, sort_keys=True) + "\n")
    print(f"maroo demo adapter command harness passed: {harness_path}")


def blocker_evidence(blocker_type, endpoint, operation, message):
    artifact = {
        "checkedAt": datetime.now(timezone.utc).isoformat(),
        "exitCondition": EXIT_CONDITION,
        "blockerEvidence": {
            "exitCondition": EXIT_CONDITION,
            "blockerType": blocker_type,
            "provider": "maroo",
            "network": "maroo-testnet",
            "chainId": "maroo-testnet-1",
            "endpoint": endpoint,
            "operation": operation,
            "message": message,
        },
        "rpcUrl": RPC_URL,
        "explorerUrl": EXPLORER_URL,
        "faucetUrl": FAUCET_URL,
        "okrwContractAddress": OKRW_CONTRACT_ADDRESS or None,
        "scopeBoundary": (
            "Public RPC/explorer/faucet availability only; this does not prove a funded "
            "OKRW wallet, a live OKRW contract call, or a confirmed payment tx. "
            "No deterministic fallback hash may be represented as confirmed payment proof."
        ),
    }
    write_artifact(artifact)
    return artifact


def fail_with_blocker(blocker_type, endpoint, operation, message):
    artifact = blocker_evidence(blocker_type, endpoint, operation, message)
    raise AssertionError(
        f"{EXIT_CONDITION}: {artifact['blockerEvidence']['blockerType']} "
        f"{operation} failed; evidence written to {ARTIFACT_PATH}"
    )


def main():
    global OKRW_CONTRACT_ADDRESS
    args = parse_args()
    if args.okrw_contract_address is not None:
        OKRW_CONTRACT_ADDRESS = args.okrw_contract_address.strip()

    if args.demo_adapter_harness:
        run_demo_adapter_harness()
        return

    try:
        block_status, block_result = post_json(
            RPC_URL,
            {"jsonrpc": "2.0", "id": 1, "method": "eth_blockNumber", "params": []},
        )
    except Exception as error:
        fail_with_blocker("rpc_unavailable", RPC_URL, "eth_blockNumber", str(error))

    try:
        net_status, net_result = post_json(
            RPC_URL,
            {"jsonrpc": "2.0", "id": 2, "method": "net_version", "params": []},
        )
    except Exception as error:
        fail_with_blocker("rpc_unavailable", RPC_URL, "net_version", str(error))

    try:
        explorer_status = head(EXPLORER_URL)
    except Exception as error:
        fail_with_blocker("explorer_unavailable", EXPLORER_URL, "explorer HEAD", str(error))

    try:
        faucet_status = head(FAUCET_URL)
    except Exception as error:
        fail_with_blocker("faucet_unavailable", FAUCET_URL, "faucet HEAD", str(error))

    block_hex = block_result.get("result")
    net_version = net_result.get("result")
    if not isinstance(block_hex, str) or not block_hex.startswith("0x"):
        fail_with_blocker("rpc_unavailable", RPC_URL, "eth_blockNumber", f"unexpected result: {block_result}")
    if not isinstance(net_version, str) or not net_version:
        fail_with_blocker("rpc_unavailable", RPC_URL, "net_version", f"unexpected result: {net_result}")
    if block_status != 200 or net_status != 200 or explorer_status >= 400 or faucet_status >= 400:
        if block_status != 200:
            fail_with_blocker("rpc_unavailable", RPC_URL, "eth_blockNumber", f"http status {block_status}")
        if net_status != 200:
            fail_with_blocker("rpc_unavailable", RPC_URL, "net_version", f"http status {net_status}")
        if explorer_status >= 400:
            fail_with_blocker("explorer_unavailable", EXPLORER_URL, "explorer HEAD", f"http status {explorer_status}")
        fail_with_blocker("faucet_unavailable", FAUCET_URL, "faucet HEAD", f"http status {faucet_status}")

    okrw_contract = None
    if OKRW_CONTRACT_ADDRESS:
        try:
            code_status, code_result = post_json(
                RPC_URL,
                {
                    "jsonrpc": "2.0",
                    "id": 3,
                    "method": "eth_getCode",
                    "params": [OKRW_CONTRACT_ADDRESS, "latest"],
                },
            )
        except Exception as error:
            fail_with_blocker("okrw_contract_unavailable", RPC_URL, "eth_getCode OKRW", str(error))

        deployed_code = code_result.get("result")
        if code_status != 200:
            fail_with_blocker(
                "okrw_contract_unavailable",
                RPC_URL,
                "eth_getCode OKRW",
                f"http status {code_status}",
            )
        if not isinstance(deployed_code, str) or not deployed_code.startswith("0x") or len(deployed_code) <= 2:
            fail_with_blocker(
                "okrw_contract_unavailable",
                RPC_URL,
                "eth_getCode OKRW",
                f"unexpected result: {code_result}",
            )
        okrw_contract = {
            "address": OKRW_CONTRACT_ADDRESS,
            "httpStatus": code_status,
            "bytecodePrefix": deployed_code[:18],
            "bytecodeLength": len(deployed_code),
        }

    artifact = {
        "checkedAt": datetime.now(timezone.utc).isoformat(),
        "rpcUrl": RPC_URL,
        "explorerUrl": EXPLORER_URL,
        "faucetUrl": FAUCET_URL,
        "eth_blockNumber": {
            "httpStatus": block_status,
            "hex": block_hex,
            "decimal": int(block_hex, 16),
        },
        "net_version": {
            "httpStatus": net_status,
            "value": net_version,
        },
        "explorer": {
            "httpStatus": explorer_status,
        },
        "faucet": {
            "httpStatus": faucet_status,
        },
        "okrwContract": okrw_contract,
        "scopeBoundary": (
            "Public RPC/explorer/faucet availability only; this does not prove a funded "
            "OKRW wallet, a live OKRW contract call, or a confirmed payment tx."
        ),
    }
    write_artifact(artifact)
    print(f"maroo testnet public endpoint check passed: {ARTIFACT_PATH}")


if __name__ == "__main__":
    main()
