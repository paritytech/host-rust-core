// swift-tools-version: 5.10
//
// TrUAPIHost — iOS host package for the Rust TrUAPI core, consumed as an SPM
// git dependency (the manifest must live at the repo root for that). All
// package sources live under ios/truapi-host/. The uniffi-generated bindings
// and the container bundle are committed build outputs (regenerate with
// ios/truapi-host/scripts/rebuild.sh); the xcframework is gitignored and
// distributed as a GitHub release asset (ios/truapi-host/scripts/publish.sh).

import PackageDescription

// Flip to true to build against the locally generated
// ios/truapi-host/Binaries/truapi_server.xcframework (run rebuild.sh first);
// false consumes the published release asset below (updated by publish.sh).
let useLocalBinary = false

let publishedBinaryURL = "https://github.com/paritytech/truapi-ios/releases/download/v0.2.0/truapi_server.xcframework.zip"
let publishedBinaryChecksum = "4fb2754c9804850634261a7cc6e1ae3252326fe1e2700f4aebd4dc4cfcd12e6b"

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
            name: "truapi_serverFFI",
            path: "ios/truapi-host/Sources/truapi_serverFFI/include",
            pkgConfig: nil,
            providers: []
        ),
        binaryTarget,
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
