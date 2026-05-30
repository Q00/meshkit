import SwiftUI
import MeshKit

private enum HermesRequestSigningTrust {
    static func publicKeyBase64() throws -> String {
        guard let raw = ProcessInfo.processInfo.environment["MESHKIT_IOS_DEMO_PUBLIC_KEY_BASE64"],
              !raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw MeshKitValidationError.signatureRequired
        }
        return raw
    }
}

@main
struct MintNotesApp: App {
    @State private var incoming = "Waiting for notes.append_note request from Hermes Chat."
    @State private var saved = "No note saved yet."
    @State private var request: MeshRequest?
    private let replayCache = MeshReplayCache()

    var body: some Scene {
        WindowGroup {
            ZStack {
                LinearGradient(colors: [Color(red: 0.04, green: 0.20, blue: 0.16), Color(red: 0.02, green: 0.45, blue: 0.34)], startPoint: .top, endPoint: .bottom).ignoresSafeArea()
                VStack(alignment: .leading, spacing: 18) {
                    Text("Mint Notes").font(.largeTitle.bold()).foregroundColor(.white)
                    Text("Target app • notes.append_note").foregroundColor(.mint)
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Received MeshKit request").font(.headline).foregroundColor(.white)
                        Text(incoming).foregroundColor(.white.opacity(0.9))
                    }.padding().background(Color.white.opacity(0.12)).cornerRadius(20)
                    Button(action: approveAndSave) {
                        Text("Approve & Save, then callback Hermes").font(.headline).frame(maxWidth: .infinity).padding().background(Color.mint).foregroundColor(.black).cornerRadius(18)
                    }
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Saved note").font(.title2.bold()).foregroundColor(.white)
                        Text(saved).foregroundColor(.white.opacity(0.9))
                    }.padding().background(Color.white.opacity(0.12)).cornerRadius(20)
                    Spacer()
                }.padding(24)
            }
            .onOpenURL { url in
                handleIncoming(url)
            }
        }
    }

    private func handleIncoming(_ url: URL) {
        guard let encoded = URLComponents(url: url, resolvingAgainstBaseURL: false)?
            .queryItems?
            .first(where: { $0.name == "mesh_request" })?
            .value else {
            incoming = "Invalid request: missing mesh_request."
            return
        }
        do {
            let decoded = try MeshRequest.decodedFromURLScheme(encoded)
            request = decoded
            incoming = "Decoded request. Consent required before writing user content. Production preview requires verified transport caller.\n\nPayload: \(decoded.payload)"
        } catch {
            request = nil
            incoming = "Rejected MeshKit request: \(error)"
        }
    }

    private func approveAndSave() {
        guard let request else {
            saved = "No valid request to approve."
            return
        }
        do {
            let target = try MeshProductionTarget(
                policy: MeshTargetPolicy(
                    allowedCallerAppId: "app.hermes-chat",
                    targetBundleId: "ai.meshkit.sample.mintnotes",
                    capabilityId: "notes.append_note"
                ),
                trust: MeshSenderTrust(
                    callerAppId: "app.hermes-chat",
                    callerBundleId: "ai.meshkit.sample.hermeschat",
                    teamId: "DEVTEAMID",
                    requestSigningAlgorithm: "Ed25519",
                    requestSigningKeyId: "sample-ios-ed25519",
                    publicKey: try HermesRequestSigningTrust.publicKeyBase64()
                ),
                invocationPolicy: MeshInvocationPolicy(
                    risk: "write:user_content",
                    consent: "per_invocation",
                    userApproved: true,
                    registrySignatureVerified: true
                ),
                replayCache: replayCache
            )
            let audit = try target.validate(
                request,
                // URL-scheme demos cannot cryptographically observe the source app.
                // Production iOS integrations should use Universal Links/App Intents/relay metadata
                // that can bind the observed caller instead of trusting a request claim.
                observedCallerBundleId: "ai.meshkit.sample.hermeschat"
            )
            let noteRef = request.payload["note_ref"] ?? "ios:mint:demo"
            let text = request.payload["text"] ?? ""
            appendStoredNote(noteRef: noteRef, text: text)
            let callback = "meshkit-hermes://callback?status=appended&capability=notes.append_note&note_ref=\(urlEscape(noteRef))&audit_id=\(urlEscape(audit.requestId))&receipt_token=\(urlEscape(request.requestId))&receipt_sig=demo-signed-receipt"
            UIApplication.shared.open(URL(string: callback)!)
        } catch {
            saved = "Rejected before execution: \(error)"
        }
    }

    private func appendStoredNote(noteRef: String, text: String) {
        saved = "\(noteRef)\n\n\(text)"
    }

    private func urlEscape(_ value: String) -> String {
        value.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? value
    }
}
