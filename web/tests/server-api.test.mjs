import assert from "node:assert/strict";
import { spawn } from "node:child_process";
import { mkdtemp, rm } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import test from "node:test";

async function waitForServer(baseUrl, processOutput) {
  const deadline = Date.now() + 5000;
  let lastError = null;
  while (Date.now() < deadline) {
    try {
      const response = await fetch(`${baseUrl}/api/acp/apps`);
      if (response.ok) return;
      lastError = new Error(`HTTP ${response.status}`);
    } catch (error) {
      lastError = error;
      await new Promise((resolve) => setTimeout(resolve, 100));
    }
  }
  throw new Error(`server did not start: ${lastError?.message || "unknown"}\n${processOutput.join("")}`);
}

async function withServer(fn) {
  const dataDir = await mkdtemp(join(tmpdir(), "meshkit-superapp-api-"));
  const port = 48000 + Math.floor(Math.random() * 1000);
  const output = [];
  const child = spawn(process.execPath, ["server.mjs"], {
    cwd: new URL("..", import.meta.url),
    env: {
      ...process.env,
      PORT: String(port),
      MESHKIT_SUPERAPP_DATA_DIR: dataDir
    },
    stdio: ["ignore", "pipe", "pipe"]
  });
  child.stdout.on("data", (chunk) => output.push(chunk.toString()));
  child.stderr.on("data", (chunk) => output.push(chunk.toString()));

  try {
    const baseUrl = `http://127.0.0.1:${port}`;
    await waitForServer(baseUrl, output);
    await fn(baseUrl);
  } finally {
    child.kill("SIGTERM");
    await new Promise((resolve) => child.once("exit", resolve));
    await rm(dataDir, { recursive: true, force: true });
  }
}

async function getJson(url) {
  const response = await fetch(url);
  assert.equal(response.ok, true, `${url} returned ${response.status}`);
  return response.json();
}

async function postJson(url, body) {
  const response = await fetch(url, {
    method: "POST",
    headers: { "content-type": "application/json" },
    body: JSON.stringify(body)
  });
  return {
    status: response.status,
    body: await response.json()
  };
}

test("local API supports discovery, preference storage, execution routing, and settlements", async () => {
  await withServer(async (baseUrl) => {
    const discovery = await getJson(`${baseUrl}/api/acp/apps`);
    assert.equal(discovery.registryMode, "signed-ocg-registry");
    assert.deepEqual(discovery.registryFiles, ["dailymart.signed.ocg.json", "mint-notes.signed.ocg.json"]);
    assert.equal(discovery.registryTrust.verifiedCount, 2);
    assert.deepEqual(discovery.apps.map((app) => app.displayName), ["HermesChat", "MintNotes", "DailyMart"]);
    assert.equal(discovery.apps.find((app) => app.appId === "app.dailymart").registrySource, "signed-ocg-registry");
    assert.equal(discovery.apps.find((app) => app.appId === "app.dailymart").registrySignatureVerification.status, "verified");

    const preference = await postJson(`${baseUrl}/api/preferences`, {
      userId: "local-user",
      agentId: "agent.meshkit-superapp",
      key: "privacy_policy",
      value: "cart/address/user/consent details stay off-chain",
      source: "server-api-test"
    });
    assert.equal(preference.status, 201);
    assert.equal(preference.body.preference.key, "privacy_policy");
    assert.equal(preference.body.preference.source, "server-api-test");

    const filteredPreference = await postJson(`${baseUrl}/api/preferences`, {
      key: "reflection_prompt",
      value: "Review the conversation above and consider whether a skill should be saved or updated.",
      source: "server-api-test"
    });
    assert.equal(filteredPreference.status, 201);
    assert.equal(filteredPreference.body.preference, null);
    assert.equal(filteredPreference.body.droppedPreference.reason, "internal-reflection-prompt");
    assert.equal(filteredPreference.body.state.memory.consolidation.droppedCount, 1);

    const paid = await postJson(`${baseUrl}/api/execute`, {
      capabilityId: "grocery.purchase_essentials",
      amount: 42,
      requestId: "req-paid-api-test"
    });
    assert.equal(paid.status, 201);
    assert.equal(paid.body.routeDecision.route, "onchain");
    assert.equal(paid.body.routeDecision.appId, "app.dailymart");
    assert.equal(paid.body.routeDecision.appliedPolicy.paymentProof, "onchain-okrw-proof");
    assert.equal(paid.body.routeDecision.appliedPolicy.payloadPrivacy, "private-payload-offchain");
    assert.equal(paid.body.transactionRecord.recordType, "onchain-sim");
    assert.match(paid.body.transactionRecord.txHash, /^0x[0-9a-f]{64}$/);
    assert.deepEqual(paid.body.transactionRecord.policySourceMemoryIds, ["pref-payment-1", "pref-privacy-1"]);

    const unpaid = await postJson(`${baseUrl}/api/execute`, {
      capabilityId: "notes.append_note",
      amount: 0,
      requestId: "req-note-api-test"
    });
    assert.equal(unpaid.status, 201);
    assert.equal(unpaid.body.routeDecision.route, "offchain");
    assert.equal(unpaid.body.routeDecision.appliedPolicy.nonPaymentTransport, "offchain-app-to-app-mcp");
    assert.equal(unpaid.body.transactionRecord.txHash, "");

    const settlements = await getJson(`${baseUrl}/api/settlements`);
    assert.deepEqual(settlements.settlementLedger.entries.map((entry) => entry.requestId), ["req-paid-api-test"]);
    assert.equal(settlements.settlementLedger.entries[0].category, "groceries");
    assert.equal(settlements.settlementLedger.entries[0].counterparty, "DailyMart");
    assert.equal(settlements.settlementLedger.entries[0].paymentProof, "onchain-okrw-proof");
    assert.equal(settlements.settlementLedger.entries[0].payloadPrivacy, "private-payload-offchain");
    assert.equal(settlements.settlementLedger.summary.totalConfirmed, 42);
    assert.equal(settlements.settlementLedger.summary.totalDebits, 42);
    assert.deepEqual(settlements.settlementLedger.summary.byCategory, { groceries: 42 });

    const state = await getJson(`${baseUrl}/api/superapp-state`);
    assert.equal(state.acpDiscovery.registryMode, "signed-ocg-registry");
    assert.equal(state.acpDiscovery.registryTrust.verifiedCount, 2);
    assert.equal(state.apps.find((app) => app.appId === "app.mint-notes").registrySource, "signed-ocg-registry");

    const invalid = await postJson(`${baseUrl}/api/execute`, {
      capabilityId: "missing.capability",
      amount: 1
    });
    assert.equal(invalid.status, 400);
    assert.match(invalid.body.message, /Capability not found/);
  });
});
