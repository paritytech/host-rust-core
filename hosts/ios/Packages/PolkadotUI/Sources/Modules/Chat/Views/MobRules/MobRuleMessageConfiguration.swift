import Foundation
import UIKit

public enum MobRuleActivityType {
    case showEvidence
    case toggleExpansion(isExpanded: Bool)
    case vote(isPositive: Bool)
    case viewAndJudge
    case skipCase
    case viewCase
}

public typealias MobRuleActivityHandler = (MobRuleActivityType) -> Void

public struct MobRuleMessageConfiguration: HashableContentConfiguration {
    let mediaPreviewProvider: (any ChatMessageMediaPreviewProviding)?
    let showPlayButton: Bool

    let tattooPreviewProvider: (any ChatMessageMediaPreviewProviding)?

    /// Documentation Video / Tattoo Photo.
    let type: String

    /// markdown supported
    let details: String

    let layout: Layout

    let activityHandler: MobRuleActivityHandler?

    public init(
        mediaPreviewProvider: (any ChatMessageMediaPreviewProviding)?,
        showPlayButton: Bool = false,
        tattooPreviewProvider: (any ChatMessageMediaPreviewProviding)?,
        type: String,
        details: String,
        layout: Layout,
        activityHandler: MobRuleActivityHandler? = nil
    ) {
        self.mediaPreviewProvider = mediaPreviewProvider
        self.showPlayButton = showPlayButton
        self.tattooPreviewProvider = tattooPreviewProvider
        self.type = type
        self.details = details
        self.layout = layout
        self.activityHandler = activityHandler
    }

    public func makeContentView() -> any UIView & UIContentView {
        MobRuleMessageView(configuration: self)
    }

    public static func == (lhs: MobRuleMessageConfiguration, rhs: MobRuleMessageConfiguration) -> Bool {
        lhs.mediaPreviewProvider?.identifier == rhs.mediaPreviewProvider?.identifier &&
            lhs.tattooPreviewProvider?.identifier == rhs.tattooPreviewProvider?.identifier &&
            lhs.type == rhs.type &&
            lhs.details == rhs.details &&
            lhs.layout == rhs.layout
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(mediaPreviewProvider?.identifier)
        hasher.combine(tattooPreviewProvider?.identifier)
        hasher.combine(type)
        hasher.combine(details)
        hasher.combine(layout)
    }
}

extension MobRuleMessageConfiguration {
    var actionType: ActionType? {
        guard case let .plain(configuration) = layout else {
            return nil
        }
        return configuration.actionType
    }

    var isSensitive: Bool {
        switch layout {
        case let .compact(configuration):
            return configuration.isSensitive
        case let .plain(configuration):
            guard case .sensitiveContent = configuration.actionType else {
                return false
            }
            return true
        }
    }

    var isArchived: Bool {
        guard case let .compact(configuration) = layout else {
            return false
        }
        return configuration.isArchived
    }

    var isCompact: Bool {
        switch layout {
        case .compact:
            true
        default:
            false
        }
    }

    var isExpanded: Bool? {
        guard case let .plain(configuration) = layout else {
            return nil
        }
        return configuration.isExpanded
    }
}

public extension MobRuleMessageConfiguration {
    enum Layout: Hashable {
        case plain(configuration: PlainLayoutConfiguration)
        case compact(configuration: CompactLayoutConfiguration)
    }

    struct PlainLayoutConfiguration: Hashable {
        let actionType: ActionType
        let isExpanded: Bool

        public init(actionType: ActionType, isExpanded: Bool) {
            self.actionType = actionType
            self.isExpanded = isExpanded
        }
    }

    struct CompactLayoutConfiguration: Hashable {
        let isSensitive: Bool
        let isArchived: Bool

        public init(isSensitive: Bool, isArchived: Bool) {
            self.isSensitive = isSensitive
            self.isArchived = isArchived
        }
    }

    enum ActionType: Hashable {
        case vote(positiveAction: ActionConfiguration, negativeAction: ActionConfiguration)
        case sensitiveContent(viewAction: ActionConfiguration, skipAction: ActionConfiguration)
    }

    struct ActionConfiguration: Hashable {
        let isEnabled: Bool
        let inProgress: Bool

        public init(isEnabled: Bool = true, inProgress: Bool = false) {
            self.isEnabled = isEnabled
            self.inProgress = inProgress
        }
    }
}

#if DEBUG

    let longDetails: String = """
    · Is the Tattoo Design matches the submitted image in terms of design? 
    · Are marks of skin reaction to the tattoo visible in the video to ensure that the process is real?
    """

    extension MobRuleMessageConfiguration {
        static func expandedVoting() -> Self {
            .init(
                mediaPreviewProvider: StaticImagePreviewProvider(image: .remove),
                tattooPreviewProvider: StaticImagePreviewProvider(image: .add),
                type: "Documentation Video",
                details: longDetails,
                layout: .plain(
                    configuration: PlainLayoutConfiguration(
                        actionType: .vote(
                            positiveAction: ActionConfiguration(inProgress: true),
                            negativeAction: ActionConfiguration()
                        ),
                        isExpanded: true
                    )
                )
            )
        }

        static func collapsedVoting() -> Self {
            .init(
                mediaPreviewProvider: StaticImagePreviewProvider(image: .remove),
                tattooPreviewProvider: StaticImagePreviewProvider(image: .add),
                type: "Documentation Video",
                details: longDetails,
                layout: .plain(
                    configuration: PlainLayoutConfiguration(
                        actionType: .vote(
                            positiveAction: ActionConfiguration(inProgress: true),
                            negativeAction: ActionConfiguration()
                        ),
                        isExpanded: false
                    )
                )
            )
        }

        static func compact() -> Self {
            .init(
                mediaPreviewProvider: StaticImagePreviewProvider(image: .remove),
                tattooPreviewProvider: StaticImagePreviewProvider(image: .add),
                type: "Documentation Video",
                details: longDetails,
                layout: .compact(
                    configuration: CompactLayoutConfiguration(
                        isSensitive: true,
                        isArchived: true
                    )
                ),
            )
        }
    }

#endif
