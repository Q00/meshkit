#!/usr/bin/env node
import http from "node:http";
import { spawn } from "node:child_process";
import { existsSync } from "node:fs";
import { homedir } from "node:os";

const PORT = Number(process.env.MESHKIT_MAWS_BRIDGE_PORT || process.env.PORT || 8787);
const RPC_URL = process.env.MESHKIT_MAROO_RPC_URL || "https://rpc-testnet.maroo.io";
const EXPLORER_URL = process.env.MESHKIT_MAROO_EXPLORER_URL || "https://explorer-testnet.maroo.io";
const MAWS_COMMAND = process.env.MESHKIT_MAWS_COMMAND || "npx";
const MAWS_ARGS = process.env.MESHKIT_MAWS_ARGS
  ? JSON.parse(process.env.MESHKIT_MAWS_ARGS)
  : [
      "--cache",
      ".build/npm-cache",
      "-y",
      "-p",
      "@solana/transaction-messages",
      "-p",
      "@maroo-chain/m-aws",
      "m-aws",
      "serve",
    ];
const MCP_TIMEOUT_MS = Number(process.env.MESHKIT_MAWS_MCP_TIMEOUT_MS || 45_000);
const RECEIPT_TIMEOUT_MS = Number(process.env.MESHKIT_MAWS_RECEIPT_TIMEOUT_MS || 20_000);
const RECEIPT_POLL_INTERVAL_MS = Number(process.env.MESHKIT_MAWS_RECEIPT_POLL_INTERVAL_MS || 1_000);
const MAX_BODY_BYTES = Number(process.env.MESHKIT_MAWS_BRIDGE_MAX_BODY_BYTES || 256 * 1024);
const CREDENTIALS_PATH = `${homedir()}/.maroo/credentials.json`;

const server = http.createServer(async (req, res) => {
  try {
    if (req.method === "GET" && req.url === "/health") {
      sendJSON(res, 200, {
        ok: true,
        data: {
          service: "meshkit-maws-transfer-bridge",
          rpcUrl: RPC_URL,
          explorerUrl: EXPLORER_URL,
          mAwsCommand: MAWS_COMMAND,
          mAwsArgs: MAWS_ARGS,
          authenticated: Boolean(process.env.WAAS_AUTH_TOKEN) || existsSync(CREDENTIALS_PATH),
          credentialsFilePresent: existsSync(CREDENTIALS_PATH),
        },
      });
      return;
    }

    if (req.method !== "POST") {
      sendJSON(res, 405, { ok: false, error: { code: "METHOD_NOT_ALLOWED", message: "POST required" } });
      return;
    }

    const request = await readJSON(req);
    validateBridgeRequest(request);

    const transferResult = await callMAWSTransferSend(request.arguments);
    if (!transferResult.ok) {
      sendJSON(res, 200, transferResult);
      return;
    }

    const txHash = transferResult.data?.txHash;
    if (!txHash) {
      sendJSON(res, 200, {
        ok: true,
        data: {
          ...transferResult.data,
          status: "pending",
          observedAt: new Date().toISOString(),
          message: "M-AWS transfer.send completed without txHash; maroo confirmation unavailable",
        },
      });
      return;
    }

    const receipt = await waitForReceipt(txHash);
    if (!receipt) {
      sendJSON(res, 200, {
        ok: true,
        data: {
          ...transferResult.data,
          txHash,
          transactionHash: txHash,
          status: "pending",
          providerOutcome: "pending",
          observedAt: new Date().toISOString(),
          explorerUrl: explorerURL(txHash),
          message: "maroo transaction submitted; receipt not available before bridge timeout",
        },
      });
      return;
    }

    const blockNumber = Number.parseInt(receipt.blockNumber, 16);
    const currentBlock = await rpc("eth_blockNumber", []);
    const currentBlockNumber = typeof currentBlock === "string" ? Number.parseInt(currentBlock, 16) : blockNumber;
    const confirmationCount = Math.max(1, currentBlockNumber - blockNumber + 1);
    const succeeded = receipt.status === "0x1";

    sendJSON(res, 200, {
      ok: true,
      data: {
        ...transferResult.data,
        txHash,
        transactionHash: txHash,
        status: succeeded ? "confirmed" : "failed",
        providerOutcome: succeeded ? "success" : "failure",
        blockHash: receipt.blockHash,
        blockNumber,
        confirmationCount,
        confirmedAt: new Date().toISOString(),
        observedAt: new Date().toISOString(),
        explorerUrl: explorerURL(txHash),
        message: succeeded ? "M-AWS transfer.send confirmed on maroo testnet" : "M-AWS transfer.send receipt failed",
      },
    });
  } catch (error) {
    sendJSON(res, 500, {
      ok: false,
      error: {
        code: "BRIDGE_ERROR",
        message: error?.message || String(error),
        retryable: true,
      },
    });
  }
});

server.listen(PORT, "127.0.0.1", () => {
  console.error(`meshkit MAWS transfer bridge listening on http://127.0.0.1:${PORT}`);
});

function validateBridgeRequest(request) {
  if (!request || typeof request !== "object") {
    throw new Error("request body must be a JSON object");
  }
  if (request.tool !== "transfer.send") {
    throw new Error("bridge only supports tool=transfer.send");
  }
  const args = request.arguments;
  for (const key of ["agentId", "to", "amount"]) {
    if (!args || typeof args[key] !== "string" || args[key].trim() === "") {
      throw new Error(`arguments.${key} is required`);
    }
  }
}

function callMAWSTransferSend(args) {
  return new Promise((resolve, reject) => {
    const child = spawn(MAWS_COMMAND, MAWS_ARGS, {
      env: process.env,
      stdio: ["pipe", "pipe", "pipe"],
    });
    let buffer = "";
    let stderr = "";
    let nextId = 1;
    const pending = new Map();

    let settled = false;
    const timeout = setTimeout(() => {
      child.kill("SIGTERM");
      if (!settled) {
        settled = true;
        reject(new Error(`M-AWS MCP timeout after ${MCP_TIMEOUT_MS}ms: ${stderr.trim()}`));
      }
    }, MCP_TIMEOUT_MS);

    child.stderr.on("data", (chunk) => {
      stderr += chunk.toString("utf8");
    });
    child.stdout.on("data", (chunk) => {
      buffer += chunk.toString("utf8");
      for (const message of readMCPMessages()) {
        if (message.id !== undefined && pending.has(message.id)) {
          pending.get(message.id)(message);
          pending.delete(message.id);
        }
      }
    });
    child.on("error", reject);
    child.on("exit", (code) => {
      if (pending.size > 0) {
        clearTimeout(timeout);
        if (!settled) {
          settled = true;
          reject(new Error(`M-AWS MCP exited with code ${code}: ${stderr.trim()}`));
        }
      }
    });

    const send = (method, params) => {
      const id = nextId++;
      writeMCPMessage(child.stdin, { jsonrpc: "2.0", id, method, params });
      return new Promise((ok) => pending.set(id, ok));
    };
    const notify = (method, params = {}) => {
      writeMCPMessage(child.stdin, { jsonrpc: "2.0", method, params });
    };

    (async () => {
      await send("initialize", {
        protocolVersion: "2024-11-05",
        capabilities: {},
        clientInfo: { name: "meshkit-maws-transfer-bridge", version: "0.1.0" },
      });
      notify("notifications/initialized");
      const response = await send("tools/call", {
        name: "transfer.send",
        arguments: {
          agentId: args.agentId,
          to: args.to,
          amount: args.amount,
          clientToken: args.clientToken,
          memo: args.memo,
        },
      });
      clearTimeout(timeout);
      child.kill("SIGTERM");
      if (!settled) {
        settled = true;
        resolve(decodeMCPToolResponse(response));
      }
    })().catch((error) => {
      clearTimeout(timeout);
      child.kill("SIGTERM");
      if (!settled) {
        settled = true;
        reject(error);
      }
    });

    function readMCPMessages() {
      const messages = [];
      while (buffer.length > 0) {
        if (buffer.startsWith("Content-Length:")) {
          const headerEnd = buffer.indexOf("\r\n\r\n");
          if (headerEnd < 0) break;
          const header = buffer.slice(0, headerEnd);
          const match = header.match(/Content-Length:\s*(\d+)/i);
          if (!match) {
            buffer = buffer.slice(headerEnd + 4);
            continue;
          }
          const length = Number(match[1]);
          const bodyStart = headerEnd + 4;
          const bodyEnd = bodyStart + length;
          if (buffer.length < bodyEnd) break;
          const body = buffer.slice(bodyStart, bodyEnd);
          buffer = buffer.slice(bodyEnd);
          try {
            messages.push(JSON.parse(body));
          } catch {
            // Ignore non-JSON MCP frames from provider tooling.
          }
          continue;
        }

        const lineEnd = buffer.indexOf("\n");
        if (lineEnd < 0) break;
        const line = buffer.slice(0, lineEnd).trim();
        buffer = buffer.slice(lineEnd + 1);
        if (!line) continue;
        try {
          messages.push(JSON.parse(line));
        } catch {
          // Ignore log lines on stdout; stderr is still captured for diagnostics.
        }
      }
      return messages;
    }
  });
}

function writeMCPMessage(stream, message) {
  const body = JSON.stringify(message);
  stream.write(`Content-Length: ${Buffer.byteLength(body, "utf8")}\r\n\r\n${body}`);
}

function decodeMCPToolResponse(response) {
  if (response.error) {
    return { ok: false, error: { code: "MCP_ERROR", message: response.error.message, detail: response.error } };
  }
  if (response.result?.structuredContent && typeof response.result.structuredContent === "object") {
    return response.result.structuredContent;
  }
  const jsonContent = response.result?.content?.find((item) => item.type === "json" && item.json);
  if (jsonContent) {
    return jsonContent.json;
  }
  const text = response.result?.content?.find((item) => item.type === "text")?.text;
  if (!text) {
    return { ok: false, error: { code: "EMPTY_MAWS_RESPONSE", message: "M-AWS returned no text content" } };
  }
  try {
    return JSON.parse(text);
  } catch (error) {
    return { ok: false, error: { code: "INVALID_MAWS_RESPONSE", message: error.message, detail: { text } } };
  }
}

async function waitForReceipt(txHash) {
  const started = Date.now();
  while (Date.now() - started < RECEIPT_TIMEOUT_MS) {
    const receipt = await rpc("eth_getTransactionReceipt", [txHash]);
    if (receipt) return receipt;
    await sleep(RECEIPT_POLL_INTERVAL_MS);
  }
  return null;
}

async function rpc(method, params) {
  const response = await fetch(RPC_URL, {
    method: "POST",
    headers: { "content-type": "application/json" },
    body: JSON.stringify({ jsonrpc: "2.0", id: Date.now(), method, params }),
  });
  if (!response.ok) {
    throw new Error(`maroo RPC ${method} HTTP ${response.status}`);
  }
  const payload = await response.json();
  if (payload.error) {
    throw new Error(`maroo RPC ${method}: ${payload.error.message || JSON.stringify(payload.error)}`);
  }
  return payload.result;
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

function explorerURL(txHash) {
  return `${EXPLORER_URL.replace(/\/$/, "")}/tx/${txHash}`;
}

function sleep(ms) {
  return new Promise((resolve) => setTimeout(resolve, ms));
}
