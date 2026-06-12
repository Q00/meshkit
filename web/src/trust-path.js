export const NETWORK = "maroo-testnet";
export const POLL_INTERVAL_MS = 2000;

export const receiptStatuses = new Set(["trusted", "verified", "unverified", "failed", "expired"]);
export const visibleReceiptStatuses = new Set(["trusted", "verified"]);
export const lifecycleStates = new Set([
  "request_indexed",
  "payment_detected",
  "receipt_issued",
  "receipt_trusted",
  "receipt_verified",
  "failed",
  "expired"
]);
export const proofStatuses = new Set(["trusted_path_complete", "backend_verified", "pending", "failed"]);
export const graphNodeTypes = new Set(["request", "payment", "receipt", "status"]);
export const graphEdgeTypes = new Set(["request_to_payment", "payment_to_receipt", "receipt_to_status"]);

const requiredRecordFields = [
  "provider",
  "network",
  "walletAccount",
  "requestId",
  "txHash",
  "receiptId",
  "receiptStatus",
  "proofStatus",
  "lifecycleState",
  "isComplete",
  "graphNodes",
  "graphEdges",
  "proofDetails"
];

const requiredProofFields = ["signedRequestHash", "anchoringReference", "policyHash"];

export function buildTrustPathUrl(walletAccount) {
  const params = new URLSearchParams({ wallet: walletAccount, network: NETWORK });
  return `/api/trust-paths?${params.toString()}`;
}

function hasText(value) {
  return typeof value === "string" && value.trim() === value && value.length > 0;
}

export function validateTrustPathRecord(record) {
  const errors = [];
  if (!record || typeof record !== "object") {
    return ["record must be an object"];
  }

  for (const field of requiredRecordFields) {
    if (!(field in record)) errors.push(`${field} is required`);
  }
  if (record.provider !== "maroo") errors.push("provider must equal maroo");
  if (record.network !== NETWORK) errors.push("network must equal maroo-testnet");
  if (record.chainId !== undefined && record.chainId !== "maroo-testnet-1") {
    errors.push("chainId must equal maroo-testnet-1 when present");
  }
  if (!hasText(record.walletAccount)) errors.push("walletAccount must be non-empty text");
  if (!hasText(record.requestId)) errors.push("requestId must be non-empty text");
  if (!hasText(record.txHash)) errors.push("txHash must be non-empty text");
  if (!hasText(record.receiptId)) errors.push("receiptId must be non-empty text");
  if (!receiptStatuses.has(record.receiptStatus)) errors.push("receiptStatus is not allowed");
  if (!proofStatuses.has(record.proofStatus)) errors.push("proofStatus is not allowed");
  if (!lifecycleStates.has(record.lifecycleState)) errors.push("lifecycleState is not allowed");
  if (typeof record.isComplete !== "boolean") errors.push("isComplete must be boolean");

  if (!Array.isArray(record.graphNodes)) {
    errors.push("graphNodes must be an array");
  } else {
    const ids = new Set();
    for (const node of record.graphNodes) {
      if (!hasText(node?.id)) errors.push("GraphNode.id is required");
      if (!graphNodeTypes.has(node?.type)) errors.push("GraphNode.type is not allowed");
      if (!hasText(node?.label)) errors.push("GraphNode.label is required");
      if (!hasText(node?.primaryValue)) errors.push("GraphNode.primaryValue is required");
      if (node?.id) ids.add(node.id);
    }

    if (!Array.isArray(record.graphEdges)) {
      errors.push("graphEdges must be an array");
    } else {
      for (const edge of record.graphEdges) {
        if (!hasText(edge?.id)) errors.push("GraphEdge.id is required");
        if (!graphEdgeTypes.has(edge?.type)) errors.push("GraphEdge.type is not allowed");
        if (!ids.has(edge?.source)) errors.push("GraphEdge.source must match a node id");
        if (!ids.has(edge?.target)) errors.push("GraphEdge.target must match a node id");
      }
    }
  }

  for (const field of requiredProofFields) {
    if (!hasText(record.proofDetails?.[field])) {
      errors.push(`proofDetails.${field} is required`);
    }
  }
  return errors;
}

export function isMainGraphRecord(record) {
  return record?.isComplete === true && visibleReceiptStatuses.has(record.receiptStatus);
}

export function normalizeTrustPathResponse(payload, walletAccount) {
  const records = Array.isArray(payload?.records) ? payload.records : [];
  return records
    .filter((record) => record.walletAccount === walletAccount)
    .filter((record) => validateTrustPathRecord(record).length === 0)
    .filter(isMainGraphRecord);
}

export function groupRecordNodes(record) {
  return {
    request: record.graphNodes.find((node) => node.type === "request"),
    payment: record.graphNodes.find((node) => node.type === "payment"),
    receipt: record.graphNodes.find((node) => node.type === "receipt"),
    status: record.graphNodes.find((node) => node.type === "status")
  };
}
