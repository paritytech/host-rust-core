import Foundation
import os
import BulletinChain
import ChainRegistry
import Products
import TrUAPIHost

/// The process-wide Pocket worker supervisor and the faces read off it.
///
/// Built once at startup, where the product resolver and the runtime provider
/// are both in hand, and read from the card views, which have neither.
final class PocketWorkerFacade: @unchecked Sendable {
    static let shared = PocketWorkerFacade()

    private struct Assembled {
        let products: any ProductResolving
        let dotNsResolver: any DotNsResolverProtocol
        let ipfsUrl: @Sendable (String) -> URL?
    }

    private let held = OSAllocatedUnfairLock<(any PocketFaceSourcing)?>(initialState: nil)
    private let assembled = OSAllocatedUnfairLock<Assembled?>(initialState: nil)

    private init() {}

    /// Nil until startup has assembled it, which is also while there is no
    /// runtime for a worker to open against.
    var faces: (any PocketFaceSourcing)? { held.withLock { $0 } }

    /// Resolves the images inside `productId`'s faces, out of that product's
    /// own worker archive. Nil before startup has assembled the Pocket.
    func images(of productId: ProductId) -> PocketImageResolver? {
        guard let assembled = assembled.withLock({ $0 }) else { return nil }

        return PocketImageResolver(
            contentId: { try? await assembled.products.resolve(productId).executables.worker?.identifier },
            dotNsResolver: assembled.dotNsResolver,
            ipfsUrl: assembled.ipfsUrl
        )
    }

    /// Wires the supervisor into the runtime provider and keeps the face source
    /// the cards read. Called once.
    func install(
        runtimeProvider: any TrUAPIHostRuntimeProviding,
        flowState: SPAFlowState,
        productFileProvider: any ChatProductFileProviding,
        chainRegistry: ChainRegistryProtocol,
        pocket: PocketFacade = .shared,
        logger: LoggerProtocol = Logger.shared
    ) {
        let supervisor = PocketWorkerSupervisor(
            builder: RealPocketWorkerBuilder(
                environment: { [weak runtimeProvider] in
                    guard let runtimeProvider else { throw PocketWorkerFacadeError.gone }

                    return try RustRuntimeEnvironment(
                        runtime: runtimeProvider.sharedRuntime(),
                        chainRegistry: chainRegistry,
                        notificationScheduler: ProductNotificationScheduler.shared,
                        ipfsFetcher: IpfsFetcher(ipfsBaseURL: AppConfig.KnownIPFS.main),
                        hostProvider: flowState.hostProvider,
                        logger: logger
                    )
                },
                products: flowState.productResolver,
                dotNsResolver: flowState.dotNsResolver,
                productFileProvider: productFileProvider,
                logger: logger
            ),
            pocket: pocket,
            logger: logger
        )

        runtimeProvider.attach(workerSupervisor: supervisor)

        let converter = HexToCIDConverter(ipfsBaseURL: AppConfig.KnownIPFS.main)
        assembled.withLock {
            $0 = Assembled(
                products: flowState.productResolver,
                dotNsResolver: flowState.dotNsResolver,
                ipfsUrl: { converter.ipfsURL(cid: $0) }
            )
        }

        held.withLock {
            $0 = RealPocketFaceSource(
                store: { await pocket.store() },
                streams: TrUAPIPocketFaceStreams(
                    runtime: { [weak runtimeProvider] in
                        guard let runtimeProvider else { throw PocketWorkerFacadeError.gone }

                        return try runtimeProvider.sharedRuntime()
                    },
                    workers: supervisor,
                    publishedCards: PublishedPocketCards.makeDefault(products: flowState.productResolver),
                    logger: logger
                ),
                logger: logger
            )
        }
    }
}

enum PocketWorkerFacadeError: Error {
    case gone
}
