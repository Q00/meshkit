#!/usr/bin/env python3
import json
import os
import subprocess
from datetime import datetime, timezone
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
MAROO_CREDENTIALS_PATH = Path.home() / ".maroo" / "credentials.json"
ARTIFACT_DIR = ROOT / "artifacts" / "maroo-testnet"
ARTIFACT_PATH = ARTIFACT_DIR / "maws-live-readiness.json"
MCP_PROBE_PATH = ARTIFACT_DIR / "maws-mcp-stdio-probe.json"
EXIT_CONDITION = "BlockedByExternalChain"


def run(command, timeout=15):
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


def load_json(path):
    if not path.exists():
        return None
    try:
        return json.loads(path.read_text())
    except json.JSONDecodeError as error:
        return {"parseError": str(error)}


def main():
    ARTIFACT_DIR.mkdir(parents=True, exist_ok=True)
    env = os.environ
    missing = []
    missing_config = []
    for key in ["MESHKIT_MAWS_BRIDGE_URL", "MESHKIT_MAWS_AGENT_ID"]:
        if not env.get(key):
            missing_config.append(key)
    missing.extend(missing_config)
    has_auth_material = bool(env.get("WAAS_AUTH_TOKEN")) or MAROO_CREDENTIALS_PATH.exists()
    missing_auth = []
    if not has_auth_material:
        missing_auth.append("WAAS_AUTH_TOKEN or ~/.maroo/credentials.json")
    missing.extend(missing_auth)
    bridge_health = None
    bridge_url = env.get("MESHKIT_MAWS_BRIDGE_URL", "").strip()
    if bridge_url:
        health_url = bridge_url.rstrip("/") + "/health"
        result = run(["curl", "-sS", "-m", "5", health_url], timeout=8)
        bridge_health = {
            "url": health_url,
            "exitCode": result.returncode,
            "stdout": result.stdout.strip()[:2000],
            "stderr": result.stderr.strip()[:2000],
        }

    maws_status = run(["npx", "-y", "@maroo-chain/m-aws", "status"], timeout=20)
    maws_mcp_probe = run(["node", "scripts/probe_maws_mcp_stdio.mjs"], timeout=100)
    maws_mcp_probe_artifact = load_json(MCP_PROBE_PATH)
    status_text = f"{maws_status.stdout}\n{maws_status.stderr}".lower()
    maws_authenticated = (
        maws_status.returncode == 0
        and "not logged in" not in status_text
        and "run one of:" not in status_text
    )
    maws_mcp_available = maws_mcp_probe.returncode == 0
    maws_mcp_error_code = (
        maws_mcp_probe_artifact.get("error", {}).get("code")
        if isinstance(maws_mcp_probe_artifact, dict)
        else None
    )
    if not maws_mcp_available and maws_mcp_error_code != "MAWS_AUTH_MISSING":
        missing.append("m-aws MCP server with transfer.send")
    auth_missing = maws_mcp_error_code == "MAWS_AUTH_MISSING" or not has_auth_material or not maws_authenticated
    config_missing = bool(missing_config)
    ready = not missing and maws_authenticated and maws_mcp_available
    blocker_type = (
        "maws_auth_unavailable"
        if auth_missing
        else "maws_mcp_unavailable"
        if not maws_mcp_available
        else "maws_config_unavailable"
        if config_missing
        else "payment_confirmation_unavailable"
    )
    blocker_causes = []
    if auth_missing:
        blocker_causes.append({
            "code": "MAWS_AUTH_MISSING",
            "message": "M-AWS is not logged in and no WAAS_AUTH_TOKEN or ~/.maroo/credentials.json is available.",
            "missing": missing_auth,
        })
    if config_missing:
        blocker_causes.append({
            "code": "MAWS_CONFIG_MISSING",
            "message": "DailyMart cannot route live transfer.send without bridge URL and agent id.",
            "missing": missing_config,
        })
    if not maws_mcp_available and not auth_missing:
        blocker_causes.append({
            "code": maws_mcp_error_code or "MAWS_MCP_UNAVAILABLE",
            "message": "M-AWS MCP did not expose transfer.send.",
            "missing": ["m-aws MCP server with transfer.send"],
        })
    artifact = {
        "checkedAt": datetime.now(timezone.utc).isoformat(),
        "provider": "maroo",
        "network": "maroo-testnet",
        "exitCondition": EXIT_CONDITION if not ready else None,
        "ready": ready,
        "missingEnvironment": missing,
        "missingAuth": missing_auth,
        "missingConfig": missing_config,
        "requiredEnvironment": [
            "MESHKIT_MAWS_BRIDGE_URL",
            "MESHKIT_MAWS_AGENT_ID",
            "WAAS_AUTH_TOKEN or stored ~/.maroo/credentials.json",
        ],
        "fundingTarget": {
            "agentId": env.get("MESHKIT_MAWS_AGENT_ID") or None,
            "walletAddress": env.get("MESHKIT_MAWS_WALLET_ADDRESS") or None,
            "walletAddressProvided": bool(env.get("MESHKIT_MAWS_WALLET_ADDRESS")),
            "faucetFundingRequired": True,
        },
        "credentialsFilePresent": MAROO_CREDENTIALS_PATH.exists(),
        "bridgeHealth": bridge_health,
        "mawsStatus": {
            "command": "npx -y @maroo-chain/m-aws status",
            "exitCode": maws_status.returncode,
            "authenticated": maws_authenticated,
            "stdout": maws_status.stdout.strip()[:4000],
            "stderr": maws_status.stderr.strip()[:4000],
        },
        "mawsMCPProbe": {
            "command": "node scripts/probe_maws_mcp_stdio.mjs",
            "artifactPath": str(MCP_PROBE_PATH),
            "exitCode": maws_mcp_probe.returncode,
            "available": maws_mcp_available,
            "blockerType": maws_mcp_probe_artifact.get("blockerType") if isinstance(maws_mcp_probe_artifact, dict) else None,
            "errorCode": maws_mcp_error_code,
            "stdout": maws_mcp_probe.stdout.strip()[:4000],
            "stderr": maws_mcp_probe.stderr.strip()[:4000],
        },
        "blockerEvidence": {
            "exitCondition": EXIT_CONDITION,
            "blockerType": blocker_type,
            "causes": blocker_causes,
            "operation": "M-AWS transfer.send live readiness",
            "message": (
                "M-AWS auth material is unavailable; DailyMart must not present deterministic fallback "
                "as a confirmed maroo OKRW transfer."
                if blocker_type == "maws_auth_unavailable"
                else "M-AWS MCP server is unavailable; DailyMart must not present deterministic fallback "
                "as a confirmed maroo OKRW transfer."
                if not maws_mcp_available
                else "M-AWS bridge/agent environment is incomplete; DailyMart must not present "
                "deterministic fallback as a confirmed maroo OKRW transfer."
                if missing
                else "M-AWS CLI status failed; live maroo OKRW transfer confirmation is unavailable."
            ),
        },
    }
    ARTIFACT_PATH.write_text(json.dumps(artifact, indent=2, sort_keys=True) + "\n")
    print(f"M-AWS live readiness artifact written: {ARTIFACT_PATH}")
    if not artifact["ready"]:
        raise SystemExit(2)


if __name__ == "__main__":
    main()
