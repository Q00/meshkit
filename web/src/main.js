import {
  POLL_INTERVAL_MS,
  buildTrustPathUrl,
  groupRecordNodes,
  normalizeTrustPathResponse
} from "./trust-path.js";
import {
  createDemoSuperappState,
  createSettlementLedger,
  routeExecution
} from "./superapp.js";

const elements = {
  walletInput: document.querySelector("#wallet-input"),
  connectButton: document.querySelector("#connect-button"),
  connectionStatus: document.querySelector("#connection-status"),
  liveDot: document.querySelector("#live-dot"),
  liveLabel: document.querySelector("#live-label"),
  sourceMode: document.querySelector("#source-mode"),
  latestBlock: document.querySelector("#latest-block"),
  netVersion: document.querySelector("#net-version"),
  recordCount: document.querySelector("#record-count"),
  recordList: document.querySelector("#record-list"),
  edgeLayer: document.querySelector("#edge-layer"),
  graphLayer: document.querySelector("#graph-layer"),
  emptyState: document.querySelector("#empty-state"),
  proofDetails: document.querySelector("#proof-details"),
  workspaceTitle: document.querySelector("#workspace-title"),
  appCount: document.querySelector("#app-count"),
  discoveredApps: document.querySelector("#discovered-apps"),
  memoryList: document.querySelector("#memory-list"),
  routeList: document.querySelector("#route-list"),
  executionList: document.querySelector("#execution-list"),
  settlementList: document.querySelector("#settlement-list"),
  settlementSummary: document.querySelector("#settlement-summary"),
  settlementTotal: document.querySelector("#settlement-total"),
  preferenceForm: document.querySelector("#preference-form"),
  preferenceKey: document.querySelector("#preference-key"),
  preferenceValue: document.querySelector("#preference-value"),
  executeUnpaidButton: document.querySelector("#execute-unpaid-button"),
  executePaidButton: document.querySelector("#execute-paid-button"),
  actionStatus: document.querySelector("#action-status")
};

let connectedWallet = "";
let pollTimer = null;
let records = [];
let selectedRecordId = "";
let pollInFlight = false;
let superappState = createDemoSuperappState();

function setLiveState(state, text) {
  elements.liveDot.dataset.state = state;
  elements.liveLabel.textContent = text;
}

function compact(value, head = 10, tail = 8) {
  if (!value || value.length <= head + tail + 3) return value || "-";
  return `${value.slice(0, head)}...${value.slice(-tail)}`;
}

function escapeHtml(value) {
  return String(value)
    .replaceAll("&", "&amp;")
    .replaceAll("<", "&lt;")
    .replaceAll(">", "&gt;")
    .replaceAll('"', "&quot;");
}

function selectRecord(recordId) {
  selectedRecordId = recordId;
  render();
}

function renderDiscovery() {
  elements.appCount.textContent = String(superappState.apps.length);
  elements.discoveredApps.innerHTML = superappState.apps.map((app) => `
    <article class="app-row">
      <div>
        <b>${escapeHtml(app.displayName)}</b>
        <small>${escapeHtml(app.acpEndpoint)} · ${escapeHtml(app.mcpTransport)}</small>
      </div>
      <span>${escapeHtml(app.capabilities[0]?.id || "-")}</span>
    </article>
  `).join("");
}

function renderMemory() {
  const consolidation = superappState.memory.consolidation || {};
  const promotedRows = superappState.memory.promotedMemory.map((memory) => `
    <article class="memory-row">
      <span>${escapeHtml(memory.key || memory.memoryKind.replace("old-", ""))}</span>
      <p>${escapeHtml(memory.content)}</p>
      <b>${escapeHtml(String(memory.importance))}</b>
    </article>
  `).join("");
  elements.memoryList.innerHTML = `${promotedRows}
    <article class="memory-row subdued">
      <span>hippocampus</span>
      <p>${escapeHtml(consolidation.policy || "durable preference filter")}</p>
      <b>${escapeHtml(`${consolidation.promotedCount || 0}/${consolidation.filteredCount || 0}/${consolidation.droppedCount || 0}`)}</b>
    </article>
  `;
}

function renderRoutes() {
  elements.routeList.innerHTML = superappState.routing.map((route) => `
    <article class="route-row ${route.route}">
      <div>
        <b>${escapeHtml(route.capabilityId)}</b>
        <small>${escapeHtml(`${route.appliedPolicy?.paymentProof || "policy"} · ${route.appliedPolicy?.payloadPrivacy || route.privacyBoundary}`)}</small>
      </div>
      <span>${escapeHtml(route.route)} · ${escapeHtml(route.transport)}</span>
    </article>
  `).join("");

  const executionRecords = Array.isArray(superappState.executionRecords) ? superappState.executionRecords : [];
  elements.executionList.innerHTML = executionRecords.slice(-4).reverse().map((record) => `
    <article class="execution-row ${record.route}">
      <div>
        <b>${escapeHtml(record.requestId)}</b>
        <small>${escapeHtml(record.capabilityId)} · ${escapeHtml(record.recordType)}</small>
      </div>
      <span>${escapeHtml(record.route)} · ${escapeHtml(record.txHash ? compact(record.txHash) : record.offchainRecordId || "off-chain")}</span>
    </article>
  `).join("");
}

function renderSettlement() {
  const ledger = superappState.settlementLedger;
  elements.settlementTotal.textContent = `${ledger.summary.totalConfirmed.toFixed(4)} ${ledger.summary.asset}`;
  const categorySummary = Object.entries(ledger.summary.byCategory || {})
    .map(([category, amount]) => `${category}: ${Number(amount).toFixed(4)}`)
    .join(" · ");
  const counterpartySummary = Object.entries(ledger.summary.byCounterparty || {})
    .map(([counterparty, amount]) => `${counterparty}: ${Number(amount).toFixed(4)}`)
    .join(" · ");
  elements.settlementSummary.innerHTML = `
    <div><span>Debits</span><b>${escapeHtml(Number(ledger.summary.totalDebits || 0).toFixed(4))} ${escapeHtml(ledger.summary.asset)}</b></div>
    <div><span>Credits</span><b>${escapeHtml(Number(ledger.summary.totalCredits || 0).toFixed(4))} ${escapeHtml(ledger.summary.asset)}</b></div>
    <p>${escapeHtml(categorySummary || "No category spend")}</p>
    <p>${escapeHtml(counterpartySummary || "No counterparty spend")}</p>
  `;
  elements.settlementList.innerHTML = ledger.entries.map((entry) => `
    <article class="settlement-row">
      <div>
        <b>${escapeHtml(entry.counterparty)} · ${escapeHtml(entry.category)}</b>
        <small>${escapeHtml(entry.requestId)} · ${escapeHtml(entry.capabilityId)} · ${escapeHtml(entry.paymentProof || "policy")} · ${escapeHtml(entry.displayTx)}</small>
      </div>
      <span>${escapeHtml(entry.direction)} · ${escapeHtml(entry.status)} · ${escapeHtml(entry.amount.toFixed(4))} ${escapeHtml(entry.asset)}</span>
    </article>
  `).join("");
}

function renderRecordList() {
  elements.recordCount.textContent = String(records.length);
  elements.recordList.innerHTML = records.map((record) => `
    <button class="record-item ${record.requestId === selectedRecordId ? "active" : ""}" data-record-id="${escapeHtml(record.requestId)}" type="button">
      <span>
        <b>${escapeHtml(record.requestId)}</b>
        <small>${escapeHtml(compact(record.txHash))}</small>
      </span>
      <em>${escapeHtml(record.receiptStatus)}</em>
    </button>
  `).join("");

  for (const button of elements.recordList.querySelectorAll("button[data-record-id]")) {
    button.addEventListener("click", () => selectRecord(button.dataset.recordId));
  }
}

function nodePosition(type) {
  return {
    request: { left: 14, top: 50 },
    payment: { left: 38, top: 50 },
    receipt: { left: 62, top: 50 },
    status: { left: 86, top: 50 }
  }[type];
}

function renderGraph(record) {
  elements.graphLayer.innerHTML = "";
  elements.edgeLayer.innerHTML = "";
  elements.emptyState.hidden = Boolean(record);
  if (!record) return;

  const nodes = groupRecordNodes(record);
  const rendered = Object.values(nodes).filter(Boolean);
  for (const node of rendered) {
    const position = nodePosition(node.type);
    const nodeElement = document.createElement("article");
    nodeElement.className = `graph-node ${node.type}`;
    nodeElement.style.left = `${position.left}%`;
    nodeElement.style.top = `${position.top}%`;
    nodeElement.innerHTML = `
      <span class="node-type">${escapeHtml(node.type)}</span>
      <b>${escapeHtml(node.label)}</b>
      <code>${escapeHtml(node.primaryValue)}</code>
    `;
    elements.graphLayer.append(nodeElement);
  }

  const edgeData = [
    ["request", "payment"],
    ["payment", "receipt"],
    ["receipt", "status"]
  ];
  const svg = elements.edgeLayer;
  svg.setAttribute("viewBox", "0 0 100 100");
  for (const [source, target] of edgeData) {
    const start = nodePosition(source);
    const end = nodePosition(target);
    const line = document.createElementNS("http://www.w3.org/2000/svg", "path");
    const x1 = start.left + 7;
    const y1 = start.top + 7;
    const x2 = end.left + 7;
    const y2 = end.top + 7;
    const midX = (x1 + x2) / 2;
    const midY = Math.min(y1, y2) - 12;
    line.setAttribute("d", `M ${x1} ${y1} Q ${midX} ${midY} ${x2} ${y2}`);
    line.setAttribute("class", "trust-edge");
    svg.append(line);
  }
}

function renderProofDetails(record) {
  if (!record) {
    elements.proofDetails.className = "proof-details muted-block";
    elements.proofDetails.textContent = "No selected record.";
    return;
  }
  elements.proofDetails.className = "proof-details";
  const details = record.proofDetails;
  elements.proofDetails.innerHTML = `
    <dl>
      <div><dt>Receipt ID</dt><dd>${escapeHtml(record.receiptId)}</dd></div>
      <div><dt>Request Hash</dt><dd>${escapeHtml(compact(details.signedRequestHash, 14, 12))}</dd></div>
      <div><dt>Anchor</dt><dd>${escapeHtml(details.anchoringReference)}</dd></div>
      <div><dt>Policy Hash</dt><dd>${escapeHtml(compact(details.policyHash, 14, 12))}</dd></div>
      <div><dt>Signing Key</dt><dd>${escapeHtml(details.receiptSigningKeyId || "-")}</dd></div>
      <div><dt>Verifier</dt><dd>${escapeHtml(details.verifierIdentity || "-")}</dd></div>
      <div><dt>Explorer</dt><dd>${details.explorerUrl ? `<a href="${escapeHtml(details.explorerUrl)}" target="_blank" rel="noreferrer">Open tx</a>` : "-"}</dd></div>
    </dl>
  `;
}

function render() {
  renderDiscovery();
  renderMemory();
  renderRoutes();
  renderSettlement();
  renderRecordList();
  const selected = records.find((record) => record.requestId === selectedRecordId) || records[0];
  selectedRecordId = selected?.requestId || "";
  elements.workspaceTitle.textContent = selected
    ? `${selected.requestId} is ${selected.receiptStatus}: on-chain settlement is linked to the signed MCP request.`
    : "ACP superapp is ready: discovered apps, memory, routing, and settlement are available.";
  renderGraph(selected);
  renderProofDetails(selected);
}

async function poll() {
  if (!connectedWallet) return;
  if (pollInFlight) return;
  pollInFlight = true;
  setLiveState("polling", "Polling maroo-testnet");
  try {
    const response = await fetch(buildTrustPathUrl(connectedWallet), { cache: "no-store" });
    if (!response.ok) throw new Error(`Indexer returned HTTP ${response.status}`);
    const payload = await response.json();
    records = normalizeTrustPathResponse(payload, connectedWallet);
    superappState = {
      ...superappState,
      routing: [
        routeExecution({
          apps: superappState.apps,
          memory: superappState.memory,
          capabilityId: "notes.append_note",
          amount: 0
        }),
        routeExecution({
          apps: superappState.apps,
          memory: superappState.memory,
          capabilityId: "grocery.purchase_essentials",
          amount: records[0]?.proofDetails?.value || 42
        })
      ],
      settlementLedger: records.length
        ? createSettlementLedger(records)
        : superappState.settlementLedger
    };
    elements.sourceMode.textContent = payload.indexerMode === "live_rpc_block_scan"
      ? `Live RPC scan (${payload.scanBlocks} blocks, ${payload.scanStatus})`
      : "maroo indexer";
    elements.latestBlock.textContent = payload.latestBlock ? String(payload.latestBlock) : "-";
    elements.netVersion.textContent = payload.netVersion || "-";
    if (!selectedRecordId && records[0]) selectedRecordId = records[0].requestId;
    const liveLabel = payload.scanStatus === "scanning"
      ? `Scanning ${payload.scanBlocks} blocks`
      : `${records.length} completed path${records.length === 1 ? "" : "s"}`;
    setLiveState(payload.scanStatus === "scanning" ? "polling" : "live", liveLabel);
    render();
  } catch (error) {
    setLiveState("error", "Indexer unavailable");
    elements.connectionStatus.textContent = error instanceof Error ? error.message : String(error);
  } finally {
    pollInFlight = false;
  }
}

async function hydrateSuperappState() {
  try {
    const response = await fetch("/api/superapp-state", { cache: "no-store" });
    if (!response.ok) throw new Error(`Superapp API returned HTTP ${response.status}`);
    superappState = await response.json();
    render();
  } catch (error) {
    elements.connectionStatus.textContent = error instanceof Error ? error.message : String(error);
    render();
  }
}

async function postJSON(url, body) {
  const response = await fetch(url, {
    method: "POST",
    headers: { "content-type": "application/json" },
    body: JSON.stringify(body)
  });
  const payload = await response.json();
  if (!response.ok) {
    throw new Error(payload.message || payload.error || `HTTP ${response.status}`);
  }
  return payload;
}

async function savePreference(event) {
  event.preventDefault();
  const key = elements.preferenceKey.value.trim();
  const value = elements.preferenceValue.value.trim();
  if (!key || !value) {
    elements.actionStatus.textContent = "Preference key and value are required.";
    return;
  }
  elements.actionStatus.textContent = "Saving preference...";
  try {
    const payload = await postJSON("/api/preferences", {
      userId: "local-user",
      agentId: "agent.meshkit-superapp",
      key,
      value,
      source: "web-ui"
    });
    superappState = payload.state;
    elements.actionStatus.textContent = payload.droppedPreference
      ? `Filtered ${key}: ${payload.droppedPreference.reason}`
      : `Saved ${key}`;
    render();
  } catch (error) {
    elements.actionStatus.textContent = error instanceof Error ? error.message : String(error);
  }
}

async function executeCapability({ capabilityId, amount, requestPrefix }) {
  elements.actionStatus.textContent = "Executing app-to-app MCP...";
  try {
    const payload = await postJSON("/api/execute", {
      capabilityId,
      amount,
      requestId: `${requestPrefix}-${Date.now()}`
    });
    await hydrateSuperappState();
    elements.actionStatus.textContent = `${payload.routeDecision.route} ${payload.transactionRecord.status}: ${payload.transactionRecord.requestId}`;
  } catch (error) {
    elements.actionStatus.textContent = error instanceof Error ? error.message : String(error);
  }
}

function connect() {
  const wallet = elements.walletInput.value.trim();
  if (!wallet) {
    elements.connectionStatus.textContent = "Enter a wallet/account identifier.";
    return;
  }
  connectedWallet = wallet;
  selectedRecordId = "";
  records = [];
  elements.connectionStatus.textContent = `Connected: ${wallet}`;
  elements.connectButton.textContent = "Reconnect";
  if (pollTimer) clearInterval(pollTimer);
  void poll();
  pollTimer = setInterval(poll, POLL_INTERVAL_MS);
}

elements.connectButton.addEventListener("click", connect);
elements.walletInput.addEventListener("keydown", (event) => {
  if (event.key === "Enter") connect();
});
elements.preferenceForm.addEventListener("submit", savePreference);
elements.executeUnpaidButton.addEventListener("click", () => executeCapability({
  capabilityId: "notes.append_note",
  amount: 0,
  requestPrefix: "req-mintnotes-ui"
}));
elements.executePaidButton.addEventListener("click", () => executeCapability({
  capabilityId: "grocery.purchase_essentials",
  amount: 42,
  requestPrefix: "req-dailymart-ui"
}));

void hydrateSuperappState();
