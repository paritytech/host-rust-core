// swift-tools-version: 5.10
//
// Two products, consumed as SPM git dependencies (the manifest must live at the
// repo root for that):
//
//   * TrUAPIHost — the iOS host package for the Rust TrUAPI core. Sources under
//     ios/truapi-host/.
//   * TrUAPIProvider — chain transport (embedded smoldot light client plus a
//     bundled chain-spec catalog) for a native host that wants its own network
//     access. Sources under ios/truapi-provider/. Independent of TrUAPIHost:
//     depend on whichever you need.
//
// For both, the uniffi-generated bindings are committed build outputs
// (regenerate with the package's scripts/rebuild.sh) while the xcframework is
// gitignored and distributed as a GitHub release asset (scripts/publish.sh).

import Foundation
import PackageDescription

// Set TRUAPI_USE_LOCAL_BINARY=1 to build against the locally generated
// ios/truapi-host/Binaries/truapi_server.xcframework (run rebuild.sh first).
// The published release asset remains the default for remote consumers.
let useLocalBinary = ProcessInfo.processInfo.environment["TRUAPI_USE_LOCAL_BINARY"] == "1"

let publishedBinaryURL = "https://github.com/paritytech/truapi/releases/download/%40parity%2Fios-host%400.4.0-chat-modality-shared-core.4/truapi_server.xcframework.zip"
let publishedBinaryChecksum = "b4d7e633e8a86bdaf104a1bcafc883549fc893514451fe7caeb951107e5038f7"

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

// The provider ships its own xcframework on the same terms, with its own toggle:
// the two products release independently, so building one against a local
// binary must not force the other to have one. Set
// TRUAPI_PROVIDER_USE_LOCAL_BINARY=1 after ios/truapi-provider/scripts/rebuild.sh.
let useLocalProviderBinary =
    ProcessInfo.processInfo.environment["TRUAPI_PROVIDER_USE_LOCAL_BINARY"] == "1"
// Set by ios/truapi-provider/scripts/publish.sh. Until the first release exists,
// remote resolution of TrUAPIProvider fails on the checksum: build it locally
// with scripts/rebuild.sh and TRUAPI_PROVIDER_USE_LOCAL_BINARY=1 meanwhile.
let providerBinaryURL = "https://github.com/paritytech/truapi/releases/download/%40parity%2Fios-provider%400.0.0-unpublished/truapi_provider.xcframework.zip"
let providerBinaryChecksum = "0000000000000000000000000000000000000000000000000000000000000000"

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
