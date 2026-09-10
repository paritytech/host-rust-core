import SwiftUI
import DesignSystem

public enum ChainConnectionState: Hashable {
    case connected
    case connecting
    case offline
}

public enum ChainStatusIcon: Hashable {
    case people
    case bulletin
    case assetHub
    case statementStore
}

public struct ChainConnectionStatusViewModel: Hashable, Identifiable {
    public let id: String
    public let title: String
    public let state: ChainConnectionState
    public let stateTitle: String
    public let latency: Duration?
    public let lastBlockDate: Date?
    public let finalityLag: Int?
    public let connectedSince: Date?
    public let thresholds: ChainHealthThresholds
    public let icon: ChainStatusIcon
    public let health: Double

    public init(
        id: String,
        title: String,
        state: ChainConnectionState,
        stateTitle: String,
        latency: Duration?,
        lastBlockDate: Date?,
        finalityLag: Int?,
        connectedSince: Date?,
        thresholds: ChainHealthThresholds,
        icon: ChainStatusIcon,
        health: Double = 0
    ) {
        self.id = id
        self.title = title
        self.state = state
        self.stateTitle = stateTitle
        self.latency = latency
        self.lastBlockDate = lastBlockDate
        self.finalityLag = finalityLag
        self.connectedSince = connectedSince
        self.thresholds = thresholds
        self.icon = icon
        self.health = health
    }

    public func withHealth(_ health: Double) -> ChainConnectionStatusViewModel {
        ChainConnectionStatusViewModel(
            id: id,
            title: title,
            state: state,
            stateTitle: stateTitle,
            latency: latency,
            lastBlockDate: lastBlockDate,
            finalityLag: finalityLag,
            connectedSince: connectedSince,
            thresholds: thresholds,
            icon: icon,
            health: health
        )
    }
}
