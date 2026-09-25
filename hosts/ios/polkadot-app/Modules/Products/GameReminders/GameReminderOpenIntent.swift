import AlarmKit
import AppIntents
import Foundation

/// What the game reminder alarm's "Play game" button runs: stop the alarm and open the product.
@available(iOS 26.1, *)
struct GameReminderOpenIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "Join"
    static var openAppWhenRun: Bool = true

    @Parameter(title: "Alarm ID")
    var alarmID: String?

    @Parameter(title: "Product link")
    var productLink: String?

    @MainActor
    func perform() async throws -> some IntentResult {
        if let productLink, let url = URL(string: productLink) {
            DeferredLinkHandler.shared.handle(with: url)
        }

        if let alarmID, let alarmUUID = UUID(uuidString: alarmID) {
            try? AlarmManager.shared.stop(id: alarmUUID)
        }

        return .result()
    }
}
