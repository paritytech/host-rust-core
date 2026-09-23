import Products
import SwiftUI
import UIKit
import UIKitExt

@MainActor
enum PocketAddCardViewFactory {
    /// Nil when the Pocket cannot be read yet, which is also when there is
    /// nowhere to put an approved card.
    static func createView(
        for link: PocketDeeplink,
        flowState: SPAFlowState,
        pocket: PocketFacade = .shared
    ) async -> UIViewController? {
        guard let store = await pocket.store() else { return nil }

        let viewModel = PocketAddCardViewModel(
            productId: link.productHost,
            cardId: link.cardId,
            interactor: makeInteractor(store: store, flowState: flowState),
            onAdded: { pocket.collectionChanged() }
        )

        let controller = UIHostingController(rootView: PocketAddCardView(viewModel: viewModel))
        controller.view.backgroundColor = .bgSurfaceMain
        viewModel.onFinish = { [weak controller] in controller?.dismiss(animated: true) }

        // Sized to the card rather than to the screen: this asks for one
        // decision, and what is behind it stays visible.
        controller.modalPresentationStyle = .pageSheet
        controller.sheetPresentationController?.detents = [
            .custom { _ in PocketAddCardView.sheetHeight }
        ]
        controller.sheetPresentationController?.preferredCornerRadius = PocketCardSize.cornerRadius

        return controller
    }

    private static func makeInteractor(
        store: any PocketCardStore,
        flowState: SPAFlowState
    ) -> PocketAddCardInteractor {
        PocketAddCardInteractor(
            publishedCards: PublishedPocketCards.makeDefault(products: flowState.productResolver),
            previews: PocketPreviewLoader(
                archive: DotNsPocketArchive(dotNsResolver: flowState.dotNsResolver),
                fetch: { try await URLSession.shared.data(from: $0).0 }
            ),
            store: store
        )
    }
}
