import assert from "node:assert/strict";
import test from "node:test";
import {
  buildTrustPathUrl,
  isMainGraphRecord,
  normalizeTrustPathResponse,
  validateTrustPathRecord
} from "../src/trust-path.js";

function validRecord(overrides = {}) {
  const record = {
    provider: "maroo",
    network: "maroo-testnet",
    chainId: "maroo-testnet-1",
    walletAccount: "maroo1demo",
    requestId: "req-1",
    txHash: "0xabc",
    receiptId: "receipt-1",
    receiptStatus: "trusted",
    proofStatus: "trusted_path_complete",
    lifecycleState: "receipt_trusted",
    isComplete: true,
    graphNodes: [
      { id: "request", type: "request", label: "Request", primaryValue: "req-1" },
      { id: "payment", type: "payment", label: "Payment", primaryValue: "0xabc" },
      { id: "receipt", type: "receipt", label: "Receipt", primaryValue: "receipt-1" },
      { id: "status", type: "status", label: "Status", primaryValue: "trusted" }
    ],
    graphEdges: [
      { id: "e1", type: "request_to_payment", source: "request", target: "payment" },
      { id: "e2", type: "payment_to_receipt", source: "payment", target: "receipt" },
      { id: "e3", type: "receipt_to_status", source: "receipt", target: "status" }
    ],
    proofDetails: {
      signedRequestHash: "a".repeat(64),
      anchoringReference: "maroo-testnet:anchor:1",
      policyHash: "b".repeat(64),
      from: "0xfrom",
      to: "0xto",
      value: "1.0000",
      blockHash: "0xblock",
      blockNumber: "100",
      transactionIndex: "0"
    }
  };
  return { ...record, ...overrides };
}

test("buildTrustPathUrl pins maroo-testnet and wallet filter", () => {
  assert.equal(
    buildTrustPathUrl("maroo1demo"),
    "/api/trust-paths?wallet=maroo1demo&network=maroo-testnet"
  );
});

test("validateTrustPathRecord accepts the required TrustPathRecord contract", () => {
  assert.deepEqual(validateTrustPathRecord(validRecord()), []);
});

test("validateTrustPathRecord rejects wrong provider and broken edges", () => {
  const errors = validateTrustPathRecord(validRecord({
    provider: "other",
    graphEdges: [{ id: "bad", type: "request_to_payment", source: "missing", target: "payment" }]
  }));
  assert(errors.includes("provider must equal maroo"));
  assert(errors.includes("GraphEdge.source must match a node id"));
});

test("isMainGraphRecord only allows complete trusted or verified records", () => {
  assert.equal(isMainGraphRecord(validRecord()), true);
  assert.equal(isMainGraphRecord(validRecord({ receiptStatus: "verified" })), true);
  assert.equal(isMainGraphRecord(validRecord({ isComplete: false })), false);
  assert.equal(isMainGraphRecord(validRecord({ receiptStatus: "unverified" })), false);
  assert.equal(isMainGraphRecord(validRecord({ receiptStatus: "failed" })), false);
});

test("normalizeTrustPathResponse filters by connected wallet and hides incomplete records", () => {
  const records = normalizeTrustPathResponse({
    records: [
      validRecord({ requestId: "mine" }),
      validRecord({ requestId: "other", walletAccount: "maroo1other" }),
      validRecord({ requestId: "pending", isComplete: false }),
      validRecord({ requestId: "unverified", receiptStatus: "unverified" })
    ]
  }, "maroo1demo");

  assert.equal(records.length, 1);
  assert.equal(records[0].requestId, "mine");
});
