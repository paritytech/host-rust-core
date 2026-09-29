import Foundation
import UIKit
import PolkadotUI
import Keystore_iOS
import AsyncExtensions
import Individuality
import UIKitExt

final class DIM1ChatExtension: ChatExtensionBot, ChatExtensionDelegateProvidable {
    private let faqItems: [ChatExtensionActions.FAQ] = [
        .init(
            id: "location",
            question: String(localized: .ChatExtension.dim1FaqQuestionLocation),
            answer: String(localized: .ChatExtension.dim1FaqAnswerLocation)
        ),
        .init(
            id: "how",
            question: String(localized: .ChatExtension.dim1FaqQuestionHow),
            answer: String(localized: .ChatExtension.dim1FaqAnswerHow)
        ),
        .init(
            id: "what",
            question: String(localized: .ChatExtension.dim1FaqQuestionWhat),
            answer: String(localized: .ChatExtension.dim1FaqAnswerWhat)
        )
    ]

    private let settings: ChatExtensionBotSettings
    private let interactor: DIM1ChatInteracting
    private let wireframe: DIM1WireframeProtocol
    private let personActions: [ChatExtensionActions.ActionModel]
    private let logger: LoggerProtocol

    private let footerContentConfiguration = AsyncCurrentValueSubject<(any HashableContentConfiguration)?>(nil)

    weak var delegate: ChatExtensionDelegate? {
        get {
            wireframe.registryDelegate
        }

        set {
            wireframe.registryDelegate = newValue
        }
    }

    init(
        interactor: DIM1ChatInteracting,
        settings: ChatExtensionBotSettings = SettingsManager.shared,
        wireframe: DIM1WireframeProtocol,
        personActions: [ChatExtensionActions.ActionModel],
        logger: LoggerProtocol = Logger.shared
    ) {
        self.interactor = interactor
        self.settings = settings
        self.wireframe = wireframe
        self.personActions = personActions
        self.logger = logger
    }

    // MARK: - Text Message Handling

    override func onTextMessage(
        _ message: Chat.LocalMessage,
        text _: String,
        context: ChatExtensionProcessingContextProtocol
    ) async -> ChatExtension.ProcessingResult {
        switch message.content {
        case let .extensionActionResponse(_, action):
            guard let item = faqItems.first(where: { $0.id == action }) else {
                return .skipped
            }
            Task {
                try await context.addNewMessage(
                    .text(item.answer),
                    delayDelivery: .custom(0.3),
                    chatExtension: self
                )
            }
            return .processed
        default:
            return .skipped
        }
    }
}

// MARK: - ChatExtensionBotProtocol

extension DIM1ChatExtension: ChatExtensionBotProtocol {
    nonisolated static let identifier: ChatExtension.Id = "DIM1Chat"

    var identifier: ChatExtension.Id { Self.identifier }

    var peerMetadata: Chat.PeerMetadata {
        Chat.PeerMetadata(
            name: String(localized: .ChatExtension.chatTitleDim1),
            contactSource: .chat,
            icon: .bot,
            input: .empty,
            moreActions: []
        )
    }

    func deliverAutomaticMessages(_ context: ChatExtensionDiscoverContextProtocol) {
        guard settings.isEnabled(extId: identifier) else {
            return
        }

        // 1. Set welcome messages
        Task {
            let messages: [Chat.LocalMessage.Content] = [
                .text(String(localized: .ChatExtension.dim1Welcome1)),
                .staticTextImageContent(
                    Chat.LocalMessage.Content.StaticTextImageContent(
                        text: String(localized: .ChatExtension.dim1Welcome2),
                        media: .dim1Arm
                    )
                ),
                .staticTextImageContent(
                    Chat.LocalMessage.Content.StaticTextImageContent(
                        text: String(localized: .ChatExtension.dim1Welcome3),
                        media: .dim1Design
                    )
                ),
                .text(String(localized: .ChatExtension.dim1Welcome4)),
                .staticTextImageContent(
                    Chat.LocalMessage.Content.StaticTextImageContent(
                        text: String(localized: .ChatExtension.dim1Welcome5),
                        media: .dim1Tattoo
                    )
                ),
                .text(String(localized: .ChatExtension.dim1Welcome6))
            ]

            try await context.setWelcomeMessages(
                from: self,
                with: { messages }
            )

            await interactor.setup()
        }

        Task { [weak self] in
            guard let self else { return }
            let processingContext = ProofOfInkProcessingContext(context: context, sender: self)
            try await processingContext.process(events: interactor.observeMessageEvents())
        }

        Task { [weak self, interactor] in
            for try await state in interactor.observeWidgetState() {
                try await self?.invalidateFooterConfiguration(with: state, context: context)
            }
        }
    }

    func process(
        action: Chat.Action,
        context: ChatExtensionActionContextProtocol
    ) async {
        switch action {
        case let .customMessage(actionId, _, messageId):
            await handleButtonClicked(buttonId: actionId, messageId: messageId, context: context)
        }
    }

    func attach(presentationView: ControllerBackedProtocol) {
        Task { @MainActor [wireframe] in
            wireframe.view = presentationView
        }
    }
}

// MARK: - Handle Actions

private extension DIM1ChatExtension {
    func handleButtonClicked(
        buttonId: String,
        messageId: String,
        context: ChatExtensionActionContextProtocol
    ) async {
        switch buttonId {
        case ActionButtonId.retryEvidenceUpload:
            await interactor.retryEvidenceUpload()

        case ActionButtonId.openEvidencePreview:
            await handleOpenEvidencePreview(messageId: messageId, context: context)

        default:
            break
        }
    }

    func handleOpenEvidencePreview(
        messageId: String,
        context: ChatExtensionActionContextProtocol
    ) async {
        guard let message = try? await context.getMessage(messageId: messageId) else {
            return
        }

        guard let evidenceData = EvidenceMessageHelper.extractEvidenceData(from: message) else {
            logger.error("Failed to extract evidence data from message: \(messageId)")
            return
        }

        wireframe.showEvidencePreview(
            evidenceId: evidenceData.evidenceId,
            type: evidenceData.type
        )
    }
}

// MARK: - Footer Configuration

extension DIM1ChatExtension: ChatExtensionActionProvidable {
    func contentConfiguration() async throws -> AnyAsyncSequence<(any HashableContentConfiguration)?> {
        footerContentConfiguration
            .removeDuplicates { lhs, rhs in
                switch (lhs, rhs) {
                case (nil, nil):
                    true
                case let (lhs?, rhs?):
                    AnyHashable(lhs) == AnyHashable(rhs)
                default:
                    false
                }
            }
            .eraseToAnyAsyncSequence()
    }
}

private extension DIM1ChatExtension {
    func invalidateFooterConfiguration(
        with state: DIM1WidgetState?,
        context: ChatExtensionDiscoverContextProtocol
    ) async throws {
        let configuration = try await footerConfiguration(for: state, context: context)
        footerContentConfiguration.send(configuration)
    }

    func footerConfiguration(
        for state: DIM1WidgetState?,
        context: ChatExtensionDiscoverContextProtocol
    ) async throws -> (any HashableContentConfiguration)? {
        switch state {
        case let .switchToCurrentDim(possible, inProgress):
            return DIM1FooterConfiguration.switchDIM(inProgress: inProgress) { [weak self] in
                Task { @MainActor in
                    self?.handleSwitchDimAction(switchPossible: possible)
                }
            }
        case .evidenceProvided:
            return DIM1FooterConfiguration.evidenceProvided()
        case .evidenceApproved:
            return DIM1FooterConfiguration.becomingPeer()
        case let .fullUsernameRegistration(upgradeData):
            return DIM1FooterConfiguration.upgradeUsername(
                liteUsername: upgradeData.displayLiteUsername,
                suggestedFullUsername: upgradeData.suggestedFullUsername
            ) { [weak self] in
                Task { @MainActor in
                    self?.wireframe.showUpgradeUsername(upgradeData)
                }
            }
        case .usernameClaimed:
            let actions = provideRouteActions()
            return DIM1FooterConfiguration.routeActions(actions: actions)
        case .applyForTattoo,
             .provideVideoEvidence,
             .providePhotoEvidence:
            let faqActions = try await faqActions(for: state, context: context)
            let action = mainAction(for: state)
            return DIM1FooterConfiguration.footer(messages: faqActions, action: action)
        case .none:
            return nil
        }
    }

    func mainAction(for state: DIM1WidgetState?) -> UIAction? {
        switch state {
        case .applyForTattoo:
            UIAction(title: String(localized: .Tattoo.actionChatReserveTattoo)) { [weak self] _ in
                Task { @MainActor in
                    self?.wireframe.openLink(AppConfig.DeepLink.reserve())
                }
            }
        case let .provideVideoEvidence(inkSpec, familyId, evidenceId):
            UIAction(title: String(localized: .Tattoo.actionProvideVideoEvidence)) { [weak self] _ in
                Task { @MainActor in
                    self?.routeToVideoEvidence(for: inkSpec, familyId: familyId, evidenceId: evidenceId)
                }
            }
        case let .providePhotoEvidence(inkSpec, familyId, evidenceId):
            UIAction(title: String(localized: .Tattoo.actionProvidePhotoEvidence)) { [weak self] _ in
                Task { @MainActor in
                    self?.routeToPhotoEvidence(for: inkSpec, familyId: familyId, evidenceId: evidenceId)
                }
            }
        case .evidenceProvided,
             .evidenceApproved,
             .fullUsernameRegistration,
             .usernameClaimed,
             .switchToCurrentDim,
             .none:
            nil
        }
    }

    func faqActions(
        for state: DIM1WidgetState?,
        context: ChatExtensionDiscoverContextProtocol
    ) async throws -> [UIAction] {
        var actions: [UIAction] = []
        for faqItem in faqItems {
            let hasResponse = try await context.hasResponse(from: self, with: faqItem.id)
            guard !hasResponse else {
                continue
            }
            let action = UIAction(
                title: faqItem.question,
                handler: { [weak self, context] action in
                    Task {
                        if let self {
                            try await context.addActionResponse(
                                action.title,
                                action: faqItem.id,
                                delayDelivery: .immediate,
                                chatExtension: self
                            )
                        }

                        try await self?.invalidateFooterConfiguration(with: state, context: context)
                    }
                }
            )
            actions.append(action)
        }
        return actions
    }
}

@MainActor
private extension DIM1ChatExtension {
    func routeToVideoEvidence(
        for design: ProofOfInkPallet.InkSpec,
        familyId: ProofOfInkPallet.FamilyId,
        evidenceId: String
    ) {
        let model = EvidenceInstructionsModel(
            onProceed: { [weak self] in
                self?.wireframe.showProvideVideoEvidence(
                    for: design,
                    familyId: familyId,
                    evidenceId: evidenceId
                )
            },
            onClose: {}
        )
        wireframe.showProvideVideoEvidenceInstruction(model: model)
    }

    func routeToPhotoEvidence(
        for design: ProofOfInkPallet.InkSpec,
        familyId: ProofOfInkPallet.FamilyId,
        evidenceId: String
    ) {
        let model = EvidenceInstructionsModel(
            onProceed: { [weak self] in
                self?.wireframe.showProvidePhotoEvidence(
                    for: design,
                    familyId: familyId,
                    evidenceId: evidenceId
                )
            },
            onClose: {}
        )
        wireframe.showProvidePhotoEvidenceInstruction(model: model)
    }
}

private extension DIM1ChatExtension {
    func provideRouteActions() -> [ChatMessageActionView.ViewModel] {
        personActions.map { action in
            ChatMessageActionView.ViewModel(
                title: action.title,
                subtitle: action.subtitle,
                buttonTitle: String(localized: .ChatExtension.polkadotPeerActionOpen)
            ) { [weak self] in
                Task { @MainActor in
                    self?.wireframe.openChatWithExtension(action.identifier)
                }
            }
        }
    }
}

extension DIM1ChatExtension {
    enum ActionButtonId {
        static let retryEvidenceUpload = "retryEvidenceUpload"
        static let openEvidencePreview = "openEvidencePreview"
    }
}

extension DIM1ChatExtension {
    enum DimSwitchingError: Error, ErrorContentConvertible {
        case unavailable

        func toErrorContent() -> ErrorContent {
            .init(
                title: String(localized: .ChatExtension.dimSwitchErrorTitle),
                message: String(localized: .ChatExtension.dim1SwitchErrorMessage)
            )
        }
    }

    @MainActor
    func handleSwitchDimAction(switchPossible possible: Bool) {
        if possible {
            wireframe.showSwitchDIMConfirmation {
                Task { [weak self] in
                    try await self?.interactor.switchToCurrentDim()
                }
            }
        } else {
            wireframe.present(error: DimSwitchingError.unavailable)
        }
    }
}
