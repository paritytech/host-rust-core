import Foundation
import os
import BulletinChain
import ChainRegistry
import Products
import TrUAPIHost

/// The process-wide product worker supervisor, and the Pocket faces read off it.
///
/// Built once at startup, where the product resolver and the runtime provider
/// are both in hand, and read from the chat bot factory and the card views,
/// which have neither.
final class TrUAPIWorkerFacade: @unchecked Sendable {
    static let shared = TrUAPIWorkerFacade()

    private struct Assembled {
        let products: any ProductResolving
        let dotNsResolver: any DotNsResolverProtocol
        let ipfsUrl: @Sendable (String) -> URL?
    }

    private let held = OSAllocatedUnfairLock<(any PocketFaceSourcing)?>(initialState: nil)
    private let assembled = OSAllocatedUnfairLock<Assembled?>(initialState: nil)
    private let running = OSAllocatedUnfairLock<(any TrUAPIWorkerSupervising)?>(initialState: nil)

    private init() {}

    /// Nil until startup has assembled it, which is also while there is no
    /// runtime for a worker to open against.
    var faces: (any PocketFaceSourcing)? { held.withLock { $0 } }

    /// What runs every product's worker. Nil until startup has installed it,
    /// which is when a chat bot falls back to the native runtime.
    var supervisor: (any TrUAPIWorkerSupervising)? { running.withLock { $0 } }

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
    /// the cards read.
    ///
    /// Called once per session, so a sign-out and back in installs a second
    /// one: the supervisor it replaces is shut down here, because nothing else
    /// holds a way back to the workers it is still running.
    func install(
        runtimeProvider: any TrUAPIHostRuntimeProviding,
        flowState: SPAFlowState,
        productFileProvider: any ChatProductFileProviding,
        chainRegistry: ChainRegistryProtocol,
        pocket: PocketFacade = .shared,
        logger: LoggerProtocol = Logger.shared
    ) {
        let supervisor = TrUAPIWorkerSupervisor(
            builder: TrUAPIWorkerBuilder(
                environment: { [weak runtimeProvider] in
                    guard let runtimeProvider else { throw TrUAPIWorkerFacadeError.gone }

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

        let replaced = running.withLock { held -> (any TrUAPIWorkerSupervising)? in
            let previous = held
            held = supervisor
            return previous
        }
        if let replaced {
            Task { await replaced.shutdown() }
        }

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
                        guard let runtimeProvider else { throw TrUAPIWorkerFacadeError.gone }

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

enum TrUAPIWorkerFacadeError: Error {
    case gone
}
