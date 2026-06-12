#!/usr/bin/env node
import assert from "node:assert/strict";

const baseUrl = process.env.MESHKIT_SUPERAPP_BASE_URL || "http://127.0.0.1:4173";
const openaiBaseUrl = (process.env.OPENAI_BASE_URL || "https://api.openai.com/v1").replace(/\/$/, "");
const openaiModel = process.env.OPENAI_MODEL || "gpt-5.4-mini";
const apiKey = process.env.OPENAI_API_KEY;
const defaultUserPrompt = "What can you do as this superapp agent? Also remember that I want low-sugar groceries and on-chain OKRW proof for paid purchases. Then append a note saying 'buy bananas first' and buy the DailyMart essentials for 42 OKRW. Tell me what happened.";
const userPrompt = process.env.ACP_AGENT_USER_PROMPT || defaultUserPrompt;
const expectedNoteText = quotedNoteText(userPrompt);

if (!apiKey) {
  throw new Error("OPENAI_API_KEY is required for the live ACP agent LLM tool-call verifier.");
}

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

async function openaiChat(messages, tools) {
  const response = await fetch(`${openaiBaseUrl}/chat/completions`, {
    method: "POST",
    headers: {
      "authorization": `Bearer ${apiKey}`,
      "content-type": "application/json"
    },
    body: JSON.stringify({
      model: openaiModel,
      temperature: 0,
      messages,
      tools,
      tool_choice: "auto"
    })
  });
  const payload = await response.json();
  if (!response.ok) {
    throw new Error(`OpenAI chat/completions returned HTTP ${response.status}: ${payload.error?.message || JSON.stringify(payload)}`);
  }
  const message = payload.choices?.[0]?.message;
  if (!message) {
    throw new Error(`OpenAI response did not include a message: ${JSON.stringify(payload)}`);
  }
  return message;
}

function quotedNoteText(prompt) {
  const match = prompt.match(/note\s+saying\s+['"]([^'"]+)['"]/i) || prompt.match(/['"]([^'"]+)['"]\s*(?:as|to)?\s*(?:a\s+)?note/i);
  return match?.[1] || "";
}

function capabilityParameters(capability) {
  const properties = {
    amount: {
      type: "number",
      description: capability.requiresPayment ? "Payment amount. Use 42 for the DailyMart demo purchase." : "Must be 0 for non-payment capabilities."
    },
    userSummary: {
      type: "string",
      description: "Short user-facing reason for this invocation."
    }
  };
  const required = ["amount", "userSummary"];

  if (capability.id === "notes.append_note") {
    properties.noteText = {
      type: "string",
      description: expectedNoteText ? `Exact note text to append. Must be exactly: ${expectedNoteText}` : "Exact note text to append."
    };
    properties.noteRef = {
      type: "string",
      description: "Stable local note reference for the target note app."
    };
    required.push("noteText");
  }

  if (capability.id === "grocery.purchase_essentials") {
    properties.items = {
      type: "array",
      items: { type: "string" },
      description: "Grocery items or essentials requested by the user."
    };
    properties.budgetOkrw = {
      type: "number",
      description: "Maximum OKRW budget for the purchase."
    };
    required.push("items", "budgetOkrw");
  }

  return {
    type: "object",
    additionalProperties: false,
    properties,
    required
  };
}

function toolFromCapability(app, capability) {
  return {
    type: "function",
    function: {
      name: `invoke__${capability.id.replaceAll(".", "__")}`,
      description: [
        `Invoke discovered ACP capability ${capability.id} on ${app.displayName}.`,
        `appId=${app.appId}; acpEndpoint=${app.acpEndpoint}; transport=${app.mcpTransport}; urlScheme=${capability.urlScheme}; routingHint=${capability.routingHint}.`,
        capability.requiresPayment ? `Requires payment in ${capability.asset || "OKRW"}.` : "Does not require payment."
      ].join(" "),
      parameters: capabilityParameters(capability)
    }
  };
}

function capabilityTools(discovery) {
  return discovery.apps.flatMap((app) =>
    app.capabilities.map((capability) => toolFromCapability(app, capability))
  );
}

function supportTools() {
  return [
    {
      type: "function",
      function: {
        name: "remember_preference",
        description: "Save one durable user preference before invoking apps. Call this separately for distinct preferences.",
        parameters: {
          type: "object",
          additionalProperties: false,
          properties: {
            key: { type: "string" },
            value: { type: "string" }
          },
          required: ["key", "value"]
        }
      }
    },
    {
      type: "function",
      function: {
        name: "get_settlement_ledger",
        description: "Read the current on-chain-only settlement ledger after executing paid app calls.",
        parameters: {
          type: "object",
          additionalProperties: false,
          properties: {}
        }
      }
    }
  ];
}

function toolIndex(discovery) {
  const index = new Map();
  for (const app of discovery.apps) {
    for (const capability of app.capabilities) {
      index.set(`invoke__${capability.id.replaceAll(".", "__")}`, { app, capability });
    }
  }
  return index;
}

async function executeToolCall(call, index, executedToolIdentities, seenToolNames) {
  const name = call.function?.name;
  const args = JSON.parse(call.function?.arguments || "{}");
  const identity = name === "remember_preference" ? `${name}:${args.key || ""}` : name;
  if (executedToolIdentities.has(identity)) {
    return {
      kind: "duplicate_ignored",
      tool: identity,
      reason: "This verifier already executed the requested ACP tool once in this conversation."
    };
  }
  executedToolIdentities.add(identity);
  seenToolNames.add(name);
  if (name === "remember_preference") {
    const payload = await requestJSON("/api/preferences", {
      method: "POST",
      body: JSON.stringify({
        userId: "local-user",
        agentId: "agent.meshkit-superapp",
        key: args.key,
        value: args.value,
        source: "llm-agent-live-verifier"
      })
    });
    return {
      kind: "preference",
      key: args.key,
      saved: Boolean(payload.preference),
      droppedReason: payload.droppedPreference?.reason || null
    };
  }
  if (name === "get_settlement_ledger") {
    const payload = await requestJSON("/api/settlements");
    return {
      kind: "settlement_ledger",
      entries: payload.settlementLedger.entries.map((entry) => ({
        requestId: entry.requestId,
        amount: entry.amount,
        asset: entry.asset,
        status: entry.status,
        paymentProof: entry.paymentProof
      })),
      summary: payload.settlementLedger.summary
    };
  }
  const discovered = index.get(name);
  if (!discovered) {
    throw new Error(`LLM called non-discovered tool: ${name}`);
  }
  const { app, capability } = discovered;
  const payload = await requestJSON("/api/execute", {
    method: "POST",
    body: JSON.stringify({
      capabilityId: capability.id,
      amount: args.amount,
      requestId: `req-llm-${capability.id.replaceAll(".", "-")}-${Date.now()}`,
      userId: "local-user",
      agentId: "agent.meshkit-superapp"
    })
  });
  return {
    kind: "acp_invocation",
    appId: app.appId,
    displayName: app.displayName,
    capabilityId: capability.id,
    acpEndpoint: app.acpEndpoint,
    urlScheme: capability.urlScheme,
    routingHint: capability.routingHint,
    userSummary: args.userSummary,
    noteText: capability.id === "notes.append_note" ? args.noteText || "" : undefined,
    noteRef: capability.id === "notes.append_note" ? args.noteRef || "local-note" : undefined,
    items: capability.id === "grocery.purchase_essentials" ? args.items || [] : undefined,
    budgetOkrw: capability.id === "grocery.purchase_essentials" ? args.budgetOkrw || args.amount : undefined,
    route: payload.routeDecision.route,
    status: payload.transactionRecord.status,
    requestId: payload.transactionRecord.requestId,
    txHash: payload.transactionRecord.txHash || "",
    recordType: payload.transactionRecord.recordType
  };
}

function discoverySummary(discovery) {
  return discovery.apps.map((app) => ({
    appId: app.appId,
    displayName: app.displayName,
    registrySource: app.registrySource,
    acpEndpoint: app.acpEndpoint,
    mcpTransport: app.mcpTransport,
    capabilities: app.capabilities.map((capability) => ({
      id: capability.id,
      risk: capability.risk,
      consent: capability.consent,
      requiresPayment: capability.requiresPayment,
      asset: capability.asset,
      urlScheme: capability.urlScheme,
      inputSchema: capability.inputSchema,
      resultSchema: capability.resultSchema,
      routingHint: capability.routingHint
    }))
  }));
}

function savedPreferenceCount(toolResults) {
  return toolResults.filter((entry) => entry.name === "remember_preference" && entry.result.saved === true).length;
}

function missingRequiredWork(requiredTools, seenToolNames, toolResults) {
  const missing = requiredTools.filter((name) => !seenToolNames.has(name));
  if (savedPreferenceCount(toolResults) < 2) {
    missing.unshift("remember_preference x2 (save separate low-sugar grocery and on-chain OKRW proof preferences)");
  }
  return missing;
}

async function main() {
  const discovery = await requestJSON("/api/acp/apps");
  assert.equal(discovery.registryMode, "signed-ocg-registry");
  assert.equal(discovery.registryTrust.verifiedCount, 2);
  assert.equal(discovery.apps.find((app) => app.appId === "app.mint-notes").capabilities[0].urlScheme, "mintnotes://mesh/invoke");
  assert.equal(discovery.apps.find((app) => app.appId === "app.dailymart").capabilities[0].urlScheme, "dailymart://mesh/invoke");

  const tools = [...capabilityTools(discovery), ...supportTools()];
  const index = toolIndex(discovery);
  const system = [
    "You are the MeshKit superapp agent.",
    "Use only the provided ACP tools. Tools were generated from live /api/acp/apps discovery.",
    "If the user asks what you can do, explain discovered apps and capabilities without inventing apps.",
    "For note requests, call notes.append_note with amount 0.",
    expectedNoteText ? `When calling notes.append_note, pass noteText exactly as: ${expectedNoteText}` : "",
    "For grocery purchase requests, call grocery.purchase_essentials with amount 42.",
    "For durable user preferences, save low-sugar groceries and on-chain OKRW proof as two separate remember_preference calls with distinct keys before app invocation.",
    "After paid purchase execution, read the settlement ledger and summarize the on-chain proof.",
    "Final answers must be concise and must not add unsolicited follow-up questions."
  ].filter(Boolean).join(" ");

  const messages = [
    { role: "system", content: system },
    {
      role: "user",
      content: [
        "Live ACP discovery summary:",
        JSON.stringify(discoverySummary(discovery)),
        "",
        `User: ${userPrompt}`
      ].join("\n")
    }
  ];

  const toolResults = [];
  const executedToolIdentities = new Set();
  const seenToolNames = new Set();
  const requiredTools = [
    "remember_preference",
    "invoke__notes__append_note",
    "invoke__grocery__purchase_essentials",
    "get_settlement_ledger"
  ];

  for (let turn = 0; turn < 6; turn += 1) {
    const message = await openaiChat(messages, tools);
    messages.push(message);
    const calls = message.tool_calls || [];
    for (const call of calls) {
      const result = await executeToolCall(call, index, executedToolIdentities, seenToolNames);
      toolResults.push({ name: call.function.name, result });
      messages.push({
        role: "tool",
        tool_call_id: call.id,
        content: JSON.stringify(result)
      });
    }
    const missing = missingRequiredWork(requiredTools, seenToolNames, toolResults);
    if (missing.length === 0) {
      break;
    }
    messages.push({
      role: "user",
      content: `Continue the same task. You still must complete these remaining ACP agent tool requirements before final answer: ${missing.join(", ")}. Use the discovered tool definitions only.`
    });
  }

  for (const name of requiredTools) {
    assert.equal(seenToolNames.has(name), true, `Missing required live LLM tool call: ${name}; got ${[...seenToolNames].join(", ")}`);
  }
  assert.ok(
    savedPreferenceCount(toolResults) >= 2,
    "Expected the LLM agent to save at least two durable preferences from the conversation."
  );

  messages.push({
    role: "user",
    content: "Now give the final user-facing answer. Mention discovered capabilities used, off-chain note result, DailyMart on-chain OKRW execution, and settlement proof."
  });
  const final = await openaiChat(messages, tools);
  const finalText = final.content || "";
  assert.match(finalText, /MintNotes|note/i);
  assert.match(finalText, /DailyMart|essentials|grocery/i);
  assert.match(finalText, /on-chain|onchain|OKRW|settlement/i);
  assert.equal(toolResults.some((entry) => entry.name === "invoke__notes__append_note" && entry.result.route === "offchain"), true);
  if (expectedNoteText) {
    assert.equal(
      toolResults.some((entry) => entry.name === "invoke__notes__append_note" && entry.result.noteText === expectedNoteText),
      true,
      `Expected the LLM agent to pass exact noteText ${JSON.stringify(expectedNoteText)}.`
    );
    assert.match(finalText, new RegExp(expectedNoteText.replace(/[.*+?^${}()|[\]\\]/g, "\\$&"), "i"));
  }
  assert.equal(toolResults.some((entry) => entry.name === "invoke__grocery__purchase_essentials" && entry.result.route === "onchain"), true);
  assert.equal(toolResults.some((entry) => entry.name === "get_settlement_ledger"), true);

  console.log(JSON.stringify({
    ok: true,
    model: openaiModel,
    userPrompt,
    registryMode: discovery.registryMode,
    verifiedCount: discovery.registryTrust.verifiedCount,
    toolCalls: toolResults.map((entry) => ({ name: entry.name, result: entry.result })),
    finalAnswer: finalText
  }, null, 2));
}

await main();
