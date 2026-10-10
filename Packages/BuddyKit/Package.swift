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
    ],
    targets: [
        .target(name: "BuddyCore"),
        .target(name: "BuddyCharacter"),
        .testTarget(name: "BuddyCoreTests", dependencies: ["BuddyCore"]),
        .testTarget(name: "BuddyCharacterTests", dependencies: ["BuddyCharacter"]),
    ]
)
