#!/usr/bin/env node
import { mkdir, writeFile } from "node:fs/promises";
import { dirname, resolve } from "node:path";

const bridgeURL = requiredEnv("MESHKIT_MAWS_BRIDGE_URL");
const agentId = requiredEnv("MESHKIT_MAWS_AGENT_ID");
const recipient = requiredEnv("MESHKIT_MAWS_PROBE_RECIPIENT");
const amount = process.env.MESHKIT_MAWS_PROBE_AMOUNT || "1";
const artifactPath = resolve(
  process.env.MESHKIT_MAWS_LIVE_PROOF_ARTIFACT || "artifacts/maroo-testnet/maws-live-transfer-proof.json",
);
const clientToken = process.env.MESHKIT_MAWS_PROBE_CLIENT_TOKEN || `meshkit-live-probe-${Date.now()}`;

const request = {
  schema_version: "meshkit-maws-transfer-send-bridge/v1",
  tool: "transfer.send",
  arguments: {
    agentId,
    to: recipient,
    amount,
    clientToken,
    memo: "MeshKit DailyMart live OKRW probe",
  },
  meshkit: {
    request_type: "meshkit_okrw_execution",
    source: "scripts/probe_maws_live_transfer.mjs",
    objective: "DailyMart M-AWS maroo OKRW live proof",
  },
};

const startedAt = new Date().toISOString();
const response = await fetch(bridgeURL, {
  method: "POST",
  headers: {
    "content-type": "application/json",
    accept: "application/json",
    ...(process.env.MESHKIT_MAWS_AUTHORIZATION
      ? { authorization: process.env.MESHKIT_MAWS_AUTHORIZATION }
      : {}),
  },
  body: JSON.stringify(request),
});
const responseText = await response.text();
let responseJSON;
try {
  responseJSON = JSON.parse(responseText);
} catch {
  responseJSON = { ok: false, error: { code: "INVALID_JSON", message: responseText } };
}

const proof = {
  checkedAt: new Date().toISOString(),
  startedAt,
  bridgeURL,
  agentId,
  recipient,
  amount,
  clientToken,
  httpStatus: response.status,
  request,
  response: responseJSON,
  confirmed: isConfirmed(responseJSON),
  requiredConfirmedFields: [
    "txHash",
    "blockHash",
    "blockNumber",
    "confirmationCount",
    "confirmedAt",
    "explorerUrl",
  ],
};

if (!proof.confirmed) {
  proof.exitCondition = "BlockedByExternalChain";
  proof.blockerEvidence = {
    exitCondition: "BlockedByExternalChain",
    blockerType: responseJSON?.ok === false ? "payment_confirmation_unavailable" : "payment_confirmation_unavailable",
    operation: "M-AWS transfer.send live proof",
    message: "Live bridge did not return a confirmed maroo OKRW transfer proof.",
  };
}

await mkdir(dirname(artifactPath), { recursive: true });
await writeFile(artifactPath, JSON.stringify(proof, null, 2) + "\n");
console.log(`M-AWS live transfer proof artifact written: ${artifactPath}`);
if (!proof.confirmed) {
  process.exit(2);
}

function isConfirmed(payload) {
  const data = payload?.data;
  return Boolean(
    payload?.ok === true &&
      data?.status === "confirmed" &&
      data?.txHash &&
      data?.blockHash &&
      Number.isFinite(Number(data?.blockNumber)) &&
      Number(data?.blockNumber) > 0 &&
      Number.isFinite(Number(data?.confirmationCount)) &&
      Number(data?.confirmationCount) > 0 &&
      data?.confirmedAt &&
      data?.explorerUrl,
  );
}

function requiredEnv(name) {
  const value = process.env[name]?.trim();
  if (!value) {
    console.error(`${name} is required`);
    process.exit(2);
  }
  return value;
}
