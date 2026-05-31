#!/usr/bin/env node
import http from "node:http";
import { execFileSync } from "node:child_process";
import { mkdirSync } from "node:fs";
import { createRequire } from "node:module";
import { resolve } from "node:path";
import { pathToFileURL } from "node:url";

const PORT = Number(process.env.MESHKIT_MAROO_OKRW_TRANSFER_BRIDGE_PORT || process.env.PORT || 8788);
const HOST = process.env.MESHKIT_MAROO_OKRW_TRANSFER_BRIDGE_HOST || process.env.HOST || "127.0.0.1";
const RPC_URL = process.env.MESHKIT_MAROO_RPC_URL || "https://rpc-testnet.maroo.io";
const EXPLORER_URL = process.env.MESHKIT_MAROO_EXPLORER_URL || "https://explorer-testnet.maroo.io";
const PRIVATE_KEY = process.env.MESHKIT_MAROO_PRIVATE_KEY || "";
const AUTHORIZATION = process.env.MESHKIT_MAROO_OKRW_TRANSFER_AUTHORIZATION || "";
const ALLOWED_RECIPIENTS = parseAddressList(process.env.MESHKIT_MAROO_OKRW_ALLOWED_RECIPIENTS || "");
const MAX_AMOUNT = process.env.MESHKIT_MAROO_OKRW_TRANSFER_MAX_AMOUNT || "";
const ETHERS_MODULE = process.env.MESHKIT_MAROO_ETHERS_MODULE || "ethers";
const TOOL_PREFIX = resolve(process.env.MESHKIT_MAROO_BRIDGE_TOOL_PREFIX || ".build/maroo-native-okrw-bridge-tool");
const RECEIPT_TIMEOUT_MS = Number(process.env.MESHKIT_MAROO_RECEIPT_TIMEOUT_MS || 45_000);
const MAX_BODY_BYTES = Number(process.env.MESHKIT_MAROO_BRIDGE_MAX_BODY_BYTES || 256 * 1024);
const requireFromHere = createRequire(import.meta.url);
let ethersModulePromise = null;

const server = http.createServer(async (req, res) => {
  try {
    if (req.method === "GET" && req.url === "/health") {
      const health = {
        service: "meshkit-maroo-native-okrw-transfer-bridge",
        listenHost: HOST,
        listenPort: PORT,
        rpcUrl: RPC_URL,
        explorerUrl: EXPLORER_URL,
        ethersModule: ETHERS_MODULE,
        privateKeyConfigured: Boolean(PRIVATE_KEY),
        authorizationRequired: Boolean(AUTHORIZATION),
        allowedRecipientsConfigured: ALLOWED_RECIPIENTS.length > 0,
        allowedRecipientCount: ALLOWED_RECIPIENTS.length,
        maxAmountOKRW: MAX_AMOUNT || null,
        signerAddress: PRIVATE_KEY ? await signerAddress() : null,
      };
      if (PRIVATE_KEY) {
        Object.assign(health, await signerChainStatus());
      }
      sendJSON(res, 200, {
        ok: true,
        data: health,
      });
      return;
    }

    if (req.method !== "POST") {
      sendJSON(res, 405, { ok: false, error: { code: "METHOD_NOT_ALLOWED", message: "POST required" } });
      return;
    }

    validateConfigured();
    validateAuthorization(req);
    const request = await readJSON(req);
    validateBridgeRequest(request);
    validateTransferPolicy(request.arguments);
    const result = await sendNativeOKRW(request.arguments);
    sendJSON(res, 200, result);
  } catch (error) {
    sendJSON(res, 500, {
      ok: false,
      error: {
        code: "MAROO_NATIVE_TRANSFER_ERROR",
        message: error?.message || String(error),
        retryable: true,
      },
    });
  }
});

server.listen(PORT, HOST, () => {
  console.error(`meshkit maroo native OKRW transfer bridge listening on http://${HOST}:${PORT}`);
});

async function sendNativeOKRW(args) {
  const { JsonRpcProvider, Wallet, parseEther } = await importEthers();
  const provider = new JsonRpcProvider(RPC_URL);
  const wallet = new Wallet(PRIVATE_KEY, provider);
  const tx = await wallet.sendTransaction({
    to: args.to,
    value: parseEther(args.amount),
  });
  const receipt = await waitWithTimeout(tx.wait(), RECEIPT_TIMEOUT_MS);
  if (!receipt) {
    return {
      ok: true,
      data: {
        txHash: tx.hash,
        transactionHash: tx.hash,
        status: "pending",
        providerOutcome: "pending",
        observedAt: new Date().toISOString(),
        explorerUrl: explorerURL(tx.hash),
        message: "maroo native OKRW transaction submitted; receipt not available before bridge timeout",
      },
    };
  }

  const currentBlock = await provider.getBlockNumber();
  const confirmationCount = Math.max(1, currentBlock - receipt.blockNumber + 1);
  const succeeded = receipt.status === 1;
  return {
    ok: true,
    data: {
      txHash: tx.hash,
      transactionHash: tx.hash,
      status: succeeded ? "confirmed" : "failed",
      providerOutcome: succeeded ? "success" : "failure",
      blockHash: receipt.blockHash,
      blockNumber: receipt.blockNumber,
      confirmationCount,
      confirmedAt: new Date().toISOString(),
      observedAt: new Date().toISOString(),
      explorerUrl: explorerURL(tx.hash),
      message: succeeded ? "maroo native OKRW transfer confirmed on testnet" : "maroo native OKRW transfer receipt failed",
    },
  };
}

async function signerAddress() {
  const { Wallet } = await importEthers();
  return new Wallet(PRIVATE_KEY).address;
}

async function signerChainStatus() {
  const { JsonRpcProvider, Wallet, formatEther } = await importEthers();
  const provider = new JsonRpcProvider(RPC_URL);
  const wallet = new Wallet(PRIVATE_KEY, provider);
  const [chainId, blockNumber, signerBalance] = await Promise.all([
    provider.getNetwork().then((network) => network.chainId.toString()),
    provider.getBlockNumber(),
    provider.getBalance(wallet.address),
  ]);
  return {
    chainId,
    blockNumber,
    signerBalanceWei: signerBalance.toString(),
    signerBalanceOKRW: formatEther(signerBalance),
  };
}

async function importEthers() {
  if (!ethersModulePromise) {
    ethersModulePromise = importConfiguredEthers();
  }
  return ethersModulePromise;
}

async function importConfiguredEthers() {
  if (ETHERS_MODULE !== "ethers") {
    return import(ETHERS_MODULE);
  }
  try {
    return await import("ethers");
  } catch (primaryError) {
    try {
      return await import(pathToFileURL(resolveEthersFromToolPrefix()).href);
    } catch {
      throw primaryError;
    }
  }
}

function resolveEthersFromToolPrefix() {
  const modulePaths = [
    `${TOOL_PREFIX}/node_modules`,
    resolve(".build/maroo-demo-wallet-tool/node_modules"),
    resolve("node_modules"),
  ];
  try {
    return requireFromHere.resolve("ethers", { paths: modulePaths });
  } catch {
    mkdirSync(TOOL_PREFIX, { recursive: true });
    execFileSync("npm", ["install", "--prefix", TOOL_PREFIX, "--no-save", "--silent", "ethers@6"], {
      stdio: "ignore",
    });
    return requireFromHere.resolve("ethers", { paths: modulePaths });
  }
}

function validateConfigured() {
  if (!PRIVATE_KEY.trim()) {
    throw new Error("MESHKIT_MAROO_PRIVATE_KEY is required for native OKRW transfer bridge");
  }
}

function validateAuthorization(req) {
  if (!AUTHORIZATION.trim()) {
    return;
  }
  const actual = req.headers.authorization || "";
  if (actual !== AUTHORIZATION) {
    const error = new Error("maroo native OKRW bridge authorization failed");
    error.code = "UNAUTHORIZED";
    throw error;
  }
}

function validateBridgeRequest(request) {
  if (!request || typeof request !== "object") {
    throw new Error("request body must be a JSON object");
  }
  if (request.schema_version !== "meshkit-maroo-native-okrw-transfer-bridge/v1") {
    throw new Error("bridge requires schema_version=meshkit-maroo-native-okrw-transfer-bridge/v1");
  }
  if (request.tool !== "maroo.native_transfer") {
    throw new Error("bridge only supports tool=maroo.native_transfer");
  }
  const args = request.arguments;
  for (const key of ["to", "amount", "clientToken"]) {
    if (!args || typeof args[key] !== "string" || args[key].trim() === "") {
      throw new Error(`arguments.${key} is required`);
    }
  }
  if (!/^0x[a-fA-F0-9]{40}$/.test(args.to)) {
    throw new Error("arguments.to must be an EVM address");
  }
  if (!/^(0|[1-9]\d*)(\.\d+)?$/.test(args.amount)) {
    throw new Error("arguments.amount must be a positive decimal OKRW amount");
  }
  if (Number(args.amount) <= 0) {
    throw new Error("arguments.amount must be greater than zero");
  }
}

function validateTransferPolicy(args) {
  if (ALLOWED_RECIPIENTS.length > 0 && !ALLOWED_RECIPIENTS.includes(args.to.toLowerCase())) {
    throw new Error("arguments.to is not allowed by MESHKIT_MAROO_OKRW_ALLOWED_RECIPIENTS");
  }
  if (MAX_AMOUNT.trim()) {
    const requested = decimalToWei(args.amount);
    const maximum = decimalToWei(MAX_AMOUNT);
    if (requested > maximum) {
      throw new Error("arguments.amount exceeds MESHKIT_MAROO_OKRW_TRANSFER_MAX_AMOUNT");
    }
  }
}

function parseAddressList(value) {
  return value
    .split(",")
    .map((item) => item.trim().toLowerCase())
    .filter(Boolean);
}

function decimalToWei(value) {
  const [whole, fraction = ""] = String(value).split(".");
  if (!/^(0|[1-9]\d*)$/.test(whole) || !/^\d*$/.test(fraction) || fraction.length > 18) {
    throw new Error("amount must be a decimal with at most 18 fractional digits");
  }
  return BigInt(whole + (fraction + "0".repeat(18)).slice(0, 18));
}

function readJSON(req) {
  return new Promise((resolve, reject) => {
    let body = "";
    req.on("data", (chunk) => {
      body += chunk.toString("utf8");
      if (Buffer.byteLength(body, "utf8") > MAX_BODY_BYTES) {
        reject(new Error("request body too large"));
        req.destroy();
      }
    });
    req.on("end", () => {
      try {
        resolve(JSON.parse(body || "{}"));
      } catch (error) {
        reject(error);
      }
    });
    req.on("error", reject);
  });
}

function sendJSON(res, status, value) {
  const body = JSON.stringify(value, null, 2) + "\n";
  res.writeHead(status, {
    "content-type": "application/json; charset=utf-8",
    "content-length": Buffer.byteLength(body),
  });
  res.end(body);
}

async function waitWithTimeout(promise, timeoutMs) {
  let timeout;
  return Promise.race([
    promise,
    new Promise((resolve) => {
      timeout = setTimeout(() => resolve(null), timeoutMs);
    }),
  ]).finally(() => clearTimeout(timeout));
}

function explorerURL(txHash) {
  return `${EXPLORER_URL.replace(/\/$/, "")}/tx/${txHash}`;
}
