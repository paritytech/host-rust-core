import Foundation

enum EvidenceTipsMode {
    case photo
    case video

    var preferredHeight: CGFloat {
        switch self {
        case .photo:
            470
        case .video:
            700
        }
    }
}

extension EvidenceTipsMode {
    var viewModel: EvidenceTipsViewModel {
        switch self {
        case .photo:
            .photoTips
        case .video:
            .videoTips
        }
    }
}

final class EvidenceTipsPresenter {
    weak var view: EvidenceTipsViewProtocol?
    let wireframe: EvidenceTipsWireframeProtocol
    let mode: EvidenceTipsMode

    init(
        mode: EvidenceTipsMode,
        wireframe: EvidenceTipsWireframeProtocol
    ) {
        self.mode = mode
        self.wireframe = wireframe
    }
}

extension EvidenceTipsPresenter: EvidenceTipsPresenterProtocol {
    func setup() {
        view?.didReceive(viewModel: mode.viewModel)
    }
}
