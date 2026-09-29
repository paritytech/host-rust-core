import UIKit
import Foundation_iOS
import UIKitExt

final class GameAlarmSettingsViewController: UIAlertController {
    var presenter: GameAlarmSettingsPresenterProtocol?
}

extension GameAlarmSettingsViewController: ControllerBackedProtocol {}

extension GameAlarmSettingsViewController: GameAlarmSettingsViewProtocol {
    func didReceive(options: [GameAlarmSettingsOption]) {
        for option in options {
            let action = UIAlertAction(title: option.label, style: .default) { [weak presenter] _ in
                presenter?.didSelect(seconds: option.seconds)
            }
            if let image = option.image {
                action.setValue(image, forKey: "image")
            }
            addAction(action)
        }

        addAction(UIAlertAction(title: String(localized: .Common.cancel), style: .cancel))
    }
}
