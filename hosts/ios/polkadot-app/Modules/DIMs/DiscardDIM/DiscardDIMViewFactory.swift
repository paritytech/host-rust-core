import Foundation

@MainActor
enum DiscardDIMViewFactory {
    static func createView(
        for model: DiscardDIMModel,
        discardDIMViewModelMaker: DiscardDIMViewModelMaking
    ) -> DiscardDIMViewProtocol {
        let wireframe = DiscardDIMWireframe()

        let presenter = DiscardDIMPresenter(
            model: model,
            wireframe: wireframe,
            viewModelMaker: discardDIMViewModelMaker
        )

        let view = DiscardDIMViewController(presenter: presenter)

        BottomSheetViewFacade.setupBottomSheet(from: view, preferredHeight: 150)

        presenter.view = view

        return view
    }
}
