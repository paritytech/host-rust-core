import Foundation

@MainActor
enum TattooConfirmViewFactory {
    static func createView(for model: TattooConfirmModel) -> TattooConfirmViewProtocol? {
        let wireframe = TattooConfirmWireframe()

        let presenter = TattooConfirmPresenter(
            model: model,
            wireframe: wireframe
        )

        let view = TattooConfirmViewController(presenter: presenter)

        BottomSheetViewFacade.setupBottomSheet(from: view, preferredHeight: nil)

        presenter.view = view

        return view
    }
}
