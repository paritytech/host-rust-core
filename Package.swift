// swift-tools-version: 5.10
//
// TrUAPIHost — iOS host package for the Rust TrUAPI core, consumed as an SPM
// git dependency (the manifest must live at the repo root for that). All
// package sources live under ios/truapi-host/; the xcframework, the
// uniffi-generated bindings, and the container bundle are committed build
// outputs — regenerate with ios/truapi-host/scripts/rebuild.sh and commit the
// result after changing the Rust core or container sources.

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
            path: "ios/truapi-host/Sources/truapi_serverFFI/include",
            pkgConfig: nil,
            providers: []
        ),
        .binaryTarget(
            name: "truapi_serverFFI_binary",
            path: "ios/truapi-host/Binaries/truapi_server.xcframework"
        ),
        .target(
            name: "TrUAPIHost",
            dependencies: ["truapi_serverFFI", "truapi_serverFFI_binary"],
            path: "ios/truapi-host/Sources/TrUAPIHost",
            resources: [.copy("Resources/truapi-container.js")]
        ),
        .testTarget(
            name: "TrUAPIHostTests",
            dependencies: ["TrUAPIHost"],
            path: "ios/truapi-host/Tests"
        ),
    ]
)
