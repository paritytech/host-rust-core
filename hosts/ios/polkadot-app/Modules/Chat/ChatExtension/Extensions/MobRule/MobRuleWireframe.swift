import UIKit
import Keystore_iOS
import UIKitExt

@MainActor
protocol MobRuleWireframeProtocol:
    ChatExtensionWireframeProtocol,
    ChatExtensionNavigating,
    AlertPresentable,
    ErrorPresentable {
    func openFullScreenEvidenceJudgement(model: ProofOfInkVotingModel)
}

@MainActor
final class MobRuleWireframe {
    weak var view: ControllerBackedProtocol?
    var botSettings: ChatExtensionBotSettings
    var application: UIApplication
    weak var registryDelegate: ChatExtensionDelegate?

    init(
        botSettings: ChatExtensionBotSettings = SettingsManager.shared,
        application: UIApplication
    ) {
        self.botSettings = botSettings
        self.application = application
    }
}

extension MobRuleWireframe: MobRuleWireframeProtocol {
    func openFullScreenEvidenceJudgement(model: ProofOfInkVotingModel) {
        guard let voting = ProofOfInkVotingViewFactory.createView(model: model) else {
            return
        }
        voting.controller.modalPresentationStyle = .fullScreen
        view?.controller.present(voting.controller, animated: true)
    }
}
