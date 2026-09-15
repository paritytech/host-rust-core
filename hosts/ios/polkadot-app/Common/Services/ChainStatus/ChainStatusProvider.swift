import Foundation
import AsyncExtensions
import PolkadotUI
import StructuredConcurrency

/// Rolling window of the most recent health scores for a single row. Median rather than
/// mean so one bad sample cannot move the ring.
struct ChainHealthWindow {
    static let capacity = 10

    private var samples: [Double] = []

    var median: Double? {
        guard !samples.isEmpty else {
            return nil
        }

        return samples.sorted()[samples.count / 2]
    }

    mutating func record(_ sample: Double) {
        samples.append(sample)

        if samples.count > Self.capacity {
            samples.removeFirst(samples.count - Self.capacity)
        }
    }

    mutating func clear() {
        samples.removeAll()
    }
}

protocol ChainStatusProviding: Actor {
    nonisolated func statusStream() -> AnyAsyncSequence<[ChainConnectionStatusViewModel]>
    func start()
}

/// Per-chain connection status.
/// One shared instance. The subject always holds a row set, so the first render carries a
/// complete set and a host subscribing later sees live state rather than a re-seed.
actor ChainStatusProvider {
    private static let connectDebounce: Duration = .milliseconds(300)

    private let networkStatusService: NetworkStatusProviding
    private let latencyProvider: ChainLatencyProviding
    private let blockProvider: ChainBlockProviding
    private let statementTracker: StatementDeliveryTracking
    private let logger: LoggerProtocol

    private nonisolated let rowsSubject: AsyncCurrentValueSubject<[ChainConnectionStatusViewModel]>

    private var statuses: [ChainConnectionTarget: NetworkStatus]
    private var latencies: [ChainConnectionTarget: Duration] = [:]
    private var blocks: [ChainConnectionTarget: ChainBlockInfo] = [:]
    private var connectedSince: [ChainConnectionTarget: Date] = [:]
    private var statementState: StatementDeliveryState = .noSubscriptions
    private var statusTasks: [Task<Void, Never>] = []
    private var healthWindows: [String: ChainHealthWindow] = [:]
    private var tickTask: Task<Void, Never>?
    private var isObserving = false
    private var lastEmittedRows: [ChainConnectionStatusViewModel] = []

    init(
        networkStatusService: NetworkStatusProviding,
        latencyProvider: ChainLatencyProviding,
        blockProvider: ChainBlockProviding,
        statementTracker: StatementDeliveryTracking,
        logger: LoggerProtocol
    ) {
        self.networkStatusService = networkStatusService
        self.latencyProvider = latencyProvider
        self.blockProvider = blockProvider
        self.statementTracker = statementTracker
        self.logger = logger

        let seededStatuses = ChainConnectionTarget.allCases
            .reduce(into: [ChainConnectionTarget: NetworkStatus]()) { $0[$1] = .connecting }

        statuses = seededStatuses
        rowsSubject = AsyncCurrentValueSubject(
            Self.makeRows(
                statuses: seededStatuses,
                latencies: [:],
                blocks: [:],
                connectedSince: [:],
                statementState: .noSubscriptions
            )
        )
    }

    deinit {
        statusTasks.forEach { $0.cancel() }
        tickTask?.cancel()
    }
}

extension ChainStatusProvider: ChainStatusProviding {
    nonisolated func statusStream() -> AnyAsyncSequence<[ChainConnectionStatusViewModel]> {
        rowsSubject.eraseToAnyAsyncSequence()
    }

    func start() {
        guard !isObserving else {
            return
        }

        isObserving = true

        // Sampling runs for the app's lifetime because the top status strip is permanent.
        // A host closing its subscription does not pause sampling.
        Task { [latencyProvider, blockProvider] in
            await latencyProvider.setActive(true)
            await blockProvider.setActive(true)
        }

        statusTasks = ChainConnectionTarget.allCases.map { target in
            observeStatus(for: target)
        } + [observeLatencies(), observeBlocks(), observeStatementState()]

        tickTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.emitRows()

                try? await Task.sleep(for: .seconds(1))
            }
        }
    }
}

private extension ChainStatusProvider {
    func observeStatus(for target: ChainConnectionTarget) -> Task<Void, Never> {
        Task { [weak self, networkStatusService, logger] in
            let statusStream = networkStatusService
                .statusStream(for: [target.chainId])
                .withDebounce(for: Self.connectDebounce) { $0 == .connected }

            do {
                for try await status in statusStream {
                    await self?.handleStatusUpdate(status, for: target)
                }
            } catch {
                logger.error("Chain status stream failed for \(target.chainId): \(error)")
            }
        }
    }

    func observeLatencies() -> Task<Void, Never> {
        Task { [weak self, latencyProvider, logger] in
            do {
                for try await latencies in latencyProvider.latencyStream() {
                    await self?.handleLatenciesUpdate(latencies)
                }
            } catch {
                logger.error("Chain latency stream failed: \(error)")
            }
        }
    }

    func observeBlocks() -> Task<Void, Never> {
        Task { [weak self, blockProvider, logger] in
            do {
                for try await blocks in blockProvider.blockStream() {
                    await self?.handleBlocksUpdate(blocks)
                }
            } catch {
                logger.error("Chain block stream failed: \(error)")
            }
        }
    }

    func observeStatementState() -> Task<Void, Never> {
        Task { [weak self, statementTracker, logger] in
            do {
                for try await state in statementTracker.stateStream() {
                    await self?.handleStatementStateUpdate(state)
                }
            } catch {
                logger.error("Statement delivery state stream failed: \(error)")
            }
        }
    }

    func handleStatusUpdate(_ status: NetworkStatus, for target: ChainConnectionTarget) async {
        let previousStatus = statuses[target]

        guard previousStatus != status else {
            return
        }

        statuses[target] = status

        if status == .connected {
            connectedSince[target] = Date()
        } else {
            connectedSince[target] = nil
            latencies[target] = nil
            blocks[target] = nil
            await latencyProvider.clearSamples(for: target)
            // Without this a drop-and-reconnect keeps captioning the row with its pre-drop data.
            await blockProvider.clear(for: target)
            healthWindows[target.chainId]?.clear()
        }

        emitRows()
    }

    func handleLatenciesUpdate(_ updatedLatencies: [ChainConnectionTarget: Duration]) async {
        guard updatedLatencies != latencies else {
            return
        }

        latencies = updatedLatencies
        emitRows()
    }

    func handleBlocksUpdate(_ updatedBlocks: [ChainConnectionTarget: ChainBlockInfo]) async {
        guard updatedBlocks != blocks else {
            return
        }

        blocks = updatedBlocks
        emitRows()
    }

    func handleStatementStateUpdate(_ state: StatementDeliveryState) async {
        guard state != statementState else {
            return
        }

        statementState = state
        emitRows()
    }

    func emitRows() {
        let rawRows = Self.makeRows(
            statuses: statuses,
            latencies: latencies,
            blocks: blocks,
            connectedSince: connectedSince,
            statementState: statementState
        )
        let now = Date()

        let scoredRows = scoreRows(rawRows, at: now)

        guard scoredRows != lastEmittedRows else { return }

        lastEmittedRows = scoredRows
        rowsSubject.send(scoredRows)
    }

    private func scoreRows(_ rows: [ChainConnectionStatusViewModel], at date: Date)
        -> [ChainConnectionStatusViewModel] {
        rows.map { row in
            let rawScore = ChainHealth.score(for: row, at: date)
            healthWindows[row.id, default: ChainHealthWindow()].record(rawScore)
            let smoothed = healthWindows[row.id]?.median ?? rawScore

            // Quantised so float noise does not push a new row set every tick.
            return row.withHealth((smoothed * 100).rounded() / 100)
        }
    }

    static func makeRows(
        statuses: [ChainConnectionTarget: NetworkStatus],
        latencies: [ChainConnectionTarget: Duration],
        blocks: [ChainConnectionTarget: ChainBlockInfo],
        connectedSince: [ChainConnectionTarget: Date],
        statementState: StatementDeliveryState
    ) -> [ChainConnectionStatusViewModel] {
        let targetRows = ChainConnectionTarget.allCases.map { target in
            let state = (statuses[target] ?? .connecting).connectionState
            let block = state == .connected ? blocks[target] : nil
            let finalityLag = computeFinalityLag(from: block)

            return ChainConnectionStatusViewModel(
                id: target.chainId,
                title: target.title,
                state: state,
                stateTitle: state.localizedTitle,
                latency: state == .connected ? latencies[target] : nil,
                lastBlockDate: block?.receivedAt,
                finalityLag: finalityLag,
                connectedSince: connectedSince[target],
                thresholds: target.healthThresholds,
                icon: target.statusIcon
            )
        }

        let statementStoreRow = makeStatementStoreRow(
            state: statementState.connectionState,
            blocks: blocks,
            latencies: latencies,
            connectedSince: connectedSince
        )

        return targetRows + [statementStoreRow]
    }

    private static func computeFinalityLag(from block: ChainBlockInfo?) -> Int? {
        block.flatMap { info in
            info.finalizedNumber.map { max(Int(info.number) - Int($0), 0) }
        }
    }

    private static func makeStatementStoreRow(
        state: ChainConnectionState,
        blocks: [ChainConnectionTarget: ChainBlockInfo],
        latencies: [ChainConnectionTarget: Duration],
        connectedSince: [ChainConnectionTarget: Date]
    ) -> ChainConnectionStatusViewModel {
        let block = state == .connected ? blocks[.chat] : nil
        let finalityLag = computeFinalityLag(from: block)

        return ChainConnectionStatusViewModel(
            id: "statement-store",
            title: "Statement Store",
            state: state,
            stateTitle: state.localizedTitle,
            latency: state == .connected ? latencies[.chat] : nil,
            lastBlockDate: block?.receivedAt,
            finalityLag: finalityLag,
            connectedSince: connectedSince[.chat],
            thresholds: ChainConnectionTarget.chat.healthThresholds,
            icon: .statementStore
        )
    }
}
