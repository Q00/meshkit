#!/usr/bin/env node
import { spawn, spawnSync } from "node:child_process";
import { existsSync, readFileSync } from "node:fs";
import { resolve } from "node:path";

const envPath = resolve(process.env.DEMO_WALLET_ENV_PATH || ".env.maroo-demo.local");
const env = {
  ...parseEnvFile(envPath),
  ...process.env,
};
const bridgeURL = requiredEnv("MESHKIT_MAROO_OKRW_TRANSFER_BRIDGE_URL");
const healthURL = healthURLForBridge(bridgeURL);
if (process.env.MESHKIT_IOS_BRIDGE_HOST && !process.env.MESHKIT_MAROO_OKRW_TRANSFER_BRIDGE_HOST) {
  env.MESHKIT_MAROO_OKRW_TRANSFER_BRIDGE_HOST = "0.0.0.0";
}
const waitForFunding = process.argv.includes("--wait-for-funding");
const waitSeconds = Number(process.env.MESHKIT_MAROO_WAIT_FOR_FUNDING_SECONDS || 300);
const pollSeconds = Number(process.env.MESHKIT_MAROO_WAIT_FOR_FUNDING_POLL_SECONDS || 5);
let bridge = null;

try {
  if (!(await bridgeHealthy(healthURL))) {
    bridge = spawn("node", ["scripts/maroo_native_okrw_transfer_bridge.mjs"], {
      cwd: new URL("..", import.meta.url),
      env,
      stdio: ["ignore", "ignore", "pipe"],
    });
    bridge.stderr.on("data", (chunk) => {
      process.stderr.write(chunk);
    });
    await waitForBridge(healthURL);
  }

  const readiness = waitForFunding ? await waitUntilFunded() : runReadiness();
  const funding = readiness.fundingCheck || {};
  if (readiness?.ready !== true) {
    printNotReady(readiness);
    process.exit(2);
  }

  runStep("direct maroo confirmed transfer proof", ["node", "scripts/probe_maroo_native_okrw_transfer.mjs"]);
  runStep("direct maroo proof verification", ["node", "scripts/verify_maroo_native_okrw_proof.mjs"]);
  runStep("aggregate maroo demo readiness", ["python3", "scripts/verify_maroo_demo_readiness.py"]);

  const proof = readJSON("artifacts/maroo-testnet/maroo-native-okrw-transfer-proof.json");
  const data = proof?.response?.data || {};
  console.log(
    [
      "maroo native OKRW live proof confirmed",
      `txHash=${data.txHash}`,
      `blockNumber=${data.blockNumber}`,
      `explorerUrl=${data.explorerUrl}`,
    ].join("\n"),
  );
} finally {
  if (bridge) {
    bridge.kill("SIGTERM");
  }
}

function runStep(label, command, options = {}) {
  console.error(`\n== ${label} ==`);
  const result = spawnSync(command[0], command.slice(1), {
    cwd: new URL("..", import.meta.url),
    env,
    encoding: "utf8",
  });
  if (result.stdout) process.stdout.write(result.stdout);
  if (result.stderr) process.stderr.write(result.stderr);
  if (result.status !== 0 && !options.allowFailure) {
    process.exit(result.status || 1);
  }
}

function runReadiness() {
  runStep("direct maroo readiness", ["python3", "scripts/verify_maroo_native_okrw_readiness.py"], {
    allowFailure: true,
  });
  return readJSON("artifacts/maroo-testnet/maroo-native-okrw-readiness.json");
}

async function waitUntilFunded() {
  const deadline = Date.now() + waitSeconds * 1000;
  let latest = runReadiness();
  while (latest?.ready !== true && Date.now() < deadline) {
    const funding = latest?.fundingCheck || {};
    console.error(
      [
        "waiting for maroo faucet funding...",
        `signerAddress=${funding.signerAddress || "unknown"}`,
        `signerBalanceOKRW=${funding.signerBalanceOKRW || "unknown"}`,
        `requiredProbeAmountOKRW=${funding.requiredProbeAmountOKRW || env.MESHKIT_MAROO_OKRW_PROBE_AMOUNT || "1"}`,
        `pollSeconds=${pollSeconds}`,
      ].join("\n"),
    );
    await new Promise((resolve) => setTimeout(resolve, pollSeconds * 1000));
    latest = runReadiness();
  }
  return latest;
}

function printNotReady(readiness) {
  const funding = readiness?.fundingCheck || {};
  console.error(
    [
      "maroo native OKRW live proof is not ready.",
      `signerAddress=${funding.signerAddress || "unknown"}`,
      `signerBalanceOKRW=${funding.signerBalanceOKRW || "unknown"}`,
      `requiredProbeAmountOKRW=${funding.requiredProbeAmountOKRW || env.MESHKIT_MAROO_OKRW_PROBE_AMOUNT || "1"}`,
      `blockerType=${readiness?.blockerEvidence?.blockerType || "unknown"}`,
      waitForFunding ? `waitedSeconds=${waitSeconds}` : "hint=rerun with --wait-for-funding while using the faucet",
    ].join("\n"),
  );
}

async function bridgeHealthy(url) {
  try {
    const response = await fetch(url);
    const body = await response.json();
    return response.ok && body?.ok === true;
  } catch {
    return false;
  }
}

async function waitForBridge(url) {
  const started = Date.now();
  while (Date.now() - started < 20_000) {
    if (await bridgeHealthy(url)) return;
    await new Promise((resolve) => setTimeout(resolve, 250));
  }
  throw new Error(`maroo native OKRW bridge did not become healthy at ${url}`);
}

function healthURLForBridge(url) {
  const parsed = new URL(url);
  parsed.pathname = "/health";
  parsed.search = "";
  parsed.hash = "";
  return parsed.toString();
}

function readJSON(path) {
  return JSON.parse(readFileSync(resolve(path), "utf8"));
}

function parseEnvFile(path) {
  if (!existsSync(path)) return {};
  const parsed = {};
  for (const line of readFileSync(path, "utf8").split(/\r?\n/)) {
    const trimmed = line.trim();
    if (!trimmed || trimmed.startsWith("#")) continue;
    const index = trimmed.indexOf("=");
    if (index < 0) continue;
    parsed[trimmed.slice(0, index)] = trimmed.slice(index + 1);
  }
  return parsed;
}

function requiredEnv(name) {
  const value = env[name]?.trim();
  if (!value) {
    console.error(`${name} is required; run scripts/create_maroo_demo_wallet.mjs or configure ${envPath}.`);
    process.exit(2);
  }
  return value;
}
