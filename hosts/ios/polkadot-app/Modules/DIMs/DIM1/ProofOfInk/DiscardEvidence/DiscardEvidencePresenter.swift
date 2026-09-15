import Foundation

@MainActor
final class DiscardEvidencePresenter {
    weak var view: DiscardEvidenceViewProtocol?
    private let model: DiscardEvidenceModel
    private let wireframe: DiscardEvidenceWireframeProtocol

    init(
        model: DiscardEvidenceModel,
        wireframe: DiscardEvidenceWireframeProtocol
    ) {
        self.model = model
        self.wireframe = wireframe
    }
}

extension DiscardEvidencePresenter: DiscardEvidencePresenterProtocol {
    func setup() {
        provideViewModel()
    }

    func cancel() {
        wireframe.close(view: view, model.cancelClosure)
    }

    func discard() {
        wireframe.close(view: view, model.discardClosure)
    }
}

private extension DiscardEvidencePresenter {
    func provideViewModel() {
        let viewModel: DiscardEvidenceViewModel =
            switch model.mode {
            case .photo:
                .discardPhotoEvidence
            case .video:
                .discardVideoEvidence
            }
        view?.didReceive(viewModel: viewModel)
    }
}
