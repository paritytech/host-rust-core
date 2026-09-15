import Foundation
import Keystore_iOS

extension SettingsManagerProtocol {
    var gameAlarmTimingSeconds: Int {
        integer(for: .gameAlarmTimingSeconds) ??
            GameAlarmSettingsInteractor.defaultAlarmTimingSeconds
    }
}

final class GameAlarmSettingsInteractor {
    weak var presenter: GameAlarmSettingsInteractorOutputProtocol?

    static let alarmTimingOptions: [Int] = [5, 10, 15, 20]
    static let defaultAlarmTimingSeconds: Int = 20
}

extension GameAlarmSettingsInteractor: GameAlarmSettingsInteractorInputProtocol {
    func setup() {
        MainActor.assumeIsolated {
            presenter?.didReceive(
                options: Self.alarmTimingOptions,
                currentSeconds: SettingsManager.shared.gameAlarmTimingSeconds
            )
        }
    }

    func save(seconds: Int) {
        guard SettingsManager.shared.gameAlarmTimingSeconds != seconds else {
            return
        }
        SettingsManager.shared.set(value: seconds, for: .gameAlarmTimingSeconds)
        MainActor.assumeIsolated {
            presenter?.didSave()
        }
    }
}
