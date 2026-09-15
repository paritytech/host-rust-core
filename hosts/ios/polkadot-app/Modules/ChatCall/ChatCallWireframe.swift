import UIKit
import UIKitExt

@MainActor
final class ChatCallWireframe: ChatCallWireframeProtocol, AlertPresentable, ApplicationSettingsPresentable {
    func close(from view: ChatCallViewProtocol?) {
        view?.controller.dismiss(animated: true)
    }

    func presentMicrophoneAccessDenied(dismissing view: ChatCallViewProtocol?) {
        let presentAlert: () -> Void = { [weak self] in
            self?.presentMicrophoneAccessAlert()
        }

        if let controller = view?.controller, controller.presentingViewController != nil {
            controller.dismiss(animated: true, completion: presentAlert)
        } else {
            presentAlert()
        }
    }
}

private extension ChatCallWireframe {
    func presentMicrophoneAccessAlert() {
        let viewModel = AlertPresentableViewModel(
            title: String(localized: .chatCallMicAccessTitle),
            message: String(localized: .chatCallMicAccessMessage),
            actions: [
                AlertPresentableAction(title: String(localized: .Common.openSettings)) { [weak self] in
                    self?.openApplicationSettings()
                }
            ],
            closeActionTitle: String(localized: .Common.notNow)
        )

        present(viewModel: viewModel, style: .alert, from: nil)
    }
}
