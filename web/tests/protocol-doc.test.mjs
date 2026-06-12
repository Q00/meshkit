import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import test from "node:test";

const repoRoot = new URL("../..", import.meta.url);

async function readRepoFile(path) {
  return readFile(new URL(path, repoRoot), "utf8");
}

test("ACP superapp protocol docs preserve required API and routing contracts", async () => {
  const doc = await readRepoFile("docs/meshkit-acp-superapp-protocol.md");

  for (const required of [
    "GET /api/acp/apps",
    "POST /api/preferences",
    "GET /api/preferences?query={text}",
    "POST /api/execute",
    "GET /api/settlements",
    "GET /api/superapp-state",
    "Agent Client Protocol",
    "scripts/verify_acp_agent_llm_toolcall.mjs",
    "OPENAI_API_KEY",
    "ocg/registry/",
    "registryMode",
    "registryFiles",
    "registryTrust",
    "signed-ocg-registry",
    "registryTrust.verifiedCount",
    "MESHKIT_ACP_REGISTRY_DIR",
    "fallback-fixture",
    "ocgAppId",
    "registrySource",
    "capabilities[].requiresPayment",
    "capabilities[].asset",
    "capabilities[].urlScheme",
    "capabilities[].inputSchema",
    "capabilities[].resultSchema",
    "registrySignatureVerification.status",
    "mintnotes://mesh/invoke",
    "dailymart://mesh/invoke",
    "OpenCapabilityGraph.acpRegistryDescriptors()",
    "AcpAppDescriptor",
    "app-to-app-url-scheme",
    "meshkit-ios-sample",
    "payment_proof_policy",
    "privacy_policy",
    "appliedPolicy.policyId",
    "appliedPolicy.sourceMemoryIds",
    "paymentProof=onchain-okrw-proof",
    "nonPaymentTransport=offchain-app-to-app-mcp",
    "payloadPrivacy=private-payload-offchain",
    "policySourceMemoryIds",
    "hippocampus-style consolidation",
    "filteredEvents",
    "droppedEvents",
    "droppedPreference",
    "consolidation",
    "internal-reflection-prompt",
    "assistant-echo-without-durable-signal",
    "duplicate-content",
    "route=onchain",
    "recordType=onchain-sim",
    "route=offchain",
    "recordType=app-to-app-url-scheme",
    "42 OKRW",
    "totalDebits",
    "totalCredits",
    "byCategory",
    "byCounterparty",
    "MESHKIT_SUPERAPP_DATA_DIR"
  ]) {
    assert.ok(doc.includes(required), `protocol doc missing ${required}`);
  }
});

test("Swift SDK exposes the ACP discovery projection used by the web superapp", async () => {
  const swift = await readRepoFile("meshkit-ios/Sources/MeshKit/OpenCapabilityGraph.swift");

  for (const required of [
    "public func acpRegistryDescriptors() -> [AcpAppDescriptor]",
    "public struct AcpAppDescriptor",
    "public struct AcpCapabilityDescriptor",
    'appId: "app.dailymart"',
    'ocgAppId: "ai.meshkit.sample.dailymart"',
    'self.routingHint = requiresPayment ? "onchain_payment" : "offchain_app_call"',
    'mcpTransport: "app-to-app-url-scheme"',
    'registrySource: "meshkit-ios-sample"'
  ]) {
    assert.ok(swift.includes(required), `Swift ACP projection missing ${required}`);
  }
});

test("generated ACP superapp seed remains checked in with acceptance criteria", async () => {
  const seed = await readRepoFile("docs/meshkit-acp-superapp.seed.yaml");

  for (const required of [
    "seed_a71e0827cbd6",
    "User-facing surface must include local web UI and local HTTP API/server",
    "GET /api/acp/apps returns HermesChat, MintNotes, DailyMart",
    "payment_proof_policy",
    "privacy_policy",
    "grocery.purchase_essentials",
    "notes.append_note",
    "GET /api/settlements returns only confirmed/verified/trusted on-chain settlement entries",
    "First web UI screen visibly shows Discovery, Memory, Route/Execution, and Ledger results"
  ]) {
    assert.ok(seed.includes(required), `seed artifact missing ${required}`);
  }
});

test("superapp UI exposes memory and execution controls on the first screen", async () => {
  const html = await readRepoFile("web/src/index.html");
  const main = await readRepoFile("web/src/main.js");

  for (const required of [
    'id="preference-form"',
    'id="preference-key"',
    'id="preference-value"',
    'id="execute-unpaid-button"',
    'id="execute-paid-button"',
    'id="execution-list"',
    'id="settlement-summary"',
    'id="settlement-list"'
  ]) {
    assert.ok(html.includes(required), `UI markup missing ${required}`);
  }

  for (const endpoint of ["/api/preferences", "/api/execute", "/api/superapp-state"]) {
    assert.ok(main.includes(endpoint), `main.js missing ${endpoint}`);
  }
});

test("live LLM ACP agent verifier is checked in with tool-call invariants", async () => {
  const verifier = await readRepoFile("scripts/verify_acp_agent_llm_toolcall.mjs");

  for (const required of [
    "/api/acp/apps",
    "/chat/completions",
    "tools",
    "tool_choice: \"auto\"",
    "remember_preference",
    "invoke__notes__append_note",
    "invoke__grocery__purchase_essentials",
    "get_settlement_ledger",
    "/api/preferences",
    "/api/execute",
    "/api/settlements",
    "mintnotes://mesh/invoke",
    "dailymart://mesh/invoke",
    "OPENAI_API_KEY"
  ]) {
    assert.ok(verifier.includes(required), `LLM ACP verifier missing ${required}`);
  }
});
