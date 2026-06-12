import { randomUUID } from "node:crypto";
import { mkdir, readFile, rename, writeFile } from "node:fs/promises";
import { dirname, join } from "node:path";
import {
  DEFAULT_AGENT_ID,
  DEFAULT_USER_ID,
  createSuperappState,
  executeAppToAppRequest,
  normalizePreferenceEvent,
  retrievePreferences,
  samplePreferenceEvents
} from "./superapp.js";

const STORE_SCHEMA_VERSION = "meshkit-superapp-store/v1";
const storeLocks = new Map();

export function createDefaultStoreState() {
  return {
    schemaVersion: STORE_SCHEMA_VERSION,
    preferenceEvents: samplePreferenceEvents.map((event) => ({ ...event })),
    executionRecords: []
  };
}

function storePath(dataDir) {
  return join(dataDir, "superapp-store.json");
}

async function writeJsonAtomic(path, value) {
  await mkdir(dirname(path), { recursive: true });
  const tmpPath = `${path}.${process.pid}.${Date.now()}.${randomUUID()}.tmp`;
  await writeFile(tmpPath, JSON.stringify(value, null, 2), "utf8");
  await rename(tmpPath, path);
}

async function withStoreWriteLock(dataDir, fn) {
  const previous = storeLocks.get(dataDir) || Promise.resolve();
  let release;
  const current = new Promise((resolve) => {
    release = resolve;
  });
  const chained = previous.then(() => current, () => current);
  storeLocks.set(dataDir, chained);
  await previous.catch(() => {});
  try {
    return await fn();
  } finally {
    release();
    if (storeLocks.get(dataDir) === chained) {
      storeLocks.delete(dataDir);
    }
  }
}

export async function loadSuperappStore(dataDir) {
  const path = storePath(dataDir);
  try {
    const raw = await readFile(path, "utf8");
    const parsed = JSON.parse(raw);
    return {
      schemaVersion: STORE_SCHEMA_VERSION,
      preferenceEvents: Array.isArray(parsed.preferenceEvents) ? parsed.preferenceEvents : [],
      executionRecords: Array.isArray(parsed.executionRecords) ? parsed.executionRecords : []
    };
  } catch (error) {
    if (error?.code !== "ENOENT") throw error;
    const initial = createDefaultStoreState();
    await writeJsonAtomic(path, initial);
    return initial;
  }
}

export async function saveSuperappStore(dataDir, state) {
  const next = {
    schemaVersion: STORE_SCHEMA_VERSION,
    preferenceEvents: Array.isArray(state.preferenceEvents) ? state.preferenceEvents : [],
    executionRecords: Array.isArray(state.executionRecords) ? state.executionRecords : []
  };
  await writeJsonAtomic(storePath(dataDir), next);
  return next;
}

export async function readPersistentSuperappState(dataDir, options = {}) {
  const store = await loadSuperappStore(dataDir);
  return {
    ...createSuperappState({ ...store, apps: options.apps }),
    storeSchemaVersion: store.schemaVersion
  };
}

export async function upsertPreference(dataDir, input, options = {}) {
  return withStoreWriteLock(dataDir, async () => {
    const store = await loadSuperappStore(dataDir);
    const normalized = normalizePreferenceEvent({
      userId: input.userId || input.user_id || DEFAULT_USER_ID,
      agentId: input.agentId || input.agent_id || DEFAULT_AGENT_ID,
      key: input.key,
      value: input.value,
      content: input.content,
      source: input.source || "local-api",
      signals: input.signals || { userPreference: 1 },
      createdAt: input.createdAt,
      updatedAt: input.updatedAt || new Date().toISOString(),
      lastAccessedAt: input.lastAccessedAt || new Date().toISOString()
    });

    const existingIndex = store.preferenceEvents.findIndex((event) =>
      (event.userId || event.user_id || DEFAULT_USER_ID) === normalized.userId &&
      (event.agentId || event.agent_id || DEFAULT_AGENT_ID) === normalized.agentId &&
      (event.key || event.id) === normalized.key
    );
    const nextEvent = {
      id: existingIndex >= 0 ? store.preferenceEvents[existingIndex].id : normalized.id,
      key: normalized.key,
      userId: normalized.userId,
      agentId: normalized.agentId,
      role: normalized.role,
      kind: normalized.kind,
      content: normalized.content,
      value: normalized.value,
      source: normalized.source,
      signals: normalized.signals,
      createdAt: existingIndex >= 0 ? store.preferenceEvents[existingIndex].createdAt : normalized.createdAt,
      updatedAt: normalized.updatedAt,
      lastAccessedAt: normalized.lastAccessedAt,
      accessCount: normalized.accessCount
    };

    if (existingIndex >= 0) {
      store.preferenceEvents[existingIndex] = nextEvent;
    } else {
      store.preferenceEvents.push(nextEvent);
    }
    await saveSuperappStore(dataDir, store);
    const state = createSuperappState({ ...store, apps: options.apps });
    const matchesPreference = (entry) =>
      entry.key === normalized.key &&
      entry.userId === normalized.userId &&
      entry.agentId === normalized.agentId;
    const preference = state.memory.promotedMemory.find(matchesPreference) ||
      state.memory.workingMemory.find(matchesPreference) ||
      null;
    return {
      preference,
      droppedPreference: preference ? null : state.memory.droppedEvents.find((event) => event.key === normalized.key) || null,
      state
    };
  });
}

export async function queryPreferences(dataDir, query = "", limit = 10, options = {}) {
  const store = await loadSuperappStore(dataDir);
  const state = createSuperappState({ ...store, apps: options.apps });
  return retrievePreferences(state.memory, query, limit);
}

export async function executePersistentRequest(dataDir, input, options = {}) {
  return withStoreWriteLock(dataDir, async () => {
    const store = await loadSuperappStore(dataDir);
    const state = createSuperappState({ ...store, apps: options.apps });
    const result = executeAppToAppRequest({
      apps: state.apps,
      memory: state.memory,
      capabilityId: input.capabilityId,
      amount: input.amount ?? 0,
      requestId: input.requestId,
      userId: input.userId || input.user_id || DEFAULT_USER_ID,
      agentId: input.agentId || input.agent_id || DEFAULT_AGENT_ID,
      now: input.createdAt || new Date().toISOString()
    });
    store.executionRecords.push(result.transactionRecord);
    await saveSuperappStore(dataDir, store);
    return {
      ...result,
      settlementLedger: createSuperappState({ ...store, apps: options.apps }).settlementLedger
    };
  });
}
