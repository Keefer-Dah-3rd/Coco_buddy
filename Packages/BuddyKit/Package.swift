// swift-tools-version: 6.0
import PackageDescription

// BuddyKit holds everything that doesn't need a window: models, timing,
// persistence and the character's pose math. Keeping it UI-free means it can be
// tested with `swift test` without launching the app.
let package = Package(
    name: "BuddyKit",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "BuddyCore", targets: ["BuddyCore"]),
        .library(name: "BuddyCharacter", targets: ["BuddyCharacter"]),
        .library(name: "BuddyIntegrations", targets: ["BuddyIntegrations"]),
        .library(name: "BuddyAssistant", targets: ["BuddyAssistant"]),
    ],
    targets: [
        .target(name: "BuddyCore"),
        .target(name: "BuddyCharacter"),
        // Google Calendar + Notion: request building, response parsing, scheduling maths.
        // No networking or Keychain here — those live in the app, so this stays testable.
        .target(name: "BuddyIntegrations", dependencies: ["BuddyCore"]),
        // The chat assistant: Claude Messages API wire format, streaming, tools, prompts.
        .target(name: "BuddyAssistant", dependencies: ["BuddyCore", "BuddyIntegrations"]),
        .testTarget(name: "BuddyCoreTests", dependencies: ["BuddyCore"]),
        .testTarget(name: "BuddyCharacterTests", dependencies: ["BuddyCharacter"]),
        .testTarget(name: "BuddyIntegrationsTests", dependencies: ["BuddyIntegrations"]),
        .testTarget(name: "BuddyAssistantTests", dependencies: ["BuddyAssistant"]),
    ]
)
