import Foundation
import AsyncExtensions
import SubstrateSdk
import Individuality

actor MobRuleProcessingContext {
    private let context: ChatExtensionDiscoverContextProtocol
    private let logger: LoggerProtocol

    init(
        context: ChatExtensionDiscoverContextProtocol,
        logger: LoggerProtocol = Logger.shared
    ) {
        self.context = context
        self.logger = logger
    }
}

// MARK: - Event processing

extension MobRuleProcessingContext {
    func processVoting(
        sequence: AnyAsyncSequence<MobRuleVote>,
        sender: ChatExtensionBotProtocol
    ) async throws {
        for try await vote in sequence {
            try Task.checkCancellation()
            try await handleNewVote(vote, sender: sender)
        }
    }

    func processCasesInfo(
        _ casesInfo: MobRuleCasesInfo?,
        sender: ChatExtensionBotProtocol
    ) async throws {
        guard let casesInfo else {
            return
        }
        for (index, caseData) in casesInfo.allCases {
            try await handleNewCaseData(caseData, for: index, sender: sender)
        }
    }
}

// MARK: - Private

private extension MobRuleProcessingContext {
    func handleNewVote(
        _ vote: MobRuleVote,
        sender: ChatExtensionBotProtocol
    ) async throws {
        let contentIdentifier = MobRuleMessageDecoder.contentIdentifier(caseIndex: vote.caseIndex)
        let messages = try await context.getMessagesByContentKey(contentIdentifier, with: sender)

        guard messages.isEmpty else {
            return
        }

        let content = MobRuleMessageDecoder.Content(
            caseIndex: vote.caseIndex,
            caseData: .open(vote.openCase),
            caseDetails: vote.openCase.details,
            userVerdict: vote.opinion,
            voteDate: Date(),
            tally: vote.openCase.tally,
            tattooFamilyId: vote.tattooFamilyId
        )

        let messageContent: Chat.LocalMessage.Content = try .customRendered(
            .init(
                decoderId: MessageDecoderIdentifier.mobRule.rawValue,
                data: JSONEncoder().encode(content),
                identifier: contentIdentifier
            )
        )

        _ = try await context.sendNewMessage(
            from: sender,
            newContent: messageContent,
            messageDeliveryDelay: .immediate
        )
    }

    func handleNewCaseData(
        _ caseData: MobRuleCaseData,
        for caseIndex: MobRulePallet.CaseIndex,
        sender: ChatExtensionBotProtocol
    ) async throws {
        let contentIdentifier = MobRuleMessageDecoder.contentIdentifier(caseIndex: caseIndex)
        let messages = try await context.getMessagesByContentKey(contentIdentifier, with: sender)

        guard
            let currentMessage = messages.first,
            case let .customRendered(renderedData) = currentMessage.content
        else {
            return
        }

        let currentContent = try MobRuleMessageDecoder.decodeContent(from: renderedData.data)

        let newContent = MobRuleMessageDecoder.Content(
            caseIndex: caseIndex,
            caseData: caseData,
            caseDetails: currentContent.caseDetails,
            userVerdict: currentContent.userVerdict,
            voteDate: currentContent.voteDate,
            tally: caseData.tally ?? currentContent.tally,
            tattooFamilyId: currentContent.tattooFamilyId
        )

        let messageContent: Chat.LocalMessage.Content = try .customRendered(
            .init(
                decoderId: MessageDecoderIdentifier.mobRule.rawValue,
                data: JSONEncoder().encode(newContent),
                identifier: contentIdentifier
            )
        )

        _ = try await context.modifyMessageContent(
            messageId: currentMessage.messageId,
            content: messageContent
        )
    }
}
