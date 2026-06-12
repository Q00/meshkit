import assert from "node:assert/strict";
import test from "node:test";
import {
  fetchAcpApps,
  executeDailyMartOnchain,
  executeMintNotesOffchain,
  fetchSuperappState,
  savePreference,
  sendAgentChat,
  summarizeSuperappState
} from "../src/api.js";
import { apiBase, configureApiPlatform } from "../src/config.js";

function installFetch(handler) {
  const previous = globalThis.fetch;
  const calls = [];
  globalThis.fetch = async (url, options = {}) => {
    calls.push({ url, options });
    const body = handler(url, options);
    return {
      ok: body.ok !== false,
      status: body.status || 200,
      async json() {
        return body.payload;
      }
    };
  };
  return () => {
    globalThis.fetch = previous;
    return calls;
  };
}

test("RN API client calls Go superapp contract endpoints", async () => {
  const restore = installFetch((url, options) => {
    if (url.endsWith("/api/acp/apps")) {
      return { payload: {
        schemaVersion: "meshkit-acp-discovery-response/v1",
        registryMode: "signed-ocg-registry",
        registryTrust: { signed: true, verifiedCount: 2 },
        apps: [
          { appId: "app.hermes-chat", displayName: "HermesChat", capabilities: [{ id: "agent.plan_trip", routingHint: "offchain_app_call", urlScheme: "hermeschat://mesh/invoke" }] },
          { appId: "app.mint-notes", displayName: "MintNotes", capabilities: [{ id: "notes.append_note", routingHint: "offchain_app_call", urlScheme: "mintnotes://mesh/invoke" }] },
          { appId: "app.dailymart", displayName: "DailyMart", capabilities: [{ id: "grocery.purchase_essentials", routingHint: "onchain_payment", urlScheme: "dailymart://mesh/invoke" }] }
        ]
      } };
    }
    if (url.endsWith("/api/superapp-state")) {
      return { payload: {
        apps: [{ appId: "app.dailymart" }, { appId: "app.mint-notes" }, { appId: "app.hermes-chat" }],
        memory: { promotedMemory: [{ memoryId: "pref-payment-1" }] },
        executionRecords: [{ requestId: "req-paid" }, { requestId: "req-note" }],
        settlementLedger: { entries: [{ requestId: "req-paid" }], summary: { totalConfirmed: 42, totalDebits: 42, asset: "OKRW" } }
      } };
    }
    if (url.endsWith("/api/preferences")) {
      const request = JSON.parse(options.body);
      assert.equal(request.key, "payment_proof_policy");
      assert.equal(request.agentId, "agent.meshkit-superapp");
      return { status: 201, payload: { preference: { key: request.key, memoryId: "payment_proof_policy" }, state: {} } };
    }
    if (url.endsWith("/api/execute")) {
      const request = JSON.parse(options.body);
      const paid = request.capabilityId === "grocery.purchase_essentials";
      return { status: 201, payload: {
        routeDecision: { route: paid ? "onchain" : "offchain", appId: paid ? "app.dailymart" : "app.mint-notes" },
        transactionRecord: { requestId: request.requestId, status: paid ? "confirmed" : "submitted", recordType: paid ? "onchain-sim" : "app-to-app-url-scheme", txHash: paid ? "0xabc" : "" }
      } };
    }
    if (url.endsWith("/api/agent-chat")) {
      const request = JSON.parse(options.body);
      assert.equal(request.messages[0].role, "user");
      return { payload: {
        schemaVersion: "meshkit-agent-chat-response/v1",
        assistant: { role: "assistant", content: "MintNotes note saved and DailyMart settled 42 OKRW." },
        toolResults: [{ name: "invoke__notes__append_note" }],
        state: { settlementLedger: { entries: [], summary: {} } }
      } };
    }
    throw new Error(`unexpected url ${url}`);
  });

  const discovery = await fetchAcpApps();
  assert.equal(discovery.registryMode, "signed-ocg-registry");
  assert.equal(discovery.registryTrust.verifiedCount, 2);
  assert.deepEqual(discovery.apps.map((app) => app.appId), ["app.hermes-chat", "app.mint-notes", "app.dailymart"]);
  assert.equal(discovery.apps.find((app) => app.appId === "app.mint-notes").capabilities[0].urlScheme, "mintnotes://mesh/invoke");
  assert.equal(discovery.apps.find((app) => app.appId === "app.dailymart").capabilities[0].routingHint, "onchain_payment");

  const state = await fetchSuperappState();
  assert.deepEqual(summarizeSuperappState(state), {
    appCount: 3,
    promotedMemoryCount: 1,
    executionCount: 2,
    settlementCount: 1,
    totalConfirmed: 42,
    totalDebits: 42,
    asset: "OKRW"
  });
  await savePreference({ key: "payment_proof_policy", value: "agent payments use on-chain OKRW proof" });
  const chat = await sendAgentChat({ messages: [{ role: "user", content: "Append a note and buy groceries." }] });
  const paid = await executeDailyMartOnchain();
  const unpaid = await executeMintNotesOffchain();
  const calls = restore();

  assert.match(chat.assistant.content, /DailyMart/);
  assert.equal(paid.routeDecision.route, "onchain");
  assert.equal(unpaid.routeDecision.route, "offchain");
  assert.match(calls.find((call) => call.url.endsWith("/api/execute")).options.body, /req-rn-dailymart-/);
  assert.equal(calls.filter((call) => call.url.endsWith("/api/acp/apps")).length, 1);
  assert.equal(calls.filter((call) => call.url.endsWith("/api/execute")).length, 2);
  assert.equal(calls.filter((call) => call.url.endsWith("/api/agent-chat")).length, 1);
});

test("RN API client surfaces Go error payloads and tolerates empty summaries", async () => {
  const restore = installFetch((url) => {
    if (url.endsWith("/api/superapp-state")) {
      return { ok: false, status: 413, payload: { message: "request body exceeds 1 MiB limit" } };
    }
    throw new Error(`unexpected url ${url}`);
  });

  await assert.rejects(fetchSuperappState(), /1 MiB/);
  assert.deepEqual(summarizeSuperappState(null), {
    appCount: 0,
    promotedMemoryCount: 0,
    executionCount: 0,
    settlementCount: 0,
    totalConfirmed: 0,
    totalDebits: 0,
    asset: "OKRW"
  });
  restore();
});

test("RN API base is platform-aware and still supports explicit runtime override", () => {
  const previousBase = globalThis.MESHKIT_SUPERAPP_API_BASE;
  delete globalThis.MESHKIT_SUPERAPP_API_BASE;
  configureApiPlatform("ios");
  assert.equal(apiBase(), "http://127.0.0.1:4173");
  configureApiPlatform("android");
  assert.equal(apiBase(), "http://10.0.2.2:4173");
  assert.equal(apiBase("unknown"), "http://127.0.0.1:4173");

  globalThis.MESHKIT_SUPERAPP_API_BASE = "http://192.168.1.20:4173";
  assert.equal(apiBase("android"), "http://192.168.1.20:4173");
  if (previousBase === undefined) {
    delete globalThis.MESHKIT_SUPERAPP_API_BASE;
  } else {
    globalThis.MESHKIT_SUPERAPP_API_BASE = previousBase;
  }
  configureApiPlatform("default");
});
