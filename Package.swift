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

let publishedBinaryURL = "https://github.com/paritytech/host-rust-core/releases/download/%40parity%2Fios-host%400.12.0/truapi_server.xcframework.zip"
let publishedBinaryChecksum = "ffd4633189a779f3206e90a6e9195d1a4fa4778e6d3321cad33a61d6be3995b9"

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

// Set TRUAPI_PROVIDER_USE_LOCAL_BINARY=1 to build against the locally generated
// ios/truapi-provider/Binaries/truapi_provider.xcframework (run rebuild.sh
// first). Separate from TRUAPI_USE_LOCAL_BINARY because the products release
// independently: a local build of one must not require a local build of the other.
let useLocalProviderBinary =
    ProcessInfo.processInfo.environment["TRUAPI_PROVIDER_USE_LOCAL_BINARY"] == "1"

// Set by ios/truapi-provider/scripts/publish.sh. No release exists yet, so remote
// resolution fails on the checksum until the first publish.

let providerBinaryURL = "https://github.com/paritytech/host-rust-core/releases/download/%40parity%2Fios-provider%400.7.0/truapi_provider.xcframework.zip"
let providerBinaryChecksum = "04fd47522fad5b12048396efae5d34c40f049623678066215654a3c9166d2bb3"

let providerBinaryTarget: Target = useLocalProviderBinary
    ? .binaryTarget(
        name: "truapi_providerFFI_binary",
        path: "ios/truapi-provider/Binaries/truapi_provider.xcframework"
    )
    : .binaryTarget(
        name: "truapi_providerFFI_binary",
        url: providerBinaryURL,
        checksum: providerBinaryChecksum
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
