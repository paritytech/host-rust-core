import Foundation
import Foundation_iOS
import UIKit
import SubstrateSdk
import Keystore_iOS
import UIKitExt
import PolkadotUI
import DesignSystem

@MainActor
final class WeeklyGameWireframe {
    weak var view: ControllerBackedProtocol?
    weak var registryDelegate: ChatExtensionDelegate?

    let application: UIApplication
    let assetId: ChainAssetId
    let notificationService: UserNotificationServicing
    let botSettings: ChatExtensionBotSettings

    init(
        assetId: ChainAssetId,
        notificationService: UserNotificationServicing,
        application: UIApplication,
        botSettings: ChatExtensionBotSettings = SettingsManager.shared
    ) {
        self.assetId = assetId
        self.notificationService = notificationService
        self.application = application
        self.botSettings = botSettings
    }
}

extension WeeklyGameWireframe: WeeklyGameWireframeProtocol {
    func dismiss(_ completion: (() -> Void)?) {
        view?.controller.dismiss(animated: true, completion: completion)
    }

    func showDeposit(
        _ neededAmount: Balance,
        model: GameDepositRequiredModel
    ) {
        guard let depositView = GameDepositRequiredViewFactory.createView(
            requiredBalance: neededAmount,
            asset: assetId,
            model: model
        ) else {
            return
        }

        depositView.controller.traitOverrides.appTheme = ThemesRegistry.default
        view?.controller.present(depositView.controller, animated: true)
    }

    func showDepositConfirmation(
        _ amount: Balance,
        model: ConfirmDepositModel
    ) {
        guard let depositView = ConfirmDepositViewFactory.createView(
            asset: assetId,
            amount: amount,
            model: model
        ) else {
            return
        }

        depositView.controller.traitOverrides.appTheme = ThemesRegistry.default
        view?.controller.present(depositView.controller, animated: true)
    }

    func showEnableNotifications(
        _ model: EnableNotificationsModel
    ) {
        let enableNotificationsView = EnableNotificationsViewFactory.createView(
            model: model,
            localNotificationService: notificationService,
            variant: .game
        )

        enableNotificationsView.controller.modalPresentationStyle = .fullScreen
        view?.controller.present(enableNotificationsView.controller, animated: true)
    }

    func showUpgradeUsername(
        _ registeredData: People.RegisteredData
    ) {
        guard let claimView = ClaimUsernameViewFactory.createFullClaimView(
            registeredData: registeredData
        ) else {
            return
        }

        let nav = AppNavigationController(rootViewController: claimView.controller)
        nav.modalPresentationStyle = .fullScreen
        view?.controller.present(nav, animated: true)
    }

    func openCurrentGame() {
        application.open(AppConfig.DeepLink.game())
    }

    func showGameAlarmSettings(model: GameAlarmSettingsModel) {
        let alarmSettingsView = GameAlarmSettingsViewFactory.createView(model: model)
        view?.controller.present(alarmSettingsView.controller, animated: true)
    }

    func showSwitchDIMConfirmation(onSwitch: @escaping () -> Void) {
        guard let view else {
            return
        }
        let viewModel = TitleDetailsSheetViewModel(
            graphics: nil,
            title: LocalizableResource { _ in
                String(localized: .ChatExtension.dim2SwitchConfirmationTitle)
            },
            message: LocalizableResource { _ in
                .normal(String(localized: .ChatExtension.dim2SwitchConfirmationMessage))
            },
            mainAction: .init(
                title: LocalizableResource { _ in
                    String(localized: .ChatExtension.dimSwitch)
                },
                handler: onSwitch,
                actionType: .destructive
            ),
            secondaryAction: .init(
                title: LocalizableResource { _ in
                    String(localized: .Common.cancel)
                },
                handler: {}
            )
        )
        let infoView = TitleDetailsSheetViewFactory.createView(
            from: viewModel,
            styler: SwitchConfirmationSheetStyler(),
            allowsSwipeDown: true
        )
        BottomSheetViewFacade.setupBottomSheet(from: infoView.controller, preferredHeight: 0)
        view.controller.present(infoView.controller, animated: true)
    }

    func showInvitationServiceUnavailable(
        depositHandler: @escaping () -> Void,
        cancelHandler: @escaping () -> Void
    ) {
        guard let view else {
            return
        }
        let viewModel = TitleDetailsSheetViewModel(
            graphics: nil,
            title: LocalizableResource { _ in
                String(localized: .Game.gameRegisterInvitationUnavailableTitle)
            },
            message: LocalizableResource { _ in
                .normal(String(localized: .Game.gameRegisterInvitationUnavailableMessage))
            },
            mainAction: .init(
                title: LocalizableResource { _ in
                    String(localized: .Game.gameRegisterInvitationUnavailableDepositAction)
                },
                handler: depositHandler
            ),
            secondaryAction: .init(
                title: LocalizableResource { _ in
                    String(localized: .Common.close)
                },
                handler: cancelHandler
            )
        )
        let buttonStyler = MessageSheetStyler.RoundedButtonFactory(
            mainStyle: .white,
            secondaryStyle: .mainDark
        )
        let infoView = TitleDetailsSheetViewFactory.createView(
            from: viewModel,
            styler: MessageSheetStyler(controlFactory: buttonStyler),
            allowsSwipeDown: true
        )
        if let sheetController = infoView.controller as? TitleDetailsSheetViewController {
            sheetController.closeOnSwipeDownClosure = cancelHandler
        }
        infoView.controller.traitOverrides.appTheme = ThemesRegistry.default
        BottomSheetViewFacade.setupBottomSheet(from: infoView.controller)
        view.controller.present(infoView.controller, animated: true)
    }
}
