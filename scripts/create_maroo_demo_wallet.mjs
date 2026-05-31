#!/usr/bin/env node
import { execFileSync } from "node:child_process";
import { randomBytes } from "node:crypto";
import { chmod, mkdir, writeFile } from "node:fs/promises";
import { dirname, resolve } from "node:path";

const envPath = resolve(process.env.MESHKIT_MAROO_DEMO_WALLET_ENV || ".env.maroo-demo.local");
const artifactPath = resolve(
  process.env.MESHKIT_MAROO_DEMO_WALLET_ARTIFACT || "artifacts/maroo-testnet/demo-wallet.json",
);
const toolPrefix = resolve(process.env.MESHKIT_MAROO_DEMO_WALLET_TOOL_PREFIX || ".build/maroo-demo-wallet-tool");
const faucetURL = process.env.MESHKIT_MAROO_FAUCET_URL || "https://faucet.maroo.io/";
const bridgeURL = process.env.MESHKIT_MAROO_OKRW_TRANSFER_BRIDGE_URL || "http://127.0.0.1:8788/transfer";
const bridgeAuthorization =
  process.env.MESHKIT_MAROO_OKRW_TRANSFER_AUTHORIZATION ||
  `meshkit-maroo-${randomBytes(24).toString("base64url")}`;
const recipient = process.env.MESHKIT_MAROO_OKRW_PROBE_RECIPIENT || "0x000000000000000000000000000000000000d417";
const amount = process.env.MESHKIT_MAROO_OKRW_PROBE_AMOUNT || "1";
const maxAmount = process.env.MESHKIT_MAROO_OKRW_TRANSFER_MAX_AMOUNT || "100";

await mkdir(toolPrefix, { recursive: true });
execFileSync("npm", ["install", "--prefix", toolPrefix, "--no-save", "--silent", "ethers@6"], {
  stdio: "ignore",
});
const wallet = JSON.parse(
  execFileSync(
    "node",
    [
      "-e",
      "const { Wallet } = require('ethers'); const wallet = Wallet.createRandom(); console.log(JSON.stringify({ address: wallet.address, privateKey: wallet.privateKey }));",
    ],
    {
      env: {
        ...process.env,
        NODE_PATH: `${toolPrefix}/node_modules`,
      },
      encoding: "utf8",
    },
  ),
);

const envFile = [
  "# MeshKit maroo testnet demo wallet.",
  "# Testnet only. Do not commit this file or reuse this key for production.",
  `MESHKIT_MAROO_PRIVATE_KEY=${wallet.privateKey}`,
  `MESHKIT_MAROO_WALLET_ADDRESS=${wallet.address}`,
  `MESHKIT_MAROO_FAUCET_WALLET_ADDRESS=${wallet.address}`,
  `MESHKIT_MAROO_OKRW_TRANSFER_BRIDGE_URL=${bridgeURL}`,
  `MESHKIT_MAROO_OKRW_TRANSFER_AUTHORIZATION=${bridgeAuthorization}`,
  `MESHKIT_MAROO_OKRW_ALLOWED_RECIPIENTS=${recipient}`,
  `MESHKIT_MAROO_OKRW_TRANSFER_MAX_AMOUNT=${maxAmount}`,
  `MESHKIT_MAROO_OKRW_PROBE_RECIPIENT=${recipient}`,
  `MESHKIT_MAROO_OKRW_PROBE_AMOUNT=${amount}`,
  "",
].join("\n");

const artifact = {
  checkedAt: new Date().toISOString(),
  provider: "maroo",
  network: "maroo-testnet",
  walletAddress: wallet.address,
  faucetUrl: faucetURL,
  envPath,
  bridgeUrl: bridgeURL,
  bridgeAuthorizationStoredInEnvFile: true,
  allowedRecipients: [recipient],
  maxAmount,
  probeRecipient: recipient,
  probeAmount: amount,
  privateKeyStoredInEnvFile: true,
  privateKeyPrinted: false,
  safetyWarnings: [
    "Wallet creation does not create OKRW or native token balance; faucet funding is required before live transfer.",
    "This private key is testnet-only and must never be reused for mainnet, production, real funds, screenshots, source code, or shared docs.",
  ],
  nextSteps: [
    `Open ${faucetURL}`,
    `Import the generated testnet-only private key from ${envPath} into a fresh MetaMask account, or instead fund an existing fresh MetaMask test account and copy that account private key into MESHKIT_MAROO_PRIVATE_KEY.`,
    `Connect the funded wallet address ${wallet.address} to the faucet.`,
    "Request maroo testnet native token and OKRW/tOKRW faucet funds for that wallet. Wallet creation alone does not create any balance.",
    `Run: set -a; source ${envPath}; set +a`,
    "Run: node scripts/run_maroo_native_okrw_live_proof.mjs --wait-for-funding",
    "Re-run: python3 scripts/verify_maroo_demo_readiness.py",
  ],
};

await mkdir(dirname(envPath), { recursive: true });
await writeFile(envPath, envFile, { mode: 0o600 });
await chmod(envPath, 0o600);
await mkdir(dirname(artifactPath), { recursive: true });
await writeFile(artifactPath, JSON.stringify(artifact, null, 2) + "\n");

console.log(`maroo demo wallet created: ${wallet.address}`);
console.log(`private key written to ignored env file: ${envPath}`);
console.log(`wallet setup artifact written: ${artifactPath}`);
