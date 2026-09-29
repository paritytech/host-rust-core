import Foundation
import UIKit

final class GameAlarmSettingsPresenter {
    weak var view: GameAlarmSettingsViewProtocol?
    let interactor: GameAlarmSettingsInteractorInputProtocol
    let model: GameAlarmSettingsModel

    init(model: GameAlarmSettingsModel, interactor: GameAlarmSettingsInteractorInputProtocol) {
        self.model = model
        self.interactor = interactor
    }
}

extension GameAlarmSettingsPresenter: GameAlarmSettingsPresenterProtocol {
    func setup() {
        interactor.setup()
    }

    func didSelect(seconds: Int) {
        interactor.save(seconds: seconds)
    }
}

extension GameAlarmSettingsPresenter: GameAlarmSettingsInteractorOutputProtocol {
    func didSave() {
        model.onUpdate()
    }

    func didReceive(options: [Int], currentSeconds: Int) {
        let viewOptions = options.map { seconds in
            GameAlarmSettingsOption(
                seconds: seconds,
                label: String(localized: .Game.gameAlarmSettingsAlertOption(sec: seconds)),
                image: seconds == currentSeconds ? UIImage(systemName: "checkmark") : nil
            )
        }

        view?.didReceive(options: viewOptions)
    }
}
