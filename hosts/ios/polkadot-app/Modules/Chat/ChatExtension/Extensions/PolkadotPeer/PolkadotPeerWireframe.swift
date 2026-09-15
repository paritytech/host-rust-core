import Foundation
import UIKit
import Keystore_iOS
import UIKitExt

@MainActor
protocol PolkadotPeerWireframeProtocol: ChatExtensionWireframeProtocol, AlertPresentable, ErrorPresentable,
    ChatExtensionNavigating {}

@MainActor
final class PolkadotPeerWireframe {
    weak var view: ControllerBackedProtocol?
    weak var registryDelegate: ChatExtensionDelegate?

    let botSettings: ChatExtensionBotSettings
    let application: UIApplication

    init(
        botSettings: ChatExtensionBotSettings = SettingsManager.shared,
        application: UIApplication
    ) {
        self.botSettings = botSettings
        self.application = application
    }
}

extension PolkadotPeerWireframe: PolkadotPeerWireframeProtocol {}
