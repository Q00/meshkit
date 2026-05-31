#!/usr/bin/env node
import { mkdir, readFile, writeFile } from "node:fs/promises";
import { existsSync } from "node:fs";
import { dirname, resolve } from "node:path";

const proofPath = resolve(
  process.env.MESHKIT_MAROO_OKRW_LIVE_PROOF_ARTIFACT ||
    "artifacts/maroo-testnet/maroo-native-okrw-transfer-proof.json",
);
const artifactPath = resolve(
  process.env.MESHKIT_MAROO_OKRW_PROOF_VERIFICATION_ARTIFACT ||
    "artifacts/maroo-testnet/maroo-native-okrw-proof-verification.json",
);
const rpcURL = process.env.MESHKIT_MAROO_RPC_URL || "https://rpc-testnet.maroo.io";

class MissingProofError extends Error {}

const verification = {
  checkedAt: new Date().toISOString(),
  provider: "maroo",
  network: "maroo-testnet",
  proofPath,
  rpcURL,
  verified: false,
  checks: [],
};

try {
  if (!existsSync(proofPath)) {
    fail("proof artifact exists", "Proof artifact is missing.");
    throw new MissingProofError();
  } else {
    pass("proof artifact exists");
  }

  const proof = JSON.parse(await readFile(proofPath, "utf8"));
  const data = proof?.response?.data || {};
  const txHash = data.txHash || data.transactionHash;
  const explorerUrl = data.explorerUrl;

  check(Boolean(proof?.confirmed), "proof marked confirmed", "Proof artifact is not marked confirmed.");
  check(/^0x[a-fA-F0-9]{64}$/.test(txHash || ""), "txHash format", `Invalid txHash: ${txHash || "missing"}`);
  check(Boolean(data.blockHash), "blockHash present", "Proof response is missing blockHash.");
  check(Number(data.blockNumber) > 0, "blockNumber present", "Proof response is missing blockNumber.");
  check(Number(data.confirmationCount) > 0, "confirmationCount present", "Proof response is missing confirmationCount.");
  check(Boolean(data.confirmedAt), "confirmedAt present", "Proof response is missing confirmedAt.");
  check(Boolean(explorerUrl), "explorerUrl present", "Proof response is missing explorerUrl.");

  if (txHash) {
    const receipt = await rpc("eth_getTransactionReceipt", [txHash]);
    verification.rpcReceipt = receipt;
    const receiptData = receipt?.result || {};
    check(Boolean(receiptData?.transactionHash), "RPC receipt exists", "maroo RPC did not return a transaction receipt.");
    check(
      equalsHex(receiptData?.transactionHash, txHash),
      "RPC txHash matches proof",
      "maroo RPC receipt transactionHash does not match proof txHash.",
    );
    check(
      equalsHex(receiptData?.blockHash, data.blockHash),
      "RPC blockHash matches proof",
      "maroo RPC receipt blockHash does not match proof blockHash.",
    );
    check(
      Number.parseInt(receiptData?.blockNumber || "0x0", 16) === Number(data.blockNumber),
      "RPC blockNumber matches proof",
      "maroo RPC receipt blockNumber does not match proof blockNumber.",
    );
    check(receiptData?.status === "0x1", "RPC receipt succeeded", "maroo RPC receipt status is not success.");
  }

  if (explorerUrl) {
    const explorer = await fetch(explorerUrl, { redirect: "follow" });
    verification.explorer = {
      url: explorerUrl,
      httpStatus: explorer.status,
      ok: explorer.ok,
    };
    check(explorer.ok, "explorer URL resolves", `Explorer URL returned HTTP ${explorer.status}.`);
  }
} catch (error) {
  if (error instanceof MissingProofError) {
    // Missing proof is already captured as the primary verification failure.
  } else {
  fail("proof verification runtime", error?.message || String(error));
  }
}

verification.verified = verification.checks.every((item) => item.passed);
if (!verification.verified) {
  verification.exitCondition = "BlockedByExternalChain";
  verification.blockerEvidence = {
    exitCondition: "BlockedByExternalChain",
    blockerType: "payment_confirmation_unavailable",
    operation: "maroo native OKRW proof verification",
    message: "Confirmed proof artifact could not be verified against maroo RPC receipt and explorer evidence.",
  };
}

await mkdir(dirname(artifactPath), { recursive: true });
await writeFile(artifactPath, JSON.stringify(verification, null, 2) + "\n");
console.log(`maroo native OKRW proof verification artifact written: ${artifactPath}`);
if (!verification.verified) {
  process.exit(2);
}

async function rpc(method, params) {
  const response = await fetch(rpcURL, {
    method: "POST",
    headers: { "content-type": "application/json" },
    body: JSON.stringify({
      jsonrpc: "2.0",
      id: 1,
      method,
      params,
    }),
  });
  return response.json();
}

function check(condition, name, message) {
  if (condition) {
    pass(name);
  } else {
    fail(name, message);
  }
}

function pass(name) {
  verification.checks.push({ name, passed: true });
}

function fail(name, message) {
  verification.checks.push({ name, passed: false, message });
}

function equalsHex(left, right) {
  return typeof left === "string" && typeof right === "string" && left.toLowerCase() === right.toLowerCase();
}
