import Foundation
import SubstrateSdk
import UIKitExt

@MainActor
protocol WeeklyGameWireframeProtocol:
    ChatExtensionWireframeProtocol,
    ChatExtensionNavigating,
    AlertPresentable,
    ErrorPresentable,
    ApplicationSettingsPresentable {
    func dismiss(_ completion: (() -> Void)?)
    func showDeposit(_ neededAmount: Balance, model: GameDepositRequiredModel)
    func showDepositConfirmation(_ amount: Balance, model: ConfirmDepositModel)
    func showEnableNotifications(_ model: EnableNotificationsModel)
    func showUpgradeUsername(_ registeredData: People.RegisteredData)
    func openCurrentGame()
    func showGameAlarmSettings(model: GameAlarmSettingsModel)
    func showSwitchDIMConfirmation(onSwitch: @escaping () -> Void)
    func showInvitationServiceUnavailable(
        depositHandler: @escaping () -> Void,
        cancelHandler: @escaping () -> Void
    )
}
