import BigInt
import Foundation
import Operation_iOS
import SubstrateSdk

public struct ExternalPayment: Equatable {
    public enum Stage: Int {
        case plan = 0
        case onboardCoins = 1
        case offboardVouchers = 2
        case completed = 3
        case failed = 4
        case rescheduled = 5
        case partiallyCompleted = 6

        public var isTerminal: Bool {
            switch self {
            case .completed,
                 .failed,
                 .rescheduled,
                 .partiallyCompleted:
                true
            case .plan,
                 .onboardCoins,
                 .offboardVouchers:
                false
            }
        }
    }

    public let id: String
    public let origin: String
    public let amountInPlanks: Balance
    public let destination: AccountId
    public var stage: Stage
    public var failureReason: String?
    public var readyAt: Date
    public let createdAt: Date
    public var updatedAt: Date

    public init(
        id: String,
        origin: String,
        amountInPlanks: Balance,
        destination: AccountId,
        stage: Stage = .plan,
        failureReason: String? = nil,
        readyAt: Date = .init(),
        createdAt: Date = .init(),
        updatedAt: Date = .init()
    ) {
        self.id = id
        self.origin = origin
        self.amountInPlanks = amountInPlanks
        self.destination = destination
        self.stage = stage
        self.failureReason = failureReason
        self.readyAt = readyAt
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

extension ExternalPayment: Operation_iOS.Identifiable {
    public var identifier: String { id }
}
