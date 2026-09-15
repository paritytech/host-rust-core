import AlarmKit
import AppIntents
import UIKit

@available(iOS 26.1, *)
struct GameAlarmPlayIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "Join"
    static var openAppWhenRun: Bool = true

    @Parameter(title: "Alarm ID")
    var alarmID: String?

    @Parameter(title: "Game Index")
    var gameIndex: Int?

    @MainActor
    func perform() async throws -> some IntentResult {
        let url = AppConfig.DeepLink.game(intendedGameIndex: gameIndex)

        await UIApplication.shared.open(url)

        if let alarmIDString = alarmID,
           let alarmUUID = UUID(uuidString: alarmIDString) {
            try? AlarmManager.shared.stop(id: alarmUUID)
        }

        return .result()
    }
}
