import Foundation
import CommonService

protocol GameTimelineServicing: BaseObservableStateStore<TimeInterval>, ApplicationServiceProtocol {}

final class GameTimelineService: BaseObservableStateStore<TimeInterval>, @unchecked Sendable {
    private let updateInterval: DispatchTimeInterval
    private let workQueue: DispatchQueue
    private let infoSyncService: GameInfoSyncServicing
    private let synchronizedTimeService: SynchronizedTimeServicing

    private var timer: DispatchSourceTimer?
    private var gameDate: Date?
    private var isStarted = false
    private var gameTask: Task<Void, Never>?

    init(
        updateInterval: DispatchTimeInterval = .seconds(1),
        workQueue: DispatchQueue = DispatchQueue(label: "GameTimelineService.workQueue"),
        infoSyncService: GameInfoSyncServicing,
        synchronizedTimeService: SynchronizedTimeServicing,
        logger: LoggerProtocol = Logger.shared
    ) {
        self.updateInterval = updateInterval
        self.workQueue = workQueue
        self.infoSyncService = infoSyncService
        self.synchronizedTimeService = synchronizedTimeService
        super.init(logger: logger)
    }

    deinit {
        gameTask?.cancel()
    }
}

extension GameTimelineService: GameTimelineServicing {
    func setup() {
        workQueue.async { [weak self] in
            guard let self else { return }
            subscribeToGameDate()
        }
    }

    func throttle() {
        workQueue.async { [weak self] in
            guard let self else { return }
            gameTask?.cancel()
            stopTimer()
            gameDate = nil
            isStarted = false
        }
    }
}

private extension GameTimelineService {
    enum Constants {
        static let fireInterval = TimeInterval(1)
    }

    func subscribeToGameDate() {
        gameTask?.cancel()

        gameTask = Task { [weak self, infoSyncService, logger] in
            do {
                for try await info in infoSyncService.observe() {
                    logger.debug("Got new game info")

                    self?.workQueue.async {
                        self?.onNewGameInfo(info)
                    }
                }

                logger.debug("Game task completed")
            } catch {
                logger.error("Game info task failed: \(error)")
            }
        }
    }

    func onNewGameInfo(_ info: GameInfo?) {
        gameDate = info?.gameDate

        if !isStarted, gameDate != nil {
            logger.debug("Starting to update timeline")
            isStarted = true
            startTimer()
        }
    }

    func performUpdateTimeline() {
        mutex.lock()
        stateObservable.state = makeTimeIntervalSinceStart()
        mutex.unlock()
    }

    func makeTimeIntervalSinceStart() -> TimeInterval? {
        guard let gameDate else {
            return nil
        }
        return Date().timeIntervalSince(gameDate)
    }

    func startTimer() {
        stopTimer()

        timer = DispatchSource.makeTimerSource(
            queue: workQueue
        )
        timer?.schedule(
            deadline: .now(),
            repeating: updateInterval
        )
        timer?.setEventHandler { [weak self] in
            self?.performUpdateTimeline()
        }
        timer?.resume()
    }

    func stopTimer() {
        guard timer != nil else {
            return
        }
        timer?.cancel()
        timer = nil
    }
}
