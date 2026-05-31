#!/usr/bin/env node
import { mkdir, readFile, writeFile } from "node:fs/promises";
import { existsSync, readFileSync } from "node:fs";
import { dirname, resolve } from "node:path";

const artifactPath = resolve(
  process.env.MESHKIT_MAROO_OPERATOR_STATUS_ARTIFACT ||
    "artifacts/maroo-testnet/demo-operator-status.json",
);
const markdownPath = resolve(
  process.env.MESHKIT_MAROO_OPERATOR_STATUS_MARKDOWN ||
    "artifacts/maroo-testnet/demo-operator-status.md",
);
const envPath = resolve(process.env.MESHKIT_MAROO_DEMO_WALLET_ENV || ".env.maroo-demo.local");
const env = existsSync(envPath) ? parseEnv(readFileSync(envPath, "utf8")) : {};
const walletSetup = readJSON("artifacts/maroo-testnet/demo-wallet-setup.json");
const readiness = readJSON("artifacts/maroo-testnet/demo-readiness.json");
const nativeReadiness = readJSON("artifacts/maroo-testnet/maroo-native-okrw-readiness.json");
const proof = readJSON("artifacts/maroo-testnet/maroo-native-okrw-transfer-proof.json");
const proofVerification = readJSON("artifacts/maroo-testnet/maroo-native-okrw-proof-verification.json");

const signerAddress =
  walletSetup?.derivedAddress ||
  nativeReadiness?.fundingCheck?.signerAddress ||
  env.MESHKIT_MAROO_WALLET_ADDRESS ||
  env.MESHKIT_MAROO_FAUCET_WALLET_ADDRESS ||
  null;
const rpcURL = env.MESHKIT_MAROO_RPC_URL || "https://rpc-testnet.maroo.io";
const balance = signerAddress ? await rpcBalance(rpcURL, signerAddress) : null;
const deterministicFailures = (readiness?.deterministicChecks || [])
  .filter((check) => !check.passed)
  .map((check) => check.name);
const directProof = readiness?.blockerEvidence?.details?.confirmedProofs?.directMaroo || {};
const directMaroo = readiness?.blockerEvidence?.details?.directMaroo || {};
const liveConfirmed = readiness?.liveConfirmed === true;

const status = {
  checkedAt: new Date().toISOString(),
  provider: "maroo",
  network: "maroo-testnet",
  envPath,
  faucetUrl: "https://faucet.maroo.io/",
  signerAddress,
  balance,
  walletSetup: {
    readyForFaucet: walletSetup?.readyForFaucet === true,
    readyForDirectBridge: walletSetup?.readyForDirectBridge === true,
    bridgeAuthorizationConfigured: walletSetup?.bridgeAuthorizationConfigured === true,
    allowedRecipientsConfigured: walletSetup?.allowedRecipientsConfigured === true,
    probeRecipientAllowed: walletSetup?.probeRecipientAllowed === true,
    maxAmountOKRW: walletSetup?.maxAmountOKRW || null,
    secretPrinted: walletSetup?.secretPrinted === true,
  },
  readiness: {
    deterministicReady: readiness?.deterministicReady === true,
    liveConfirmed,
    demoStatus: readiness?.demoStatus || null,
    deterministicFailures,
    blockerType: directMaroo?.blockerType || readiness?.blockerEvidence?.blockerType || null,
  },
  directMaroo: {
    ready: nativeReadiness?.ready === true,
    bridgeHealthUrl: directMaroo?.bridgeHealthUrl || nativeReadiness?.bridgeHealth?.url || null,
    requiredProbeAmountOKRW:
      nativeReadiness?.fundingCheck?.requiredProbeAmountOKRW ||
      env.MESHKIT_MAROO_OKRW_PROBE_AMOUNT ||
      "1",
    proofExists: directProof?.exists === true || Boolean(proof),
    proofConfirmed: directProof?.confirmed === true || proof?.confirmed === true,
    verifiedOnChain: directProof?.verifiedOnChain === true || proofVerification?.verified === true,
    txHash: proof?.response?.data?.txHash || null,
    explorerUrl: proof?.response?.data?.explorerUrl || null,
  },
  nextAction: nextAction({
    liveConfirmed,
    deterministicFailures,
    walletSetup,
    balance,
    nativeReadiness,
    proofVerification,
  }),
  commands: {
    addBridgeAuthorization: "node scripts/ensure_maroo_bridge_authorization.mjs",
    addBridgePolicy: "node scripts/ensure_maroo_bridge_policy.mjs",
    waitForFundingAndProof: "node scripts/run_maroo_native_okrw_live_proof.mjs --wait-for-funding",
    installPhysicalIPad: "MESHKIT_IOS_BRIDGE_HOST=<mac-lan-ip> scripts/install_ios_device.sh",
    aggregateReadiness: "python3 scripts/verify_maroo_demo_readiness.py",
  },
  secretFieldsPrinted: false,
};

await mkdir(dirname(artifactPath), { recursive: true });
await writeFile(artifactPath, JSON.stringify(status, null, 2) + "\n");
await writeFile(markdownPath, markdown(status));
console.log(`maroo demo operator status written: ${artifactPath}`);
console.log(`maroo demo operator status markdown written: ${markdownPath}`);
if (!liveConfirmed) {
  process.exit(2);
}

function nextAction(input) {
  if (input.liveConfirmed) return "Live maroo OKRW proof is confirmed and verified.";
  if (input.deterministicFailures.length > 0) {
    return `Fix deterministic checks: ${input.deterministicFailures.join(", ")}`;
  }
  if (input.walletSetup?.bridgeAuthorizationConfigured !== true) {
    return "Run node scripts/ensure_maroo_bridge_authorization.mjs.";
  }
  if (input.walletSetup?.allowedRecipientsConfigured !== true || input.walletSetup?.probeRecipientAllowed !== true) {
    return "Run node scripts/ensure_maroo_bridge_policy.mjs.";
  }
  const balanceOKRW = Number(input.balance?.balanceOKRW || 0);
  const required = Number(input.nativeReadiness?.fundingCheck?.requiredProbeAmountOKRW || 1);
  if (!Number.isFinite(balanceOKRW) || balanceOKRW < required) {
    return `Fund ${signerAddress} at https://faucet.maroo.io/, then run node scripts/run_maroo_native_okrw_live_proof.mjs --wait-for-funding.`;
  }
  if (input.proofVerification?.verified !== true) {
    return "Run node scripts/run_maroo_native_okrw_live_proof.mjs --wait-for-funding to capture txHash, RPC receipt, and explorer proof.";
  }
  return "Run python3 scripts/verify_maroo_demo_readiness.py.";
}

function markdown(status) {
  return [
    "# Maroo Demo Operator Status",
    "",
    `Checked: ${status.checkedAt}`,
    `Signer: ${status.signerAddress || "unknown"}`,
    `Balance: ${status.balance?.balanceOKRW ?? "unknown"} OKRW`,
    `Deterministic ready: ${status.readiness.deterministicReady}`,
    `Live confirmed: ${status.readiness.liveConfirmed}`,
    `Blocker: ${status.readiness.blockerType || "none"}`,
    `Bridge auth configured: ${status.walletSetup.bridgeAuthorizationConfigured}`,
    `Bridge policy configured: ${status.walletSetup.allowedRecipientsConfigured}`,
    `Proof verified on chain: ${status.directMaroo.verifiedOnChain}`,
    "",
    `Next: ${status.nextAction}`,
    "",
    "Commands:",
    `- ${status.commands.waitForFundingAndProof}`,
    `- ${status.commands.installPhysicalIPad}`,
    `- ${status.commands.aggregateReadiness}`,
    "",
  ].join("\n");
}

async function rpcBalance(rpcURL, address) {
  try {
    const response = await fetch(rpcURL, {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify({
        jsonrpc: "2.0",
        id: 1,
        method: "eth_getBalance",
        params: [address, "latest"],
      }),
    });
    const payload = await response.json();
    const wei = typeof payload.result === "string" ? BigInt(payload.result) : null;
    return {
      rpcURL,
      address,
      balanceWei: wei === null ? null : wei.toString(),
      balanceOKRW: wei === null ? null : formatEther(wei),
      httpStatus: response.status,
    };
  } catch (error) {
    return {
      rpcURL,
      address,
      error: error?.message || String(error),
    };
  }
}

function formatEther(wei) {
  const raw = wei.toString().padStart(19, "0");
  const whole = raw.slice(0, -18);
  const fraction = raw.slice(-18).replace(/0+$/, "");
  return fraction ? `${whole}.${fraction}` : whole;
}

function readJSON(path) {
  const resolved = resolve(path);
  if (!existsSync(resolved)) return null;
  try {
    return JSON.parse(readFileSync(resolved, "utf8"));
  } catch {
    return null;
  }
}

function parseEnv(contents) {
  const parsed = {};
  for (const line of contents.split(/\r?\n/)) {
    const trimmed = line.trim();
    if (!trimmed || trimmed.startsWith("#") || !trimmed.includes("=")) continue;
    const index = trimmed.indexOf("=");
    parsed[trimmed.slice(0, index)] = trimmed.slice(index + 1);
  }
  return parsed;
}
