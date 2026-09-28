import Foundation
@preconcurrency import Products
import TrUAPIHost

enum PocketWorkerError: Error, CustomStringConvertible {
    case noPocketWorker(ProductId)

    var description: String {
        switch self {
        case let .noPocketWorker(productId): "\(productId) publishes no Pocket worker"
        }
    }
}

/// Assembles one product's worker: its archive, its Worker execution, and the
/// headless engine its entry module runs in.
struct RealPocketWorkerBuilder: PocketWorkerBuilding {
    private let environment: @Sendable () throws -> RustRuntimeEnvironment
    private let products: any ProductResolving
    private let dotNsResolver: any DotNsResolverProtocol
    private let productFileProvider: any ChatProductFileProviding
    private let logger: LoggerProtocol

    init(
        environment: @escaping @Sendable () throws -> RustRuntimeEnvironment,
        products: any ProductResolving,
        dotNsResolver: any DotNsResolverProtocol,
        productFileProvider: any ChatProductFileProviding,
        logger: LoggerProtocol = Logger.shared
    ) {
        self.environment = environment
        self.products = products
        self.dotNsResolver = dotNsResolver
        self.productFileProvider = productFileProvider
        self.logger = logger
    }

    func makeRuntime(productId: ProductId, pocket: ProductPocketHostBridge) async throws -> TrUAPIWorkerRuntime {
        let resolved = try? await products.resolve(productId)
        let source = try await workerSource(for: resolved, productId: productId)

        let context = try ChatProductEngineFactory.makeContext(
            source: source,
            productFileProvider: productFileProvider,
            logger: logger
        )

        return try TrUAPIWorkerRuntime(
            productUrl: context.productUrl,
            executionModel: environment().makePocketWorkerExecution(
                productId: productId,
                routers: ProductRoutersFacade.worker(),
                pocket: pocket
            ),
            engineFactory: context.engineFactory,
            logger: logger
        )
    }

    /// A published Pocket worker, or the script installed by hand through debug
    /// settings — the same rule the chat bot follows, and what makes a card
    /// drivable before its product publishes anything.
    private func workerSource(
        for resolved: ResolvedProduct?,
        productId: ProductId
    ) async throws -> ProductWorkerSource {
        let resolved = resolved ?? .legacy(id: productId)

        if let published = ProductWorkerSource.published(for: resolved, serving: .pocket) {
            // Fetched before the engine boots: the scheme handler reads the
            // archive off disk, and a page loaded before it is there fails as a
            // missing module rather than waiting.
            _ = try await dotNsResolver.resolveToLocalURL(dotNsName: published.contentId)

            return published
        }

        guard let installed = ProductWorkerSource.installedByHand(for: resolved, entryPath: {
            productFileProvider.manualScriptEntryPath(productId: $0)
        }) else {
            throw PocketWorkerError.noPocketWorker(productId)
        }

        return installed
    }
}
