import Foundation
import SubstrateSdk
import Keystore_iOS
import Individuality

protocol ConnectionAttemptTracking {
    func getLastOfferId(gameIndex: GamePallet.GameIndex, remoteAccountId: AccountId) -> String?
    func persistOfferId(_ offerId: String, gameIndex: GamePallet.GameIndex, remoteAccountId: AccountId)
    func clearOfferId(gameIndex: GamePallet.GameIndex, remoteAccountId: AccountId)
}

final class ConnectionAttemptTracker {
    private static let keyPrefix = "video_game_p2p_offer_"

    private let settingsManager: SettingsManagerProtocol

    init(settingsManager: SettingsManagerProtocol = SettingsManager.shared) {
        self.settingsManager = settingsManager
    }

    private func storageKey(
        gameIndex: GamePallet.GameIndex,
        remoteAccountId: AccountId
    ) -> String {
        Self.keyPrefix + "\(gameIndex)_\(remoteAccountId.toHex())"
    }
}

extension ConnectionAttemptTracker: ConnectionAttemptTracking {
    func getLastOfferId(
        gameIndex: GamePallet.GameIndex,
        remoteAccountId: AccountId
    ) -> String? {
        let key = storageKey(gameIndex: gameIndex, remoteAccountId: remoteAccountId)
        return settingsManager.string(for: key)
    }

    func persistOfferId(
        _ offerId: String,
        gameIndex: GamePallet.GameIndex,
        remoteAccountId: AccountId
    ) {
        let key = storageKey(gameIndex: gameIndex, remoteAccountId: remoteAccountId)
        settingsManager.set(value: offerId, for: key)
    }

    func clearOfferId(
        gameIndex: GamePallet.GameIndex,
        remoteAccountId: AccountId
    ) {
        let key = storageKey(gameIndex: gameIndex, remoteAccountId: remoteAccountId)
        settingsManager.removeValue(for: key)
    }
}
