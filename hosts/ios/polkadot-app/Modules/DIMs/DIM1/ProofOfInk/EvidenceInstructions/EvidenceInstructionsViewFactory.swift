import Foundation

@MainActor
enum EvidenceInstructionsViewFactory {
    static func createView(
        for model: EvidenceInstructionsModel,
        mode: EvidenceInstructionsMode
    ) -> EvidenceInstructionsViewProtocol? {
        let wireframe = EvidenceInstructionsWireframe()
        let viewModelProvider = EvidenceInstructionsViewModelProvider(mode: mode)

        let interactor = EvidenceInstructionsInteractor(
            mode: mode,
            batteryLevelMediator: BatteryLevelMediator(),
            storageSpaceMediator: StorageSpaceMediator()
        )

        let presenter = EvidenceInstructionsPresenter(
            model: model,
            wireframe: wireframe,
            viewModelProvider: viewModelProvider,
            interactor: interactor
        )
        let view = EvidenceInstructionsViewController(presenter: presenter)

        presenter.view = view
        interactor.presenter = presenter

        return view
    }
}
