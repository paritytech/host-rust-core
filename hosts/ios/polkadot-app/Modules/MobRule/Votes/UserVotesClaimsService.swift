import Foundation
import SubstrateSdk
import Operation_iOS
import Individuality

protocol UserVotesClaimsServicing: AnyObject {
    func syncClaims(for userCases: [MobRulePallet.CaseIndex])
    func stopCurrentSync()
}

final class UserVotesClaimsService: UserVotesClaimsServicing {
    private let caseCleanService: CleanCaseServicing
    private let connection: JSONRPCEngine
    private let runtimeService: RuntimeCodingServiceProtocol
    private let workQueue: DispatchQueue
    private let logger: LoggerProtocol
    private let maxClaimableVotes: ClaimableVotesLimit
    private var caseSyncService: DoneCasesSyncService?

    init(
        caseCleanService: CleanCaseServicing,
        connection: JSONRPCEngine,
        runtimeService: RuntimeCodingServiceProtocol,
        workQueue: DispatchQueue,
        maxClaimableVotes: ClaimableVotesLimit,
        logger: LoggerProtocol = Logger.shared
    ) {
        self.caseCleanService = caseCleanService
        self.connection = connection
        self.runtimeService = runtimeService
        self.workQueue = workQueue
        self.maxClaimableVotes = maxClaimableVotes
        self.logger = logger
    }

    func syncClaims(for userCases: [MobRulePallet.CaseIndex]) {
        caseSyncService?.stopSyncUp()
        logger.info("Started claim for user cases \(userCases)")
        caseSyncService = DoneCasesSyncService(
            connection: connection,
            runtimeService: runtimeService,
            observers: [self],
            caseIndexes: userCases,
            workQueue: workQueue
        )
        caseSyncService?.setup()
    }

    func stopCurrentSync() {
        logger.info("Stopped claims for user cases")
        caseSyncService?.stopSyncUp()
        caseSyncService = nil
    }
}

extension UserVotesClaimsService: DoneCasesSyncObserver {
    func casesDidUpdate(with result: MobRulePallet.DoneCasesResult, blockHash: Data?) {
        caseCleanService.cleanCases(
            result,
            maxClaimableVotes: maxClaimableVotes,
            blockHash: blockHash
        ) { [weak self] result in
            switch result {
            case .success:
                self?.logger.info("Clean cases extrinsic submitted for: \(result)")
            case let .failure(error):
                self?.logger.error("Clean cases extrinsic failed: \(error) \(error.localizedDescription)")
            }
        }
    }

    func casesSubscriptionFailed(with error: Error) {
        logger.error("User cases subscription failed: \(error) \(error.localizedDescription)")
    }
}
