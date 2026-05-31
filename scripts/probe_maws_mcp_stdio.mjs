#!/usr/bin/env node
import { spawn } from "node:child_process";
import { mkdir, writeFile } from "node:fs/promises";
import { dirname, resolve } from "node:path";

const command = process.env.MESHKIT_MAWS_COMMAND || "npx";
const args = process.env.MESHKIT_MAWS_ARGS
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
const timeoutMs = Number(process.env.MESHKIT_MAWS_MCP_PROBE_TIMEOUT_MS || 90_000);
const artifactPath = resolve(
  process.env.MESHKIT_MAWS_MCP_PROBE_ARTIFACT || "artifacts/maroo-testnet/maws-mcp-stdio-probe.json",
);

const startedAt = new Date().toISOString();
const child = spawn(command, args, {
  env: process.env,
  stdio: ["pipe", "pipe", "pipe"],
});

let buffer = "";
let stderr = "";
let nextId = 1;
const pending = new Map();
let settled = false;

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

child.on("exit", async (code) => {
  if (!settled) {
    settled = true;
    await finish(failedProbeResult({
      ok: false,
      exitCondition: "BlockedByExternalChain",
      blockerType: "maws_mcp_unavailable",
      error: {
        code: "MAWS_MCP_EXITED",
        message: `m-aws MCP exited before responding with code ${code}`,
      },
    }));
  }
});

const timer = setTimeout(async () => {
  if (!settled) {
    settled = true;
    child.kill("SIGTERM");
    await finish(failedProbeResult({
      ok: false,
      exitCondition: "BlockedByExternalChain",
      blockerType: "maws_mcp_unavailable",
      error: {
        code: "MAWS_MCP_TIMEOUT",
        message: `m-aws MCP did not answer initialize/tools.list within ${timeoutMs}ms`,
      },
    }));
  }
}, timeoutMs);

try {
  const initialize = await send("initialize", {
    protocolVersion: "2024-11-05",
    capabilities: {},
    clientInfo: { name: "meshkit-maws-mcp-probe", version: "0.1.0" },
  });
  notify("notifications/initialized");
  const tools = await send("tools/list", {});
  const toolNames = tools.result?.tools?.map((tool) => tool.name).sort() || [];
  const transferSend = tools.result?.tools?.find((tool) => tool.name === "transfer.send") || null;
  clearTimeout(timer);
  settled = true;
  child.kill("SIGTERM");
  await finish({
    ok: Boolean(transferSend),
    initialize,
    toolNames,
    transferSend,
    exitCondition: transferSend ? null : "BlockedByExternalChain",
    blockerType: transferSend ? null : "maws_transfer_tool_unavailable",
    error: transferSend
      ? null
      : {
          code: "TRANSFER_SEND_MISSING",
          message: "m-aws MCP started, but tools/list did not expose transfer.send",
        },
  });
} catch (error) {
  clearTimeout(timer);
  settled = true;
  child.kill("SIGTERM");
  await finish(failedProbeResult({
    ok: false,
    exitCondition: "BlockedByExternalChain",
    blockerType: "maws_mcp_unavailable",
    error: {
      code: "MAWS_MCP_PROBE_FAILED",
      message: error?.message || String(error),
    },
  }));
}

function send(method, params) {
  const id = nextId++;
  writeMCPMessage({ jsonrpc: "2.0", id, method, params });
  return new Promise((resolve) => pending.set(id, resolve));
}

function notify(method, params = {}) {
  writeMCPMessage({ jsonrpc: "2.0", method, params });
}

function writeMCPMessage(message) {
  const body = JSON.stringify(message);
  child.stdin.write(`Content-Length: ${Buffer.byteLength(body, "utf8")}\r\n\r\n${body}`);
}

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
        // Ignore malformed frames so stderr remains the primary diagnostic.
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
      // Ignore stdout log lines.
    }
  }
  return messages;
}

async function finish(result) {
  const artifact = {
    checkedAt: new Date().toISOString(),
    startedAt,
    command,
    args,
    provider: "maroo",
    network: "maroo-testnet",
    stderr: stderr.trim().slice(0, 8000),
    ...result,
  };
  await mkdir(dirname(artifactPath), { recursive: true });
  await writeFile(artifactPath, JSON.stringify(artifact, null, 2) + "\n");
  console.log(`M-AWS MCP stdio probe artifact written: ${artifactPath}`);
  if (!artifact.ok) {
    process.exit(2);
  }
}

function failedProbeResult(result) {
  if (stderr.includes("No credentials found") || stderr.includes("WAAS_AUTH_TOKEN is not set")) {
    return {
      ...result,
      blockerType: "maws_auth_unavailable",
      error: {
        code: "MAWS_AUTH_MISSING",
        message: "m-aws MCP started but refused to serve tools because no ~/.maroo credentials or WAAS_AUTH_TOKEN were available",
      },
    };
  }
  return result;
}
