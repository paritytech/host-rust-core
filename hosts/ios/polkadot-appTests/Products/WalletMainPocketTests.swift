import Foundation
import AsyncExtensions
import ChainRegistry
import PolkadotUI
import Products
import Testing
import UIKit
@testable import polkadot_app

/// The Wallet tab is the Pocket's only surface, and it re-reads the collection
/// only when it is told one changed. Nothing else re-reads on its own, so a
/// change the tab was not listening for leaves it stale until the next one.
@MainActor
struct WalletMainPocketTests {
    /// Warming fetches an archive per host-placed product, and the collection
    /// is read again only when a change is announced. A change that landed
    /// while the tab was still busy with the last read must still be heard:
    /// the stream announces once and keeps nothing for a listener that has not
    /// arrived, and nothing re-reads the collection on its own afterwards.
    @Test
    func hearsAChangeThatLandedWhileItWasStillBusyWithTheLastRead() async throws {
        let repository = InMemoryPocketCardRepository()
        let pocket = PocketFacade(tld: { "paseo" }, repository: repository)
        let view = RecordingView()
        let presenter = makePresenter(pocket: pocket, view: view, warmDelay: .milliseconds(400))

        presenter.setup()
        try await settle()
        let beforeTheChange = view.pocketCards.count

        await repository.insert(loyalty, face: .nil)
        pocket.collectionChanged()
        try await settle()

        #expect(view.pocketCards.count > beforeTheChange)
        #expect(view.pocketCards.last?.contains { $0.key == loyalty.key } == true)
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
private func makePresenter(
    pocket: PocketFacade,
    view: RecordingView,
    warmDelay: Duration = .zero
) -> WalletMainPresenter {
    let presenter = WalletMainPresenter(
        interactor: StubInteractor(),
        wireframe: StubWireframe(),
        titleViewModelFactory: StubTitleViewModelFactory(),
        pocketPrewarmer: PocketPrewarmer(products: StubResolver(), dotNsResolver: SlowArchives(delay: warmDelay)),
        pocket: pocket
    )
    presenter.view = view
    return presenter
}

private final class RecordingView: WalletMainViewProtocol {
    private(set) var pocketCards: [[PocketCardViewModel]] = []

    let controller = UIViewController()
    let isSetup = true

    func didReceive(isCollectiblesAvailable _: Bool) {}
    func didReceive(titleViewModel _: NetworkStatusTitleView.ViewModel) {}

    func didReceive(pocketCards: [PocketCardViewModel]) {
        self.pocketCards.append(pocketCards)
    }
}

private final class StubInteractor: WalletMainInteractorInputProtocol {
    func setup() {}
}

private final class StubWireframe: WalletMainWireframeProtocol {
    func showCollectibles(from _: WalletMainViewProtocol?, url _: URL) {}
    func showPocketCard(_: PocketCardViewModel) {}
    func confirmPocketCardRemoval(_: PocketCardViewModel, onConfirm _: @escaping () -> Void) {}
}

private struct StubTitleViewModelFactory: NetworkStatusTitleViewModelMaking {
    func createTitleViewModel(for _: NetworkStatus) -> NetworkStatusTitleView.ViewModel {
        NetworkStatusTitleView.ViewModel(text: "Wallet", isLoading: false)
    }
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
