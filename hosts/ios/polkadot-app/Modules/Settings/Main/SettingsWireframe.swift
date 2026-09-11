import Foundation
import UIKit
import UIKitExt

@MainActor
final class SettingsWireframe: SettingsWireframeProtocol {
    private let serviceCoordinator: ServiceCoordinatorProtocol
    private let emailComposePresenter: EmailComposePresenting
    private let flowStateProvider: any SPAFlowStateProviding

    init(
        serviceCoordinator: ServiceCoordinatorProtocol,
        emailComposePresenter: EmailComposePresenting,
        flowStateProvider: any SPAFlowStateProviding
    ) {
        self.serviceCoordinator = serviceCoordinator
        self.emailComposePresenter = emailComposePresenter
        self.flowStateProvider = flowStateProvider
    }

    func showBackupFlow(from view: (any SettingsViewProtocol)?) {
        guard let backup = BackupViewFactory.createView() else {
            return
        }

        view?.controller.navigationController?.pushViewController(backup.controller, animated: true)
    }

    func showLinkedDevices(from view: (any SettingsViewProtocol)?) {
        guard let linkedDevicesView = LinkedDevicesViewFactory.createView(
            serviceCoordinator: serviceCoordinator
        ) else {
            return
        }

        view?.controller.navigationController?.pushViewController(
            linkedDevicesView.controller,
            animated: true
        )
    }

    func showCurrencyPicker(from view: (any SettingsViewProtocol)?) {
        let pickerController = CurrencyPickerViewFactory.createView()
        view?.controller.navigationController?.pushViewController(pickerController, animated: true)
    }

    func openMailComposer(from view: (any SettingsViewProtocol)?) {
        guard let view else { return }
        emailComposePresenter.use(presenter: view)
        let draft = EmailDraft(
            subject: "",
            message: "",
            recipients: [AppConfig.contactEmail],
            attachment: nil
        )
        emailComposePresenter.presentEmail(with: draft) { _ in }
    }

    func showContactEmailFallback(_ email: String, from view: (any SettingsViewProtocol)?) {
        let copyAction = AlertPresentableAction(title: String(localized: .Common.copyEmail)) {
            UIPasteboard.general.string = email
        }

        let viewModel = AlertPresentableViewModel(
            title: String(localized: .Common.errorMailAppNotAvailable),
            message: email,
            actions: [copyAction],
            closeActionTitle: String(localized: .Common.close)
        )

        present(viewModel: viewModel, style: .alert, from: view)
    }

    func showBlockedUsers(from view: (any SettingsViewProtocol)?) {
        guard let blockedUsersView = BlockedUsersViewFactory.createView() else {
            return
        }

        view?.controller.navigationController?.pushViewController(
            blockedUsersView.controller,
            animated: true
        )
    }

    func showApps(from view: (any SettingsViewProtocol)?) {
        guard let appsView = AppsListViewFactory.createView(flowStateProvider: flowStateProvider) else {
            return
        }

        view?.controller.navigationController?.pushViewController(
            appsView.controller,
            animated: true
        )
    }

    func showThemeSelection(
        from view: (any SettingsViewProtocol)?,
        onFinish: @escaping () -> Void
    ) {
        guard let view else { return }

        let controller = ThemeSelectionViewFactory.createView { [weak view] in
            view?.controller.navigationController?.popViewController(animated: true)
            onFinish()
        }

        controller.hidesBottomBarWhenPushed = true

        view.controller.navigationController?.pushViewController(controller, animated: true)
    }
}
