import { createServer } from "node:http";
import { readFile } from "node:fs/promises";
import { extname, join, normalize } from "node:path";
import { fileURLToPath } from "node:url";
import { loadAcpDiscovery } from "./src/acp-registry.js";
import {
  executePersistentRequest,
  queryPreferences,
  readPersistentSuperappState,
  upsertPreference
} from "./src/superapp-store.js";

const root = fileURLToPath(new URL(".", import.meta.url));
const repoRoot = normalize(join(root, ".."));
const publicRoot = join(root, "src");
const dataRoot = process.env.MESHKIT_SUPERAPP_DATA_DIR || join(root, ".meshkit-data");
const ocgRegistryRoot = process.env.MESHKIT_ACP_REGISTRY_DIR || join(repoRoot, "ocg", "registry");
const port = Number(process.env.PORT || 4173);
const rpcEndpoint = "https://rpc-testnet.maroo.io";
const explorerBaseUrl = "https://explorer-testnet.maroo.io";
const defaultScanBlocks = Number(process.env.MESHKIT_MAROO_SCAN_BLOCKS || 1200);
const scanCache = new Map();

const contentTypes = {
  ".html": "text/html; charset=utf-8",
  ".css": "text/css; charset=utf-8",
  ".js": "text/javascript; charset=utf-8",
  ".json": "application/json; charset=utf-8",
  ".svg": "image/svg+xml; charset=utf-8"
};

function json(res, status, body) {
  res.writeHead(status, {
    "content-type": "application/json; charset=utf-8",
    "cache-control": "no-store"
  });
  res.end(JSON.stringify(body, null, 2));
}

async function readJsonBody(req) {
  const chunks = [];
  for await (const chunk of req) chunks.push(chunk);
  if (chunks.length === 0) return {};
  const raw = Buffer.concat(chunks).toString("utf8").trim();
  if (!raw) return {};
  try {
    return JSON.parse(raw);
  } catch {
    const error = new Error("request body must be valid JSON");
    error.statusCode = 400;
    throw error;
  }
}

async function withApiError(res, fn) {
  try {
    await fn();
  } catch (error) {
    json(res, error.statusCode || 400, {
      error: "api_error",
      message: error instanceof Error ? error.message : String(error)
    });
  }
}

async function rpc(method, params = []) {
  const response = await fetch(rpcEndpoint, {
    method: "POST",
    headers: { "content-type": "application/json" },
    body: JSON.stringify({ jsonrpc: "2.0", id: Date.now(), method, params })
  });
  if (!response.ok) {
    throw new Error(`maroo RPC ${method} failed with HTTP ${response.status}`);
  }
  const payload = await response.json();
  if (payload.error) {
    throw new Error(payload.error.message || `maroo RPC ${method} failed`);
  }
  return payload.result;
}

function shortHash(value) {
  return `${value.slice(0, 8)}...${value.slice(-6)}`;
}

function toHexBlock(number) {
  return `0x${number.toString(16)}`;
}

function decimalFromWei(weiHex) {
  const wei = BigInt(weiHex || "0x0");
  const whole = wei / 10n ** 18n;
  const fraction = (wei % 10n ** 18n).toString().padStart(18, "0").slice(0, 4);
  return `${whole}.${fraction}`;
}

function normalizeAddress(address) {
  return address.trim().toLowerCase();
}

async function mapLimit(items, limit, fn) {
  const results = new Array(items.length);
  let nextIndex = 0;
  async function worker() {
    while (nextIndex < items.length) {
      const currentIndex = nextIndex;
      nextIndex += 1;
      results[currentIndex] = await fn(items[currentIndex], currentIndex);
    }
  }
  await Promise.all(Array.from({ length: Math.min(limit, items.length) }, worker));
  return results;
}

function makeLiveRecord({ wallet, tx, receipt, block }) {
  const txIndex = Number.parseInt(tx.transactionIndex || receipt?.transactionIndex || "0x0", 16);
  const blockNumber = Number.parseInt(tx.blockNumber || block.number, 16);
  const requestId = `live-maroo-${blockNumber}-${txIndex}`;
  const receiptStatus = receipt?.status === "0x1" ? "verified" : "failed";
  const value = decimalFromWei(tx.value);
  const direction = normalizeAddress(tx.from) === normalizeAddress(wallet) ? "sent" : "received";

  return {
    provider: "maroo",
    network: "maroo-testnet",
    chainId: "maroo-testnet-1",
    walletAccount: wallet,
    requestId,
    txHash: tx.hash,
    receiptId: `maroo-receipt-${shortHash(tx.hash)}`,
    receiptStatus,
    proofStatus: receiptStatus === "verified" ? "backend_verified" : "failed",
    lifecycleState: receiptStatus === "verified" ? "receipt_verified" : "failed",
    isComplete: receiptStatus === "verified",
    graphNodes: [
      { id: `${requestId}:request`, type: "request", label: "Wallet account", primaryValue: shortHash(wallet) },
      { id: `${requestId}:payment`, type: "payment", label: `${direction} ${value} tOKRW`, primaryValue: shortHash(tx.hash) },
      { id: `${requestId}:receipt`, type: "receipt", label: "On-chain receipt", primaryValue: `block ${blockNumber}` },
      { id: `${requestId}:status`, type: "status", label: "RPC receipt status", primaryValue: receiptStatus }
    ],
    graphEdges: [
      { id: `${requestId}:request-payment`, type: "request_to_payment", source: `${requestId}:request`, target: `${requestId}:payment` },
      { id: `${requestId}:payment-receipt`, type: "payment_to_receipt", source: `${requestId}:payment`, target: `${requestId}:receipt` },
      { id: `${requestId}:receipt-status`, type: "receipt_to_status", source: `${requestId}:receipt`, target: `${requestId}:status` }
    ],
    proofDetails: {
      signedRequestHash: tx.hash,
      anchoringReference: `maroo-testnet:block:${blockNumber}`,
      policyHash: block.hash,
      verifierIdentity: "maroo-json-rpc",
      explorerUrl: `${explorerBaseUrl}/tx/${tx.hash}`,
      from: tx.from,
      to: tx.to || "",
      value,
      blockHash: block.hash,
      blockNumber: String(blockNumber),
      transactionIndex: String(txIndex)
    }
  };
}

async function findWalletTransactions(wallet, latestBlock, scanBlocks) {
  const normalizedWallet = normalizeAddress(wallet);
  const startBlock = Math.max(0, latestBlock - scanBlocks + 1);
  const blockNumbers = [];
  for (let blockNumber = latestBlock; blockNumber >= startBlock; blockNumber -= 1) {
    blockNumbers.push(blockNumber);
  }

  const blocks = await mapLimit(blockNumbers, 16, (blockNumber) =>
    rpc("eth_getBlockByNumber", [toHexBlock(blockNumber), true])
  );
  const matches = [];
  for (const block of blocks.filter(Boolean)) {
    const transactions = Array.isArray(block.transactions) ? block.transactions : [];
    for (const tx of transactions) {
      const fromMatches = typeof tx.from === "string" && normalizeAddress(tx.from) === normalizedWallet;
      const toMatches = typeof tx.to === "string" && normalizeAddress(tx.to) === normalizedWallet;
      if (fromMatches || toMatches) {
        matches.push({ tx, block });
      }
    }
  }

  const withReceipts = await mapLimit(matches.slice(0, 12), 4, async (match) => ({
    ...match,
    receipt: await rpc("eth_getTransactionReceipt", [match.tx.hash])
  }));
  return withReceipts;
}

function cacheKey(wallet, scanBlocks) {
  return `${normalizeAddress(wallet)}:${scanBlocks}`;
}

function getCache(wallet, scanBlocks) {
  return scanCache.get(cacheKey(wallet, scanBlocks)) || {
    records: [],
    status: "idle",
    error: null,
    scannedAt: null
  };
}

function startBackgroundScan({ wallet, latestBlock, scanBlocks, netVersion, balanceHex }) {
  const key = cacheKey(wallet, scanBlocks);
  const current = getCache(wallet, scanBlocks);
  if (current.status === "scanning") return current;

  const next = {
    ...current,
    status: "scanning",
    error: null,
    latestBlock,
    netVersion,
    walletBalance: decimalFromWei(balanceHex)
  };
  scanCache.set(key, next);

  void (async () => {
    try {
      const matches = await findWalletTransactions(wallet, latestBlock, scanBlocks);
      scanCache.set(key, {
        status: "ready",
        error: null,
        scannedAt: new Date().toISOString(),
        latestBlock,
        netVersion,
        walletBalance: decimalFromWei(balanceHex),
        records: matches.map((match) => makeLiveRecord({ wallet, ...match }))
      });
    } catch (error) {
      scanCache.set(key, {
        ...next,
        status: "error",
        error: error instanceof Error ? error.message : String(error)
      });
    }
  })();
  return next;
}

async function trustPaths(req, res, url) {
  const wallet = url.searchParams.get("wallet")?.trim();
  const network = url.searchParams.get("network")?.trim();
  if (!wallet) {
    json(res, 400, { error: "wallet query parameter is required" });
    return;
  }
  if (network !== "maroo-testnet") {
    json(res, 400, { error: "network must be maroo-testnet" });
    return;
  }

  try {
    const requestedScanBlocks = Number(url.searchParams.get("scanBlocks") || defaultScanBlocks);
    const scanBlocks = Math.min(Math.max(requestedScanBlocks, 1), 2500);
    const [latestHex, netVersion, balanceHex] = await Promise.all([
      rpc("eth_blockNumber"),
      rpc("net_version"),
      rpc("eth_getBalance", [wallet, "latest"])
    ]);
    const latestBlock = Number.parseInt(latestHex, 16);
    const cached = getCache(wallet, scanBlocks);
    const cacheAgeMs = cached.scannedAt ? Date.now() - Date.parse(cached.scannedAt) : Infinity;
    const shouldScan = cached.status === "idle"
      || cached.status === "error"
      || cacheAgeMs > 15000
      || (latestBlock - (cached.latestBlock || 0)) > 12;
    const state = shouldScan
      ? startBackgroundScan({ wallet, latestBlock, scanBlocks, netVersion, balanceHex })
      : cached;

    json(res, 200, {
      provider: "maroo",
      network: "maroo-testnet",
      chainId: "maroo-testnet-1",
      indexerMode: "live_rpc_block_scan",
      rpcEndpoint,
      netVersion,
      latestBlock,
      scanBlocks,
      scanStatus: state.status,
      scanError: state.error,
      scannedAt: state.scannedAt,
      walletBalance: decimalFromWei(balanceHex),
      pollIntervalSeconds: 2,
      records: state.records || []
    });
  } catch (error) {
    json(res, 502, {
      error: "maroo-testnet indexer unavailable",
      message: error instanceof Error ? error.message : String(error)
    });
  }
}

async function superappState(req, res) {
  const discovery = await loadAcpDiscovery({ registryDir: ocgRegistryRoot });
  json(res, 200, {
    ...await readPersistentSuperappState(dataRoot, { apps: discovery.apps }),
    acpDiscovery: {
      registryMode: discovery.registryMode,
      registryDir: discovery.registryDir,
      registryFiles: discovery.registryFiles,
      registryTrust: discovery.registryTrust,
      registryError: discovery.registryError
    },
    apiMode: "local-deterministic-superapp-state"
  });
}

async function acpApps(req, res) {
  const discovery = await loadAcpDiscovery({ registryDir: ocgRegistryRoot });
  json(res, 200, {
    schemaVersion: "meshkit-acp-discovery-response/v1",
    registryMode: discovery.registryMode,
    registryDir: discovery.registryDir,
    registryFiles: discovery.registryFiles,
    registryTrust: discovery.registryTrust,
    registryError: discovery.registryError,
    apps: discovery.apps
  });
}

async function preferences(req, res, url) {
  if (req.method === "GET") {
    const query = url.searchParams.get("query") || "";
    const limit = Number(url.searchParams.get("limit") || 10);
    const discovery = await loadAcpDiscovery({ registryDir: ocgRegistryRoot });
    json(res, 200, {
      schemaVersion: "meshkit-preference-query-response/v1",
      preferences: await queryPreferences(dataRoot, query, limit, { apps: discovery.apps })
    });
    return;
  }
  if (req.method === "POST") {
    await withApiError(res, async () => {
      const body = await readJsonBody(req);
      const discovery = await loadAcpDiscovery({ registryDir: ocgRegistryRoot });
      const result = await upsertPreference(dataRoot, body, { apps: discovery.apps });
      json(res, 201, {
        schemaVersion: "meshkit-preference-upsert-response/v1",
        preference: result.preference,
        droppedPreference: result.droppedPreference,
        state: result.state
      });
    });
    return;
  }
  json(res, 405, { error: "method_not_allowed" });
}

async function execute(req, res) {
  if (req.method !== "POST") {
    json(res, 405, { error: "method_not_allowed" });
    return;
  }
  await withApiError(res, async () => {
    const body = await readJsonBody(req);
    const discovery = await loadAcpDiscovery({ registryDir: ocgRegistryRoot });
    const result = await executePersistentRequest(dataRoot, body, { apps: discovery.apps });
    json(res, 201, {
      schemaVersion: "meshkit-execution-response/v1",
      ...result
    });
  });
}

async function settlements(req, res) {
  const discovery = await loadAcpDiscovery({ registryDir: ocgRegistryRoot });
  const state = await readPersistentSuperappState(dataRoot, { apps: discovery.apps });
  json(res, 200, {
    schemaVersion: "meshkit-settlement-query-response/v1",
    settlementLedger: state.settlementLedger
  });
}

async function serveStatic(req, res, url) {
  const pathname = url.pathname === "/" ? "/index.html" : url.pathname;
  const filePath = normalize(join(publicRoot, pathname));
  if (!filePath.startsWith(publicRoot)) {
    res.writeHead(403);
    res.end("Forbidden");
    return;
  }

  try {
    const body = await readFile(filePath);
    res.writeHead(200, {
      "content-type": contentTypes[extname(filePath)] || "application/octet-stream",
      "cache-control": "no-store"
    });
    res.end(body);
  } catch {
    res.writeHead(404, { "content-type": "text/plain; charset=utf-8" });
    res.end("Not found");
  }
}

createServer(async (req, res) => {
  const url = new URL(req.url || "/", `http://${req.headers.host || "localhost"}`);
  if (url.pathname === "/api/trust-paths") {
    await trustPaths(req, res, url);
    return;
  }
  if (url.pathname === "/api/superapp-state") {
    await superappState(req, res, url);
    return;
  }
  if (url.pathname === "/api/acp/apps") {
    await acpApps(req, res);
    return;
  }
  if (url.pathname === "/api/preferences") {
    await preferences(req, res, url);
    return;
  }
  if (url.pathname === "/api/execute") {
    await execute(req, res);
    return;
  }
  if (url.pathname === "/api/settlements") {
    await settlements(req, res);
    return;
  }
  await serveStatic(req, res, url);
}).listen(port, () => {
  console.log(`MeshKit maroo trust-path web running at http://localhost:${port}`);
});
