#!/usr/bin/env node
import assert from "node:assert/strict";

const baseUrl = process.env.MESHKIT_SUPERAPP_BASE_URL || "http://127.0.0.1:4173";
const openaiModel = process.env.OPENAI_MODEL || "gpt-5.4-mini";

async function requestJSON(path, options = {}) {
  const response = await fetch(`${baseUrl}${path}`, {
    headers: {
      "content-type": "application/json",
      ...(options.headers || {})
    },
    ...options
  });
  const payload = await response.json();
  if (!response.ok) {
    throw new Error(`${path} returned HTTP ${response.status}: ${payload.message || payload.error || JSON.stringify(payload)}`);
  }
  return payload;
}

async function chat(messages) {
  return requestJSON("/api/agent-chat", {
    method: "POST",
    body: JSON.stringify({ messages })
  });
}

const discovery = await requestJSON("/api/acp/apps");
assert.equal(discovery.registryMode, "signed-ocg-registry");
assert.equal(discovery.registryTrust.verifiedCount, 2);

const userTurns = [
  "What can you do as the MeshKit superapp agent? Keep it concise.",
  "Which discovered ACP apps are available right now? Do not invent apps.",
  "Remember this durable preference: I prefer low-sugar groceries.",
  "Remember this durable payment requirement: paid purchases need on-chain OKRW proof.",
  "Before executing anything, tell me how you will keep notes off-chain and paid purchases on-chain.",
  "Append a MintNotes note saying \"buy bananas first\".",
  "Buy DailyMart essentials for 42 OKRW using my low-sugar grocery preference.",
  "Read the settlement ledger and tell me the payment proof for the DailyMart purchase.",
  "Summarize the executed note and grocery purchase in one short answer.",
  "Final check: what preferences do you remember, what app calls executed, and what settlement evidence exists?"
];

const messages = [];
const turns = [];
const allToolResults = [];

for (const user of userTurns) {
  messages.push({ role: "user", content: user });
  const response = await chat(messages);
  assert.equal(response.schemaVersion, "meshkit-agent-chat-response/v1");
  assert.equal(response.assistant?.role, "assistant");
  assert.ok(response.assistant?.content?.trim(), `assistant response was empty for user turn: ${user}`);
  turns.push({ user, assistant: response.assistant.content });
  for (const toolResult of response.toolResults || []) {
    allToolResults.push({ turn: turns.length, ...toolResult });
  }
  messages.push(response.assistant);
}

assert.ok(turns.length >= 10, `expected at least 10 conversation turns, got ${turns.length}`);
assert.match(turns[0].assistant, /MintNotes|DailyMart|HermesChat|capabilit/i);

const toolResults = allToolResults;
const toolNames = toolResults.map((entry) => entry.name);
assert.ok(toolNames.filter((name) => name === "remember_preference").length >= 2, `expected two remember_preference calls, got ${toolNames.join(", ")}`);
assert.ok(
  toolResults.filter((entry) => entry.name === "remember_preference" && entry.result?.remembered === true).length >= 2,
  `expected two remembered preferences, got ${JSON.stringify(toolResults.filter((entry) => entry.name === "remember_preference"))}`
);
assert.ok(toolNames.includes("invoke__notes__append_note"), `missing notes tool: ${toolNames.join(", ")}`);
assert.ok(toolNames.includes("invoke__grocery__purchase_essentials"), `missing grocery tool: ${toolNames.join(", ")}`);
assert.ok(toolNames.includes("get_settlement_ledger"), `missing settlement tool: ${toolNames.join(", ")}`);

const note = toolResults.find((entry) => entry.name === "invoke__notes__append_note")?.result;
const grocery = toolResults.find((entry) => entry.name === "invoke__grocery__purchase_essentials")?.result;
const ledgers = toolResults.filter((entry) => entry.name === "get_settlement_ledger").map((entry) => entry.result?.settlementLedger).filter(Boolean);
const ledger = ledgers.at(-1);
assert.equal(note?.route, "offchain");
assert.equal(note?.noteText, "buy bananas first");
assert.equal(grocery?.route, "onchain");
assert.equal(grocery?.status, "confirmed");
assert.equal(grocery?.budgetOkrw, 42);
assert.equal(ledger?.summary?.totalConfirmed, 42);
assert.match(turns.at(-1).assistant, /buy bananas first|note/i);
assert.match(turns.at(-1).assistant, /DailyMart|42 OKRW|grocery/i);
assert.match(turns.at(-1).assistant, /on-chain|onchain|settlement|proof|OKRW/i);

console.log(JSON.stringify({
  ok: true,
  model: openaiModel,
  registryMode: discovery.registryMode,
  verifiedCount: discovery.registryTrust.verifiedCount,
  turnCount: turns.length,
  turns,
  toolCalls: toolResults,
  settlementSummary: ledger.summary
}, null, 2));
