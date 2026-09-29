import Foundation
import WebRTC

extension RTCIceConnectionState: @retroactive CustomStringConvertible {
    public var description: String {
        switch self {
        case .new: return "new"
        case .checking: return "checking"
        case .connected: return "connected"
        case .completed: return "completed"
        case .failed: return "failed"
        case .disconnected: return "disconnected"
        case .closed: return "closed"
        case .count: return "count"
        @unknown default: return "Unknown \(rawValue)"
        }
    }
}

extension RTCPeerConnectionState: @retroactive CustomStringConvertible {
    public var description: String {
        switch self {
        case .new: return "new"
        case .connecting: return "connecting"
        case .connected: return "connected"
        case .disconnected: return "disconnected"
        case .failed: return "failed"
        case .closed: return "closed"
        @unknown default: return "Unknown \(rawValue)"
        }
    }
}

extension RTCSignalingState: @retroactive CustomStringConvertible {
    public var description: String {
        switch self {
        case .stable: return "stable"
        case .haveLocalOffer: return "haveLocalOffer"
        case .haveLocalPrAnswer: return "haveLocalPrAnswer"
        case .haveRemoteOffer: return "haveRemoteOffer"
        case .haveRemotePrAnswer: return "haveRemotePrAnswer"
        case .closed: return "closed"
        @unknown default: return "Unknown \(rawValue)"
        }
    }
}

extension RTCIceGatheringState: @retroactive CustomStringConvertible {
    public var description: String {
        switch self {
        case .new: return "new"
        case .gathering: return "gathering"
        case .complete: return "complete"
        @unknown default: return "Unknown \(rawValue)"
        }
    }
}

extension RTCDataChannelState: @retroactive CustomStringConvertible {
    public var description: String {
        switch self {
        case .connecting: return "connecting"
        case .open: return "open"
        case .closing: return "closing"
        case .closed: return "closed"
        @unknown default: return "Unknown \(rawValue)"
        }
    }
}
