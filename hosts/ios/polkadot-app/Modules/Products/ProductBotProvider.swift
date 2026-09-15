import AsyncExtensions
import Foundation
import Operation_iOS
import Products
import StructuredConcurrency

protocol ProductBotProviding {
    func observeBots() -> AnyAsyncSequence<[ProductBot]>
}

final class ProductBotProvider: ProductBotProviding {
    private let productProvider: StreamableProvider<Product>
    private let botFactory: ProductBotFactory
    private let dotNsResolver: DotNsResolverProtocol
    private let productResolver: ProductResolving
    private let logger: LoggerProtocol

    init(
        productProvider: StreamableProvider<Product>,
        botFactory: ProductBotFactory,
        dotNsResolver: DotNsResolverProtocol,
        productResolver: ProductResolving,
        logger: LoggerProtocol = Logger.shared
    ) {
        self.productProvider = productProvider
        self.botFactory = botFactory
        self.dotNsResolver = dotNsResolver
        self.productResolver = productResolver
        self.logger = logger
    }

    func observeBots() -> AnyAsyncSequence<[ProductBot]> {
        productProvider.asyncStream()
            .scan([String: Product]()) { dict, changes in
                changes.mergeToDict(dict)
            }
            .map { [self] productDict in
                await makeBots(for: Array(productDict.values))
            }
            .eraseToAnyAsyncSequence()
    }
}

private extension ProductBotProvider {
    /// The last async seam before a bot is built: the file provider that serves the worker runs
    /// synchronously, so the worker's archive and entry module have to be known by now.
    ///
    /// Resolved concurrently — serially, one unreachable product delays every other bot.
    func makeBots(for products: [Product]) async -> [ProductBot] {
        let resolved = await withTaskGroup(of: ResolvedProduct?.self) { group in
            for product in products {
                group.addTask { await self.resolveForBot(product) }
            }

            return await group.reduce(into: [ResolvedProduct]()) { result, resolved in
                resolved.map { result.append($0) }
            }
        }

        return resolved.compactMap { botFactory.create(resolved: $0) }
    }

    /// Nil for a product whose published manifest is broken. That is the product's bug, and
    /// running the base name's archive in its place would serve something it never declared.
    ///
    /// A name that cannot be read still degrades to the legacy shape. Since workers now come only
    /// from a manifest, that yields a bot for hand-installed debug scripts and nothing else — a
    /// published product's bot needs its worker subname, so it needs a resolve that succeeded.
    func resolveForBot(_ product: Product) async -> ResolvedProduct? {
        do {
            let resolved = try await productResolver.resolve(product.identifier)
            await warmWorkerArchive(of: resolved)

            return resolved
        } catch ProductResolutionError.malformedManifest {
            logger.error("Skipping the chat bot for \(product.identifier): its manifest is malformed")
            return nil
        } catch {
            logger.error("Falling back to the legacy chat worker for \(product.identifier): \(error)")
            return .legacy(id: product.identifier, displayName: product.name)
        }
    }

    /// A manifest worker ships its own archive, which nothing else downloads. Legacy workers share
    /// the base name's archive, warmed when the product itself was opened.
    ///
    /// A failed warm only fails this bot, at the point the engine asks for the files. It must not
    /// turn a manifest product into a legacy one and serve the base archive as its worker.
    func warmWorkerArchive(of resolved: ResolvedProduct) async {
        // Chat is the only surface iOS runs a worker on, so anything else is a download nothing reads.
        guard let worker = resolved.executables.worker, worker.includesChat else { return }

        do {
            _ = try await dotNsResolver.resolveToLocalURL(dotNsName: worker.identifier)
        } catch {
            logger.error("Failed to warm the chat worker archive \(worker.identifier): \(error)")
        }
    }
}
