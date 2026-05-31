#!/usr/bin/env python3
import json
import os
import re
import subprocess
from datetime import datetime, timezone
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
ARTIFACT_DIR = ROOT / "artifacts" / "maroo-testnet"
ARTIFACT_PATH = ARTIFACT_DIR / "faucet-readiness.json"
DEMO_WALLET_ENV_PATH = Path(os.environ.get("MESHKIT_MAROO_DEMO_WALLET_ENV", ROOT / ".env.maroo-demo.local"))
FAUCET_URL = os.environ.get("MESHKIT_MAROO_FAUCET_URL", "https://faucet.maroo.io/")


def fetch_text(url):
    result = subprocess.run(
        [
            "curl",
            "-sSL",
            "-A",
            "meshkit-maroo-faucet-readiness/0.1",
            "-H",
            "accept: text/html,application/xhtml+xml",
            "-w",
            "\n%{http_code} %{url_effective}",
            url,
        ],
        text=True,
        capture_output=True,
        timeout=15,
    )
    if result.returncode != 0:
        raise RuntimeError(result.stderr.strip() or result.stdout.strip() or f"curl exited {result.returncode}")
    body, _, trailer = result.stdout.rpartition("\n")
    status_text, _, final_url = trailer.partition(" ")
    return int(status_text), final_url.strip() or url, body


def load_env_file(path):
    if not path.exists():
        return {}
    values = {}
    for line in path.read_text().splitlines():
        stripped = line.strip()
        if not stripped or stripped.startswith("#") or "=" not in stripped:
            continue
        key, value = stripped.split("=", 1)
        values[key] = value
    return values


def main():
    ARTIFACT_DIR.mkdir(parents=True, exist_ok=True)
    env = {**load_env_file(DEMO_WALLET_ENV_PATH), **os.environ}
    wallet_address = env.get("MESHKIT_MAROO_FAUCET_WALLET_ADDRESS", "").strip()
    maws_funding_address = env.get("MESHKIT_MAWS_WALLET_ADDRESS", "").strip()
    maws_agent_id = env.get("MESHKIT_MAWS_AGENT_ID", "").strip()
    direct_funding_address = env.get("MESHKIT_MAROO_WALLET_ADDRESS", "").strip()
    probe_recipient = (
        env.get("MESHKIT_MAWS_PROBE_RECIPIENT", "").strip()
        or env.get("MESHKIT_MAROO_OKRW_PROBE_RECIPIENT", "").strip()
    )
    wallet_address_valid = bool(re.fullmatch(r"0x[a-fA-F0-9]{40}", wallet_address)) if wallet_address else False
    evm_address_pattern = r"0x[a-fA-F0-9]{40}"
    try:
        status, final_url, text = fetch_text(FAUCET_URL)
        page_available = status == 200
    except Exception as error:
        status = None
        final_url = FAUCET_URL
        text = ""
        page_available = False
        fetch_error = str(error)
    else:
        fetch_error = None

    artifact = {
        "checkedAt": datetime.now(timezone.utc).isoformat(),
        "provider": "maroo",
        "network": "maroo-testnet",
        "faucetUrl": FAUCET_URL,
        "demoWalletEnvPath": str(DEMO_WALLET_ENV_PATH),
        "demoWalletEnvPresent": DEMO_WALLET_ENV_PATH.exists(),
        "finalUrl": final_url,
        "httpStatus": status,
        "pageAvailable": page_available,
        "walletAddressProvided": bool(wallet_address),
        "walletAddressValid": wallet_address_valid,
        "fundingTargets": {
            "explicitFaucetWallet": {
                "address": wallet_address or None,
                "provided": bool(wallet_address),
                "validEVMAddress": wallet_address_valid,
            },
            "mawsAgentWallet": {
                "agentId": maws_agent_id or None,
                "walletAddress": maws_funding_address or None,
                "walletAddressProvided": bool(maws_funding_address),
                "validEVMAddress": bool(re.fullmatch(evm_address_pattern, maws_funding_address)) if maws_funding_address else False,
                "fundingRequiredBeforeLiveTransfer": True,
            },
            "directMarooWallet": {
                "walletAddress": direct_funding_address or None,
                "walletAddressProvided": bool(direct_funding_address),
                "validEVMAddress": bool(re.fullmatch(evm_address_pattern, direct_funding_address)) if direct_funding_address else False,
                "privateKeyConfigured": bool(env.get("MESHKIT_MAROO_PRIVATE_KEY")),
                "fundingRequiredBeforeLiveTransfer": True,
            },
            "probeRecipient": {
                "address": probe_recipient or None,
                "provided": bool(probe_recipient),
                "validEVMAddress": bool(re.fullmatch(evm_address_pattern, probe_recipient)) if probe_recipient else False,
            },
        },
        "automationSupported": False,
        "manualFundingRequired": True,
        "manualFundingEvidenceRequired": [
            "Fund the M-AWS agent wallet or the direct maroo signer wallet from https://faucet.maroo.io/.",
            "Record the funded wallet address in MESHKIT_MAWS_WALLET_ADDRESS, MESHKIT_MAROO_WALLET_ADDRESS, or MESHKIT_MAROO_FAUCET_WALLET_ADDRESS.",
            "Produce a confirmed OKRW transfer proof artifact with txHash, blockHash, blockNumber, confirmationCount, confirmedAt, and explorerUrl.",
        ],
        "manualFundingSteps": [
            "Open https://faucet.maroo.io/",
            "Connect the maroo testnet wallet that will fund M-AWS or the direct OKRW transfer bridge.",
            "Request test tokens from the faucet.",
            "Re-run python3 scripts/verify_maroo_demo_readiness.py and require liveConfirmed=true only after a confirmed transfer proof exists.",
        ],
        "observedPageClaims": {
            "connectWallet": "Connect Wallet" in text or "Connect your wallet" in text,
            "requestTokens": "Request test tokens" in text,
            "tOKRWPerRequest": "5,000 tOKRW" in text,
            "rateLimit": "Max 5" in text,
            "holdingCap": "10,000 tOKRW" in text,
        },
        "fetchError": fetch_error,
        "exitCondition": None if page_available else "BlockedByExternalChain",
        "blockerEvidence": None
        if page_available
        else {
            "exitCondition": "BlockedByExternalChain",
            "blockerType": "faucet_unavailable",
            "operation": "maroo testnet faucet readiness",
            "message": "maroo faucet page could not be fetched; testnet wallet funding cannot be verified from this environment.",
        },
    }
    ARTIFACT_PATH.write_text(json.dumps(artifact, indent=2, sort_keys=True) + "\n")
    print(f"maroo faucet readiness artifact written: {ARTIFACT_PATH}")
    if not page_available:
        raise SystemExit(2)


if __name__ == "__main__":
    main()
