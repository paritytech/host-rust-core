import Foundation
import Foundation_iOS
import SubstrateSdk
import SubstrateStorageSubscription
import Individuality

enum MobRulePointsTracking {
    struct PayoutStateChange: BatchStorageSubscriptionResult {
        enum Key: String {
            case creditDistribution
            case roundSchedule
        }

        let creditDistribution: UncertainStorage<MobRulePallet.CreditDistribution?>
        let roundSchedules: UncertainStorage<MobRulePallet.RoundSchedules?>
        let blockHash: Data?

        init(
            values: [BatchStorageSubscriptionResultValue],
            blockHashJson: JSON,
            context: [CodingUserInfoKey: Any]?
        ) throws {
            creditDistribution = try UncertainStorage<MobRulePallet.CreditDistribution?>(
                values: values,
                mappingKey: Key.creditDistribution.rawValue,
                context: context
            )

            roundSchedules = try UncertainStorage<MobRulePallet.RoundSchedules?>(
                values: values,
                mappingKey: Key.roundSchedule.rawValue,
                context: context
            )

            blockHash = try blockHashJson.map(to: Data?.self, with: context)
        }
    }

    struct PayoutState: Equatable {
        let creditDistribution: MobRulePallet.CreditDistribution?
        let roundSchedules: MobRulePallet.RoundSchedules?
        let blockHash: Data?

        func applying(_ changes: PayoutStateChange) -> PayoutState {
            PayoutState(
                creditDistribution: changes.creditDistribution.valueWhenDefined(else: creditDistribution),
                roundSchedules: changes.roundSchedules.valueWhenDefined(else: roundSchedules),
                blockHash: changes.blockHash
            )
        }

        var currentRound: MobRulePallet.RoundIndex? {
            creditDistribution?.round
        }
    }

    struct PointsStateChange: BatchStorageSubscriptionResult {
        enum Key: String {
            case claimable
            case pending
        }

        let claimable: UncertainStorage<MobRulePallet.Points?>
        let pending: UncertainStorage<MobRulePallet.Points?>
        let blockHash: Data?

        init(
            values: [BatchStorageSubscriptionResultValue],
            blockHashJson: JSON,
            context: [CodingUserInfoKey: Any]?
        ) throws {
            claimable = try UncertainStorage<StringScaleMapper<MobRulePallet.Points>?>(
                values: values,
                mappingKey: Key.claimable.rawValue,
                context: context
            )
            .map { $0?.value }

            pending = try UncertainStorage<StringScaleMapper<MobRulePallet.Points>?>(
                values: values,
                mappingKey: Key.pending.rawValue,
                context: context
            )
            .map { $0?.value }

            blockHash = try blockHashJson.map(to: Data?.self, with: context)
        }
    }

    struct PointsState: Equatable {
        let claimable: MobRulePallet.Points?
        let pending: MobRulePallet.Points?

        func applying(_ changes: PointsStateChange) -> PointsState {
            PointsState(
                claimable: changes.claimable.valueWhenDefined(else: claimable),
                pending: changes.pending.valueWhenDefined(else: pending)
            )
        }
    }

    struct State: Equatable {
        let payout: PayoutState
        let points: PointsState
        let blockHash: Data?

        func applying(_ changes: PointsStateChange) -> State {
            State(
                payout: payout,
                points: points.applying(changes),
                blockHash: changes.blockHash
            )
        }
    }
}
