import Foundation
import AsyncExtensions
import ChainRegistry
import PolkadotUI
import Products
import Testing
import UIKit
@testable import polkadot_app

/// The Wallet tab is the Pocket's only surface, and it follows the collection
/// from storage. A card entering or leaving reaches it whoever put it there,
/// including the core removing one through a product's own bridge.
@MainActor
struct WalletMainPocketTests {
    /// Warming fetches an archive per host-placed product. A change that landed
    /// while the tab was still busy warming the last one must still reach it,
    /// or the tab sits on a collection that has already moved.
    @Test
    func showsAChangeThatLandedWhileItWasStillWarmingTheLastOne() async throws {
        let repository = InMemoryPocketCardRepository()
        let presenter = RecordingPresenter()
        let interactor = makeInteractor(
            repository: repository,
            presenter: presenter,
            warmDelay: .milliseconds(400)
        )

        interactor.setup()
        try await settle()
        let beforeTheChange = presenter.pocketCards.count

        await repository.insert(loyalty, face: .nil)
        try await settle()

        #expect(presenter.pocketCards.count > beforeTheChange)
        #expect(presenter.pocketCards.last?.contains { $0.key == loyalty.key } == true)
    }

    /// A removal the core made through a product's bridge writes to the same
    /// storage and nothing announces it, so the tab has to see it by following.
    @Test
    func showsACardLeavingTheCollection() async throws {
        let repository = InMemoryPocketCardRepository([loyalty])
        let presenter = RecordingPresenter()
        let interactor = makeInteractor(repository: repository, presenter: presenter)

        interactor.setup()
        try await settle()
        #expect(presenter.pocketCards.last?.contains { $0.key == loyalty.key } == true)

        _ = try await repository.delete(loyalty.key)
        try await settle()

        #expect(presenter.pocketCards.last?.contains { $0.key == loyalty.key } == false)
    }
}

// MARK: - Fixtures

private let loyalty = PocketCardEntry(
    key: PocketCardKey(productId: "game.paseo", cardId: PocketCardId(value: "loyalty")),
    title: "Loyalty",
    privileged: false
)

/// The tab hands its reads to tasks, so the assertions wait for them rather
/// than for a fixed time.
private func settle() async throws {
    for _ in 0 ..< 20 {
        await Task.yield()
    }
    try await Task.sleep(for: .milliseconds(150))
}

@MainActor
private func makeInteractor(
    repository: InMemoryPocketCardRepository,
    presenter: RecordingPresenter,
    warmDelay: Duration = .zero
) -> WalletMainInteractor {
    let interactor = WalletMainInteractor(
        collectiblesURLProvider: StubCollectiblesURLProvider(),
        networkStatusObserver: StubNetworkStatusObserver(),
        pocketPrewarmer: PocketPrewarmer(products: StubResolver(), dotNsResolver: SlowArchives(delay: warmDelay)),
        pocket: PocketFacade(tld: { "paseo" }, repository: repository)
    )
    interactor.presenter = presenter
    return interactor
}

@MainActor
private final class RecordingPresenter: WalletMainInteractorOutputProtocol {
    private(set) var pocketCards: [[PocketCardViewModel]] = []

    func didReceiveCollectibles(url _: URL?) {}
    func didReceive(networkStatus _: NetworkStatus) {}

    func didReceive(pocketCards: [PocketCardViewModel]) {
        self.pocketCards.append(pocketCards)
    }
}

private struct StubCollectiblesURLProvider: CollectiblesURLProviding {
    func resolveURL() async -> URL? { nil }
}

private final class StubNetworkStatusObserver: NetworkStatusObserving {
    func start(onStatus _: @escaping @MainActor (NetworkStatus) -> Void) {}
}

private struct StubResolver: ProductResolving {
    func resolve(_ productId: ProductId) async throws -> ResolvedProduct {
        ResolvedProduct(
            id: productId,
            displayName: productId,
            description: nil,
            icon: nil,
            executables: ProductExecutables(
                app: ProductExecutable.App(identifier: "app.\(productId)", appVersion: .zero),
                widget: nil,
                worker: nil
            ),
            hasManifest: true
        )
    }
}

/// Stands in for the archive fetch a warm performs, which is the slow part the
/// collection must not be read behind.
private final class SlowArchives: DotNsResolverProtocol, @unchecked Sendable {
    let delay: Duration

    init(delay: Duration) {
        self.delay = delay
    }

    func resolveToLocalURL(dotNsName: String) async throws -> URL {
        if delay > .zero { try await Task.sleep(for: delay) }

        return URL(fileURLWithPath: "/tmp/\(dotNsName)")
    }

    func getMetadataEntry(dotNsName _: String, key _: String) async throws -> String? { nil }
    func progressStream(dotNsName _: String) -> AnyAsyncSequence<DotNsLoadProgress> {
        AsyncStream<DotNsLoadProgress> { $0.finish() }.eraseToAnyAsyncSequence()
    }

    func clearCache() throws {}
}
