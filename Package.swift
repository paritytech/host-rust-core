// swift-tools-version: 5.10
//
// TrUAPIHost — iOS host package for the Rust TrUAPI core — and TrUAPIProvider —
// chain transport over an embedded smoldot light client with a bundled chain-spec
// catalog — consumed as SPM git dependencies (the manifest must live at the repo
// root for that). Package sources live under ios/truapi-host/ and
// ios/truapi-provider/. The two products are independent and release on separate
// tags. For both, the uniffi-generated bindings are committed build outputs
// (regenerate with the package's scripts/rebuild.sh) while the xcframework is
// gitignored and distributed as a GitHub release asset (scripts/publish.sh).

import Foundation
import PackageDescription

// Set TRUAPI_USE_LOCAL_BINARY=1 to build against the locally generated
// ios/truapi-host/Binaries/truapi_server.xcframework (run rebuild.sh first).
// The published release asset remains the default for remote consumers.
let useLocalBinary = ProcessInfo.processInfo.environment["TRUAPI_USE_LOCAL_BINARY"] == "1"

let publishedBinaryURL = "https://github.com/paritytech/host-rust-core/releases/download/%40parity%2Fios-host%400.7.0/truapi_server.xcframework.zip"
let publishedBinaryChecksum = "682149477072500511ae24bd3f631acb7614e52549ae01f87d8640304db6e5f2"

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
        .library(name: "TrUAPIHost", targets: ["TrUAPIHost"]),
        .library(name: "TrUAPIProvider", targets: ["TrUAPIProvider"]),
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
        .systemLibrary(
            name: "truapi_providerFFI",
            path: "ios/truapi-provider/Sources/truapi_providerFFI/include",
            pkgConfig: nil,
            providers: []
        ),
        providerBinaryTarget,
        .target(
            name: "TrUAPIProvider",
            dependencies: ["truapi_providerFFI", "truapi_providerFFI_binary"],
            path: "ios/truapi-provider/Sources/TrUAPIProvider"
        ),
    ]
)
