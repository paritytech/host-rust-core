// swift-tools-version: 5.10
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "Coinage",
    defaultLocalization: "en",
    platforms: [.iOS(.v17)],
    products: [
        .library(
            name: "Coinage",
            targets: ["Coinage"]
        )
    ],
    dependencies: [
        .package(
            url: "https://github.com/novasamatech/Keystore-iOS",
            from: "1.0.1"
        ),
        .package(
            url: "https://github.com/novasamatech/substrate-sdk-ios",
            from: "5.7.0"
        ),
        .package(
            url: "https://github.com/novasamatech/Crypto-iOS",
            from: "0.3.0"
        ),
        .package(
            url: "https://github.com/novasamatech/extrinsic-service-ios",
            from: "1.11.0"
        ),
        .package(
            url: "https://github.com/attaswift/BigInt",
            from: "5.5.1"
        ),
        .package(
            url: "https://github.com/novasamatech/logger-ios",
            from: "0.0.1"
        ),
        .package(
            url: "https://github.com/novasamatech/Operation-iOS",
            from: "2.3.0"
        ),
        .package(
            url: "https://github.com/apple/swift-async-algorithms",
            from: "1.0.4"
        ),
        .package(
            url: "https://github.com/sideeffect-io/AsyncExtensions",
            exact: "0.5.4"
        ),
        .package(
            url: "https://github.com/pointfreeco/swift-clocks",
            from: "1.0.6"
        ),
        .package(path: "../KeyDerivation"),
        .package(path: "../StructuredConcurrency"),
        .package(path: "../CommonService"),
        .package(path: "../OperationExt"),
        .package(path: "../ChainStore"),
        .package(path: "../FoundationExt"),
        .package(path: "../SubstrateSdkExt"),
        .package(path: "../XcmDefinition"),
        .package(path: "../Individuality"),
        .package(path: "../StateMachine"),
        .package(path: "../SubstrateOperation"),
        .package(path: "../BackgroundExecution"),
        .package(path: "../ExtrinsicServiceExt"),
        .package(path: "../DurableTransactions")
    ],
    targets: [
        .target(
            name: "Coinage",
            dependencies: [
                .product(name: "Keystore-iOS", package: "keystore-ios"),
                .product(name: "SubstrateSdk", package: "substrate-sdk-ios"),
                .product(name: "SubstrateStorageSubscription", package: "substrate-sdk-ios"),
                .product(name: "NovaCrypto", package: "crypto-ios"),
                .product(name: "ExtrinsicService", package: "extrinsic-service-ios"),
                .product(name: "BigInt", package: "BigInt"),
                .product(name: "SDKLogger", package: "logger-ios"),
                .product(name: "Operation-iOS", package: "operation-ios"),
                .product(name: "AsyncAlgorithms", package: "swift-async-algorithms"),
                .product(name: "AsyncExtensions", package: "AsyncExtensions"),
                "KeyDerivation",
                "StructuredConcurrency",
                "CommonService",
                "OperationExt",
                "ChainStore",
                "FoundationExt",
                "SubstrateSdkExt",
                "XcmDefinition",
                "Individuality",
                "StateMachine",
                "SubstrateOperation",
                "BackgroundExecution",
                "ExtrinsicServiceExt",
                "DurableTransactions"
            ],
        ),
        .testTarget(
            name: "CoinageTests",
            dependencies: [
                "Coinage",
                "BackgroundExecution",
                "ExtrinsicServiceExt",
                "DurableTransactions",
                .product(name: "DurableTransactionsTestSupport", package: "DurableTransactions"),
                .product(name: "Clocks", package: "swift-clocks")
            ],
            path: "Tests"
        )
    ]
)
