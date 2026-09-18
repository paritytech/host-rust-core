import Foundation
import Products

/// Resolves the funding product's entry pages from remote config: one destination for topping up,
/// one for withdrawing. A destination is either a dot-domain (`getcash.dot`) or a full URL whose
/// path names the page (`https://getcash.dot/offramp`), exactly as published.
protocol FundingDomainProviding: Sendable {
    func fundingPage() async throws -> ProductPage
    func offrampPage() async throws -> ProductPage
    /// Product labels of both entry pages, read synchronously from remote config.
    func fundingLabels() -> Set<String>
}

enum FundingDomainError: Error {
    case unavailable
}

final class FundingDomainProvider: FundingDomainProviding, @unchecked Sendable {
    private let hostProvider: ProductHostProviding
    private let remoteConfig: @Sendable () -> RemoteAppConfig?

    init(
        hostProvider: ProductHostProviding,
        remoteConfig: @escaping @Sendable () -> RemoteAppConfig? = { AppConfigProvider.shared.getRemoteConfig() }
    ) {
        self.hostProvider = hostProvider
        self.remoteConfig = remoteConfig
    }

    func fundingPage() async throws -> ProductPage {
        try await page(for: remoteConfig()?.fundingUrl)
    }

    func offrampPage() async throws -> ProductPage {
        try await page(for: remoteConfig()?.offrampUrl)
    }

    func fundingLabels() -> Set<String> {
        let config = remoteConfig()
        let pages = [config?.fundingUrl, config?.offrampUrl].compactMap { destination in
            destination.flatMap { hostProvider.page(navigationDestination: $0) }
        }
        return Set(pages.map(\.host.name))
    }
}

private extension FundingDomainProvider {
    /// Awaits the chain TLD through the host provider, then parses the destination into a page.
    func page(for destination: String?) async throws -> ProductPage {
        guard let destination, !destination.isEmpty else {
            throw FundingDomainError.unavailable
        }

        guard let page = hostProvider.page(navigationDestination: destination) else {
            throw FundingDomainError.unavailable
        }

        return page
    }
}
