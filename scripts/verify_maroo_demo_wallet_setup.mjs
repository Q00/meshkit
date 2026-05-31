#!/usr/bin/env node
import { execFileSync } from "node:child_process";
import { existsSync, readFileSync } from "node:fs";
import { mkdir, writeFile } from "node:fs/promises";
import { dirname, resolve } from "node:path";

const envPath = resolve(process.env.MESHKIT_MAROO_DEMO_WALLET_ENV || ".env.maroo-demo.local");
const artifactPath = resolve(
  process.env.MESHKIT_MAROO_DEMO_WALLET_SETUP_ARTIFACT ||
    "artifacts/maroo-testnet/demo-wallet-setup.json",
);
const toolPrefix = resolve(process.env.MESHKIT_MAROO_DEMO_WALLET_TOOL_PREFIX || ".build/maroo-demo-wallet-tool");

const fileEnv = existsSync(envPath) ? parseEnvFile(readFileSync(envPath, "utf8")) : {};
const merged = { ...fileEnv, ...process.env };
const privateKey = merged.MESHKIT_MAROO_PRIVATE_KEY || "";
const expectedAddress = merged.MESHKIT_MAROO_WALLET_ADDRESS || merged.MESHKIT_MAROO_FAUCET_WALLET_ADDRESS || "";
const faucetAddress = merged.MESHKIT_MAROO_FAUCET_WALLET_ADDRESS || "";
const bridgeURL = merged.MESHKIT_MAROO_OKRW_TRANSFER_BRIDGE_URL || "";
const bridgeAuthorization = merged.MESHKIT_MAROO_OKRW_TRANSFER_AUTHORIZATION || "";
const allowedRecipients = merged.MESHKIT_MAROO_OKRW_ALLOWED_RECIPIENTS || "";
const maxAmount = merged.MESHKIT_MAROO_OKRW_TRANSFER_MAX_AMOUNT || "";
const probeRecipient = merged.MESHKIT_MAROO_OKRW_PROBE_RECIPIENT || "";

await mkdir(toolPrefix, { recursive: true });
execFileSync("npm", ["install", "--prefix", toolPrefix, "--no-save", "--silent", "ethers@6"], {
  stdio: "ignore",
});

let derivedAddress = null;
let privateKeyValid = false;
let privateKeyError = null;
if (privateKey) {
  try {
    derivedAddress = execFileSync(
      "node",
      ["-e", "const { Wallet } = require('ethers'); console.log(new Wallet(process.env.PRIVATE_KEY).address);"],
      {
        env: {
          ...process.env,
          NODE_PATH: `${toolPrefix}/node_modules`,
          PRIVATE_KEY: privateKey,
        },
        encoding: "utf8",
      },
    ).trim();
    privateKeyValid = /^0x[a-fA-F0-9]{40}$/.test(derivedAddress);
  } catch (error) {
    privateKeyError = error?.message || String(error);
  }
}

const addressMatches = Boolean(
  privateKeyValid &&
    expectedAddress &&
    derivedAddress &&
    expectedAddress.toLowerCase() === derivedAddress.toLowerCase(),
);
const faucetMatches = Boolean(
  privateKeyValid &&
    faucetAddress &&
    derivedAddress &&
    faucetAddress.toLowerCase() === derivedAddress.toLowerCase(),
);
const bridgeConfigured = Boolean(bridgeURL);
const probeRecipientValid = /^0x[a-fA-F0-9]{40}$/.test(probeRecipient);
const allowedRecipientList = allowedRecipients
  .split(",")
  .map((item) => item.trim().toLowerCase())
  .filter(Boolean);
const probeRecipientAllowed = allowedRecipientList.length === 0 || allowedRecipientList.includes(probeRecipient.toLowerCase());
const maxAmountConfigured = Boolean(maxAmount);
const probeAmount = merged.MESHKIT_MAROO_OKRW_PROBE_AMOUNT || "";
const maxAmountCoversProbe = !maxAmountConfigured || !probeAmount || Number(probeAmount) <= Number(maxAmount);
const readyForFaucet = Boolean(addressMatches && faucetMatches);
const readyForDirectBridge = Boolean(
  readyForFaucet &&
    bridgeConfigured &&
    probeRecipientValid &&
    probeRecipientAllowed &&
    maxAmountCoversProbe,
);

const artifact = {
  checkedAt: new Date().toISOString(),
  provider: "maroo",
  network: "maroo-testnet",
  envPath,
  privateKeyPresent: Boolean(privateKey),
  privateKeyValid,
  privateKeyError,
  derivedAddress,
  configuredWalletAddress: expectedAddress || null,
  configuredFaucetWalletAddress: faucetAddress || null,
  walletAddressMatchesPrivateKey: addressMatches,
  faucetWalletMatchesPrivateKey: faucetMatches,
  bridgeURL: bridgeURL || null,
  bridgeConfigured,
  bridgeAuthorizationConfigured: Boolean(bridgeAuthorization),
  allowedRecipientsConfigured: allowedRecipientList.length > 0,
  allowedRecipients: allowedRecipientList,
  probeRecipientAllowed,
  maxAmountOKRW: maxAmount || null,
  maxAmountCoversProbe,
  probeRecipient: probeRecipient || null,
  probeRecipientValid,
  readyForFaucet,
  readyForDirectBridge,
  secretPrinted: false,
  safetyWarnings: [
    "Wallet creation does not create OKRW or native token balance; faucet funding is required before live transfer.",
    "This private key is testnet-only and must never be reused for mainnet, production, real funds, screenshots, source code, or shared docs.",
    "Set MESHKIT_MAROO_OKRW_TRANSFER_AUTHORIZATION before binding the bridge beyond loopback for a physical iPad demo.",
  ],
  nextSteps: readyForDirectBridge
    ? [
        `Open https://faucet.maroo.io/ and connect/fund ${derivedAddress}`,
        `Run: node scripts/ensure_maroo_bridge_authorization.mjs if bridgeAuthorizationConfigured is false`,
        `Run: set -a; source ${envPath}; set +a`,
        "Run: node scripts/run_maroo_native_okrw_live_proof.mjs --wait-for-funding",
        "Run: python3 scripts/verify_maroo_demo_readiness.py",
      ]
    : [
        "Run node scripts/create_maroo_demo_wallet.mjs or fix .env.maroo-demo.local.",
        "Make MESHKIT_MAROO_WALLET_ADDRESS and MESHKIT_MAROO_FAUCET_WALLET_ADDRESS match MESHKIT_MAROO_PRIVATE_KEY.",
        "Configure MESHKIT_MAROO_OKRW_TRANSFER_BRIDGE_URL and MESHKIT_MAROO_OKRW_PROBE_RECIPIENT.",
      ],
};

await mkdir(dirname(artifactPath), { recursive: true });
await writeFile(artifactPath, JSON.stringify(artifact, null, 2) + "\n");
console.log(`maroo demo wallet setup artifact written: ${artifactPath}`);
if (!readyForDirectBridge) {
  process.exit(2);
}

function parseEnvFile(contents) {
  const env = {};
  for (const line of contents.split(/\r?\n/)) {
    const trimmed = line.trim();
    if (!trimmed || trimmed.startsWith("#")) continue;
    const index = trimmed.indexOf("=");
    if (index < 0) continue;
    env[trimmed.slice(0, index)] = trimmed.slice(index + 1);
  }
  return env;
}
