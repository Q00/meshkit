import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import test from "node:test";

test("RN first screen exposes the required MeshKit superapp surfaces", async () => {
  const app = await readFile(new URL("../App.tsx", import.meta.url), "utf8");
  for (const required of [
    "Discovery",
    "Agent Chat",
    "Memory",
    "Route / Execution",
    "Ledger",
    "MintNotes Off-chain",
    "DailyMart 42 OKRW",
    "payment_proof_policy",
    "executeDailyMartOnchain",
    "executeMintNotesOffchain",
    "sendAgentChat",
    "summarizeSuperappState",
    "StatusBanner",
    "ActionButton",
    "actionLockRef",
    "configureApiPlatform(Platform.OS)",
    "accessibilityLiveRegion=\"polite\"",
    "accessibilityState={{ disabled: Boolean(disabled), busy: Boolean(disabled) }}",
    "accessibilityLabel=\"Save preference memory\"",
    "Retry loading superapp state",
    "No ACP apps discovered.",
    "KeyboardAvoidingView",
    "accessibilityLabel=\"Agent chat message\"",
    "accessibilityLabel=\"Send agent chat message\"",
    "Start a real conversation with the MeshKit agent."
  ]) {
    assert.ok(app.includes(required), `App.tsx missing ${required}`);
  }
  for (const requiredStyle of [
    "flexWrap: \"wrap\"",
    "minHeight: 44",
    "hitSlop={6}",
    "hitSlop={8}",
    "numberOfLines={1}",
    "numberOfLines={2}",
    "ellipsizeMode=\"middle\"",
    "ellipsizeMode=\"tail\"",
    "color: \"#52616f\""
  ]) {
    assert.ok(app.includes(requiredStyle), `App.tsx missing responsive/accessibility style ${requiredStyle}`);
  }
});
