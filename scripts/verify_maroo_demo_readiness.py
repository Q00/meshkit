#!/usr/bin/env python3
import json
import os
import subprocess
from datetime import datetime, timezone
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
ARTIFACT_DIR = ROOT / "artifacts" / "maroo-testnet"
ARTIFACT_PATH = ARTIFACT_DIR / "demo-readiness.json"


def run_command(name, command, cwd=ROOT, timeout=120, env=None):
    started_at = datetime.now(timezone.utc).isoformat()
    try:
        result = subprocess.run(
            command,
            cwd=cwd,
            text=True,
            capture_output=True,
            timeout=timeout,
            env=env,
        )
        return {
            "name": name,
            "command": command,
            "cwd": str(cwd),
            "startedAt": started_at,
            "finishedAt": datetime.now(timezone.utc).isoformat(),
            "exitCode": result.returncode,
            "passed": result.returncode == 0,
            "stdout": result.stdout.strip()[-4000:],
            "stderr": result.stderr.strip()[-4000:],
        }
    except subprocess.TimeoutExpired as error:
        return {
            "name": name,
            "command": command,
            "cwd": str(cwd),
            "startedAt": started_at,
            "finishedAt": datetime.now(timezone.utc).isoformat(),
            "exitCode": 124,
            "passed": False,
            "stdout": ((error.stdout or "") if isinstance(error.stdout, str) else "").strip()[-4000:],
            "stderr": f"timeout after {timeout}s",
        }


def load_json(path):
    if not path.exists():
        return None
    try:
        return json.loads(path.read_text())
    except json.JSONDecodeError as error:
        return {"parseError": str(error)}


def proof_confirmed(path, verification_path=None):
    payload = load_json(path)
    data = payload.get("response", {}).get("data", {}) if isinstance(payload, dict) else {}
    field_confirmed = bool(
        isinstance(payload, dict)
        and payload.get("confirmed") is True
        and data.get("status") == "confirmed"
        and data.get("txHash")
        and data.get("blockHash")
        and data.get("blockNumber")
        and data.get("confirmationCount")
        and data.get("confirmedAt")
        and data.get("explorerUrl")
    )
    if not verification_path:
        return field_confirmed
    verification = load_json(verification_path)
    return field_confirmed and isinstance(verification, dict) and verification.get("verified") is True


def proof_status(path, verification_path=None):
    payload = load_json(path)
    data = payload.get("response", {}).get("data", {}) if isinstance(payload, dict) else {}
    verification = load_json(verification_path) if verification_path else None
    return {
        "path": str(path),
        "exists": path.exists(),
        "confirmed": proof_confirmed(path, verification_path),
        "status": data.get("status") if isinstance(data, dict) else None,
        "txHashPresent": bool(data.get("txHash")) if isinstance(data, dict) else False,
        "blockHashPresent": bool(data.get("blockHash")) if isinstance(data, dict) else False,
        "explorerUrlPresent": bool(data.get("explorerUrl")) if isinstance(data, dict) else False,
        "verificationPath": str(verification_path) if verification_path else None,
        "verifiedOnChain": verification.get("verified") if isinstance(verification, dict) else None,
    }


def live_readiness_summary(
    maws_readiness,
    native_readiness,
    faucet_readiness,
    maws_mcp_probe,
    maws_proof_path,
    native_proof_path,
    native_proof_verification_path,
):
    maws_status = maws_readiness.get("mawsStatus", {}) if isinstance(maws_readiness, dict) else {}
    maws_probe = maws_readiness.get("mawsMCPProbe", {}) if isinstance(maws_readiness, dict) else {}
    return {
        "faucet": {
            "pageAvailable": faucet_readiness.get("pageAvailable") if isinstance(faucet_readiness, dict) else None,
            "manualFundingRequired": faucet_readiness.get("manualFundingRequired") if isinstance(faucet_readiness, dict) else None,
            "automationSupported": faucet_readiness.get("automationSupported") if isinstance(faucet_readiness, dict) else None,
            "fundingTargets": faucet_readiness.get("fundingTargets", {}) if isinstance(faucet_readiness, dict) else {},
            "manualFundingEvidenceRequired": faucet_readiness.get("manualFundingEvidenceRequired", [])
            if isinstance(faucet_readiness, dict)
            else [],
        },
        "maws": {
            "ready": maws_readiness.get("ready") if isinstance(maws_readiness, dict) else None,
            "checkedAt": maws_readiness.get("checkedAt") if isinstance(maws_readiness, dict) else None,
            "exitCondition": maws_readiness.get("exitCondition") if isinstance(maws_readiness, dict) else None,
            "missingEnvironment": maws_readiness.get("missingEnvironment", []) if isinstance(maws_readiness, dict) else [],
            "missingAuth": maws_readiness.get("missingAuth", []) if isinstance(maws_readiness, dict) else [],
            "missingConfig": maws_readiness.get("missingConfig", []) if isinstance(maws_readiness, dict) else [],
            "fundingTarget": maws_readiness.get("fundingTarget", {}) if isinstance(maws_readiness, dict) else {},
            "blockerCauses": maws_readiness.get("blockerEvidence", {}).get("causes", [])
            if isinstance(maws_readiness, dict)
            else [],
            "cliStatus": {
                "exitCode": maws_status.get("exitCode"),
                "authenticated": maws_status.get("authenticated"),
                "stderr": maws_status.get("stderr"),
            },
            "mcpProbe": {
                "exitCode": maws_probe.get("exitCode"),
                "available": maws_probe.get("available"),
                "errorCode": maws_mcp_probe.get("error", {}).get("code") if isinstance(maws_mcp_probe, dict) else None,
                "blockerType": maws_mcp_probe.get("blockerType") if isinstance(maws_mcp_probe, dict) else None,
            },
        },
        "directMaroo": {
            "ready": native_readiness.get("ready") if isinstance(native_readiness, dict) else None,
            "checkedAt": native_readiness.get("checkedAt") if isinstance(native_readiness, dict) else None,
            "exitCondition": native_readiness.get("exitCondition") if isinstance(native_readiness, dict) else None,
            "missingEnvironment": native_readiness.get("missingEnvironment", []) if isinstance(native_readiness, dict) else [],
            "fundingCheck": native_readiness.get("fundingCheck", {}) if isinstance(native_readiness, dict) else {},
            "blockerType": (native_readiness.get("blockerEvidence") or {}).get("blockerType")
            if isinstance(native_readiness, dict)
            else None,
            "bridgeHealthUrl": (native_readiness.get("bridgeHealth") or {}).get("url")
            if isinstance(native_readiness, dict)
            else None,
        },
        "confirmedProofs": {
            "maws": proof_status(maws_proof_path),
            "directMaroo": proof_status(native_proof_path, native_proof_verification_path),
        },
    }


def command_status(name, passed, evidence, **extra):
    status = {
        "name": name,
        "passed": bool(passed),
        "evidence": evidence,
    }
    status.update(extra)
    return status


def main():
    ARTIFACT_DIR.mkdir(parents=True, exist_ok=True)
    maroo_status_path = ARTIFACT_DIR / "status.json"
    maws_readiness_path = ARTIFACT_DIR / "maws-live-readiness.json"
    maws_mcp_probe_path = ARTIFACT_DIR / "maws-mcp-stdio-probe.json"
    native_readiness_path = ARTIFACT_DIR / "maroo-native-okrw-readiness.json"
    faucet_readiness_path = ARTIFACT_DIR / "faucet-readiness.json"
    wallet_setup_path = ARTIFACT_DIR / "demo-wallet-setup.json"
    maws_proof_path = ARTIFACT_DIR / "maws-live-transfer-proof.json"
    native_proof_path = ARTIFACT_DIR / "maroo-native-okrw-transfer-proof.json"
    native_proof_verification_path = ARTIFACT_DIR / "maroo-native-okrw-proof-verification.json"
    simulator_destination = os.environ.get(
        "MESHKIT_IOS_SIMULATOR_DESTINATION",
        "platform=iOS Simulator,name=iPad Pro 11-inch (M4),OS=18.6",
    )

    deterministic_runs = [
        run_command("maroo public endpoint status", ["python3", "scripts/verify_maroo_testnet_status.py"], timeout=30),
        run_command("maroo faucet readiness", ["python3", "scripts/verify_maroo_faucet_readiness.py"], timeout=30),
        run_command("maroo demo wallet setup", ["node", "scripts/verify_maroo_demo_wallet_setup.mjs"], timeout=30),
        run_command(
            "maroo operator status",
            ["node", "scripts/maroo_demo_operator_status.mjs"],
            timeout=30,
        ),
        run_command("M-AWS bridge contract", ["node", "scripts/verify_maws_transfer_bridge_contract.mjs"], timeout=30),
        run_command(
            "direct maroo bridge contract",
            ["node", "scripts/verify_maroo_native_okrw_transfer_bridge_contract.mjs"],
            timeout=30,
        ),
        run_command("mobile docs/runtime verifier", ["python3", "scripts/verify_mobile_e2e_runtime_docs.py"], timeout=30),
        run_command("physical iPad install script syntax", ["bash", "-n", "scripts/install_ios_device.sh"], timeout=30),
        run_command(
            "physical iPad maroo launch env verifier",
            ["bash", "scripts/verify_ios_device_maroo_launch_env.sh"],
            timeout=45,
        ),
        run_command("Swift tests", ["swift", "test"], cwd=ROOT / "meshkit-ios", timeout=120),
        run_command(
            "DailyMart iPad simulator build",
            [
                "xcodebuild",
                "-project",
                "meshkit-ios/Samples/iOSDemo/MeshKitiOSDemo.xcodeproj",
                "-scheme",
                "DailyMart",
                "-destination",
                simulator_destination,
                "build",
            ],
            timeout=180,
        ),
        run_command(
            "DailyMart pending proof UI test",
            [
                "xcodebuild",
                "test",
                "-project",
                "meshkit-ios/Samples/iOSDemo/MeshKitiOSDemo.xcodeproj",
                "-scheme",
                "MeshKitiOSDemoUITests",
                "-destination",
                simulator_destination,
                "-only-testing:MeshKitiOSDemoUITests/MeshKitiOSDemoUITests/testDailyMartPendingReceiptRendersProviderNeutralChainProofFields",
            ],
            timeout=180,
        ),
    ]
    run_by_name = {item["name"]: item for item in deterministic_runs}

    live_readiness_runs = [
        run_command("M-AWS live readiness", ["python3", "scripts/verify_maws_live_readiness.py"], timeout=45),
        run_command(
            "direct maroo bridge readiness",
            ["python3", "scripts/verify_maroo_native_okrw_readiness.py"],
            timeout=15,
        ),
    ]

    if os.environ.get("MESHKIT_MAWS_BRIDGE_URL") and os.environ.get("MESHKIT_MAWS_AGENT_ID") and os.environ.get("MESHKIT_MAWS_PROBE_RECIPIENT"):
        live_readiness_runs.append(
            run_command("M-AWS confirmed transfer proof probe", ["node", "scripts/probe_maws_live_transfer.mjs"], timeout=90)
        )
    if os.environ.get("MESHKIT_MAROO_OKRW_TRANSFER_BRIDGE_URL") and os.environ.get("MESHKIT_MAROO_OKRW_PROBE_RECIPIENT"):
        live_readiness_runs.append(
            run_command(
                "direct maroo confirmed transfer proof probe",
                ["node", "scripts/probe_maroo_native_okrw_transfer.mjs"],
                timeout=90,
            )
        )
    if native_proof_path.exists():
        live_readiness_runs.append(
            run_command(
                "direct maroo proof verification",
                ["node", "scripts/verify_maroo_native_okrw_proof.mjs"],
                timeout=30,
            )
        )

    maroo_status = load_json(maroo_status_path)
    faucet_readiness = load_json(faucet_readiness_path)
    wallet_setup = load_json(wallet_setup_path)
    maws_readiness = load_json(maws_readiness_path)
    maws_mcp_probe = load_json(maws_mcp_probe_path)
    native_readiness = load_json(native_readiness_path)

    deterministic_checks = [
        command_status(
            "maroo public endpoint status",
            isinstance(maroo_status, dict)
            and isinstance(maroo_status.get("eth_blockNumber"), dict)
            and maroo_status["eth_blockNumber"].get("httpStatus") == 200
            and isinstance(maroo_status.get("net_version"), dict)
            and maroo_status["net_version"].get("value") == "450815"
            and isinstance(maroo_status.get("explorer"), dict)
            and maroo_status["explorer"].get("httpStatus") == 200,
            str(maroo_status_path),
            run=run_by_name["maroo public endpoint status"],
        ),
        command_status(
            "maroo faucet readiness",
            isinstance(faucet_readiness, dict)
            and faucet_readiness.get("pageAvailable") is True
            and faucet_readiness.get("manualFundingRequired") is True
            and faucet_readiness.get("automationSupported") is False,
            str(faucet_readiness_path),
            run=run_by_name["maroo faucet readiness"],
        ),
        command_status(
            "maroo demo wallet setup",
            isinstance(wallet_setup, dict)
            and wallet_setup.get("readyForFaucet") is True
            and wallet_setup.get("readyForDirectBridge") is True,
            str(wallet_setup_path),
            run=run_by_name["maroo demo wallet setup"],
        ),
        command_status(
            "maroo operator status",
            run_by_name["maroo operator status"]["exitCode"] in (0, 2),
            "node scripts/maroo_demo_operator_status.mjs",
            run=run_by_name["maroo operator status"],
        ),
        command_status(
            "M-AWS bridge contract",
            run_by_name["M-AWS bridge contract"]["passed"],
            "node scripts/verify_maws_transfer_bridge_contract.mjs",
            run=run_by_name["M-AWS bridge contract"],
        ),
        command_status(
            "direct maroo bridge contract",
            run_by_name["direct maroo bridge contract"]["passed"],
            "node scripts/verify_maroo_native_okrw_transfer_bridge_contract.mjs",
            run=run_by_name["direct maroo bridge contract"],
        ),
        command_status(
            "mobile docs/runtime verifier",
            run_by_name["mobile docs/runtime verifier"]["passed"],
            "python3 scripts/verify_mobile_e2e_runtime_docs.py",
            run=run_by_name["mobile docs/runtime verifier"],
        ),
        command_status(
            "physical iPad install script syntax",
            run_by_name["physical iPad install script syntax"]["passed"],
            "bash -n scripts/install_ios_device.sh",
            run=run_by_name["physical iPad install script syntax"],
        ),
        command_status(
            "physical iPad maroo launch env verifier",
            run_by_name["physical iPad maroo launch env verifier"]["passed"],
            "bash scripts/verify_ios_device_maroo_launch_env.sh",
            run=run_by_name["physical iPad maroo launch env verifier"],
        ),
        command_status(
            "Swift tests",
            run_by_name["Swift tests"]["passed"],
            "cd meshkit-ios && swift test",
            run=run_by_name["Swift tests"],
        ),
        command_status(
            "DailyMart iPad simulator build",
            run_by_name["DailyMart iPad simulator build"]["passed"],
            "xcodebuild DailyMart iPad simulator build",
            run=run_by_name["DailyMart iPad simulator build"],
        ),
        command_status(
            "DailyMart pending proof UI test",
            run_by_name["DailyMart pending proof UI test"]["passed"],
            "xcodebuild DailyMart pending proof UI test",
            run=run_by_name["DailyMart pending proof UI test"],
        ),
    ]

    live_checks = [
        command_status(
            "M-AWS MCP server available",
            isinstance(maws_mcp_probe, dict) and maws_mcp_probe.get("ok") is True,
            str(maws_mcp_probe_path),
        ),
        command_status(
            "M-AWS live readiness",
            isinstance(maws_readiness, dict) and maws_readiness.get("ready") is True,
            str(maws_readiness_path),
        ),
        command_status(
            "direct maroo bridge readiness",
            isinstance(native_readiness, dict) and native_readiness.get("ready") is True,
            str(native_readiness_path),
        ),
        command_status(
            "M-AWS confirmed transfer proof",
            proof_confirmed(maws_proof_path),
            str(maws_proof_path),
        ),
        command_status(
            "direct maroo confirmed transfer proof",
            proof_confirmed(native_proof_path, native_proof_verification_path),
            str(native_proof_path),
        ),
    ]

    deterministic_ready = all(item["passed"] for item in deterministic_checks)
    live_confirmed = any(item["name"].endswith("confirmed transfer proof") and item["passed"] for item in live_checks)
    blocker_details = live_readiness_summary(
        maws_readiness,
        native_readiness,
        faucet_readiness,
        maws_mcp_probe,
        maws_proof_path,
        native_proof_path,
        native_proof_verification_path,
    )
    artifact = {
        "checkedAt": datetime.now(timezone.utc).isoformat(),
        "provider": "maroo",
        "network": "maroo-testnet",
        "deterministicReady": deterministic_ready,
        "liveConfirmed": live_confirmed,
        "demoStatus": "ready_for_confirmed_payment_demo" if live_confirmed else "ready_for_dry_run_pending_demo",
        "exitCondition": None if live_confirmed else "BlockedByExternalChain",
        "deterministicChecks": deterministic_checks,
        "liveChecks": live_checks,
        "liveReadinessRuns": live_readiness_runs,
        "blockerEvidence": None
        if live_confirmed
        else {
            "exitCondition": "BlockedByExternalChain",
            "blockerType": "payment_confirmation_unavailable",
            "operation": "DailyMart maroo OKRW confirmed demo readiness",
            "message": (
                "Deterministic integration checks pass, but no M-AWS or direct maroo confirmed "
                "OKRW transfer proof artifact is available."
            ),
            "details": blocker_details,
        },
    }
    ARTIFACT_PATH.write_text(json.dumps(artifact, indent=2, sort_keys=True) + "\n")
    print(f"maroo demo readiness artifact written: {ARTIFACT_PATH}")
    if not live_confirmed:
        raise SystemExit(2)


if __name__ == "__main__":
    main()
