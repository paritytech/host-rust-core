import Foundation

@MainActor
enum EvidenceTipsViewFactory {
    static func createView(mode: EvidenceTipsMode) -> EvidenceTipsViewProtocol {
        let wireframe = EvidenceTipsWireframe()
        let presenter = EvidenceTipsPresenter(mode: mode, wireframe: wireframe)
        let view = EvidenceTipsViewController(presenter: presenter)

        presenter.view = view

        return view
    }
}
