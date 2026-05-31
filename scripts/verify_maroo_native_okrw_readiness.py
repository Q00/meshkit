#!/usr/bin/env python3
import json
import os
import subprocess
from datetime import datetime, timezone
from decimal import Decimal, InvalidOperation
from pathlib import Path
from urllib.parse import urlparse, urlunparse


ROOT = Path(__file__).resolve().parents[1]
ARTIFACT_DIR = ROOT / "artifacts" / "maroo-testnet"
ARTIFACT_PATH = ARTIFACT_DIR / "maroo-native-okrw-readiness.json"
EXIT_CONDITION = "BlockedByExternalChain"
DEFAULT_ENV_PATH = ROOT / ".env.maroo-demo.local"


def load_env_file(path):
    env = {}
    if not path.exists():
        return env
    for line in path.read_text().splitlines():
        stripped = line.strip()
        if not stripped or stripped.startswith("#") or "=" not in stripped:
            continue
        key, value = stripped.split("=", 1)
        env[key] = value
    return env


def merged_environment():
    env_path = Path(os.environ.get("DEMO_WALLET_ENV_PATH", DEFAULT_ENV_PATH))
    file_env = load_env_file(env_path)
    return {**file_env, **os.environ}, env_path


def run(command, timeout=8):
    try:
        return subprocess.run(
            command,
            cwd=ROOT,
            text=True,
            capture_output=True,
            timeout=timeout,
        )
    except subprocess.TimeoutExpired as error:
        return subprocess.CompletedProcess(
            command,
            124,
            stdout=(error.stdout or "") if isinstance(error.stdout, str) else "",
            stderr=f"timeout after {timeout}s",
        )


def main():
    ARTIFACT_DIR.mkdir(parents=True, exist_ok=True)
    env, env_path = merged_environment()
    rpc_url = env.get("MESHKIT_MAROO_RPC_URL", "https://rpc-testnet.maroo.io")
    missing = []
    for key in ["MESHKIT_MAROO_OKRW_TRANSFER_BRIDGE_URL", "MESHKIT_MAROO_PRIVATE_KEY"]:
        if not env.get(key):
            missing.append(key)

    bridge_health = None
    bridge_url = env.get("MESHKIT_MAROO_OKRW_TRANSFER_BRIDGE_URL", "").strip()
    if bridge_url:
        health_url = health_url_for_bridge(bridge_url)
        result = run(["curl", "-sS", "-m", "5", health_url], timeout=8)
        parsed_stdout = parse_json(result.stdout.strip())
        bridge_health = {
            "url": health_url,
            "exitCode": result.returncode,
            "stdout": result.stdout.strip()[:2000],
            "stderr": result.stderr.strip()[:2000],
            "json": parsed_stdout,
        }

    required_amount = decimal_string(env.get("MESHKIT_MAROO_OKRW_PROBE_AMOUNT", "1"))
    health_json = bridge_health.get("json") if isinstance(bridge_health, dict) else None
    health_data = health_json.get("data", {}) if isinstance(health_json, dict) else {}
    configured_signer = (
        health_data.get("signerAddress")
        or env.get("MESHKIT_MAROO_WALLET_ADDRESS")
        or env.get("MESHKIT_MAROO_FAUCET_WALLET_ADDRESS")
    )
    rpc_balance = rpc_get_balance(rpc_url, configured_signer) if configured_signer else None
    signer_balance = decimal_string(health_data.get("signerBalanceOKRW"))
    if signer_balance is None and isinstance(rpc_balance, dict):
        signer_balance = decimal_string(rpc_balance.get("balanceOKRW"))
    balance_sufficient = (
        signer_balance is not None and required_amount is not None and signer_balance >= required_amount
    )
    signer_address_present = bool(configured_signer)
    bridge_ok = bridge_health is not None and bridge_health["exitCode"] == 0 and isinstance(health_json, dict) and health_json.get("ok") is True
    ready = not missing and bridge_ok and signer_address_present and balance_sufficient
    artifact = {
        "checkedAt": datetime.now(timezone.utc).isoformat(),
        "provider": "maroo",
        "network": "maroo-testnet",
        "ready": ready,
        "exitCondition": None if ready else EXIT_CONDITION,
        "envPath": str(env_path),
        "requiredEnvironment": [
            "MESHKIT_MAROO_OKRW_TRANSFER_BRIDGE_URL",
            "MESHKIT_MAROO_PRIVATE_KEY",
        ],
        "missingEnvironment": missing,
        "bridgeHealth": bridge_health,
        "fundingCheck": {
            "requiredProbeAmountOKRW": env.get("MESHKIT_MAROO_OKRW_PROBE_AMOUNT", "1"),
            "signerAddress": configured_signer,
            "signerBalanceOKRW": health_data.get("signerBalanceOKRW") or (rpc_balance or {}).get("balanceOKRW"),
            "signerBalanceWei": health_data.get("signerBalanceWei") or (rpc_balance or {}).get("balanceWei"),
            "balanceSufficientForProbe": balance_sufficient,
            "rpcBalance": rpc_balance,
        },
        "blockerEvidence": None
        if ready
        else {
            "exitCondition": EXIT_CONDITION,
            "blockerType": blocker_type(missing, bridge_ok, signer_address_present, balance_sufficient),
            "operation": "maroo native OKRW transfer readiness",
            "message": (
                "Direct maroo OKRW bridge, signer, or funded balance is incomplete; DailyMart must "
                "not present deterministic fallback as a confirmed maroo OKRW transfer."
            ),
        },
    }
    ARTIFACT_PATH.write_text(json.dumps(artifact, indent=2, sort_keys=True) + "\n")
    print(f"maroo native OKRW readiness artifact written: {ARTIFACT_PATH}")
    if not ready:
        raise SystemExit(2)


def health_url_for_bridge(bridge_url):
    parsed = urlparse(bridge_url)
    if not parsed.scheme or not parsed.netloc:
        return bridge_url.rstrip("/") + "/health"
    return urlunparse((parsed.scheme, parsed.netloc, "/health", "", "", ""))


def parse_json(text):
    try:
        return json.loads(text)
    except json.JSONDecodeError:
        return None


def rpc_get_balance(rpc_url, address):
    if not address:
        return None
    body = json.dumps(
        {
            "jsonrpc": "2.0",
            "id": 1,
            "method": "eth_getBalance",
            "params": [address, "latest"],
        }
    )
    result = run(
        [
            "curl",
            "-sS",
            "-m",
            "8",
            "-H",
            "content-type: application/json",
            "-d",
            body,
            rpc_url,
        ],
        timeout=10,
    )
    parsed = parse_json(result.stdout.strip())
    balance_wei = None
    balance_okrw = None
    if isinstance(parsed, dict) and isinstance(parsed.get("result"), str):
        try:
            balance_wei_int = int(parsed["result"], 16)
            balance_wei = str(balance_wei_int)
            balance_okrw = str(Decimal(balance_wei_int) / Decimal(10**18))
        except ValueError:
            pass
    return {
        "rpcUrl": rpc_url,
        "address": address,
        "exitCode": result.returncode,
        "httpResponse": parsed,
        "balanceWei": balance_wei,
        "balanceOKRW": balance_okrw,
    }


def decimal_string(value):
    if value is None:
        return None
    try:
        return Decimal(str(value))
    except (InvalidOperation, ValueError):
        return None


def blocker_type(missing, bridge_ok, signer_address_present, balance_sufficient):
    if "MESHKIT_MAROO_PRIVATE_KEY" in missing:
        return "funded_wallet_unavailable"
    if not balance_sufficient:
        return "funded_wallet_unavailable"
    if not bridge_ok or not signer_address_present:
        return "payment_confirmation_unavailable"
    return "payment_confirmation_unavailable"


if __name__ == "__main__":
    main()
