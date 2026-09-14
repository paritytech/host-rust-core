import Foundation
import UIKit
import UIKitExt

final class DebugSettingsPresenter {
    weak var view: DebugSettingsViewProtocol?

    let wireframe: DebugSettingsWireframeProtocol
    let interactor: DebugSettingsInteractorInputProtocol
    let shareActivityPresenter: ShareActivityPresenting
    let emailComposePresenter: EmailComposePresenting

    init(
        interactor: DebugSettingsInteractorInputProtocol,
        wireframe: DebugSettingsWireframeProtocol,
        shareActivityPresenter: ShareActivityPresenting,
        emailComposePresenter: EmailComposePresenting
    ) {
        self.interactor = interactor
        self.wireframe = wireframe
        self.shareActivityPresenter = shareActivityPresenter
        self.emailComposePresenter = emailComposePresenter
    }
}

extension DebugSettingsPresenter: DebugSettingsPresenterProtocol {
    func setup() {
        interactor.setup()
    }

    func clearBackup() {
        interactor.clearBackup()
    }

    func clearReferral() {
        interactor.clearReferral()
    }

    func clearJWTToken() {
        interactor.clearJWTToken()
    }

    func shareLogs() {
        guard let draft = interactor.makeLogsDraft() else {
            return
        }

        if emailComposePresenter.canSendMail() {
            emailComposePresenter.presentEmail(with: draft) { _ in }
        } else if let attachment = draft.attachment {
            shareActivityPresenter.share(activityItems: [attachment.url]) { _ in }
        }
    }

    func createIssue() {
        let viewModel = AlertPresentableViewModel(
            title: String(localized: .debugCreateIssue),
            message: String(localized: .debugIssueInstructions),
            actions: [
                AlertPresentableAction(title: String(localized: .debugIssueSaveLogs)) { [weak self] in
                    self?.saveIssueLogs()
                },
                AlertPresentableAction(title: String(localized: .Common.cancel), style: .cancel)
            ]
        )
        wireframe.present(viewModel: viewModel, style: .alert, from: view)
    }

    func showProducts() {
        wireframe.showProducts(from: view)
    }

    func showDotNsBrowser() {
        wireframe.showDotNsBrowser(from: view)
    }

    func showThemeSelection() {
        wireframe.showThemeSelection(from: view)
    }

    func replaceWithRandomEntropy() {
        let alert = UIAlertController(
            title: "Replace Entropy",
            message: "This will replace the root entropy with a new random one.",
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        alert.addAction(UIAlertAction(title: "Replace", style: .destructive) { [weak self] _ in
            self?.interactor.replaceWithRandomEntropy()
        })

        view?.controller.present(alert, animated: true)
    }

    func toggleStrategyDebug() {
        interactor.toggleStrategyDebug()
    }

    func toggleTruApiRuntime() {
        interactor.toggleTruApiRuntime()

        let viewModel = AlertPresentableViewModel(
            title: "Restart Required",
            message: "TrUAPI runtime changed. Restart the app to apply the new runtime.",
            actions: [
                AlertPresentableAction(title: "Restart") { [weak self] in
                    self?.interactor.restartApp()
                },
                AlertPresentableAction(title: "Cancel", style: .cancel) { [weak self] in
                    self?.interactor.toggleTruApiRuntime()
                }
            ]
        )

        wireframe.present(viewModel: viewModel, style: .alert, from: view)
    }

    func openTrUAPIPlayground() {
        wireframe.showTrUAPIPlayground(from: view)
    }
}

private extension DebugSettingsPresenter {
    func saveIssueLogs() {
        guard let attachment = interactor.makeLogsDraft()?.attachment else {
            presentIssueError(String(localized: .debugIssueCollectFailed))
            return
        }

        guard attachment.data.count <= 25 * 1_024 * 1_024 else {
            presentIssueError(String(localized: .debugIssueLogsTooLarge))
            return
        }

        wireframe.saveIssueLogs(attachment.url, from: view)
    }

    func presentIssueError(_ message: String) {
        wireframe.present(
            message: message,
            title: String(localized: .Common.error),
            closeAction: String(localized: .Common.close),
            from: view
        )
    }
}

extension DebugSettingsPresenter: DebugSettingsInteractorOutputProtocol {
    func didReceive(canClearBackup: Bool) {
        view?.didReceive(canClearBackup: canClearBackup)
    }

    func didReceive(canClearReferral: Bool) {
        view?.didReceive(canClearReferral: canClearReferral)
    }

    func didReceive(hasJWTToken: Bool) {
        view?.didReceive(hasJWTToken: hasJWTToken)
    }

    func didReceive(strategyDebugEnabled: Bool) {
        view?.didReceive(strategyDebugEnabled: strategyDebugEnabled)
    }

    func didReceive(truApiRuntimeEnabled: Bool) {
        view?.didReceive(truApiRuntimeEnabled: truApiRuntimeEnabled)
    }
}
