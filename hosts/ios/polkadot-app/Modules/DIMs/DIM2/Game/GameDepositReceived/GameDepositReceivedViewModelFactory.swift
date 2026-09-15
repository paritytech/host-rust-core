import Foundation

protocol GameDepositReceivedViewModelMaking {
    func viewModel() -> GameDepositReceivedViewLayout.ViewModel
}

final class GameDepositReceivedViewModelFactory: GameDepositReceivedViewModelMaking {
    let registrationAvailable: Bool

    init(registrationAvailable: Bool) {
        self.registrationAvailable = registrationAvailable
    }

    func viewModel() -> GameDepositReceivedViewLayout.ViewModel {
        if registrationAvailable {
            GameDepositReceivedViewLayout.ViewModel(
                details: String(localized: .Game.gameDepositReceivedTitle),
                registerButtonText: String(localized: .Game.gameDepositReceivedRegisterAction),
                skipButtonText: String(localized: .Game.gameDepositReceivedSkipAction)
            )
        } else {
            GameDepositReceivedViewLayout.ViewModel(
                details: String(localized: .Game.gameDepositReceivedRegistrationUnavailableTitle),
                registerButtonText: nil,
                skipButtonText: String(localized: .Common.close)
            )
        }
    }
}
