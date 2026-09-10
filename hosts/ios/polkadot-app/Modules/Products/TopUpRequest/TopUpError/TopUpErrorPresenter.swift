import Foundation

final class TopUpErrorPresenter {
    weak var view: TopUpErrorViewProtocol?
    let wireframe: TopUpErrorWireframeProtocol

    private let context: TopUpRequestContext
    private let error: Error
    private let title: String
    private let message: String
    private let closeButtonTitle: String

    init(
        wireframe: TopUpErrorWireframeProtocol,
        context: TopUpRequestContext,
        error: Error,
        title: String,
        message: String,
        closeButtonTitle: String
    ) {
        self.wireframe = wireframe
        self.context = context
        self.error = error
        self.title = title
        self.message = message
        self.closeButtonTitle = closeButtonTitle
    }
}

extension TopUpErrorPresenter: TopUpErrorPresenterProtocol {
    func setup() {
        view?.didReceive(
            title: title,
            message: message,
            closeButtonTitle: closeButtonTitle
        )
    }

    func didTapClose() {
        wireframe.dismiss(view: view)
        context.deliverFailed(error)
    }
}
