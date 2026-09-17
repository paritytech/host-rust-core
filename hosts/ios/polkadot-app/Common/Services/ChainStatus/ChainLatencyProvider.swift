import Foundation
import AsyncExtensions
import ChainRegistry
import StructuredConcurrency
import SubstrateSdk

protocol ChainLatencyProviding: Actor {
    nonisolated func latencyStream() -> AnyAsyncSequence<[ChainConnectionTarget: Duration]>
    func clearSamples(for target: ChainConnectionTarget)
    func setActive(_ isActive: Bool)
}

/// Rolling window of the most recent probe round-trips for a single chain.
private struct ChainLatencyWindow {
    private static let capacity = 3

    private var samples: [Duration] = []

    var median: Duration? {
        guard !samples.isEmpty else {
            return nil
        }

        return samples.sorted()[samples.count / 2]
    }

    mutating func record(_ sample: Duration) {
        samples.append(sample)

        if samples.count > Self.capacity {
            samples.removeFirst(samples.count - Self.capacity)
        }
    }

    mutating func clear() {
        samples.removeAll()
    }
}

/// Per-chain round-trip latency, sampled on a fixed interval while a host asks for it.
///
/// Sibling to `ChainStatusProvider` rather than part of it: this owns probe timing only, so
/// row composition stays in one place.
actor ChainLatencyProvider {
    private static let probeInterval: Duration = .seconds(30)
    private static let probeTimeout: Duration = .seconds(10)

    private let chainRegistry: ChainRegistryProtocol
    private let logger: LoggerProtocol

    private let latenciesSubject = AsyncCurrentValueSubject<[ChainConnectionTarget: Duration]>([:])

    private var windows: [ChainConnectionTarget: ChainLatencyWindow] = [:]
    private var probeTask: Task<Void, Never>?
    private var isActive = false

    init(chainRegistry: ChainRegistryProtocol, logger: LoggerProtocol) {
        self.chainRegistry = chainRegistry
        self.logger = logger
    }

    deinit {
        probeTask?.cancel()
    }
}

extension ChainLatencyProvider: ChainLatencyProviding {
    nonisolated func latencyStream() -> AnyAsyncSequence<[ChainConnectionTarget: Duration]> {
        latenciesSubject.eraseToAnyAsyncSequence()
    }

    func clearSamples(for target: ChainConnectionTarget) {
        windows[target]?.clear()

        emitLatencies()
    }

    func setActive(_ isActive: Bool) {
        guard isActive != self.isActive else {
            return
        }

        self.isActive = isActive
        logger.debug("Latency sampling \(isActive ? "started" : "stopped")")

        guard isActive else {
            // Samples are kept so reopening shows the last known latency instead of blanking;
            // stale samples are dropped by status transitions, not by deactivation.
            probeTask?.cancel()
            probeTask = nil
            return
        }

        probeTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.probeAll()

                try? await Task.sleep(for: Self.probeInterval)
            }
        }
    }
}

private extension ChainLatencyProvider {
    func probeAll() async {
        let samples = await withTaskGroup(of: (ChainConnectionTarget, Duration?).self) { group in
            for target in ChainConnectionTarget.allCases {
                group.addTask { [weak self] in
                    guard let self else {
                        return (target, nil)
                    }

                    return await (target, probe(target))
                }
            }

            return await group.reduce(into: [ChainConnectionTarget: Duration]()) { accumulator, element in
                accumulator[element.0] = element.1
            }
        }

        record(samples)
    }

    func probe(_ target: ChainConnectionTarget) async -> Duration? {
        guard let connection = chainRegistry.getConnection(for: target.chainId) else {
            logger.debug("No connection to probe latency for \(target.chainId)")

            return nil
        }

        let start = ContinuousClock.now

        do {
            try await withTimeout(Self.probeTimeout) {
                // Resending on reconnect would resolve a probe issued while the socket was down
                // and count the whole outage as latency; failing fast discards the sample instead.
                let _: SubstrateHealthResult = try await connection.asyncCallMethod(
                    RPCMethod.healthCheck,
                    params: nil as [String]?,
                    options: JSONRPCOptions(resendOnReconnect: false)
                )
            }
        } catch {
            logger.debug("Latency probe failed for \(target.chainId): \(error)")

            return nil
        }

        let sample = ContinuousClock.now - start

        logger.debug("Latency probe for \(target.chainId): \(sample)")

        return sample
    }

    func record(_ samples: [ChainConnectionTarget: Duration]) {
        guard !samples.isEmpty else {
            return
        }

        for (target, sample) in samples {
            windows[target, default: ChainLatencyWindow()].record(sample)
        }

        emitLatencies()
    }

    func emitLatencies() {
        latenciesSubject.send(windows.compactMapValues(\.median))
    }
}
