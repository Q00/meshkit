import { apiBase } from "./config.js";

async function requestJSON(path, options = {}) {
  const response = await fetch(`${apiBase()}${path}`, {
    headers: {
      "content-type": "application/json",
      ...(options.headers || {})
    },
    ...options
  });
  let payload;
  try {
    payload = await response.json();
  } catch {
    payload = { message: `HTTP ${response.status}` };
  }
  if (!response.ok) {
    const message = payload?.message || payload?.error || `HTTP ${response.status}`;
    throw new Error(message);
  }
  return payload;
}

export async function fetchSuperappState() {
  return requestJSON("/api/superapp-state");
}

export async function fetchAcpApps() {
  return requestJSON("/api/acp/apps");
}

export async function savePreference({ key, value, source = "rn-ui" }) {
  return requestJSON("/api/preferences", {
    method: "POST",
    body: JSON.stringify({
      userId: "local-user",
      agentId: "agent.meshkit-superapp",
      key,
      value,
      source
    })
  });
}

export async function sendAgentChat({ messages }) {
  return requestJSON("/api/agent-chat", {
    method: "POST",
    body: JSON.stringify({ messages })
  });
}

export async function executeCapability({ capabilityId, amount, requestPrefix }) {
  return requestJSON("/api/execute", {
    method: "POST",
    body: JSON.stringify({
      capabilityId,
      amount,
      requestId: `${requestPrefix}-${new Date().toISOString()}`
    })
  });
}

export async function executeMintNotesOffchain() {
  return executeCapability({
    capabilityId: "notes.append_note",
    amount: 0,
    requestPrefix: "req-rn-mintnotes"
  });
}

export async function executeDailyMartOnchain() {
  return executeCapability({
    capabilityId: "grocery.purchase_essentials",
    amount: 42,
    requestPrefix: "req-rn-dailymart"
  });
}

export function summarizeSuperappState(state) {
  const ledger = state?.settlementLedger || { entries: [], summary: {} };
  return {
    appCount: Array.isArray(state?.apps) ? state.apps.length : 0,
    promotedMemoryCount: state?.memory?.promotedMemory?.length || 0,
    executionCount: state?.executionRecords?.length || 0,
    settlementCount: ledger.entries?.length || 0,
    totalConfirmed: ledger.summary?.totalConfirmed || 0,
    totalDebits: ledger.summary?.totalDebits || 0,
    asset: ledger.summary?.asset || "OKRW"
  };
}
