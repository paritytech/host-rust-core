import Foundation
import Foundation_iOS
import Individuality
import UIKit
import UIKitExt
import PolkadotUI

@MainActor
protocol DIM1WireframeProtocol: ChatExtensionWireframeProtocol,
    ChatExtensionNavigating,
    AlertPresentable, ErrorPresentable,
    EvidencePreviewPresentable,
    BottomSheetMessagePresentable {
    func showProvideVideoEvidenceInstruction(model: EvidenceInstructionsModel)
    func showProvidePhotoEvidenceInstruction(model: EvidenceInstructionsModel)

    func showProvideVideoEvidence(
        for design: ProofOfInkPallet.InkSpec,
        familyId: ProofOfInkPallet.FamilyId,
        evidenceId: String
    )

    func showProvidePhotoEvidence(
        for design: ProofOfInkPallet.InkSpec,
        familyId: ProofOfInkPallet.FamilyId,
        evidenceId: String
    )

    func showUpgradeUsername(_ registeredData: People.RegisteredData)
    func showSwitchDIMConfirmation(onSwitch: @escaping () -> Void)
}

@MainActor
final class DIM1Wireframe {
    var mediaPreviewActiveDataSources: [PhotoPreviewDataSource] = []

    weak var view: ControllerBackedProtocol?
    weak var registryDelegate: ChatExtensionDelegate?

    let application: UIApplication
    let botSettings: ChatExtensionBotSettings
    let videoPreviewPlayerFactory: VideoPreviewPlayerFactoryProtocol

    init(
        application: UIApplication,
        botSettings: ChatExtensionBotSettings,
        videoPreviewPlayerFactory: VideoPreviewPlayerFactoryProtocol
    ) {
        self.application = application
        self.botSettings = botSettings
        self.videoPreviewPlayerFactory = videoPreviewPlayerFactory
    }
}

extension DIM1Wireframe: DIM1WireframeProtocol {
    func showProvideVideoEvidenceInstruction(model: EvidenceInstructionsModel) {
        guard let view = EvidenceInstructionsViewFactory.createView(for: model, mode: .video) else {
            return
        }
        view.controller.modalPresentationStyle = .fullScreen
        present(view.controller, animated: true)
    }

    func showProvidePhotoEvidenceInstruction(model: EvidenceInstructionsModel) {
        guard let view = EvidenceInstructionsViewFactory.createView(for: model, mode: .photo) else {
            return
        }
        view.controller.modalPresentationStyle = .fullScreen
        present(view.controller, animated: true)
    }

    func showProvideVideoEvidence(
        for design: ProofOfInkPallet.InkSpec,
        familyId: ProofOfInkPallet.FamilyId,
        evidenceId: String
    ) {
        guard let videoView = TattooEvidenceVideoViewFactory.createView(
            for: design,
            familyId: familyId,
            evidenceId: evidenceId
        ) else {
            return
        }
        let navController = AppNavigationController(rootViewController: videoView.controller)
        navController.barSettings = .init(style: .defaultStyle, shouldSetCloseButton: true)
        navController.modalPresentationStyle = .fullScreen
        present(navController, animated: true)
    }

    func showProvidePhotoEvidence(
        for design: ProofOfInkPallet.InkSpec,
        familyId: ProofOfInkPallet.FamilyId,
        evidenceId: String
    ) {
        guard let videoView = TattooEvidencePhotoViewFactory.createView(
            for: design,
            familyId: familyId,
            evidenceId: evidenceId
        ) else {
            return
        }
        let navController = AppNavigationController(rootViewController: videoView.controller)
        navController.barSettings = .init(style: .defaultStyle, shouldSetCloseButton: true)
        navController.modalPresentationStyle = .fullScreen
        present(navController, animated: true)
    }

    func showUpgradeUsername(_ registeredData: People.RegisteredData) {
        guard let view = ClaimUsernameViewFactory.createFullClaimView(
            registeredData: registeredData
        ) else {
            return
        }

        let navController = AppNavigationController(rootViewController: view.controller)
        navController.barSettings = .init(style: .defaultStyle, shouldSetCloseButton: true)
        navController.modalPresentationStyle = .fullScreen
        present(navController, animated: true)
    }

    func showSwitchDIMConfirmation(onSwitch: @escaping () -> Void) {
        guard let view else {
            return
        }
        let viewModel = TitleDetailsSheetViewModel(
            graphics: nil,
            title: LocalizableResource { _ in
                String(localized: .ChatExtension.dim1SwitchConfirmationTitle)
            },
            message: LocalizableResource { _ in
                .normal(String(localized: .ChatExtension.dim1SwitchConfirmationMessage))
            },
            mainAction: .init(
                title: LocalizableResource { _ in
                    String(localized: .ChatExtension.dimSwitch)
                },
                handler: onSwitch,
                actionType: .destructive
            ),
            secondaryAction: .init(
                title: LocalizableResource { _ in
                    String(localized: .Common.cancel)
                },
                handler: {}
            )
        )
        let infoView = TitleDetailsSheetViewFactory.createView(
            from: viewModel,
            styler: SwitchConfirmationSheetStyler(),
            allowsSwipeDown: true
        )
        BottomSheetViewFacade.setupBottomSheet(from: infoView.controller, preferredHeight: 0)
        view.controller.present(infoView.controller, animated: true)
    }
}

extension DIM1WireframeProtocol {
    func present(_ viewController: UIViewController, animated: Bool) {
        view?.controller.present(viewController, animated: animated)
    }

    func showEvidencePreview(evidenceId: String, type: EvidencePreviewType) {
        showEvidencePreview(evidenceId: evidenceId, type: type, from: view?.controller)
    }
}
