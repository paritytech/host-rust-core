import Foundation
import Testing
import Clocks

@testable import polkadot_app

@Suite("Search runner stream forwarding", .timeLimit(.minutes(1)))
struct SearchRunnerTests {
    @Test("operation is not subscribed before the debounce elapses")
    func debounceGatesSubscription() async {
        let clock = TestClock<Duration>()
        let context = TestContext(clock: clock, hasContent: { _ in true })
        defer { context.tearDown() }

        // Proves the search task reached the debounce sleep, so the assertion below
        // cannot pass merely because the task had not started yet.
        #expect(await context.recorder.markers(atLeast: 1) == [.started])

        await clock.advance(by: .milliseconds(299))

        #expect(!context.subscription.isSubscribed)

        await clock.advance(by: .milliseconds(1))

        #expect(context.subscription.isSubscribed)
    }

    @Test("waiting is emitted at the debounce and waiting delay, not before")
    func waitingEmittedAfterCombinedDelay() async {
        let clock = TestClock<Duration>()
        let context = TestContext(clock: clock, hasContent: { _ in true })
        defer { context.tearDown() }

        await clock.advance(by: .milliseconds(799))

        #expect(await context.recorder.markers == [.started])

        await clock.advance(by: .milliseconds(1))

        #expect(await context.recorder.markers(atLeast: 2) == [.started, .waiting])
    }

    @Test("stream elements are forwarded in order")
    func elementsForwardedInOrder() async {
        let clock = TestClock<Duration>()
        let context = TestContext(clock: clock, hasContent: { _ in true })
        defer { context.tearDown() }

        await clock.advance(by: .milliseconds(300))

        context.continuation.yield(1)
        context.continuation.yield(2)
        context.continuation.finish()

        #expect(await context.recorder.markers(atLeast: 3) == [.started, .result(1), .result(2)])
    }

    @Test("loader still appears after a contentless first phase")
    func loaderSurvivesContentlessFirstPhase() async {
        let clock = TestClock<Duration>()
        let context = TestContext(clock: clock, hasContent: { _ in false })
        defer { context.tearDown() }

        await clock.advance(by: .milliseconds(300))

        context.continuation.yield(1)

        #expect(await context.recorder.markers(atLeast: 2) == [.started, .result(1)])

        await clock.advance(by: .milliseconds(500))

        #expect(await context.recorder.markers(atLeast: 3) == [.started, .result(1), .waiting])
    }

    @Test("a contentless phase is held until the loader floor elapses")
    func contentlessPhaseHeldUntilFloorElapses() async {
        let clock = TestClock<Duration>()
        let context = TestContext(clock: clock, hasContent: { _ in false })
        defer { context.tearDown() }

        await clock.advance(by: .milliseconds(800))

        #expect(await context.recorder.markers(atLeast: 2) == [.started, .waiting])

        context.continuation.yield(1)
        context.continuation.finish()
        await context.contentProbe.checked(atLeast: 1)

        #expect(await context.recorder.markers == [.started, .waiting])

        await clock.advance(by: .milliseconds(499))

        #expect(await context.recorder.markers == [.started, .waiting])

        await clock.advance(by: .milliseconds(1))

        #expect(await context.recorder.markers(atLeast: 3) == [.started, .waiting, .result(1)])
    }

    @Test("a phase with content replaces the loader immediately")
    func contentPhaseReplacesLoaderImmediately() async {
        let clock = TestClock<Duration>()
        let context = TestContext(clock: clock, hasContent: { _ in true })
        defer { context.tearDown() }

        await clock.advance(by: .milliseconds(800))

        #expect(await context.recorder.markers(atLeast: 2) == [.started, .waiting])

        context.continuation.yield(1)

        #expect(await context.recorder.markers(atLeast: 3) == [.started, .waiting, .result(1)])
    }
}

// MARK: - Helpers

private enum Marker: Equatable {
    case started
    case waiting
    case result(Int)

    init(state: SearchRunner.State<Int>) {
        switch state {
        case .started:
            self = .started
        case .waiting:
            self = .waiting
        case let .result(value):
            self = .result(value)
        }
    }
}

private actor MarkerRecorder {
    private(set) var markers: [Marker] = []

    private var pendingCount: Int?
    private var pendingContinuation: CheckedContinuation<[Marker], Never>?

    func append(_ marker: Marker) {
        markers.append(marker)

        guard let pendingCount, markers.count >= pendingCount else { return }

        let continuation = pendingContinuation
        self.pendingCount = nil
        pendingContinuation = nil
        continuation?.resume(returning: markers)
    }

    /// Suspends until at least `count` markers have been recorded, then returns all of them.
    /// Prefer this over yield-based settling whenever a marker is expected to arrive.
    func markers(atLeast count: Int) async -> [Marker] {
        guard markers.count < count else { return markers }

        return await withCheckedContinuation { continuation in
            pendingCount = count
            pendingContinuation = continuation
        }
    }
}

/// Signals that the runner dequeued an element: `hasContent` runs before the loader floor wait,
/// so awaiting it parks the test exactly where the runner is blocked on the clock.
private actor ContentProbe {
    private var count = 0

    private var pendingCount: Int?
    private var pendingContinuation: CheckedContinuation<Void, Never>?

    func record() {
        count += 1

        guard let pendingCount, count >= pendingCount else { return }

        let continuation = pendingContinuation
        self.pendingCount = nil
        pendingContinuation = nil
        continuation?.resume()
    }

    func checked(atLeast count: Int) async {
        guard self.count < count else { return }

        await withCheckedContinuation { continuation in
            pendingCount = count
            pendingContinuation = continuation
        }
    }
}

private final class SubscriptionFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var value = false

    var isSubscribed: Bool { lock.withLock { value } }

    func markSubscribed() {
        lock.withLock { value = true }
    }
}

private struct TestContext {
    let continuation: AsyncStream<Int>.Continuation
    let subscription = SubscriptionFlag()
    let recorder = MarkerRecorder()
    let contentProbe = ContentProbe()

    private let consumingTask: Task<Void, Never>

    init(clock: TestClock<Duration>, hasContent: @escaping @Sendable (Int) -> Bool) {
        let (stream, continuation) = AsyncStream.makeStream(of: Int.self)
        self.continuation = continuation

        let runner = SearchRunner(clock: clock)
        let subscription = subscription
        let recorder = recorder
        let contentProbe = contentProbe

        consumingTask = Task {
            let states = runner.run {
                subscription.markSubscribed()
                return stream
            } hasContent: { element in
                Task { await contentProbe.record() }

                return hasContent(element)
            }

            for await state in states {
                await recorder.append(Marker(state: state))
            }
        }
    }

    func tearDown() {
        continuation.finish()
        consumingTask.cancel()
    }
}
