import Foundation
import Observation
import PolkadotUI
import Products

/// Drives the approval sheet: loads what is being offered, then stores exactly
/// that when the user approves it.
@Observable
@MainActor
final class PocketAddCardViewModel {
    enum State {
        case loading
        case offered(PocketAddCardOffer, face: CustomMessageWidgetNode?)
        case refused(String)
    }

    private(set) var state: State = .loading
    private(set) var isAdding = false

    var onFinish: () -> Void = {}

    private let productId: ProductId
    private let cardId: String
    private let interactor: PocketAddCardInteractor
    private let onAdded: () -> Void
    private let resolver: any WidgetDesignTokenResolving

    init(
        productId: ProductId,
        cardId: String,
        interactor: PocketAddCardInteractor,
        onAdded: @escaping () -> Void,
        resolver: any WidgetDesignTokenResolving = WidgetDesignTokenResolver()
    ) {
        self.productId = productId
        self.cardId = cardId
        self.interactor = interactor
        self.onAdded = onAdded
        self.resolver = resolver
    }

    func load() async {
        do {
            let screened = try PocketCardIdentifier.screen(cardId)
            let offer = try await interactor.loadOffer(productId: productId, cardId: screened)
            state = .offered(offer, face: offer.face.toWidgetNode(resolver: resolver))
        } catch {
            state = .refused(message(for: error))
        }
    }

    func add() async {
        guard case let .offered(offer, _) = state, !isAdding else { return }

        isAdding = true
        await interactor.approve(offer)
        onAdded()
        onFinish()
    }

    /// A product that publishes no such card is told apart from one that
    /// publishes no cards at all, because the two are fixed differently.
    private func message(for error: any Error) -> String {
        switch error {
        case PocketPublishError.noPocket: String(localized: .pocketDeeplinkNoPocket)
        case PocketPublishError.unknownCard: String(localized: .pocketDeeplinkUnknownCard)
        default: String(localized: .pocketAddCardFailed)
        }
    }
}
