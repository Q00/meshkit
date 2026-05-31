#!/usr/bin/env node
import http from "node:http";
import net from "node:net";
import { mkdtemp, writeFile, rm } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join, resolve } from "node:path";
import { pathToFileURL } from "node:url";
import { spawn } from "node:child_process";
import assert from "node:assert/strict";

const txHash = "0x" + "1".repeat(64);
const failedTxHash = "0x" + "2".repeat(64);
const pendingTxHash = "0x" + "3".repeat(64);
const blockHash = "0x" + "4".repeat(64);

const tmp = await mkdtemp(join(tmpdir(), "meshkit-maroo-native-"));
let bridge;

try {
  const fakeEthersPath = join(tmp, "fake-ethers.mjs");
  await writeFile(fakeEthersPath, fakeEthersSource(), "utf8");

  const bridgePort = await freePort();
  bridge = spawn("node", ["scripts/maroo_native_okrw_transfer_bridge.mjs"], {
    cwd: new URL("..", import.meta.url),
    env: {
      ...process.env,
      MESHKIT_MAROO_OKRW_TRANSFER_BRIDGE_PORT: String(bridgePort),
      MESHKIT_MAROO_OKRW_TRANSFER_BRIDGE_HOST: "127.0.0.1",
      MESHKIT_MAROO_PRIVATE_KEY: "0x" + "a".repeat(64),
      MESHKIT_MAROO_OKRW_TRANSFER_AUTHORIZATION: "Bearer contract-secret",
      MESHKIT_MAROO_OKRW_ALLOWED_RECIPIENTS: "0x000000000000000000000000000000000000d417",
      MESHKIT_MAROO_OKRW_TRANSFER_MAX_AMOUNT: "350",
      MESHKIT_MAROO_ETHERS_MODULE: pathToFileURL(fakeEthersPath).href,
      MESHKIT_MAROO_RPC_URL: "https://rpc-testnet.maroo.io",
      MESHKIT_MAROO_RECEIPT_TIMEOUT_MS: "50",
    },
    stdio: ["ignore", "pipe", "pipe"],
  });
  await waitForHealth(bridgePort);

  const health = await getJSON(bridgePort, "/health");
  assert.equal(health.ok, true);
  assert.equal(health.data.listenHost, "127.0.0.1");
  assert.equal(health.data.listenPort, bridgePort);
  assert.equal(health.data.privateKeyConfigured, true);
  assert.equal(health.data.authorizationRequired, true);
  assert.equal(health.data.allowedRecipientsConfigured, true);
  assert.equal(health.data.allowedRecipientCount, 1);
  assert.equal(health.data.maxAmountOKRW, "350");
  assert.equal(health.data.signerAddress, "0x000000000000000000000000000000000000aAaA");

  const unauthorized = await postJSON(bridgePort, requestBody({ amount: "100" }), { authorization: "Bearer wrong" });
  assert.equal(unauthorized.ok, false);
  assert.equal(unauthorized.error.code, "MAROO_NATIVE_TRANSFER_ERROR");
  assert.match(unauthorized.error.message, /authorization failed/);

  const deniedRecipient = await postJSON(
    bridgePort,
    requestBody({ to: "0x000000000000000000000000000000000000d418", amount: "100" }),
  );
  assert.equal(deniedRecipient.ok, false);
  assert.match(deniedRecipient.error.message, /not allowed/);

  const deniedAmount = await postJSON(bridgePort, requestBody({ amount: "351" }));
  assert.equal(deniedAmount.ok, false);
  assert.match(deniedAmount.error.message, /exceeds/);

  const confirmed = await postJSON(bridgePort, requestBody({ amount: "100" }));
  assert.equal(confirmed.ok, true);
  assert.equal(confirmed.data.txHash, txHash);
  assert.equal(confirmed.data.status, "confirmed");
  assert.equal(confirmed.data.providerOutcome, "success");
  assert.equal(confirmed.data.blockHash, blockHash);
  assert.equal(confirmed.data.blockNumber, 9069000);
  assert.equal(confirmed.data.confirmationCount, 13);
  assert.match(confirmed.data.explorerUrl, new RegExp(`/tx/${txHash}$`));

  const failed = await postJSON(bridgePort, requestBody({ amount: "200" }));
  assert.equal(failed.ok, true);
  assert.equal(failed.data.txHash, failedTxHash);
  assert.equal(failed.data.status, "failed");
  assert.equal(failed.data.providerOutcome, "failure");
  assert.equal(failed.data.blockHash, blockHash);

  const pending = await postJSON(bridgePort, requestBody({ amount: "300" }));
  assert.equal(pending.ok, true);
  assert.equal(pending.data.txHash, pendingTxHash);
  assert.equal(pending.data.status, "pending");
  assert.equal(pending.data.providerOutcome, "pending");
  assert.equal(pending.data.blockHash, undefined);
  assert.equal(pending.data.confirmedAt, undefined);

  const invalid = await postJSON(bridgePort, requestBody({ to: "not-an-address" }));
  assert.equal(invalid.ok, false);
  assert.equal(invalid.error.code, "MAROO_NATIVE_TRANSFER_ERROR");
  assert.match(invalid.error.message, /EVM address/);

  console.log("maroo native OKRW transfer bridge contract verification passed");
} finally {
  if (bridge) bridge.kill("SIGTERM");
  await rm(tmp, { recursive: true, force: true });
}

function requestBody(overrides = {}) {
  return {
    schema_version: "meshkit-maroo-native-okrw-transfer-bridge/v1",
    tool: "maroo.native_transfer",
    arguments: {
      to: overrides.to || "0x000000000000000000000000000000000000d417",
      amount: overrides.amount || "100",
      clientToken: "native-contract-test",
      memo: "MeshKit DailyMart native maroo OKRW contract test",
    },
    meshkit: { request_type: "meshkit_okrw_execution" },
  };
}

function fakeEthersSource() {
  return `
export class JsonRpcProvider {
  constructor(url) {
    this.url = url;
  }
  async getBlockNumber() {
    return 9069012;
  }
  async getNetwork() {
    return { chainId: 450815n };
  }
  async getBalance(address) {
    return 5000000000000000000000n;
  }
}

export class Wallet {
  constructor(privateKey, provider = null) {
    this.privateKey = privateKey;
    this.provider = provider;
    this.address = "0x000000000000000000000000000000000000aAaA";
  }
  async sendTransaction(tx) {
    if (tx.value === "200000000000000000000") {
      return {
        hash: "${failedTxHash}",
        wait: async () => ({
          status: 0,
          blockHash: "${blockHash}",
          blockNumber: 9069000,
        }),
      };
    }
    if (tx.value === "300000000000000000000") {
      return {
        hash: "${pendingTxHash}",
        wait: () => new Promise(() => {}),
      };
    }
    return {
      hash: "${txHash}",
      wait: async () => ({
        status: 1,
        blockHash: "${blockHash}",
        blockNumber: 9069000,
      }),
    };
  }
}

export function parseEther(value) {
  const [whole, fraction = ""] = String(value).split(".");
  const padded = (fraction + "0".repeat(18)).slice(0, 18);
  return BigInt(whole + padded).toString();
}

export function formatEther(value) {
  const raw = BigInt(value).toString().padStart(19, "0");
  const whole = raw.slice(0, -18);
  const fraction = raw.slice(-18).replace(/0+$/, "");
  return fraction ? whole + "." + fraction : whole;
}
`;
}

async function waitForHealth(port) {
  const started = Date.now();
  while (Date.now() - started < 5000) {
    try {
      const response = await fetch(`http://127.0.0.1:${port}/health`);
      if (response.ok) return;
    } catch {
      // retry
    }
    await new Promise((resolve) => setTimeout(resolve, 100));
  }
  throw new Error("bridge health check timed out");
}

async function getJSON(port, path) {
  const response = await fetch(`http://127.0.0.1:${port}${path}`);
  return response.json();
}

async function postJSON(port, body, headers = {}) {
  const response = await fetch(`http://127.0.0.1:${port}/transfer`, {
    method: "POST",
    headers: {
      "content-type": "application/json",
      authorization: "Bearer contract-secret",
      ...headers,
    },
    body: JSON.stringify(body),
  });
  return response.json();
}

function freePort() {
  return new Promise((resolve, reject) => {
    const server = net.createServer();
    server.listen(0, "127.0.0.1", () => {
      const address = server.address();
      server.close(() => resolve(address.port));
    });
    server.on("error", reject);
  });
}
