import Testing
import Foundation
@testable import PolkadotUI

struct ChainHealthTests {
    private let thresholds = ChainHealthThresholds(
        blockAge: ChainHealthBounds(healthy: .seconds(12), zero: .seconds(60)),
        finalityLag: ChainHealthCountBounds(healthy: 6, zero: 24),
        ping: ChainHealthBounds(healthy: .milliseconds(200), zero: .milliseconds(2_000)),
        missingTermGrace: .seconds(20)
    )

    // MARK: - Score calculation

    @Test("Score is 0 when offline")
    func scoreOffline() {
        let row = makeRow(state: .offline)
        let score = ChainHealth.score(for: row, at: Date())

        #expect(score == 0)
    }

    @Test("Score is 0 when connecting")
    func scoreConnecting() {
        let row = makeRow(state: .connecting)
        let score = ChainHealth.score(for: row, at: Date())

        #expect(score == 0)
    }

    @Test("Score is 1 (full health) when all terms are healthy")
    func scoreFullHealth() {
        let now = Date()
        let row = makeConnectedRow(
            lastBlockDate: now.addingTimeInterval(-5),
            finalityLag: 3,
            connectedSince: now.addingTimeInterval(-30)
        )

        let score = ChainHealth.score(for: row, at: now)

        #expect(score == 1)
    }

    @Test("Score degrades as block age increases")
    func scoreBlockAgeLinear() {
        let now = Date()
        let connectedAt = now.addingTimeInterval(-30)

        let rowHalfAge = makeConnectedRow(
            lastBlockDate: now.addingTimeInterval(-36),
            finalityLag: 3,
            connectedSince: connectedAt
        )
        let scoreHalfAge = ChainHealth.score(for: rowHalfAge, at: now)

        let rowAlmostDead = makeConnectedRow(
            lastBlockDate: now.addingTimeInterval(-59),
            finalityLag: 3,
            connectedSince: connectedAt
        )
        let scoreAlmostDead = ChainHealth.score(for: rowAlmostDead, at: now)

        #expect(scoreHalfAge > 0.4)
        #expect(scoreHalfAge < 0.6)
        #expect(scoreAlmostDead < 0.1)
    }

    @Test("Score is 0 when any term is completely unhealthy")
    func scoreZeroWhenTermFails() {
        let now = Date()
        let row = makeConnectedRow(
            lastBlockDate: now.addingTimeInterval(-61),
            finalityLag: 3,
            connectedSince: now.addingTimeInterval(-30)
        )

        let score = ChainHealth.score(for: row, at: now)

        #expect(score == 0)
    }

    @Test("Score omits nil terms within grace period")
    func scoreGracePeriod() {
        let now = Date()
        let row = makeConnectedRow(connectedSince: now.addingTimeInterval(-10))

        let score = ChainHealth.score(for: row, at: now)

        #expect(score == 1, "Ping alone should be 1 during grace period")
    }

    @Test("Score counts nil as 0 after grace period expires")
    func scoreAfterGrace() {
        let now = Date()
        let row = makeConnectedRow(connectedSince: now.addingTimeInterval(-25))

        let score = ChainHealth.score(for: row, at: now)

        #expect(score == 0, "Nil terms should be 0 after grace expires")
    }

    @Test("Score handles nil connectedSince as grace expired")
    func scoreNilConnectedSince() {
        let row = makeConnectedRow(connectedSince: nil)

        let score = ChainHealth.score(for: row, at: Date())

        #expect(score == 0, "Nil connectedSince should treat grace as expired")
    }

    // MARK: - Arc color

    // Note: Color comparisons are omitted because DesignSystem colors use dynamic providers
    // that don't compare as equal in unit tests. The arc coloring is tested implicitly through
    // view rendering and is verified manually in integration tests.
}

// MARK: - Helpers

private extension ChainHealthTests {
    func makeConnectedRow(
        lastBlockDate: Date? = nil,
        finalityLag: Int? = nil,
        connectedSince: Date?
    ) -> ChainConnectionStatusViewModel {
        makeRow(
            state: .connected,
            latency: .milliseconds(100),
            lastBlockDate: lastBlockDate,
            finalityLag: finalityLag,
            connectedSince: connectedSince
        )
    }

    func makeRow(
        state: ChainConnectionState,
        latency: Duration? = nil,
        lastBlockDate: Date? = nil,
        finalityLag: Int? = nil,
        connectedSince: Date? = nil
    ) -> ChainConnectionStatusViewModel {
        let stateTitle =
            switch state {
            case .connected:
                "Connected"
            case .connecting:
                "Connecting"
            case .offline:
                "Offline"
            }

        return ChainConnectionStatusViewModel(
            id: "test",
            title: "Test",
            state: state,
            stateTitle: stateTitle,
            latency: latency,
            lastBlockDate: lastBlockDate,
            finalityLag: finalityLag,
            connectedSince: connectedSince,
            thresholds: thresholds,
            icon: .people
        )
    }
}
