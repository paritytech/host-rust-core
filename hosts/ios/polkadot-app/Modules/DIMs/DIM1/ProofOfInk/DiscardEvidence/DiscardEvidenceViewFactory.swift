import Foundation

@MainActor
enum DiscardEvidenceViewFactory {
    static func createView(for model: DiscardEvidenceModel) -> DiscardEvidenceViewProtocol? {
        let wireframe = DiscardEvidenceWireframe()

        let presenter = DiscardEvidencePresenter(
            model: model,
            wireframe: wireframe
        )

        let view = DiscardEvidenceViewController(presenter: presenter)

        BottomSheetViewFacade.setupBottomSheet(from: view, preferredHeight: 256)

        presenter.view = view

        return view
    }
}
