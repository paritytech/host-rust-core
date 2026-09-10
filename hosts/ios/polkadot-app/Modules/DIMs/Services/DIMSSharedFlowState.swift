import Foundation
import CommonService
import os

protocol DIMSSharedFlowStateProtocol {
    var syncStateStore: DetermineStateSyncStore { get }
    var personDataStore: DetermineStatePersonDataStore { get }
    var scoreInfoSyncService: ScoreInfoSyncServicing { get }
    var personhoodRegistrationService: PersonhoodRegistrationServicing { get }

    func setup()
    func throttle()
}

class DIMSSharedFlowState {
    let personhoodRegistrationService: PersonhoodRegistrationServicing
    let personRegistrationSyncService: PersonhoodRegistrationSyncService
    let syncService: DetermineStateSyncService
    let syncStateStore: DetermineStateSyncStore
    let personDataStore: DetermineStatePersonDataStore
    let gameInfoSyncService: GameInfoSyncServicing
    let scoreInfoSyncService: ScoreInfoSyncServicing
    let logger: LoggerProtocol

    private let lock = OSAllocatedUnfairLock<Bool>(initialState: false)

    init(
        syncService: DetermineStateSyncService,
        syncStateStore: DetermineStateSyncStore,
        personDataStore: DetermineStatePersonDataStore,
        personhoodRegistrationService: PersonhoodRegistrationServicing,
        personRegistrationSyncService: PersonhoodRegistrationSyncService,
        gameInfoSyncService: GameInfoSyncServicing,
        scoreInfoSyncService: ScoreInfoSyncServicing,
        logger: LoggerProtocol = Logger.shared
    ) {
        self.syncService = syncService
        self.syncStateStore = syncStateStore
        self.personDataStore = personDataStore
        self.personhoodRegistrationService = personhoodRegistrationService
        self.personRegistrationSyncService = personRegistrationSyncService
        self.gameInfoSyncService = gameInfoSyncService
        self.scoreInfoSyncService = scoreInfoSyncService
        self.logger = logger
    }
}

extension DIMSSharedFlowState: DIMSSharedFlowStateProtocol {
    func setup() {
        lock.withLock { isActive in
            guard !isActive else {
                return
            }

            isActive = true

            syncService.setup()
            gameInfoSyncService.setup()
            scoreInfoSyncService.setup()
            personRegistrationSyncService.setup()
            personhoodRegistrationService.setup()
            personhoodRegistrationService.triggerRegistration()

            personDataStore.add(
                observer: self,
                queue: nil
            ) { [weak self] _, newPersonData in
                guard let accountOrPerson = newPersonData?.makeAccountOrPerson() else {
                    return
                }

                self?.gameInfoSyncService.setAccountOrPerson(accountOrPerson)
                self?.scoreInfoSyncService.setAccountOrPerson(accountOrPerson)
            }
        }
    }

    func throttle() {
        lock.withLock { isActive in
            guard isActive else {
                return
            }

            isActive = false

            personDataStore.remove(observer: self)

            syncService.throttle()
            gameInfoSyncService.throttle()
            scoreInfoSyncService.throttle()
            personRegistrationSyncService.throttle()
            personhoodRegistrationService.throttle()
        }
    }
}
