import Foundation

protocol DiscardDIMViewModelMaking {
    func makeVieModel() -> DiscardDIMViewModel
}

final class DiscardTattooViewModelFactory: DiscardDIMViewModelMaking {
    func makeVieModel() -> DiscardDIMViewModel {
        DiscardDIMViewModel(
            title: String(localized: .Game.terminateTattooConfirmationTitle),
            description: String(localized: .Game.terminateTattooConfirmationDescription),
            mainAction: String(localized: .Game.terminateTattooConfirmationTerminateTitle),
            cancelAction: String(localized: .Common.cancel)
        )
    }
}

final class DiscardGameViewModelFactory: DiscardDIMViewModelMaking {
    func makeVieModel() -> DiscardDIMViewModel {
        DiscardDIMViewModel(
            title: String(localized: .Game.terminateGameConfirmationTitle),
            description: String(localized: .Game.terminateGameConfirmationDescription),
            mainAction: String(localized: .Game.terminateGameConfirmationTerminateTitle),
            cancelAction: String(localized: .Common.cancel)
        )
    }
}
