import assert from "node:assert/strict";
import { execFileSync } from "node:child_process";
import { mkdtemp, rm, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import test from "node:test";

const repoRoot = new URL("../..", import.meta.url);
const swiftSource = new URL("meshkit-ios/Sources/MeshKit/OpenCapabilityGraph.swift", repoRoot);

test("Swift ACP projection compiles and returns the web superapp descriptor contract", async () => {
  const dir = await mkdtemp(join(tmpdir(), "meshkit-swift-acp-projection-"));
  try {
    const verifierPath = join(dir, "main.swift");
    const outputPath = join(dir, "verify-acp-projection");
    await writeFile(verifierPath, `
import Foundation

let graph = OpenCapabilityGraph(
    schemaVersion: "0.1",
    apps: OpenCapabilityGraph.mintNotesSample.apps + OpenCapabilityGraph.dailyMartSample.apps
)
let descriptors = graph.acpRegistryDescriptors()
let mintNotes = descriptors.first { $0.appId == "app.mint-notes" }!
let dailyMart = descriptors.first { $0.appId == "app.dailymart" }!

precondition(descriptors.count == 2)
precondition(mintNotes.ocgAppId == "ai.meshkit.sample.notes")
precondition(mintNotes.mcpTransport == "app-to-app-url-scheme")
precondition(mintNotes.registrySource == "meshkit-ios-sample")
precondition(mintNotes.capabilities.first!.routingHint == "offchain_app_call")
precondition(mintNotes.capabilities.first!.requiresPayment == false)
precondition(dailyMart.ocgAppId == "ai.meshkit.sample.dailymart")
precondition(dailyMart.capabilities.first!.routingHint == "onchain_payment")
precondition(dailyMart.capabilities.first!.requiresPayment == true)
precondition(dailyMart.capabilities.first!.asset == "OKRW")
print("swift-acp-projection-ok")
`, "utf8");

    execFileSync("swiftc", [swiftSource.pathname, verifierPath, "-o", outputPath], {
      cwd: new URL("../..", import.meta.url),
      stdio: "pipe"
    });
    const output = execFileSync(outputPath, [], { encoding: "utf8" }).trim();
    assert.equal(output, "swift-acp-projection-ok");
  } finally {
    await rm(dir, { recursive: true, force: true });
  }
});
