// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "PadelKit",
    platforms: [
        .iOS(.v17),
        .watchOS(.v10),
        .macOS(.v14),
    ],
    products: [
        .library(name: "PadelCore", targets: ["PadelCore"]),
        .library(name: "PadelSync", targets: ["PadelSync"]),
        .library(name: "PadelStore", targets: ["PadelStore"]),
    ],
    targets: [
        // Pure domain: models, formats, scheduling, scoring, standings. Foundation only.
        .target(name: "PadelCore"),
        // iPhone <-> Watch synchronization protocol, outbox and reconciliation.
        .target(name: "PadelSync", dependencies: ["PadelCore"]),
        // Persistence and observable app/watch state containers.
        .target(name: "PadelStore", dependencies: ["PadelCore", "PadelSync"]),
        .testTarget(name: "PadelCoreTests", dependencies: ["PadelCore"]),
        .testTarget(name: "PadelSyncTests", dependencies: ["PadelCore", "PadelSync", "PadelStore"]),
        .testTarget(name: "PadelStoreTests", dependencies: ["PadelCore", "PadelSync", "PadelStore"]),
    ]
)
