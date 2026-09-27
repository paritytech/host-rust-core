// swift-tools-version: 5.10
//
// TrUAPIProvider — chain transport over an embedded smoldot light client with a
// bundled chain-spec catalog. The uniffi-generated bindings and the xcframework
// are gitignored build outputs: regenerate them with scripts/rebuild.sh.

import PackageDescription

let package = Package(
    name: "TrUAPIProvider",
    platforms: [.iOS(.v17)],
    products: [
        .library(name: "TrUAPIProvider", targets: ["TrUAPIProvider"]),
    ],
    targets: [
        .systemLibrary(
            name: "truapi_providerFFI",
            path: "Sources/truapi_providerFFI/include",
            pkgConfig: nil,
            providers: []
        ),
        .binaryTarget(
            name: "truapi_providerFFI_binary",
            path: "Binaries/truapi_provider.xcframework"
        ),
        .target(
            name: "TrUAPIProvider",
            dependencies: ["truapi_providerFFI", "truapi_providerFFI_binary"],
            path: "Sources/TrUAPIProvider"
        ),
    ]
)
