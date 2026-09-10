import Foundation
import BulletinChain
import Individuality
import PolkadotUI

extension MobRuleMessageConfiguration {
    init(
        messageContent: MobRuleMessageDecoder.Content,
        activityHandler: MobRuleActivityHandler?
    ) {
        self = ConfigurationFactory.makeCompactConfiguration(
            messageContent: messageContent,
            activityHandler: activityHandler
        )
    }

    init(
        context: MobRuleVottableCaseContext,
        activityHandler: MobRuleActivityHandler?
    ) {
        self = ConfigurationFactory.makePlainConfiguration(
            context: context,
            activityHandler: activityHandler
        )
    }
}

private enum ConfigurationFactory {
    static func makeCompactConfiguration(
        messageContent: MobRuleMessageDecoder.Content,
        activityHandler: MobRuleActivityHandler?
    ) -> MobRuleMessageConfiguration {
        .init(
            mediaPreviewProvider: makeMediaPreviewProvider(
                caseDetails: messageContent.caseDetails
            ),
            tattooPreviewProvider: makeTattooPreviewProvider(
                caseDetails: messageContent.caseDetails,
                familyId: messageContent.tattooFamilyId
            ),
            type: makeType(caseDetails: messageContent.caseDetails),
            details: "",
            layout: .compact(configuration: .init(
                isSensitive: makeIsSensitive(tally: messageContent.tally),
                isArchived: makeIsArchived(caseData: messageContent.caseData)
            )),
            activityHandler: activityHandler
        )
    }

    static func makePlainConfiguration(
        context: MobRuleVottableCaseContext,
        activityHandler: MobRuleActivityHandler?
    ) -> MobRuleMessageConfiguration {
        .init(
            mediaPreviewProvider: makeMediaPreviewProvider(
                caseDetails: context.openCase.details
            ),
            showPlayButton: isVideoEvidence(caseDetails: context.openCase.details),
            tattooPreviewProvider: makeTattooPreviewProvider(
                caseDetails: context.openCase.details,
                familyId: context.familyId
            ),
            type: makeType(caseDetails: context.openCase.details),
            details: makeDetails(caseDetails: context.openCase.details),
            layout: .plain(configuration: .init(
                actionType: makeActionType(
                    vottableCase: context.openCase,
                    inProgressVote: context.inProgressVote,
                    sensitiveAllowed: context.sensitiveAllowed
                ),
                isExpanded: context.isExpanded
            )),
            activityHandler: activityHandler
        )
    }

    static func makeType(caseDetails: MobRulePallet.CaseDetails) -> String {
        switch caseDetails.statement {
        case let .proofOfInk(proofOfInk):
            if proofOfInk.probableAcceptable {
                String(localized: .ChatExtension.mobRulePhotoCase)
            } else {
                String(localized: .ChatExtension.mobRuleVideoCase)
            }
        case .identityCredential:
            "Identity (not supported)"
        case .usernameValid:
            "Username (not supported)"
        }
    }

    static func makeDetails(caseDetails: MobRulePallet.CaseDetails) -> String {
        switch caseDetails.statement {
        case .proofOfInk:
            String(localized: .ChatExtension.mobRuleProofOfInkDetails)
        case .identityCredential:
            "Identity (not supported)"
        case .usernameValid:
            "Username (not supported)"
        }
    }

    static func makeIsSensitive(tally: MobRulePallet.VoteTally?) -> Bool {
        guard let tally else {
            return false
        }
        return tally.contempt > 0
    }

    static func makeIsArchived(caseData: MobRuleCaseData) -> Bool {
        switch caseData {
        case .open,
             .ripe:
            false
        case .done:
            true
        }
    }

    static func makeActionType(
        vottableCase: MobRulePallet.OpenCase,
        inProgressVote: MobRuleVote?,
        sensitiveAllowed: Bool
    ) -> MobRuleMessageConfiguration.ActionType {
        if sensitiveAllowed || !makeIsSensitive(tally: vottableCase.tally) {
            makeVoteAction(inProgressVote: inProgressVote)
        } else {
            makeSensitiveContentAction()
        }
    }

    static func makeVoteAction(
        inProgressVote: MobRuleVote?
    ) -> MobRuleMessageConfiguration.ActionType {
        let isEnabled = inProgressVote == nil
        let inProgressPositive = makeInProgressPositive(inProgressVote: inProgressVote)
        let inProgressNegative = makeInProgressNegative(inProgressVote: inProgressVote)

        return .vote(
            positiveAction: .init(isEnabled: isEnabled, inProgress: inProgressPositive),
            negativeAction: .init(isEnabled: isEnabled, inProgress: inProgressNegative)
        )
    }

    static func makeInProgressPositive(
        inProgressVote: MobRuleVote?
    ) -> Bool {
        guard
            case let .truth(truth) = inProgressVote?.opinion,
            case .confidentTrue = truth
        else {
            return false
        }
        return true
    }

    static func makeInProgressNegative(
        inProgressVote: MobRuleVote?
    ) -> Bool {
        guard
            case let .truth(truth) = inProgressVote?.opinion,
            case .confidentFalse = truth
        else {
            return false
        }
        return true
    }

    static func isVideoEvidence(
        caseDetails: MobRulePallet.CaseDetails
    ) -> Bool {
        guard
            case let .proofOfInk(value) = caseDetails.statement
        else {
            return false
        }

        return !value.probableAcceptable
    }

    static func makeSensitiveContentAction() -> MobRuleMessageConfiguration.ActionType {
        .sensitiveContent(
            viewAction: .init(isEnabled: true, inProgress: false),
            skipAction: .init(isEnabled: true, inProgress: false)
        )
    }

    static func makeMediaPreviewProvider(
        caseDetails: MobRulePallet.CaseDetails
    ) -> (any ChatMessageMediaPreviewProviding)? {
        guard
            case let .proofOfInk(value) = caseDetails.statement
        else {
            return nil
        }

        let hash = value.evidence.toHexString()
        let hexConverter = HexToCIDConverter()

        guard let url = hexConverter.convertToIPFSURL(
            fileHash: hash,
            codec: .json
        ) else {
            return nil
        }

        if value.probableAcceptable {
            return PhotoEvidenceMediator(manifestURL: url)
        } else {
            return IPFSVideoSource(manifestURL: url)
        }
    }

    static func makeTattooPreviewProvider(
        caseDetails: MobRulePallet.CaseDetails,
        familyId: ProofOfInkPallet.FamilyId?
    ) -> TattooChatMessageMediaPreviewProvider? {
        guard
            let familyId,
            case let .proofOfInk(value) = caseDetails.statement
        else {
            return nil
        }
        return TattooChatMessageMediaPreviewProvider(
            design: value.design,
            familyId: familyId
        )
    }
}
