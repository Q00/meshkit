#!/usr/bin/env node
import http from "node:http";
import net from "node:net";
import { mkdtemp, writeFile, rm } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { spawn } from "node:child_process";
import assert from "node:assert/strict";

const txHash = "0x" + "7".repeat(64);
const failedTxHash = "0x" + "6".repeat(64);
const pendingTxHash = "0x" + "5".repeat(64);
const blockHash = "0x" + "8".repeat(64);

const tmp = await mkdtemp(join(tmpdir(), "meshkit-maws-bridge-"));
let bridge;
let rpcServer;

try {
  const fakeMcpPath = join(tmp, "fake-maws-mcp.mjs");
  await writeFile(fakeMcpPath, fakeMcpSource(), "utf8");

  const rpcPort = await freePort();
  rpcServer = await startFakeRPC(rpcPort);
  const bridgePort = await freePort();
  bridge = spawn("node", ["scripts/maws_transfer_bridge.mjs"], {
    cwd: new URL("..", import.meta.url),
    env: {
      ...process.env,
      MESHKIT_MAWS_BRIDGE_PORT: String(bridgePort),
      MESHKIT_MAWS_COMMAND: "node",
      MESHKIT_MAWS_ARGS: JSON.stringify([fakeMcpPath]),
      MESHKIT_MAROO_RPC_URL: `http://127.0.0.1:${rpcPort}`,
      MESHKIT_MAWS_MCP_TIMEOUT_MS: "5000",
      MESHKIT_MAWS_RECEIPT_TIMEOUT_MS: "2000",
    },
    stdio: ["ignore", "pipe", "pipe"],
  });
  await waitForHealth(bridgePort);

  const confirmed = await postJSON(bridgePort, {
    schema_version: "meshkit-maws-transfer-send-bridge/v1",
    tool: "transfer.send",
    arguments: {
      agentId: "agent-live",
      to: "0x000000000000000000000000000000000000dEaD",
      amount: "100",
      clientToken: "contract-test-confirmed",
    },
    meshkit: { request_type: "meshkit_okrw_execution" },
  });
  assert.equal(confirmed.ok, true);
  assert.equal(confirmed.data.txHash, txHash);
  assert.equal(confirmed.data.status, "confirmed");
  assert.equal(confirmed.data.providerOutcome, "success");
  assert.equal(confirmed.data.blockHash, blockHash);
  assert.equal(confirmed.data.blockNumber, 9068000);
  assert.equal(confirmed.data.confirmationCount, 11);
  assert.match(confirmed.data.explorerUrl, new RegExp(`/tx/${txHash}$`));

  const pending = await postJSON(bridgePort, {
    schema_version: "meshkit-maws-transfer-send-bridge/v1",
    tool: "transfer.send",
    arguments: {
      agentId: "receipt-pending",
      to: "0x000000000000000000000000000000000000dEaD",
      amount: "100",
    },
    meshkit: { request_type: "meshkit_okrw_execution" },
  });
  assert.equal(pending.ok, true);
  assert.equal(pending.data.txHash, pendingTxHash);
  assert.equal(pending.data.status, "pending");
  assert.equal(pending.data.providerOutcome, "pending");
  assert.equal(pending.data.blockHash, undefined);
  assert.equal(pending.data.confirmedAt, undefined);

  const failed = await postJSON(bridgePort, {
    schema_version: "meshkit-maws-transfer-send-bridge/v1",
    tool: "transfer.send",
    arguments: {
      agentId: "receipt-failed",
      to: "0x000000000000000000000000000000000000dEaD",
      amount: "100",
    },
    meshkit: { request_type: "meshkit_okrw_execution" },
  });
  assert.equal(failed.ok, true);
  assert.equal(failed.data.txHash, failedTxHash);
  assert.equal(failed.data.status, "failed");
  assert.equal(failed.data.providerOutcome, "failure");
  assert.equal(failed.data.blockHash, blockHash);

  const denied = await postJSON(bridgePort, {
    schema_version: "meshkit-maws-transfer-send-bridge/v1",
    tool: "transfer.send",
    arguments: {
      agentId: "policy-denied",
      to: "0x000000000000000000000000000000000000dEaD",
      amount: "100",
    },
    meshkit: { request_type: "meshkit_okrw_execution" },
  });
  assert.equal(denied.ok, false);
  assert.equal(denied.error.code, "POLICY_REJECTED");
  assert.match(denied.error.message, /Policy rejected/);

  console.log("M-AWS transfer bridge contract verification passed");
} finally {
  if (bridge) bridge.kill("SIGTERM");
  if (rpcServer) await new Promise((resolve) => rpcServer.close(resolve));
  await rm(tmp, { recursive: true, force: true });
}

function fakeMcpSource() {
  return `
let buffer = "";
process.stdin.on("data", (chunk) => {
  buffer += chunk.toString("utf8");
  while (buffer.length > 0) {
    const headerEnd = buffer.indexOf("\\r\\n\\r\\n");
    if (headerEnd < 0) return;
    const header = buffer.slice(0, headerEnd);
    const match = header.match(/Content-Length:\\s*(\\d+)/i);
    if (!match) throw new Error("missing Content-Length");
    const length = Number(match[1]);
    const bodyStart = headerEnd + 4;
    const bodyEnd = bodyStart + length;
    if (buffer.length < bodyEnd) return;
    const request = JSON.parse(buffer.slice(bodyStart, bodyEnd));
    buffer = buffer.slice(bodyEnd);
    if (request.method === "initialize") {
      respond(request.id, { protocolVersion: "2024-11-05", capabilities: { tools: {} }, serverInfo: { name: "fake-m-aws", version: "0.0.0" } });
    } else if (request.method === "tools/call") {
      const args = request.params.arguments || {};
      if (args.memo !== undefined && args.memo !== "MeshKit DailyMart OKRW execution") {
        respond(request.id, { content: [{ type: "text", text: JSON.stringify({ ok: false, error: { code: "INVALID_MEMO", message: "memo was not forwarded" } }) }], isError: true });
      } else
      if (args.agentId === "policy-denied") {
        respond(request.id, { content: [{ type: "text", text: JSON.stringify({ ok: false, error: { code: "POLICY_REJECTED", message: "Policy rejected: limit exceeded" } }) }], isError: true });
      } else if (args.agentId === "receipt-pending") {
        respond(request.id, { content: [{ type: "text", text: JSON.stringify({ ok: true, data: { txHash: "${pendingTxHash}", from: "0xagent", to: args.to, amount: args.amount, unit: "OKRW" } }) }], isError: false });
      } else if (args.agentId === "receipt-failed") {
        respond(request.id, { content: [{ type: "text", text: JSON.stringify({ ok: true, data: { txHash: "${failedTxHash}", from: "0xagent", to: args.to, amount: args.amount, unit: "OKRW" } }) }], isError: false });
      } else {
        respond(request.id, { content: [{ type: "text", text: JSON.stringify({ ok: true, data: { txHash: "${txHash}", from: "0xagent", to: args.to, amount: args.amount, unit: "OKRW" } }) }], isError: false });
      }
    }
  }
});
function respond(id, result) {
  const body = JSON.stringify({ jsonrpc: "2.0", id, result });
  process.stdout.write("Content-Length: " + Buffer.byteLength(body, "utf8") + "\\r\\n\\r\\n" + body);
}
`;
}

function startFakeRPC(port) {
  const server = http.createServer(async (req, res) => {
    let body = "";
    for await (const chunk of req) body += chunk.toString("utf8");
    const request = JSON.parse(body || "{}");
    let result = null;
    if (request.method === "eth_getTransactionReceipt" && request.params?.[0] === pendingTxHash) {
      result = null;
    } else if (request.method === "eth_getTransactionReceipt" && request.params?.[0] === failedTxHash) {
      result = {
        transactionHash: failedTxHash,
        blockHash,
        blockNumber: "0x8a5de0",
        status: "0x0",
      };
    } else if (request.method === "eth_getTransactionReceipt") {
      result = {
        transactionHash: txHash,
        blockHash,
        blockNumber: "0x8a5de0",
        status: "0x1",
      };
    } else if (request.method === "eth_blockNumber") {
      result = "0x8a5dea";
    }
    const response = JSON.stringify({ jsonrpc: "2.0", id: request.id, result });
    res.writeHead(200, { "content-type": "application/json" });
    res.end(response);
  });
  return new Promise((resolve) => server.listen(port, "127.0.0.1", () => resolve(server)));
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

async function postJSON(port, body) {
  const response = await fetch(`http://127.0.0.1:${port}/transfer`, {
    method: "POST",
    headers: { "content-type": "application/json" },
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
