export const ACP_SCHEMA_VERSION = "meshkit-acp-superapp/v1";
export const MEMORY_SCHEMA_VERSION = "meshkit-preference-memory/v1";
export const ROUTING_SCHEMA_VERSION = "meshkit-execution-routing/v1";
export const SETTLEMENT_SCHEMA_VERSION = "meshkit-settlement-ledger/v1";

const nowIso = "2026-06-08T00:00:00.000Z";
export const DEFAULT_USER_ID = "local-user";
export const DEFAULT_AGENT_ID = "agent.meshkit-superapp";

export const acpRegistry = Object.freeze([
  Object.freeze({
    appId: "app.hermes-chat",
    displayName: "HermesChat",
    publisher: "MeshKit Samples",
    acpEndpoint: "acp://hermes-chat/apps",
    mcpTransport: "app-to-app-url-scheme",
    bundleId: "ai.meshkit.sample.hermeschat",
    capabilities: Object.freeze([
      Object.freeze({
        id: "agent.plan_trip",
        displayName: "Plan errand",
        risk: "read_only",
        consent: "remember_for_app",
        requiresPayment: false,
        urlScheme: "hermeschat://mesh/invoke",
        inputSchema: Object.freeze(["intent", "preference_refs"]),
        resultSchema: Object.freeze(["plan", "recommended_app_ids"])
      })
    ])
  }),
  Object.freeze({
    appId: "app.mint-notes",
    ocgAppId: "ai.meshkit.sample.notes",
    displayName: "MintNotes",
    publisher: "MeshKit Samples",
    acpEndpoint: "acp://mint-notes/apps",
    mcpTransport: "app-to-app-url-scheme",
    bundleId: "ai.meshkit.sample.mintnotes",
    platform: "ios-demo",
    registrySource: "meshkit-ios-sample",
    capabilities: Object.freeze([
      Object.freeze({
        id: "notes.append_note",
        displayName: "Append note",
        risk: "write:user_content",
        consent: "per_invocation",
        requiresPayment: false,
        urlScheme: "mintnotes://mesh/invoke",
        inputSchema: Object.freeze(["note_ref", "text"]),
        resultSchema: Object.freeze(["status", "note_ref", "audit_id"])
      })
    ])
  }),
  Object.freeze({
    appId: "app.dailymart",
    ocgAppId: "ai.meshkit.sample.dailymart",
    displayName: "DailyMart",
    publisher: "MeshKit Samples",
    acpEndpoint: "acp://dailymart/apps",
    mcpTransport: "app-to-app-url-scheme",
    bundleId: "ai.meshkit.sample.dailymart",
    platform: "ios-demo",
    registrySource: "meshkit-ios-sample",
    capabilities: Object.freeze([
      Object.freeze({
        id: "grocery.purchase_essentials",
        displayName: "Purchase essentials",
        risk: "spend:money",
        consent: "budgeted_per_invocation",
        requiresPayment: true,
        asset: "OKRW",
        urlScheme: "dailymart://mesh/invoke",
        inputSchema: Object.freeze(["items", "address_ref", "budget_okrw"]),
        resultSchema: Object.freeze(["status", "order_id", "total_okrw", "receipt_id"])
      })
    ])
  })
]);

function titleCaseCapability(id) {
  return String(id || "")
    .split(/[._-]/)
    .filter(Boolean)
    .map((part) => `${part.slice(0, 1).toUpperCase()}${part.slice(1)}`)
    .join(" ");
}

function schemaKeys(schema) {
  if (!schema || typeof schema !== "object") return [];
  if (Array.isArray(schema.required)) return schema.required;
  if (schema.properties && typeof schema.properties === "object") return Object.keys(schema.properties);
  return [];
}

export function createAcpAppFromOcgManifest(manifest, overrides = {}) {
  const app = manifest?.app;
  const capabilities = Array.isArray(manifest?.capabilities) ? manifest.capabilities : [];
  if (!app || typeof app !== "object") {
    throw new Error("OCG manifest app is required");
  }
  if (!capabilities.length) {
    throw new Error("OCG manifest capabilities are required");
  }
  const displayName = overrides.displayName || app.display_name || app.app_id;
  const normalizedSlug = String(displayName).toLowerCase().replace(/[^a-z0-9]+/g, "-").replace(/^-|-$/g, "");

  return {
    schemaVersion: ACP_SCHEMA_VERSION,
    appId: overrides.appId || `app.${normalizedSlug}`,
    ocgAppId: app.app_id,
    displayName,
    publisher: overrides.publisher || app.publisher || "Unknown Publisher",
    acpEndpoint: overrides.acpEndpoint || `acp://${normalizedSlug}/apps`,
    mcpTransport: overrides.mcpTransport || "app-to-app-url-scheme",
    bundleId: overrides.bundleId || app.package_name || app.app_id,
    platform: app.platform || "unknown",
    packageName: app.package_name || app.app_id,
    verified: Boolean(app.verified),
    registrySource: overrides.registrySource || "ocg-registry",
    trust: manifest.trust || null,
    registrySignature: manifest.registry_signature || null,
    registrySignatureVerification: overrides.registrySignatureVerification || null,
    capabilities: capabilities.map((capability) => {
      const requiresPayment = capability.risk === "spend:money";
      return {
        id: capability.id,
        displayName: overrides.capabilityDisplayNames?.[capability.id] || titleCaseCapability(capability.id),
        version: capability.version || "1.0",
        description: capability.description || "",
        risk: capability.risk,
        consent: capability.consent,
        requiresPayment,
        asset: requiresPayment ? "OKRW" : null,
        urlScheme: overrides.urlSchemes?.[capability.id] || `${normalizedSlug}://mesh/invoke`,
        inputSchema: schemaKeys(capability.input_schema),
        resultSchema: schemaKeys(capability.result_schema),
        routingHint: requiresPayment ? "onchain_payment" : "offchain_app_call",
        ocg: {
          inputSchema: capability.input_schema || null,
          resultSchema: capability.result_schema || null,
          android: capability.android || null
        }
      };
    })
  };
}

export const samplePreferenceEvents = Object.freeze([
  Object.freeze({
    id: "pref-payment-1",
    key: "payment_proof_policy",
    role: "user",
    kind: "conversation",
    content: "agent payments use on-chain OKRW proof and non-payment calls stay off-chain",
    source: "seed-fixture",
    signals: Object.freeze({ userPreference: 1, decision: 1 }),
    createdAt: "2026-06-08T09:00:00.000Z"
  }),
  Object.freeze({
    id: "pref-privacy-1",
    key: "privacy_policy",
    role: "user",
    kind: "conversation",
    content: "cart/address/user/consent details stay off-chain",
    source: "seed-fixture",
    signals: Object.freeze({ userPreference: 1, privacy: 1 }),
    createdAt: "2026-06-08T09:03:00.000Z"
  }),
  Object.freeze({
    id: "pref-food-1",
    key: "grocery_defaults",
    role: "user",
    kind: "conversation",
    content: "User prefers low-sugar grocery defaults and wants bananas before snacks.",
    source: "demo-fixture",
    signals: Object.freeze({ userPreference: 1, projectRelevance: 0.8 }),
    createdAt: "2026-06-08T09:05:00.000Z"
  })
]);

function assertText(value, label) {
  const normalized = String(value ?? "").trim();
  if (!normalized) throw new Error(`${label} is required`);
  return normalized;
}

function compactHash(value, head = 8, tail = 6) {
  if (!value) return "-";
  if (value.length <= head + tail + 3) return value;
  return `${value.slice(0, head)}...${value.slice(-tail)}`;
}

function incrementBreakdown(target, key, amount) {
  const normalizedKey = key || "unknown";
  target[normalizedKey] = Number(((target[normalizedKey] || 0) + amount).toFixed(4));
}

function settlementCategory(capabilityId) {
  if (capabilityId === "grocery.purchase_essentials") return "groceries";
  if (capabilityId?.startsWith("notes.")) return "notes";
  return "agent-services";
}

function settlementCounterparty(appId) {
  if (appId === "app.dailymart") return "DailyMart";
  if (appId === "app.mint-notes") return "MintNotes";
  return appId || "Unknown";
}

function normalizeQuery(value) {
  return String(value || "").trim().toLowerCase();
}

function tokenize(value) {
  return normalizeQuery(value)
    .replace(/[^a-z0-9가-힣_:. -]/g, " ")
    .split(/\s+/)
    .filter(Boolean);
}

export function stripRecalledMemoryContext(content) {
  return String(content || "")
    .replace(/<memory-context>[\s\S]*?<\/memory-context>/gi, "")
    .replace(/\n{3,}/g, "\n\n")
    .trim();
}

export function isInternalReflectionPrompt(content) {
  const normalized = String(content || "").trim();
  return /^Review the conversation above and consider whether a skill should be saved or updated\.?/i.test(normalized)
    || /Only act when something is genuinely worth saving/i.test(normalized)
    || /SURVEY the existing skill landscape/i.test(normalized);
}

export function hasDurableSignal(signals = {}) {
  return Object.entries(signals || {}).some(([signalName, signalValue]) => {
    const normalizedName = String(signalName).toLowerCase();
    const normalizedValue = Number(signalValue);
    return normalizedValue > 0 && (
      normalizedName.includes("preference")
      || normalizedName.includes("correction")
      || normalizedName.includes("decision")
      || normalizedName.includes("memory")
      || normalizedName.includes("durable")
      || normalizedName.includes("project")
      || normalizedName.includes("recurrence")
    );
  });
}

export function looksLikeDurableFact(content) {
  const normalized = String(content || "");
  return /\b(user|caller)\s+(prefers|expects|wants|asked|requires|needs)\b/i.test(normalized)
    || /\b(remember|decision|decided|should|must|needs?|requires?|preference|project|memory|hippocampus|consolidation)\b/i.test(normalized);
}

function contentFingerprint(event) {
  return [
    event.userId || DEFAULT_USER_ID,
    event.agentId || DEFAULT_AGENT_ID,
    normalizeQuery(event.content).replace(/\s+/g, " ")
  ].join(":");
}

function createDroppedPreferenceEvent(event, reason) {
  return {
    id: event.id,
    key: event.key,
    role: event.role,
    kind: event.kind,
    reason
  };
}

function durableScore(event) {
  const signals = event.signals || {};
  const signalValues = Object.values(signals).filter((value) => Number.isFinite(Number(value)));
  const average = signalValues.length
    ? signalValues.reduce((total, value) => total + Number(value), 0) / signalValues.length
    : 0;
  const content = normalizeQuery(event.content);
  const preferenceBoost = looksLikeDurableFact(content)
    ? 0.25
    : 0;
  const roleBoost = event.role === "user" ? 0.15 : 0;
  return Number(Math.min(1, Math.max(0.01, average + preferenceBoost + roleBoost)).toFixed(4));
}

export function deterministicHex(input, bytes = 32) {
  let state = 0x811c9dc5;
  const text = String(input);
  for (let index = 0; index < text.length; index += 1) {
    state ^= text.charCodeAt(index);
    state = Math.imul(state, 0x01000193) >>> 0;
  }
  let hex = "";
  while (hex.length < bytes * 2) {
    state ^= state << 13;
    state ^= state >>> 17;
    state ^= state << 5;
    hex += (state >>> 0).toString(16).padStart(8, "0");
  }
  return `0x${hex.slice(0, bytes * 2)}`;
}

export function discoverAcpApps(registry = acpRegistry) {
  return registry.map((app) => ({
    schemaVersion: ACP_SCHEMA_VERSION,
    appId: app.appId,
    ocgAppId: app.ocgAppId || app.appId,
    displayName: app.displayName,
    publisher: app.publisher,
    acpEndpoint: app.acpEndpoint,
    mcpTransport: app.mcpTransport,
    bundleId: app.bundleId,
    platform: app.platform || "local",
    registrySource: app.registrySource || "local-fixture",
    capabilities: app.capabilities.map((capability) => ({
      ...capability,
      routingHint: capability.requiresPayment ? "onchain_payment" : "offchain_app_call"
    }))
  }));
}

export function normalizePreferenceEvent(event = {}, index = 0) {
  const key = assertText(event.key || event.memoryId || event.id || `preference_${index + 1}`, "preference key");
  const content = assertText(event.value || event.content, "preference value");
  const createdAt = event.createdAt || nowIso;
  const updatedAt = event.updatedAt || createdAt;
  return {
    id: event.id || key,
    key,
    role: event.role || "user",
    kind: event.kind || "preference",
    content,
    value: content,
    userId: event.userId || event.user_id || DEFAULT_USER_ID,
    agentId: event.agentId || event.agent_id || DEFAULT_AGENT_ID,
    source: event.source || event.metadata?.source || "local-api",
    signals: { ...(event.signals || { userPreference: 1 }) },
    createdAt,
    updatedAt,
    lastAccessedAt: event.lastAccessedAt || updatedAt,
    accessCount: Number.isFinite(Number(event.accessCount)) ? Number(event.accessCount) : 1
  };
}

export function consolidatePreferenceEvents(events = samplePreferenceEvents) {
  const filteredEvents = [];
  const droppedEvents = [];
  const seenFingerprints = new Set();

  events.map(normalizePreferenceEvent).forEach((event) => {
    const originalContent = event.content;
    const content = stripRecalledMemoryContext(originalContent);
    const sanitizedEvent = {
      ...event,
      content,
      value: content
    };

    if (!content) {
      droppedEvents.push(createDroppedPreferenceEvent(sanitizedEvent, "empty-after-sanitization"));
      return;
    }

    if (["system", "developer", "internal"].includes(sanitizedEvent.role) || sanitizedEvent.kind === "internal") {
      droppedEvents.push(createDroppedPreferenceEvent(sanitizedEvent, "internal-event"));
      return;
    }

    if (isInternalReflectionPrompt(content)) {
      droppedEvents.push(createDroppedPreferenceEvent(sanitizedEvent, "internal-reflection-prompt"));
      return;
    }

    if (sanitizedEvent.role === "assistant" && !hasDurableSignal(sanitizedEvent.signals)) {
      droppedEvents.push(createDroppedPreferenceEvent(sanitizedEvent, "assistant-echo-without-durable-signal"));
      return;
    }

    const fingerprint = contentFingerprint(sanitizedEvent);
    if (seenFingerprints.has(fingerprint)) {
      droppedEvents.push(createDroppedPreferenceEvent(sanitizedEvent, "duplicate-content"));
      return;
    }
    seenFingerprints.add(fingerprint);

    const importance = durableScore(sanitizedEvent);
    filteredEvents.push({
      ...sanitizedEvent,
      importance,
      signals: {
        ...sanitizedEvent.signals,
        hippocampalDurability: looksLikeDurableFact(content) || hasDurableSignal(sanitizedEvent.signals) ? 1 : 0.1,
        hippocampalImportance: importance
      },
      consolidation: {
        filtered: true,
        recalledContextStripped: content !== originalContent,
        source: "brain-hippocampus-inspired"
      }
    });
  });

  const promotedEvents = filteredEvents.filter((event) =>
    event.importance >= 0.75
    || hasDurableSignal(event.signals)
    || looksLikeDurableFact(event.content)
  );

  return {
    apiKind: "meshkit_preference_consolidation_result",
    schemaVersion: MEMORY_SCHEMA_VERSION,
    filteredEvents,
    promotedEvents,
    droppedEvents
  };
}

export function createPreferenceMemory(events = samplePreferenceEvents) {
  const consolidation = consolidatePreferenceEvents(events);
  const promotedIds = new Set(consolidation.promotedEvents.map((event) => event.id));
  const workingMemory = consolidation.filteredEvents.map((event) => ({
    schemaVersion: MEMORY_SCHEMA_VERSION,
    memoryId: event.id,
    key: event.key,
    userId: event.userId,
    agentId: event.agentId,
    memoryKind: "young-working-memory",
    value: event.value,
    content: event.content,
    source: event.source,
    createdAt: event.createdAt,
    updatedAt: event.updatedAt,
    lastAccessedAt: event.lastAccessedAt,
    accessCount: event.accessCount,
    importance: event.importance,
    signals: event.signals,
    metadata: {
      role: event.role,
      source: event.source,
      hippocampus: {
        ...event.consolidation,
        promoted: promotedIds.has(event.id)
      }
    }
  }));

  const promotedMemory = workingMemory
    .filter((memory) => promotedIds.has(memory.memoryId))
    .map((memory) => ({
      ...memory,
      memoryKind: "old-long-term-memory",
      promotedAt: nowIso,
      promotionReason: "hippocampus-filtered-durable-event",
      metadata: {
        ...memory.metadata,
        hippocampus: {
          ...memory.metadata.hippocampus,
          promoted: true,
          promotionReason: "hippocampus-filtered-durable-event"
        }
      }
    }));

  return {
    schemaVersion: MEMORY_SCHEMA_VERSION,
    userId: consolidation.filteredEvents[0]?.userId || DEFAULT_USER_ID,
    agentId: consolidation.filteredEvents[0]?.agentId || DEFAULT_AGENT_ID,
    workingMemory,
    promotedMemory,
    filteredEvents: consolidation.filteredEvents.map((event) => ({
      id: event.id,
      key: event.key,
      role: event.role,
      kind: event.kind,
      source: event.source,
      recalledContextStripped: event.consolidation.recalledContextStripped
    })),
    droppedEvents: consolidation.droppedEvents,
    consolidation: {
      apiKind: consolidation.apiKind,
      schemaVersion: consolidation.schemaVersion,
      filteredCount: consolidation.filteredEvents.length,
      promotedCount: promotedMemory.length,
      droppedCount: consolidation.droppedEvents.length,
      policy: "strip recalled memory context, drop internal events, drop assistant echoes without durable signals, dedupe content"
    }
  };
}

export function retrievePreferences(memory, query, limit = 3) {
  const queryTerms = tokenize(query);
  const source = Array.isArray(memory?.promotedMemory) ? memory.promotedMemory : [];
  return source
    .map((entry) => {
      const contentTerms = new Set(tokenize(entry.content));
      const matchCount = queryTerms.filter((term) => contentTerms.has(term)).length;
      const semanticBoost = /payment|pay|결제|on-chain|onchain|chain|okrw/i.test(query + entry.content) ? 0.2 : 0;
      return {
        ...entry,
        retrievalScore: Number((entry.importance + matchCount * 0.15 + semanticBoost).toFixed(4))
      };
    })
    .sort((left, right) => right.retrievalScore - left.retrievalScore || left.memoryId.localeCompare(right.memoryId))
    .slice(0, limit);
}

export function findCapability(apps, capabilityId) {
  for (const app of apps) {
    const capability = app.capabilities.find((candidate) => candidate.id === capabilityId);
    if (capability) return { app, capability };
  }
  return null;
}

function policyMemories(memory) {
  return (Array.isArray(memory?.promotedMemory) ? memory.promotedMemory : [])
    .filter((entry) => ["payment_proof_policy", "privacy_policy"].includes(entry.key));
}

function includesAny(value, patterns) {
  return patterns.some((pattern) => pattern.test(value));
}

export function deriveRoutingPolicy({ memory = createPreferenceMemory(), recalledPreferences = [], requiresPayment = false } = {}) {
  const explicitPolicyMemories = policyMemories(memory);
  const fallbackPolicyMemories = recalledPreferences.filter((entry) =>
    ["payment_proof_policy", "privacy_policy"].includes(entry.key)
  );
  const sourceMemories = [...new Map(
    (explicitPolicyMemories.length ? explicitPolicyMemories : fallbackPolicyMemories)
      .map((entry) => [entry.memoryId, entry])
  ).values()];
  const paymentPolicy = sourceMemories.find((entry) => entry.key === "payment_proof_policy");
  const privacyPolicy = sourceMemories.find((entry) => entry.key === "privacy_policy");
  const paymentContent = normalizeQuery(paymentPolicy?.content);
  const privacyContent = normalizeQuery(privacyPolicy?.content);
  const paymentPrefersOnchain = includesAny(paymentContent, [/on-chain/, /onchain/, /okrw proof/, /chain.*proof/]);
  const nonPaymentPrefersOffchain = includesAny(paymentContent, [/non-payment.*off-chain/, /non-payment.*offchain/, /calls stay off-chain/]);
  const privatePayloadOffchain = includesAny(privacyContent, [/off-chain/, /offchain/, /cart\/address\/user\/consent/, /private/]);

  return {
    policyId: "meshkit-superapp-routing-policy/v1",
    source: sourceMemories.length ? "preference-memory" : "safe-default",
    sourceMemoryIds: sourceMemories.map((entry) => entry.memoryId),
    paymentProof: requiresPayment && paymentPrefersOnchain
      ? "onchain-okrw-proof"
      : requiresPayment
        ? "onchain-required-by-capability"
        : "no-payment-proof",
    nonPaymentTransport: nonPaymentPrefersOffchain ? "offchain-app-to-app-mcp" : "offchain-app-to-app-mcp-default",
    payloadPrivacy: privatePayloadOffchain ? "private-payload-offchain" : "minimal-chain-visible-fields-only",
    chainVisibleFields: requiresPayment
      ? ["signedRequestHash", "policyHash", "txHash", "settlementStatus"]
      : [],
    offchainFields: ["capabilityPayload", "cart", "addressRef", "userIdentityRef", "consentText"],
    decisionReason: requiresPayment
      ? "paid capability uses on-chain proof while private payload fields stay off-chain"
      : "non-payment app-to-app MCP call stays off-chain"
  };
}

export function routeExecution({ apps = discoverAcpApps(), memory = createPreferenceMemory(), capabilityId, amount = 0 }) {
  const normalizedCapabilityId = assertText(capabilityId, "capabilityId");
  const normalizedAmount = Number(amount);
  if (!Number.isFinite(normalizedAmount) || normalizedAmount < 0) {
    throw new Error("amount must be a non-negative number");
  }
  const match = findCapability(apps, normalizedCapabilityId);
  if (!match) {
    throw new Error(`Capability not found: ${normalizedCapabilityId}`);
  }

  const requiresPayment = match.capability.requiresPayment === true || normalizedAmount > 0;
  const recalledPreferences = retrievePreferences(memory, `${match.capability.id} ${match.capability.displayName} payment`, 3);
  const appliedPolicy = deriveRoutingPolicy({ memory, recalledPreferences, requiresPayment });
  const route = requiresPayment ? "onchain" : "offchain";

  return {
    schemaVersion: ROUTING_SCHEMA_VERSION,
    route,
    transport: route === "onchain" ? "maroo-testnet-okrw" : match.app.mcpTransport,
    appId: match.app.appId,
    capabilityId: match.capability.id,
    requiresPayment,
    asset: requiresPayment ? (match.capability.asset || "OKRW") : null,
    amount: normalizedAmount,
    privacyBoundary: route === "onchain"
      ? "Only request hash, policy hash, tx hash, and settlement status are chain-visible."
      : "Capability payload stays in app-to-app MCP and is not anchored as payment.",
    recalledPreferences,
    appliedPolicy
  };
}

export function executeAppToAppRequest({
  apps = discoverAcpApps(),
  memory = createPreferenceMemory(),
  capabilityId,
  amount = 0,
  requestId,
  userId = DEFAULT_USER_ID,
  agentId = DEFAULT_AGENT_ID,
  now = nowIso
} = {}) {
  const routeDecision = routeExecution({ apps, memory, capabilityId, amount });
  const stableRequestId = requestId || `req-${routeDecision.capabilityId.replaceAll(".", "-")}-${routeDecision.amount}`;
  const base = `${stableRequestId}:${routeDecision.appId}:${routeDecision.capabilityId}:${routeDecision.amount}:${routeDecision.route}`;
  const signedRequestHash = deterministicHex(`signed:${base}`);
  const policyHash = deterministicHex([
    "policy",
    userId,
    agentId,
    routeDecision.capabilityId,
    routeDecision.appliedPolicy.policyId,
    routeDecision.appliedPolicy.paymentProof,
    routeDecision.appliedPolicy.payloadPrivacy,
    routeDecision.appliedPolicy.sourceMemoryIds.join("|")
  ].join(":"));

  if (routeDecision.route === "onchain") {
    const txHash = deterministicHex(`tx:${base}`);
    return {
      routeDecision,
      transactionRecord: {
        schemaVersion: ROUTING_SCHEMA_VERSION,
        route: "onchain",
        recordType: "onchain-sim",
        requestId: stableRequestId,
        userId,
        agentId,
        appId: routeDecision.appId,
        capabilityId: routeDecision.capabilityId,
        provider: "maroo",
        network: "maroo-testnet",
        asset: routeDecision.asset || "OKRW",
        amount: routeDecision.amount,
        status: "confirmed",
        txHash,
        explorerUrl: `https://explorer-testnet.maroo.io/tx/${txHash}`,
        policyHash,
        signedRequestHash,
        appliedPolicy: routeDecision.appliedPolicy,
        policySourceMemoryIds: routeDecision.appliedPolicy.sourceMemoryIds,
        chainVisibleFields: routeDecision.appliedPolicy.chainVisibleFields,
        offchainFields: routeDecision.appliedPolicy.offchainFields,
        createdAt: now
      }
    };
  }

  return {
    routeDecision,
    transactionRecord: {
      schemaVersion: ROUTING_SCHEMA_VERSION,
      route: "offchain",
      recordType: "app-to-app-url-scheme",
      requestId: stableRequestId,
      userId,
      agentId,
      appId: routeDecision.appId,
      capabilityId: routeDecision.capabilityId,
      amount: 0,
      status: "submitted",
      offchainRecordId: deterministicHex(`offchain:${base}`, 12),
      txHash: "",
      signedRequestHash,
      appliedPolicy: routeDecision.appliedPolicy,
      policySourceMemoryIds: routeDecision.appliedPolicy.sourceMemoryIds,
      chainVisibleFields: routeDecision.appliedPolicy.chainVisibleFields,
      offchainFields: routeDecision.appliedPolicy.offchainFields,
      createdAt: now
    }
  };
}

export function createSettlementLedger(records = []) {
  const onchainRecords = records.filter((record) => record?.route === "onchain" || record?.txHash);
  const entries = onchainRecords.map((record, index) => {
    const amount = Number(record.amount || record.proofDetails?.value || 0);
    const status = record.status || record.receiptStatus || "verified";
    const appId = record.appId || "app.dailymart";
    const capabilityId = record.capabilityId || "grocery.purchase_essentials";
    return {
      schemaVersion: SETTLEMENT_SCHEMA_VERSION,
      entryId: record.entryId || `settlement-${index + 1}`,
      requestId: record.requestId,
      appId,
      capabilityId,
      provider: record.provider || "maroo",
      network: record.network || "maroo-testnet",
      asset: record.asset || "OKRW",
      amount,
      status,
      direction: record.direction || "debit",
      category: record.category || settlementCategory(capabilityId),
      counterparty: record.counterparty || settlementCounterparty(appId),
      txHash: record.txHash,
      explorerUrl: record.explorerUrl || record.proofDetails?.explorerUrl || "",
      policyHash: record.policyHash || record.proofDetails?.policyHash || "",
      signedRequestHash: record.signedRequestHash || record.proofDetails?.signedRequestHash || "",
      policyId: record.appliedPolicy?.policyId || "",
      paymentProof: record.appliedPolicy?.paymentProof || "",
      payloadPrivacy: record.appliedPolicy?.payloadPrivacy || "",
      policySourceMemoryIds: record.policySourceMemoryIds || record.appliedPolicy?.sourceMemoryIds || [],
      displayTx: compactHash(record.txHash)
    };
  });

  const totalConfirmed = entries
    .filter((entry) => ["trusted", "verified", "confirmed"].includes(entry.status))
    .reduce((total, entry) => total + entry.amount, 0);
  const confirmedEntries = entries.filter((entry) => ["trusted", "verified", "confirmed"].includes(entry.status));
  const byStatus = {};
  const byApp = {};
  const byCategory = {};
  const byCounterparty = {};
  for (const entry of entries) {
    incrementBreakdown(byStatus, entry.status, entry.amount);
  }
  for (const entry of confirmedEntries) {
    incrementBreakdown(byApp, entry.appId, entry.amount);
    incrementBreakdown(byCategory, entry.category, entry.amount);
    incrementBreakdown(byCounterparty, entry.counterparty, entry.amount);
  }

  return {
    schemaVersion: SETTLEMENT_SCHEMA_VERSION,
    generatedAt: nowIso,
    entries,
    summary: {
      totalEntries: entries.length,
      totalConfirmed,
      totalDebits: confirmedEntries
        .filter((entry) => entry.direction === "debit")
        .reduce((total, entry) => total + entry.amount, 0),
      totalCredits: confirmedEntries
        .filter((entry) => entry.direction === "credit")
        .reduce((total, entry) => total + entry.amount, 0),
      asset: "OKRW",
      byStatus,
      byApp,
      byCategory,
      byCounterparty
    }
  };
}

export function createDemoSuperappState(trustRecords = []) {
  const apps = discoverAcpApps();
  const memory = createPreferenceMemory();
  const offchainPlan = routeExecution({
    apps,
    memory,
    capabilityId: "notes.append_note",
    amount: 0
  });
  const onchainPlan = routeExecution({
    apps,
    memory,
    capabilityId: "grocery.purchase_essentials",
    amount: 42
  });
  const fallbackSettlement = [{
    route: "onchain",
    requestId: "req-dailymart-demo-001",
    appId: "app.dailymart",
    capabilityId: "grocery.purchase_essentials",
    provider: "maroo",
    network: "maroo-testnet",
    asset: "OKRW",
    amount: 42,
    status: "confirmed",
    txHash: "0x0f6e2d4c8b7a9001f6e2d4c8b7a9001f6e2d4c8b7a9001f6e2d4c8b7a9001",
    explorerUrl: "https://explorer-testnet.maroo.io/tx/0x0f6e2d4c8b7a9001f6e2d4c8b7a9001f6e2d4c8b7a9001f6e2d4c8b7a9001",
    policyHash: "policy-dailymart-okrw",
    signedRequestHash: "signed-mcp-request-dailymart"
  }];

  return {
    apps,
    memory,
    routing: [offchainPlan, onchainPlan],
    settlementLedger: createSettlementLedger(trustRecords.length ? trustRecords : fallbackSettlement)
  };
}

export function createSuperappState({ preferenceEvents = samplePreferenceEvents, executionRecords = [], apps = discoverAcpApps() } = {}) {
  const memory = createPreferenceMemory(preferenceEvents);
  const offchainPlan = routeExecution({ apps, memory, capabilityId: "notes.append_note", amount: 0 });
  const onchainPlan = routeExecution({ apps, memory, capabilityId: "grocery.purchase_essentials", amount: 42 });
  const records = executionRecords.length
    ? executionRecords
    : [executeAppToAppRequest({
        apps,
        memory,
        capabilityId: "grocery.purchase_essentials",
        amount: 42,
        requestId: "req-dailymart-demo-001"
      }).transactionRecord];

  return {
    apps,
    memory,
    routing: [offchainPlan, onchainPlan],
    executionRecords: records,
    settlementLedger: createSettlementLedger(records)
  };
}
