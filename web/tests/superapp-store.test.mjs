import assert from "node:assert/strict";
import { mkdtemp, rm } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import test from "node:test";
import {
  executePersistentRequest,
  queryPreferences,
  readPersistentSuperappState,
  upsertPreference
} from "../src/superapp-store.js";

async function withTempStore(fn) {
  const dir = await mkdtemp(join(tmpdir(), "meshkit-superapp-store-"));
  try {
    await fn(dir);
  } finally {
    await rm(dir, { recursive: true, force: true });
  }
}

test("persistent preference store upserts and retrieves brain-style memory fields", async () => {
  await withTempStore(async (dir) => {
    const result = await upsertPreference(dir, {
      userId: "user-local",
      agentId: "agent-local",
      key: "payment_proof_policy",
      value: "agent payments use on-chain OKRW proof and non-payment calls stay off-chain",
      source: "test"
    });
    const preferences = await queryPreferences(dir, "payment OKRW", 3);

    assert.equal(result.preference.key, "payment_proof_policy");
    assert.equal(result.preference.userId, "user-local");
    assert.equal(result.preference.agentId, "agent-local");
    assert.equal(result.preference.source, "test");
    assert.ok(result.preference.promotedAt);
    assert.equal(preferences[0].key, "payment_proof_policy");
  });
});

test("persistent preference upsert preserves the stable memory identity", async () => {
  await withTempStore(async (dir) => {
    const first = await upsertPreference(dir, {
      userId: "user-local",
      agentId: "agent-local",
      key: "privacy_policy",
      value: "cart/address/user/consent details stay off-chain",
      source: "first-write"
    });
    const updated = await upsertPreference(dir, {
      userId: "user-local",
      agentId: "agent-local",
      key: "privacy_policy",
      value: "cart/address/user/consent details stay off-chain for settlement privacy",
      source: "second-write"
    });
    const state = await readPersistentSuperappState(dir);
    const privacyMemories = state.memory.promotedMemory.filter((entry) =>
      entry.key === "privacy_policy" && entry.userId === "user-local" && entry.agentId === "agent-local"
    );

    assert.equal(updated.preference.memoryId, first.preference.memoryId);
    assert.equal(updated.preference.source, "second-write");
    assert.deepEqual(privacyMemories.map((entry) => entry.memoryId), [first.preference.memoryId]);
  });
});

test("persistent execution store records paid on-chain and unpaid off-chain routes", async () => {
  await withTempStore(async (dir) => {
    const paid = await executePersistentRequest(dir, {
      capabilityId: "grocery.purchase_essentials",
      amount: 42,
      requestId: "req-paid"
    });
    const unpaid = await executePersistentRequest(dir, {
      capabilityId: "notes.append_note",
      amount: 0,
      requestId: "req-note"
    });
    const state = await readPersistentSuperappState(dir);

    assert.equal(paid.routeDecision.route, "onchain");
    assert.match(paid.transactionRecord.txHash, /^0x[0-9a-f]{64}$/);
    assert.equal(unpaid.routeDecision.route, "offchain");
    assert.equal(unpaid.transactionRecord.txHash, "");
    assert.deepEqual(state.executionRecords.map((record) => record.requestId), ["req-paid", "req-note"]);
    assert.deepEqual(state.settlementLedger.entries.map((entry) => entry.requestId), ["req-paid"]);
    assert.equal(state.settlementLedger.summary.totalConfirmed, 42);
  });
});

test("persistent execution store serializes concurrent paid and unpaid writes", async () => {
  await withTempStore(async (dir) => {
    const [paid, unpaid] = await Promise.all([
      executePersistentRequest(dir, {
        capabilityId: "grocery.purchase_essentials",
        amount: 42,
        requestId: "req-concurrent-paid"
      }),
      executePersistentRequest(dir, {
        capabilityId: "notes.append_note",
        amount: 0,
        requestId: "req-concurrent-unpaid"
      })
    ]);
    const state = await readPersistentSuperappState(dir);

    assert.equal(paid.routeDecision.route, "onchain");
    assert.equal(unpaid.routeDecision.route, "offchain");
    assert.deepEqual(
      state.executionRecords.map((record) => record.requestId).sort(),
      ["req-concurrent-paid", "req-concurrent-unpaid"]
    );
    assert.deepEqual(state.settlementLedger.entries.map((entry) => entry.requestId), ["req-concurrent-paid"]);
    assert.equal(state.settlementLedger.summary.totalConfirmed, 42);
  });
});

test("persistent execution store rejects invalid inputs", async () => {
  await withTempStore(async (dir) => {
    await assert.rejects(
      () => executePersistentRequest(dir, { capabilityId: "missing.capability", amount: 1 }),
      /Capability not found/
    );
    await assert.rejects(
      () => executePersistentRequest(dir, { capabilityId: "notes.append_note", amount: -1 }),
      /amount must be a non-negative number/
    );
  });
});
