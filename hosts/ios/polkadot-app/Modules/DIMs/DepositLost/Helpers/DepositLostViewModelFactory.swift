import Foundation
import UIKit

protocol DepositLostViewModelMaking {
    func make() -> DepositLostViewLayout.ViewModel
}

final class DepositLostViewModelFactory: DepositLostViewModelMaking {
    func make() -> DepositLostViewLayout.ViewModel {
        DepositLostViewLayout.ViewModel(
            image: .gameDepositLost,
            title: String(localized: .Game.gameDepositLostTitle),
            subtitle: String(localized: .Game.gameDepositLostSubtitle)
        )
    }
}
