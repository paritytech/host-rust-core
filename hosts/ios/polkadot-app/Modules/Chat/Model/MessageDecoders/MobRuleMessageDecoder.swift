import Foundation
import Foundation_iOS
import SubstrateSdk
import PolkadotUI
import Individuality
import SwiftUI

final class MobRuleMessageDecoder {
    let identifier = MessageDecoderIdentifier.mobRule

    private let timeFormatter: TimestampFormatting

    init(timeFormatter: TimestampFormatting = MessageTimestampFormatter()) {
        self.timeFormatter = timeFormatter
    }
}

// MARK: - ChatMessageCustomDecoding

extension MobRuleMessageDecoder: ChatMessageCustomDecoding {
    func decode(data: Data, context: ChatMessageDecodingContext) -> [any HashableContentConfiguration] {
        guard let content = try? Self.decodeContent(from: data) else {
            return []
        }
        let messageConfig = MobRuleMessageConfiguration(
            messageContent: content,
            activityHandler: {
                ActivityHandler.handleActivity(
                    with: $0,
                    context: context
                )
            }
        )
        let judgementConfig = makeJudgementConfig(content: content)
        return [messageConfig, judgementConfig]
    }

    func previewString(data: Data) -> String {
        guard let content = try? Self.decodeContent(from: data) else {
            return ""
        }
        return makeText(verdict: content.userVerdict)
    }
}

// MARK: - Configurations

private extension MobRuleMessageDecoder {
    func makeJudgementConfig(
        content: Content
    ) -> any HashableContentConfiguration {
        ChatMessageContainerConfiguration.outboxRichText(
            text: makeText(verdict: content.userVerdict),
            statusConfiguration: .outbox(
                date: content.voteDate,
                formatter: timeFormatter,
                status: .delivered,
                isEdited: false
            ),
            canReply: false
        )
    }

    func makeText(verdict: MobRulePallet.Judgement) -> String {
        switch verdict {
        case let .truth(truth):
            switch truth {
            case .confidentFalse:
                String(localized: .ChatExtension.mobRuleFalse)
            case .confidentTrue:
                String(localized: .ChatExtension.mobRuleTrue)
            }
        case .contempt:
            String(localized: .ChatExtension.mobRuleContempt)
        }
    }
}

// MARK: - Content

extension MobRuleMessageDecoder {
    struct Content: Equatable, Codable {
        let caseIndex: MobRulePallet.CaseIndex
        let caseData: MobRuleCaseData
        let caseDetails: MobRulePallet.CaseDetails
        let userVerdict: MobRulePallet.Judgement
        let voteDate: Date
        let tally: MobRulePallet.VoteTally?
        let tattooFamilyId: ProofOfInkPallet.FamilyId?
    }

    static func contentIdentifier(caseIndex: MobRulePallet.CaseIndex) -> String {
        ["mobrule", "\(caseIndex)"].joined(with: .colon)
    }

    static func decodeContent(from data: Data) throws -> Content {
        try JSONDecoder().decode(Content.self, from: data)
    }
}

// MARK: - ActivityHandler

private extension MobRuleMessageDecoder {
    enum ActivityHandler {
        static func handleActivity(
            with type: MobRuleActivityType,
            context: ChatMessageDecodingContext
        ) {
            switch type {
            case .viewCase:
                handleViewCase(context: context)
            case .showEvidence,
                 .toggleExpansion,
                 .vote,
                 .viewAndJudge,
                 .skipCase:
                break
            }
        }

        static func handleViewCase(
            context: ChatMessageDecodingContext
        ) {
            let action = Chat.Action.customMessage(
                actionId: MobRulesChatExtension.ActionButtonId.viewCase,
                payload: nil,
                messageId: context.messageId
            )
            context.processAction(action)
        }
    }
}
