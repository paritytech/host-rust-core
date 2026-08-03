// swift-tools-version: 5.10
//
// TrUAPI iOS host package: Rust core (xcframework binary target) +
// uniffi-generated bindings + the hand-written host shell + the bundled
// TS lockdown container.
//
// The xcframework, the generated bindings, and the container bundle are
// gitignored build outputs — run scripts/rebuild.sh after checkout and after
// changing the Rust core or container sources.

import PackageDescription

let package = Package(
    name: "TrUAPIHost",
    platforms: [.iOS(.v17)],
    products: [
        .library(name: "TrUAPIHost", targets: ["TrUAPIHost"])
    ],
    targets: [
        .systemLibrary(
            name: "truapi_serverFFI",
            path: "Sources/truapi_serverFFI/include",
            pkgConfig: nil,
            providers: []
        ),
        .binaryTarget(
            name: "truapi_serverFFI_binary",
            path: "Binaries/truapi_server.xcframework"
        ),
        .target(
            name: "TrUAPIHost",
            dependencies: ["truapi_serverFFI", "truapi_serverFFI_binary"],
            path: "Sources/TrUAPIHost",
            resources: [.copy("Resources/truapi-container.js")]
        ),
        .testTarget(
            name: "TrUAPIHostTests",
            dependencies: ["TrUAPIHost"],
            path: "Tests"
        ),
    ]
)
