import Foundation
import SubstrateSdk

struct GameVideoVoting {
    private let accountId: AccountId
    private(set) var statesByPlayer = [AccountId: GameVideoVotingState]()
    private(set) var interactedWithPlayers: Set<AccountId> = []
    private var host: AccountId?

    init(accountId: AccountId) {
        self.accountId = accountId
    }
}

extension GameVideoVoting: CustomStringConvertible {
    var description: String {
        let selfId = accountId.toHex().prefix(8)
        let hostId = host.map { $0.toHex().prefix(8).description } ?? "none"

        let votesDescription = statesByPlayer
            .map { playerId, state in
                let shortId = playerId.toHex().prefix(8)
                let interacted = interactedWithPlayers.contains(playerId) ? "(interacted)" : ""
                return "  \(shortId)... → \(state) [\(interacted)]"
            }
            .sorted()
            .joined(separator: "\n")

        return """
        GameVideoVoting(
          self:    \(selfId)...
          host:    \(hostId)...
          votes:
        \(votesDescription.isEmpty ? "  (empty)" : votesDescription)
        )
        """
    }
}

extension GameVideoVoting {
    mutating func prepareVoting(
        for host: AccountId,
        players: [AccountId]
    ) -> Bool {
        if self.host == host {
            return false
        }

        statesByPlayer.removeAll()
        interactedWithPlayers = []
        self.host = host

        players.forEach { player in
            if shouldCountVote(for: player) {
                statesByPlayer[player] = .notDecided
            }
        }

        return true
    }

    mutating func interactWithPlayer(_ player: AccountId) {
        interactedWithPlayers.insert(player)
    }

    mutating func vote(for player: AccountId, vote: GameVideoVotingState) -> Bool {
        guard canVote(for: player) else {
            return false
        }
        interactedWithPlayers.insert(player)

        statesByPlayer[player] = vote

        return true
    }

    func canVote(for player: AccountId) -> Bool {
        guard
            statesByPlayer[player] != nil,
            shouldCountVote(for: player)
        else {
            return false
        }
        return true
    }

    mutating func applyAutoRejection(isHostDisconnected: Bool) {
        // do not set negative vote if host disconnected
        guard !isHostDisconnected else {
            return
        }
        statesByPlayer.forEach { player, state in
            if state == .notDecided {
                statesByPlayer[player] = .negative
            }
        }
    }
}

private extension GameVideoVoting {
    func shouldCountVote(for player: AccountId) -> Bool {
        accountId != player && host != player
    }
}

enum GameVideoVotingState {
    case notDecided
    case positive
    case negative
}
