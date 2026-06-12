import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import test from "node:test";
import {
  ACP_SCHEMA_VERSION,
  discoverAcpApps,
  createAcpAppFromOcgManifest,
  createPreferenceMemory,
  consolidatePreferenceEvents,
  deriveRoutingPolicy,
  retrievePreferences,
  routeExecution,
  createSettlementLedger,
  createDemoSuperappState,
  executeAppToAppRequest,
  createSuperappState,
  stripRecalledMemoryContext
} from "../src/superapp.js";
import { loadAcpDiscovery, loadUnsignedAcpDiscovery } from "../src/acp-registry.js";

test("ACP discovery exposes app-to-app MCP capabilities with routing hints", () => {
  const apps = discoverAcpApps();
  const dailyMart = apps.find((app) => app.appId === "app.dailymart");

  assert.equal(apps.every((app) => app.schemaVersion === ACP_SCHEMA_VERSION), true);
  assert.ok(dailyMart);
  assert.equal(dailyMart.mcpTransport, "app-to-app-url-scheme");
  assert.equal(dailyMart.ocgAppId, "ai.meshkit.sample.dailymart");
  assert.equal(dailyMart.registrySource, "meshkit-ios-sample");
  assert.equal(dailyMart.capabilities[0].id, "grocery.purchase_essentials");
  assert.equal(dailyMart.capabilities[0].routingHint, "onchain_payment");
});

test("ACP discovery can be derived from existing OCG registry manifests", async () => {
  const mintManifest = JSON.parse(await readFile(new URL("../../ocg/registry/mint-notes.ocg.json", import.meta.url), "utf8"));
  const dailyManifest = JSON.parse(await readFile(new URL("../../ocg/registry/dailymart.ocg.json", import.meta.url), "utf8"));
  const mint = createAcpAppFromOcgManifest(mintManifest, {
    appId: "app.mint-notes",
    displayName: "MintNotes",
    bundleId: "ai.meshkit.sample.mintnotes"
  });
  const dailyMart = createAcpAppFromOcgManifest(dailyManifest, {
    appId: "app.dailymart",
    bundleId: "ai.meshkit.sample.dailymart"
  });

  assert.equal(mint.ocgAppId, "ai.meshkit.sample.notes");
  assert.equal(mint.capabilities[0].id, "notes.append_note");
  assert.equal(mint.capabilities[0].routingHint, "offchain_app_call");
  assert.deepEqual(mint.capabilities[0].inputSchema, ["note_ref", "text"]);
  assert.equal(dailyMart.ocgAppId, "ai.meshkit.sample.dailymart");
  assert.equal(dailyMart.capabilities[0].id, "grocery.purchase_essentials");
  assert.equal(dailyMart.capabilities[0].routingHint, "onchain_payment");
  assert.deepEqual(dailyMart.capabilities[0].inputSchema, ["items", "max_budget_krw", "delivery_window", "payment_method"]);

  const current = discoverAcpApps();
  assert.equal(current.find((app) => app.appId === "app.mint-notes").capabilities[0].id, mint.capabilities[0].id);
  assert.equal(current.find((app) => app.appId === "app.dailymart").capabilities[0].id, dailyMart.capabilities[0].id);
});

test("file-backed ACP discovery verifies signed OCG registry manifests and preserves Hermes fallback", async () => {
  const discovery = await loadAcpDiscovery({
    registryDir: new URL("../../ocg/registry", import.meta.url).pathname
  });

  assert.equal(discovery.registryMode, "signed-ocg-registry");
  assert.deepEqual(discovery.registryFiles, ["dailymart.signed.ocg.json", "mint-notes.signed.ocg.json"]);
  assert.equal(discovery.registryTrust.signed, true);
  assert.equal(discovery.registryTrust.verifiedCount, 2);
  assert.deepEqual(discovery.registryTrust.keyIds, ["ocg-registry-test-2026-05"]);
  assert.deepEqual(discovery.apps.map((app) => app.displayName), ["HermesChat", "MintNotes", "DailyMart"]);
  assert.equal(discovery.apps.find((app) => app.appId === "app.hermes-chat").registrySource, "local-fixture");
  assert.equal(discovery.apps.find((app) => app.appId === "app.mint-notes").registrySource, "signed-ocg-registry");
  assert.equal(discovery.apps.find((app) => app.appId === "app.mint-notes").capabilities[0].urlScheme, "mintnotes://mesh/invoke");
  assert.equal(discovery.apps.find((app) => app.appId === "app.dailymart").registrySignatureVerification.status, "verified");
  assert.equal(discovery.apps.find((app) => app.appId === "app.dailymart").capabilities[0].urlScheme, "dailymart://mesh/invoke");
  assert.equal(discovery.apps.find((app) => app.appId === "app.dailymart").capabilities[0].routingHint, "onchain_payment");
});

test("unsigned ACP discovery remains available as deterministic fallback", async () => {
  const discovery = await loadUnsignedAcpDiscovery({
    registryDir: new URL("../../ocg/registry", import.meta.url).pathname
  });

  assert.equal(discovery.registryMode, "ocg-registry");
  assert.equal(discovery.registryTrust.signed, false);
  assert.deepEqual(discovery.registryFiles, ["dailymart.ocg.json", "mint-notes.ocg.json"]);
});

test("preference memory promotes durable user preference events", () => {
  const memory = createPreferenceMemory([
    {
      id: "pref-1",
      role: "user",
      content: "User prefers on-chain payment proof for groceries.",
      signals: { userPreference: 1 }
    },
    {
      id: "note-1",
      role: "assistant",
      content: "Transient assistant echo.",
      signals: {}
    }
  ]);

  assert.equal(memory.workingMemory.length, 1);
  assert.deepEqual(memory.droppedEvents.map((event) => event.reason), ["assistant-echo-without-durable-signal"]);
  assert.deepEqual(memory.promotedMemory.map((entry) => entry.memoryId), ["pref-1"]);
  assert.equal(retrievePreferences(memory, "payment groceries")[0].memoryId, "pref-1");
  assert.equal(memory.promotedMemory[0].metadata.hippocampus.promoted, true);
  assert.equal(memory.promotedMemory[0].promotionReason, "hippocampus-filtered-durable-event");
  assert.deepEqual(Object.keys(memory.promotedMemory[0]).filter((key) => [
    "userId",
    "agentId",
    "memoryId",
    "key",
    "value",
    "source",
    "importance",
    "createdAt",
    "updatedAt",
    "lastAccessedAt",
    "promotedAt"
  ].includes(key)).sort(), [
    "agentId",
    "createdAt",
    "importance",
    "key",
    "lastAccessedAt",
    "memoryId",
    "promotedAt",
    "source",
    "updatedAt",
    "userId",
    "value"
  ]);
});

test("preference consolidation follows brain-style hippocampus filtering", () => {
  const withContext = [
    "<memory-context>",
    "Previously recalled implementation details that should not be re-saved.",
    "</memory-context>",
    "User prefers on-chain OKRW proof for agent payments."
  ].join("\n");
  const consolidation = consolidatePreferenceEvents([
    {
      id: "pref-context",
      key: "payment_proof_policy",
      role: "user",
      content: withContext,
      signals: { userPreference: 1 }
    },
    {
      id: "internal-1",
      key: "internal",
      role: "developer",
      content: "Developer-only implementation instruction.",
      signals: { projectRelevance: 1 }
    },
    {
      id: "reflection-1",
      key: "reflection",
      role: "user",
      content: "Review the conversation above and consider whether a skill should be saved or updated.",
      signals: { userPreference: 1 }
    },
    {
      id: "assistant-echo-1",
      key: "echo",
      role: "assistant",
      content: "User prefers on-chain OKRW proof for agent payments.",
      signals: {}
    },
    {
      id: "duplicate-1",
      key: "duplicate",
      role: "user",
      content: "User prefers on-chain OKRW proof for agent payments.",
      signals: { userPreference: 1 }
    },
    {
      id: "assistant-durable",
      key: "assistant_durable",
      role: "assistant",
      content: "Decision: keep payment proof on-chain and private payloads off-chain.",
      signals: { durable: 1, decision: 1 }
    }
  ]);

  assert.equal(stripRecalledMemoryContext(withContext), "User prefers on-chain OKRW proof for agent payments.");
  assert.deepEqual(consolidation.filteredEvents.map((event) => event.id), ["pref-context", "assistant-durable"]);
  assert.deepEqual(consolidation.promotedEvents.map((event) => event.id), ["pref-context", "assistant-durable"]);
  assert.deepEqual(consolidation.droppedEvents.map((event) => event.reason), [
    "internal-event",
    "internal-reflection-prompt",
    "assistant-echo-without-durable-signal",
    "duplicate-content"
  ]);

  const memory = createPreferenceMemory([
    {
      id: "pref-context",
      key: "payment_proof_policy",
      role: "user",
      content: withContext,
      signals: { userPreference: 1 }
    }
  ]);
  assert.equal(memory.workingMemory[0].content, "User prefers on-chain OKRW proof for agent payments.");
  assert.equal(memory.filteredEvents[0].recalledContextStripped, true);
  assert.equal(memory.consolidation.policy.includes("drop assistant echoes"), true);
});

test("execution router sends payments on-chain and non-payment MCP calls off-chain", () => {
  const apps = discoverAcpApps();
  const memory = createPreferenceMemory();
  const noteRoute = routeExecution({ apps, memory, capabilityId: "notes.append_note", amount: 0 });
  const groceryRoute = routeExecution({ apps, memory, capabilityId: "grocery.purchase_essentials", amount: 42 });

  assert.equal(noteRoute.route, "offchain");
  assert.equal(noteRoute.transport, "app-to-app-url-scheme");
  assert.equal(groceryRoute.route, "onchain");
  assert.equal(groceryRoute.transport, "maroo-testnet-okrw");
  assert.equal(groceryRoute.asset, "OKRW");
  assert.equal(groceryRoute.appliedPolicy.source, "preference-memory");
  assert.equal(groceryRoute.appliedPolicy.paymentProof, "onchain-okrw-proof");
  assert.equal(groceryRoute.appliedPolicy.payloadPrivacy, "private-payload-offchain");
  assert.deepEqual(groceryRoute.appliedPolicy.chainVisibleFields, ["signedRequestHash", "policyHash", "txHash", "settlementStatus"]);
  assert.equal(noteRoute.appliedPolicy.nonPaymentTransport, "offchain-app-to-app-mcp");
  assert.deepEqual(noteRoute.appliedPolicy.chainVisibleFields, []);
  assert.ok(groceryRoute.recalledPreferences.some((entry) => entry.content.includes("on-chain OKRW proof")));
});

test("routing policy is derived from durable preference memory", () => {
  const memory = createPreferenceMemory([
    {
      id: "payment-policy",
      key: "payment_proof_policy",
      role: "user",
      content: "agent payments use on-chain OKRW proof and non-payment calls stay off-chain",
      signals: { userPreference: 1, decision: 1 }
    },
    {
      id: "privacy-policy",
      key: "privacy_policy",
      role: "user",
      content: "cart/address/user/consent details stay off-chain",
      signals: { userPreference: 1, privacy: 1 }
    }
  ]);

  const paidPolicy = deriveRoutingPolicy({ memory, requiresPayment: true });
  const freePolicy = deriveRoutingPolicy({ memory, requiresPayment: false });

  assert.equal(paidPolicy.paymentProof, "onchain-okrw-proof");
  assert.equal(paidPolicy.payloadPrivacy, "private-payload-offchain");
  assert.deepEqual(paidPolicy.sourceMemoryIds, ["payment-policy", "privacy-policy"]);
  assert.equal(freePolicy.paymentProof, "no-payment-proof");
  assert.equal(freePolicy.nonPaymentTransport, "offchain-app-to-app-mcp");
});

test("settlement ledger aggregates chain-backed entries without off-chain calls", () => {
  const ledger = createSettlementLedger([
    {
      route: "offchain",
      requestId: "req-note",
      capabilityId: "notes.append_note",
      amount: 0
    },
    {
      route: "onchain",
      requestId: "req-pay",
      capabilityId: "grocery.purchase_essentials",
      amount: 12.5,
      status: "confirmed",
      txHash: "0xabc123"
    }
  ]);

  assert.equal(ledger.entries.length, 1);
  assert.equal(ledger.entries[0].requestId, "req-pay");
  assert.equal(ledger.entries[0].direction, "debit");
  assert.equal(ledger.entries[0].category, "groceries");
  assert.equal(ledger.entries[0].counterparty, "DailyMart");
  assert.equal(ledger.summary.totalConfirmed, 12.5);
  assert.equal(ledger.summary.totalDebits, 12.5);
  assert.equal(ledger.summary.totalCredits, 0);
  assert.deepEqual(ledger.summary.byCategory, { groceries: 12.5 });
  assert.deepEqual(ledger.summary.byCounterparty, { DailyMart: 12.5 });
});

test("demo superapp state includes discovery, memory, routing, and settlement surfaces", () => {
  const state = createDemoSuperappState();

  assert.equal(state.apps.length >= 3, true);
  assert.equal(state.memory.promotedMemory.length >= 2, true);
  assert.deepEqual(state.routing.map((route) => route.route), ["offchain", "onchain"]);
  assert.equal(state.settlementLedger.entries.length >= 1, true);
});

test("executeAppToAppRequest creates deterministic on-chain and off-chain records", () => {
  const apps = discoverAcpApps();
  const memory = createPreferenceMemory();
  const paid = executeAppToAppRequest({
    apps,
    memory,
    capabilityId: "grocery.purchase_essentials",
    amount: 42,
    requestId: "req-paid"
  });
  const unpaid = executeAppToAppRequest({
    apps,
    memory,
    capabilityId: "notes.append_note",
    amount: 0,
    requestId: "req-note"
  });

  assert.equal(paid.routeDecision.route, "onchain");
  assert.equal(paid.routeDecision.appliedPolicy.paymentProof, "onchain-okrw-proof");
  assert.equal(paid.transactionRecord.recordType, "onchain-sim");
  assert.match(paid.transactionRecord.txHash, /^0x[0-9a-f]{64}$/);
  assert.equal(paid.transactionRecord.appliedPolicy.payloadPrivacy, "private-payload-offchain");
  assert.deepEqual(paid.transactionRecord.policySourceMemoryIds, ["pref-payment-1", "pref-privacy-1"]);
  assert.equal(unpaid.routeDecision.route, "offchain");
  assert.equal(unpaid.transactionRecord.recordType, "app-to-app-url-scheme");
  assert.equal(unpaid.transactionRecord.txHash, "");
});

test("createSuperappState projects stored records into on-chain-only ledger totals", () => {
  const paid = executeAppToAppRequest({
    capabilityId: "grocery.purchase_essentials",
    amount: 42,
    requestId: "req-paid"
  }).transactionRecord;
  const unpaid = executeAppToAppRequest({
    capabilityId: "notes.append_note",
    amount: 0,
    requestId: "req-note"
  }).transactionRecord;
  const state = createSuperappState({
    executionRecords: [paid, unpaid]
  });

  assert.deepEqual(state.executionRecords.map((record) => record.route), ["onchain", "offchain"]);
  assert.deepEqual(state.settlementLedger.entries.map((entry) => entry.requestId), ["req-paid"]);
  assert.equal(state.settlementLedger.summary.totalConfirmed, 42);
  assert.deepEqual(state.settlementLedger.summary.byApp, { "app.dailymart": 42 });
  assert.deepEqual(state.settlementLedger.summary.byStatus, { confirmed: 42 });
  assert.equal(state.settlementLedger.entries[0].paymentProof, "onchain-okrw-proof");
  assert.equal(state.settlementLedger.entries[0].payloadPrivacy, "private-payload-offchain");
});
