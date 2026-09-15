import Foundation
import WebRTC

enum VideoGamePeerEngineState {
    case connecting
    case connected(Connected)
    case disconnected

    struct Connected {
        let multiplexedChannel: MultiplexedDataChannel
        let remoteVideoTrack: RTCVideoTrack?
    }
}

extension VideoGamePeerEngineState {
    /// Treats two states as equivalent for de-duplication: the payload-free
    /// cases match by case, and `.connected` matches when it carries the same
    /// channel and remote track, so only meaningful transitions are emitted.
    func isEquivalent(to other: VideoGamePeerEngineState) -> Bool {
        switch (self, other) {
        case (.connecting, .connecting),
             (.disconnected, .disconnected):
            true
        case let (.connected(lhs), .connected(rhs)):
            lhs.multiplexedChannel === rhs.multiplexedChannel
                && lhs.remoteVideoTrack === rhs.remoteVideoTrack
        default:
            false
        }
    }
}

extension VideoGamePeerEngineState: CustomStringConvertible {
    var description: String {
        switch self {
        case .connecting:
            "connecting"
        case let .connected(connected):
            "connected(videoTrack=\(connected.remoteVideoTrack != nil))"
        case .disconnected:
            "disconnected"
        }
    }
}
