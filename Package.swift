// swift-tools-version: 5.10
//
// TrUAPIHost — iOS host package for the Rust TrUAPI core, consumed as an SPM
// git dependency (the manifest must live at the repo root for that). All
// package sources live under ios/truapi-host/. The uniffi-generated bindings
// and the container bundle are committed build outputs (regenerate with
// ios/truapi-host/scripts/rebuild.sh); the xcframework is gitignored and
// distributed as a GitHub release asset (ios/truapi-host/scripts/publish.sh).

import Foundation
import PackageDescription

// Set TRUAPI_USE_LOCAL_BINARY=1 to build against the locally generated
// ios/truapi-host/Binaries/truapi_server.xcframework (run rebuild.sh first).
// The published release asset remains the default for remote consumers.
let useLocalBinary = ProcessInfo.processInfo.environment["TRUAPI_USE_LOCAL_BINARY"] == "1"

let publishedBinaryURL = "https://github.com/paritytech/truapi/releases/download/%40parity%2Fios-host%400.4.0-chat-modality-shared-core.1/truapi_server.xcframework.zip"
let publishedBinaryChecksum = "eb0d19f57256bc4a57e693cd85b50db9d111c95fb4f7d5f77bc518d537d305fa"

let binaryTarget: Target = useLocalBinary
    ? .binaryTarget(
        name: "truapi_serverFFI_binary",
        path: "ios/truapi-host/Binaries/truapi_server.xcframework"
    )
    : .binaryTarget(
        name: "truapi_serverFFI_binary",
        url: publishedBinaryURL,
        checksum: publishedBinaryChecksum
    )

let package = Package(
    name: "TrUAPIHost",
    platforms: [.iOS(.v17)],
    products: [
        .library(name: "TrUAPIHost", targets: ["TrUAPIHost"])
    ],
    targets: [
        .systemLibrary(
            name: "truapiFFI",
            path: "ios/truapi-host/Sources/truapiFFI/include",
            pkgConfig: nil,
            providers: []
        ),
        .systemLibrary(
            name: "truapi_platformFFI",
            path: "ios/truapi-host/Sources/truapi_platformFFI/include",
            pkgConfig: nil,
            providers: []
        ),
        .systemLibrary(
            name: "truapi_serverFFI",
            path: "ios/truapi-host/Sources/truapi_serverFFI/include",
            pkgConfig: nil,
            providers: []
        ),
        binaryTarget,
        .target(
            name: "TrUAPIHost",
            dependencies: [
                "truapiFFI", "truapi_platformFFI", "truapi_serverFFI", "truapi_serverFFI_binary",
            ],
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
