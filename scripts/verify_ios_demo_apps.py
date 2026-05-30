#!/usr/bin/env python3
from pathlib import Path
root = Path(__file__).resolve().parents[1]
checks = {
    "meshkit-ios/Samples/HermesChatApp/Package.swift": ["HermesChatApp", "MeshKit"],
    "meshkit-ios/Samples/HermesChatApp/Sources/HermesChatApp/main.swift": ["Hermes Chat", "Open Mint Notes", "mintnotes://mesh/invoke", "Hermes Hub"],
    "meshkit-ios/Samples/MintNotesApp/Package.swift": ["MintNotesApp", "MeshKit"],
    "meshkit-ios/Samples/MintNotesApp/Sources/MintNotesApp/main.swift": ["Mint Notes", "Approve & Save", "meshkit-hermes://callback", "notes.append_note"],
}
for rel, needles in checks.items():
    path = root / rel
    assert path.exists(), f"missing {rel}"
    text = path.read_text()
    for needle in needles:
        assert needle in text, f"{rel} missing {needle}"
print("iOS demo app scaffold verification passed")
