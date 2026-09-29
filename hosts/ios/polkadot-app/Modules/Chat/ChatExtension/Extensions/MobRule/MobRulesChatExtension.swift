import Foundation
import AsyncExtensions
import Individuality
import PolkadotUI
import UIKitExt

final class MobRulesChatExtension: ChatExtensionBot {
    let settings: ChatExtensionBotSettings
    let interactor: MobRuleInteracting
    let logger: LoggerProtocol

    private let wireframe: MobRuleWireframeProtocol

    private var widgetState: MobRuleWidgetState?
    private let footerContentConfiguration = AsyncCurrentValueSubject<
        (any HashableContentConfiguration)?
    >(nil)

    private var widgetStateTask: Task<Void, Error>?
    private var successfulVoteTask: Task<Void, Error>?

    init(
        settings: ChatExtensionBotSettings,
        interactor: MobRuleInteracting,
        logger: LoggerProtocol = Logger.shared,
        wireframe: MobRuleWireframeProtocol
    ) {
        self.settings = settings
        self.interactor = interactor
        self.logger = logger
        self.wireframe = wireframe
    }
}

extension MobRulesChatExtension: ChatExtensionBotProtocol {
    static var identifier: ChatExtension.Id { "MobRulesChat" }

    var identifier: ChatExtension.Id { Self.identifier }

    var peerMetadata: Chat.PeerMetadata {
        Chat.PeerMetadata(
            name: String(localized: .MobRule.chatName),
            contactSource: .chat,
            icon: .bot,
            input: .empty,
            moreActions: []
        )
    }

    func deliverAutomaticMessages(_ context: any ChatExtensionDiscoverContextProtocol) {
        guard settings.isEnabled(extId: identifier) else {
            return
        }

        Task { [interactor, context] in
            let messages: [Chat.LocalMessage.Content] = [
                .staticTextImageContent(
                    Chat.LocalMessage.Content.StaticTextImageContent(
                        text: String(localized: .MobRule.messageWelcome1),
                        media: .MobRule.welcome1
                    )
                )
            ]

            try await context.setWelcomeMessages(
                from: self,
                with: { messages }
            )

            await interactor.setup()
        }

        widgetStateTask?.cancel()
        widgetStateTask = Task { [weak self, context, interactor] in
            guard let self else { return }

            let processingContext = MobRuleProcessingContext(context: context)

            for try await state in interactor.observeWidgetState() {
                try Task.checkCancellation()
                widgetState = state

                let config = mapToFooterConfiguration(state)
                footerContentConfiguration.send(config)

                try await processingContext.processCasesInfo(widgetState?.casesInfo, sender: self)
            }
        }

        successfulVoteTask?.cancel()
        successfulVoteTask = Task { [weak self, context, interactor] in
            guard let self else { return }
            let processingContext = MobRuleProcessingContext(context: context)
            try await processingContext.processVoting(
                sequence: interactor.observeSuccessfulVote(),
                sender: self
            )
        }
    }

    func process(action: Chat.Action, context: any ChatExtensionActionContextProtocol) async {
        switch action {
        case let .customMessage(actionId, _, messageId):
            switch actionId {
            case MobRulesChatExtension.ActionButtonId.viewCase:
                do {
                    try await handleViewCaseFromMessage(messageId: messageId, context: context)
                } catch {
                    logger.error("Error handling view case from message: \(error)")
                }
            default:
                break
            }
        }
    }

    func attach(presentationView: ControllerBackedProtocol) {
        Task { @MainActor [wireframe] in
            wireframe.view = presentationView
        }
    }
}

// MARK: - ChatExtensionActionProvidable

extension MobRulesChatExtension: ChatExtensionActionProvidable {
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

// MARK: - Private

private extension MobRulesChatExtension {
    func mapToFooterConfiguration(_ state: MobRuleWidgetState?) -> (any HashableContentConfiguration)? {
        guard let state else {
            return nil
        }

        if state.isSuspended {
            return makeSuspendedFooterConfiguration()
        }

        let availableCasesCount = makeAvailableCasesCount(
            vottableCasesCount: state.vottableCasesCount
        )

        let widgetConfig = MobRuleWidgetConfiguration(
            availableCasesCount: availableCasesCount,
            activeCaseModel: state.vottableCaseContext.map { makeWidgetMessageConfig(context: $0) },
            systemMessage: makeSystemMessage(widgetState: state)
        )

        return GenericFooterConfiguration(contentConfiguration: widgetConfig)
    }

    func makeSuspendedFooterConfiguration() -> any HashableContentConfiguration {
        MobRuleFooterConfiguration.suspended { [weak self] in
            self?.navigateToWeeklyGame()
        }
    }

    func navigateToWeeklyGame() {
        Task { @MainActor [wireframe] in
            wireframe.openChatWithExtension(DIM2ChatExtension.identifier)
        }
    }

    func makeAvailableCasesCount(vottableCasesCount: Int) -> Int? {
        if vottableCasesCount > 1 {
            vottableCasesCount - 1
        } else {
            nil
        }
    }

    func makeWidgetMessageConfig(
        context: MobRuleVottableCaseContext
    ) -> MobRuleMessageConfiguration {
        .init(
            context: context,
            activityHandler: { [weak self] in
                self?.handleWidgetActivity(with: $0, for: context.caseIndex)
            }
        )
    }

    func makeSystemMessage(widgetState: MobRuleWidgetState) -> String? {
        guard widgetState.vottableCase == nil, widgetState.votedOnce else {
            return nil
        }
        return .init(localized: .ChatExtension.mobRuleNoAvailableCases)
    }
}

// MARK: - Mob rule activity handling (Widget Part)

private extension MobRulesChatExtension {
    func handleWidgetActivity(
        with type: MobRuleActivityType,
        for caseIndex: MobRulePallet.CaseIndex
    ) {
        switch type {
        case .showEvidence:
            handleShowEvidence()
        case let .toggleExpansion(isExpanded):
            handleToggleExpansion(isExpanded: isExpanded)
        case let .vote(isPositive):
            handleVote(isPositive: isPositive, for: caseIndex)
        case .viewAndJudge:
            handleViewAndJudge(caseIndex: caseIndex)
        case .skipCase:
            handleSkipCase()
        case .viewCase:
            // should be no such case in current widget UI
            break
        }
    }

    func handleShowEvidence() {
        guard let state = widgetState,
              let vottableCase = state.vottableCase,
              case let .proofOfInk(statement) = vottableCase.details.statement,
              let caseIndex = state.vottableCaseIndex,
              let familyId = state.vottableTattooFamilyId else {
            return
        }

        // Current case vote is not in progress
        let votingAvailable = state.inProgressVote == nil

        let model = ProofOfInkVotingModel(
            statement: statement,
            caseIndex: caseIndex,
            familyId: familyId,
            votingAvailable: votingAvailable
        ) { [weak self] positive in
            self?.handleVote(isPositive: positive, for: caseIndex)
        }

        Task { @MainActor in
            wireframe.openFullScreenEvidenceJudgement(model: model)
        }
    }

    func handleToggleExpansion(isExpanded: Bool) {
        Task {
            await interactor.setCurrentCaseExpanded(isExpanded: !isExpanded)
        }
    }

    func handleVote(isPositive: Bool, for caseIndex: MobRulePallet.CaseIndex) {
        Task {
            do {
                try await interactor.submitVote(
                    for: caseIndex,
                    with: .truth(isPositive ? .confidentTrue : .confidentFalse)
                )
            } catch {
                logger.error("Error: \(error)")
            }
        }
    }

    func handleViewAndJudge(caseIndex: MobRulePallet.CaseIndex) {
        Task {
            await interactor.markSensitiveAllow(for: caseIndex)
        }
    }

    func handleSkipCase() {}

    // MARK: - Mob rule activity handling (Message Part)

    func handleViewCaseFromMessage(
        messageId: Chat.MessageId,
        context: any ChatExtensionActionContextProtocol
    ) async throws {
        guard let message = try await context.getMessage(messageId: messageId),
              case let .customRendered(customData) = message.content,
              let decodedContent = try? MobRuleMessageDecoder.decodeContent(from: customData.data),
              case let .proofOfInk(statement) = decodedContent.caseDetails.statement,
              let familyId = decodedContent.tattooFamilyId else {
            return
        }

        let model = ProofOfInkVotingModel(
            statement: statement,
            caseIndex: decodedContent.caseIndex,
            familyId: familyId,
            votingAvailable: false,
            onVoting: nil
        )

        await MainActor.run {
            wireframe.openFullScreenEvidenceJudgement(model: model)
        }
    }
}

// MARK: - ActionButtonId

extension MobRulesChatExtension {
    enum ActionButtonId {
        static let viewCase = "viewCase"
    }
}
