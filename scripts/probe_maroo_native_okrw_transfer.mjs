#!/usr/bin/env node
import { mkdir, writeFile } from "node:fs/promises";
import { dirname, resolve } from "node:path";

const bridgeURL = requiredEnv("MESHKIT_MAROO_OKRW_TRANSFER_BRIDGE_URL");
const recipient = requiredEnv("MESHKIT_MAROO_OKRW_PROBE_RECIPIENT");
const amount = process.env.MESHKIT_MAROO_OKRW_PROBE_AMOUNT || "1";
const artifactPath = resolve(
  process.env.MESHKIT_MAROO_OKRW_LIVE_PROOF_ARTIFACT ||
    "artifacts/maroo-testnet/maroo-native-okrw-transfer-proof.json",
);
const clientToken = process.env.MESHKIT_MAROO_OKRW_PROBE_CLIENT_TOKEN || `meshkit-native-okrw-${Date.now()}`;

const request = {
  schema_version: "meshkit-maroo-native-okrw-transfer-bridge/v1",
  tool: "maroo.native_transfer",
  arguments: {
    to: recipient,
    amount,
    clientToken,
    memo: "MeshKit DailyMart native maroo OKRW probe",
  },
  meshkit: {
    request_type: "meshkit_okrw_execution",
    source: "scripts/probe_maroo_native_okrw_transfer.mjs",
    objective: "DailyMart direct maroo OKRW live proof",
  },
};

const startedAt = new Date().toISOString();
const response = await fetch(bridgeURL, {
  method: "POST",
  headers: {
    "content-type": "application/json",
    accept: "application/json",
    ...(process.env.MESHKIT_MAROO_OKRW_TRANSFER_AUTHORIZATION
      ? { authorization: process.env.MESHKIT_MAROO_OKRW_TRANSFER_AUTHORIZATION }
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
    blockerType: "payment_confirmation_unavailable",
    operation: "maroo native OKRW transfer live proof",
    message: "Native maroo OKRW bridge did not return a confirmed testnet transfer proof.",
  };
}

await mkdir(dirname(artifactPath), { recursive: true });
await writeFile(artifactPath, JSON.stringify(proof, null, 2) + "\n");
console.log(`maroo native OKRW transfer proof artifact written: ${artifactPath}`);
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
