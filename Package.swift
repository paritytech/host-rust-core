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

let publishedBinaryURL = "https://github.com/paritytech/truapi/releases/download/%40parity%2Fios-host%400.3.0/truapi_server.xcframework.zip"
let publishedBinaryChecksum = "c2eeb3d79d3186f4b85de43a18fd7df127a2f3ffe814def9b7dd4e1b897934e0"

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
