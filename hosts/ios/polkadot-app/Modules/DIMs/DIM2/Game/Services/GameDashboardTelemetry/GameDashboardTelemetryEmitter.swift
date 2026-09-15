import Foundation
import SubstrateSdk
import ChainRegistry
import SubstrateSdkExt

/// Fire-and-forget API used by the rest of the app.
/// Callers never await delivery; the emitter owns retry, queueing, and lifecycle.
protocol GameDashboardTelemetryServicing: Sendable {
    func sendRegistration(
        localAccount: AccountId,
        usernameAccountId: AccountId?,
        username: String?
    )

    func sendReporting(
        localAccount: AccountId,
        roundsPeers: [[(peer: AccountId, state: VideoGamePeerEngineState)]]
    )

    func sendEnd(
        localAccount: AccountId,
        roundsReports: [[(peer: AccountId, verdict: GameDashboardVerdict)]]
    )
}

/// Schedules dashboard telemetry POSTs through a stateless transport client.
///
/// Owns the queue, retry policy, and a long-lived `Task` so in-flight POSTs
/// (especially `/end`) survive teardown of the screens that submit them.
/// The transport layer ([GameDashboardTelemetryClient]) does one POST per call
/// and throws typed errors; this emitter applies the policy.
final class GameDashboardTelemetryEmitter: @unchecked Sendable, GameDashboardTelemetryServicing {
    private let client: any GameDashboardTelemetryClienting
    private let chainFormat: ChainFormat
    private let logger: LoggerProtocol
    private let dateProvider: () -> Date

    private let maxQueueSize = 50
    private let retryDelays: [TimeInterval] = [1, 2, 4]

    private let mutex = NSLock()
    private var queue: [Event] = []
    private var pumpTask: Task<Void, Never>?

    init(
        client: any GameDashboardTelemetryClienting,
        chainFormat: ChainFormat,
        logger: LoggerProtocol = Logger.shared,
        dateProvider: @escaping () -> Date = { Date() }
    ) {
        self.client = client
        self.chainFormat = chainFormat
        self.logger = logger
        self.dateProvider = dateProvider
    }

    func sendRegistration(
        localAccount: AccountId,
        usernameAccountId: AccountId?,
        username: String?
    ) {
        let payload = GameDashboardPayloads.Registration(
            who: slug(localAccount),
            usernameAccountId: usernameAccountId.map {
                GameDashboardSlug.address($0, chainFormat: chainFormat)
            },
            username: username,
            timestamp: currentTimestampMs()
        )
        enqueue(.registration(payload))
    }

    func sendReporting(
        localAccount: AccountId,
        roundsPeers: [[(peer: AccountId, state: VideoGamePeerEngineState)]]
    ) {
        let peers = roundsPeers.map { round in
            round.map { entry in
                GameDashboardPayloads.Reporting.Peer(
                    id: slug(entry.peer),
                    state: entry.state.dashboardState
                )
            }
        }
        let payload = GameDashboardPayloads.Reporting(
            who: slug(localAccount),
            peers: peers,
            timestamp: currentTimestampMs()
        )
        enqueue(.reporting(payload))
    }

    func sendEnd(
        localAccount: AccountId,
        roundsReports: [[(peer: AccountId, verdict: GameDashboardVerdict)]]
    ) {
        let reports = roundsReports.map { round in
            round.map { entry in
                GameDashboardPayloads.End.Report(
                    id: slug(entry.peer),
                    verdict: entry.verdict.rawValue
                )
            }
        }
        let payload = GameDashboardPayloads.End(
            who: slug(localAccount),
            reports: reports,
            timestamp: currentTimestampMs()
        )
        enqueue(.end(payload))
    }
}

// MARK: - Event model

private extension GameDashboardTelemetryEmitter {
    enum Event {
        case registration(GameDashboardPayloads.Registration)
        case reporting(GameDashboardPayloads.Reporting)
        case end(GameDashboardPayloads.End)

        var label: String {
            switch self {
            case .registration: "registration"
            case .reporting: "reporting"
            case .end: "end"
            }
        }
    }
}

// MARK: - Queue + scheduling

private extension GameDashboardTelemetryEmitter {
    func slug(_ accountId: AccountId) -> String {
        GameDashboardSlug.account(accountId, chainFormat: chainFormat)
    }

    func currentTimestampMs() -> Int64 {
        Int64(dateProvider().timeIntervalSince1970 * 1_000)
    }

    func enqueue(_ event: Event) {
        mutex.withLock {
            if queue.count >= maxQueueSize {
                let dropped = queue.removeFirst()
                logger.warning(
                    "Dashboard telemetry queue full, dropped oldest: \(dropped.label)"
                )
            }
            queue.append(event)

            if pumpTask == nil {
                pumpTask = Task { [weak self] in
                    await self?.pump()
                }
            }
        }
    }

    func pump() async {
        while let event = dequeueNext() {
            await deliver(event)
        }

        mutex.withLock {
            pumpTask = nil
        }
    }

    func dequeueNext() -> Event? {
        mutex.withLock {
            queue.isEmpty ? nil : queue.removeFirst()
        }
    }

    func deliver(_ event: Event) async {
        for delay in retryDelays {
            do {
                try await post(event)
                return
            } catch let error as GameDashboardTelemetryError {
                switch error {
                case .transient:
                    try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                case let .nonRetryable(status, _):
                    logger.warning(
                        "Dashboard telemetry rejected (\(status)) at \(event.label); dropping"
                    )
                    return
                case let .encodingFailed(underlying):
                    logger.error(
                        "Dashboard telemetry encode failed at \(event.label): \(underlying)"
                    )
                    return
                case .invalidURL:
                    logger.error("Dashboard telemetry: invalid URL for \(event.label)")
                    return
                }
            } catch {
                try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            }
        }
        // Final attempt after exhausting delays.
        do {
            try await post(event)
        } catch {
            logger.warning("Dashboard telemetry dropped after retries: \(event.label)")
        }
    }

    func post(_ event: Event) async throws {
        switch event {
        case let .registration(payload):
            try await client.postRegistration(payload)
        case let .reporting(payload):
            try await client.postReporting(payload)
        case let .end(payload):
            try await client.postEnd(payload)
        }
    }
}

private extension VideoGamePeerEngineState {
    var dashboardState: String {
        switch self {
        case .connected:
            "connected"
        case .connecting,
             .disconnected:
            "disconnected"
        }
    }
}
