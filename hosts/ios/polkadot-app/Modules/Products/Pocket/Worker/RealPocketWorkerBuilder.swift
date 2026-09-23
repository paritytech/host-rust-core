import Foundation
import Products
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

    func makeRuntime(productId: ProductId, pocket: ProductPocketHostBridge) async throws -> PocketWorkerRuntime {
        let resolved = try? await products.resolve(productId)
        let source = try await workerSource(for: resolved, productId: productId)

        let context = try ChatProductEngineFactory.makeContext(
            source: source,
            productFileProvider: productFileProvider,
            logger: logger
        )

        return try PocketWorkerRuntime(
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
    /// settings — the same fallback the chat bot takes, and what makes a card
    /// drivable before its product publishes anything.
    private func workerSource(
        for resolved: ResolvedProduct?,
        productId: ProductId
    ) async throws -> ProductWorkerSource {
        if let worker = resolved?.executables.worker, worker.includesPocket {
            // Fetched before the engine boots: the scheme handler reads the
            // archive off disk, and a page loaded before it is there fails as a
            // missing module rather than waiting.
            _ = try await dotNsResolver.resolveToLocalURL(dotNsName: worker.identifier)

            return ProductWorkerSource(contentId: worker.identifier, entryRelativePath: worker.entrypoint)
        }

        let installedId = resolved?.id ?? productId
        guard let entry = productFileProvider.manualScriptEntryPath(productId: installedId) else {
            throw PocketWorkerError.noPocketWorker(productId)
        }

        return ProductWorkerSource(contentId: installedId, entryRelativePath: entry)
    }
}
