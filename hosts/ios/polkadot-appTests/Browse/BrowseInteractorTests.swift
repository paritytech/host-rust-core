import Testing
import Foundation
import UIKit
@testable import polkadot_app
@testable import Products

final class BrowseInteractorTests {
    private func makeHost() -> ProductHost? {
        ProductHost.parse("browse.dot", tld: "dot")
    }

    @Test
    @MainActor
    func syncHostReturnsWithoutAsyncCall() async {
        guard let host = makeHost() else {
            Issue.record("Failed to create ProductHost")
            return
        }

        let stub = StubHostProvider(
            syncHostResult: nil,
            asyncHostResult: .success(host)
        )
        let presenter = StubPresenter()
        let logger = Logger.shared

        let interactor = BrowseInteractor(hostProvider: stub, logger: logger)
        interactor.presenter = presenter

        interactor.resolveBrowseHost()

        // Let main actor hop complete
        try? await Task.sleep(for: .milliseconds(10))

        #expect(presenter.didResolveCallCount == 1)
        #expect(presenter.lastResolvedHost?.name == host.name)
        #expect(stub.resolveHostCallCount == 1)
    }

    @Test
    @MainActor
    func syncNilThenAsyncSuccessResolves() async {
        guard let host = makeHost() else {
            Issue.record("Failed to create ProductHost")
            return
        }

        let stub = StubHostProvider(
            syncHostResult: nil,
            asyncHostResult: .success(host)
        )
        let presenter = StubPresenter()
        let logger = Logger.shared

        let interactor = BrowseInteractor(hostProvider: stub, logger: logger)
        interactor.presenter = presenter

        interactor.resolveBrowseHost()

        // Let async operation and main actor hop complete
        try? await Task.sleep(for: .milliseconds(100))

        #expect(presenter.didResolveCallCount == 1)
        #expect(presenter.lastResolvedHost?.name == host.name)
    }

    @Test
    @MainActor
    func syncNilThenAsyncThrowFails() async {
        struct TestError: Error {}

        let stub = StubHostProvider(
            syncHostResult: nil,
            asyncHostResult: .failure(TestError())
        )
        let presenter = StubPresenter()
        let logger = Logger.shared

        let interactor = BrowseInteractor(hostProvider: stub, logger: logger)
        interactor.presenter = presenter

        interactor.resolveBrowseHost()

        // Let async operation and main actor hop complete
        try? await Task.sleep(for: .milliseconds(100))

        #expect(presenter.didFailResolveCallCount == 1)
        #expect(presenter.didResolveCallCount == 0)
    }

    @Test
    @MainActor
    func syncNilThenAsyncNilFails() async {
        let stub = StubHostProvider(
            syncHostResult: nil,
            asyncHostResult: .success(nil)
        )
        let presenter = StubPresenter()
        let logger = Logger.shared

        let interactor = BrowseInteractor(hostProvider: stub, logger: logger)
        interactor.presenter = presenter

        interactor.resolveBrowseHost()

        // Let async operation and main actor hop complete
        try? await Task.sleep(for: .milliseconds(100))

        #expect(presenter.didFailResolveCallCount == 1)
        #expect(presenter.didResolveCallCount == 0)
    }

    @Test
    @MainActor
    func passesCorrectLabel() async {
        let stub = StubHostProvider(
            syncHostResult: nil,
            asyncHostResult: .success(nil)
        )
        let presenter = StubPresenter()
        let logger = Logger.shared

        let interactor = BrowseInteractor(hostProvider: stub, logger: logger)
        interactor.presenter = presenter

        interactor.resolveBrowseHost()

        // Let async operation and main actor hop complete
        try? await Task.sleep(for: .milliseconds(100))

        #expect(stub.lastLabel == AppConfig.DotNs.dotNsBrowse)
    }
}

// MARK: - Stubs

private final class StubHostProvider: ProductHostProviding {
    let syncHostResult: ProductHost?
    let asyncHostResult: Result<ProductHost?, Error>

    private(set) var resolveHostCallCount = 0
    private(set) var lastLabel: String?

    init(
        syncHostResult: ProductHost?,
        asyncHostResult: Result<ProductHost?, Error>
    ) {
        self.syncHostResult = syncHostResult
        self.asyncHostResult = asyncHostResult
    }

    func host(rawString _: String) -> ProductHost? {
        nil
    }

    func host(url _: URL) -> ProductHost? {
        nil
    }

    func host(navigationDestination _: String) -> ProductHost? {
        nil
    }

    func page(url _: URL) -> ProductPage? {
        nil
    }

    func page(navigationDestination _: String) -> ProductPage? {
        nil
    }

    func host(label: String) -> ProductHost? {
        lastLabel = label
        return syncHostResult
    }

    func resolveHost(label: String) async throws -> ProductHost? {
        resolveHostCallCount += 1
        lastLabel = label
        return try asyncHostResult.get()
    }

    func resolveHost(rawString _: String) async throws -> ProductHost? {
        nil
    }
}

@MainActor
private final class StubPresenter: BrowseInteractorOutputProtocol {
    var didResolveCallCount = 0
    var didFailResolveCallCount = 0
    var lastResolvedHost: ProductHost?

    func didResolve(host: ProductHost) {
        didResolveCallCount += 1
        lastResolvedHost = host
    }

    func didFailResolving() {
        didFailResolveCallCount += 1
    }
}
