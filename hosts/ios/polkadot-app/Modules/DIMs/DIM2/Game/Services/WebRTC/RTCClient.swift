import Foundation
import Foundation_iOS
@preconcurrency import WebRTC
import SubstrateSdk
import os

protocol RTCRendererManaging: AnyObject {
    func connectLocalRenderer(_ renderer: RTCVideoRenderer)
    func disconnectLocalRenderer(_ renderer: RTCVideoRenderer)

    func hasRemoteVideoTrack(for peerId: AccountId) -> Bool
    func connectRenderer(_ renderer: RTCVideoRenderer, for peerId: AccountId)
    func disconnectRenderer(_ renderer: RTCVideoRenderer, for peerId: AccountId)
}

final class RTCClient {
    private let peerConnectionFactory: RTCPeerConnectionFactory

    private struct MutableState {
        var remoteVideoTracks: [AccountId: RTCVideoTrack] = [:]
        var localVideoTrack: RTCVideoTrack?

        /// Renderers currently attached to each peer's track. Used to re-pair sinks
        /// across `setRemoteVideoTrack` and to detach them on track removal.
        /// Keyed by `ObjectIdentifier` because `RTCVideoRenderer` is a class-bound protocol.
        var remoteSinks: [AccountId: [ObjectIdentifier: RTCVideoRenderer]] = [:]
    }

    private let state = OSAllocatedUnfairLock(initialState: MutableState())

    private let rendererQueue = DispatchQueue(label: "RTCClient.renderer", qos: .userInteractive)

    private let captureQueue = DispatchQueue(label: "RTCClient.capture", qos: .userInitiated)

    private var videoCapturerWrapper: RTCVideoCapturerWrapper?

    var localVideoTrack: RTCVideoTrack? {
        state.withLock { $0.localVideoTrack }
    }

    private let isAudioEnabled: Bool
    private let logger: LoggerProtocol
    private let rtcLogger: RTCCallbackLogger?

    init(
        peerConnectionFactory: RTCPeerConnectionFactory,
        isAudioEnabled: Bool,
        videoProfile: RTCVideoProfile,
        logger: LoggerProtocol = Logger.shared
    ) {
        self.peerConnectionFactory = peerConnectionFactory
        self.isAudioEnabled = isAudioEnabled
        self.logger = logger

        if EnviromentVariables.isDebugEnabled {
            rtcLogger = RTCCallbackLogger()
            startLogging()
        } else {
            rtcLogger = nil
        }

        createMediaSenders(videoProfile: videoProfile)
    }

    deinit {
        logger.debug("Deinit")
        stopLogging()
    }

    // MARK: - Local Capture Lifecycle

    /// Starts the camera capture so the local video track produces frames.
    /// Peer connections can attach the local video track before capture starts.
    /// Returns immediately; the actual camera startup runs on `captureQueue`.
    func startLocalCapture() {
        guard let videoCapturerWrapper else { return }

        captureQueue.async {
            videoCapturerWrapper.start()
        }
    }

    /// Returns immediately; the actual camera teardown runs on `captureQueue`.
    func stopLocalCapture() {
        guard let videoCapturerWrapper else { return }

        captureQueue.async {
            videoCapturerWrapper.stop()
        }
    }

    // MARK: - Remote Track Management

    /// Sets the remote video track for a given peer. Called when connection state updates.
    /// Any renderers already registered for this peer are automatically re-paired from the
    /// old track to the new one.
    func setRemoteVideoTrack(_ track: RTCVideoTrack?, for peerId: AccountId) {
        state.withLock { state in
            let oldTrack = state.remoteVideoTracks[peerId]
            if let track {
                state.remoteVideoTracks[peerId] = track
            } else {
                state.remoteVideoTracks.removeValue(forKey: peerId)
            }
            guard oldTrack !== track else { return }

            let sinks = Array((state.remoteSinks[peerId] ?? [:]).values)
            guard !sinks.isEmpty else { return }

            rendererQueue.async {
                for renderer in sinks {
                    oldTrack?.remove(renderer)
                    track?.add(renderer)
                }
            }
        }
    }

    /// Removes the remote video track for a given peer. Any renderers registered for this peer
    /// are detached from the old track but remain in the registry, so a subsequent
    /// `setRemoteVideoTrack` for the same peer will rebind them automatically.
    func removeRemoteVideoTrack(for peerId: AccountId) {
        state.withLock { state in
            guard let oldTrack = state.remoteVideoTracks.removeValue(forKey: peerId) else { return }
            let sinks = Array((state.remoteSinks[peerId] ?? [:]).values)
            guard !sinks.isEmpty else { return }

            rendererQueue.async {
                for renderer in sinks {
                    oldTrack.remove(renderer)
                }
            }
        }
    }

    /// Removes all remote video tracks and clears the sink registry, detaching every registered
    /// renderer from its track.
    func removeAllRemoteVideoTracks() {
        state.withLock { state in
            var detachments: [(RTCVideoTrack, RTCVideoRenderer)] = []
            for (peerId, track) in state.remoteVideoTracks {
                guard let sinks = state.remoteSinks[peerId] else { continue }
                for renderer in sinks.values {
                    detachments.append((track, renderer))
                }
            }
            state.remoteVideoTracks.removeAll()
            state.remoteSinks.removeAll()

            guard !detachments.isEmpty else { return }
            rendererQueue.async {
                for (track, renderer) in detachments {
                    track.remove(renderer)
                }
            }
        }
    }

    // MARK: - Private

    private func createMediaSenders(videoProfile: RTCVideoProfile) {
        let videoSource = peerConnectionFactory.videoSource()
        let videoCapturerWrapper = RTCVideoCapturerWrapper(
            videoSource: videoSource,
            videoProfile: videoProfile
        )
        self.videoCapturerWrapper = videoCapturerWrapper

        let track = peerConnectionFactory.videoTrack(with: videoSource, trackId: "video0")
        state.withLock { $0.localVideoTrack = track }
    }
}

// MARK: - RTCRendererManaging

extension RTCClient: RTCRendererManaging {
    func connectLocalRenderer(_ renderer: RTCVideoRenderer) {
        startLocalCapture()
        let track = state.withLock { $0.localVideoTrack }
        rendererQueue.async { track?.add(renderer) }
    }

    func disconnectLocalRenderer(_ renderer: RTCVideoRenderer) {
        let track = state.withLock { $0.localVideoTrack }
        rendererQueue.async { track?.remove(renderer) }
    }

    func hasRemoteVideoTrack(for peerId: AccountId) -> Bool {
        state.withLock { $0.remoteVideoTracks[peerId] != nil }
    }

    func connectRenderer(_ renderer: RTCVideoRenderer, for peerId: AccountId) {
        state.withLock { state in
            state.remoteSinks[peerId, default: [:]][ObjectIdentifier(renderer)] = renderer
            let track = state.remoteVideoTracks[peerId]
            rendererQueue.async { track?.add(renderer) }
        }
    }

    func disconnectRenderer(_ renderer: RTCVideoRenderer, for peerId: AccountId) {
        state.withLock { state in
            state.remoteSinks[peerId]?.removeValue(forKey: ObjectIdentifier(renderer))
            if state.remoteSinks[peerId]?.isEmpty == true {
                state.remoteSinks.removeValue(forKey: peerId)
            }
            let track = state.remoteVideoTracks[peerId]
            rendererQueue.async { track?.remove(renderer) }
        }
    }
}

// MARK: - Logs

private extension RTCClient {
    func startLogging() {
        guard let rtcLogger else {
            return
        }

        rtcLogger.severity = .none
        rtcLogger.start { [weak self] message, severity in
            guard let self else {
                return
            }
            let message = "[WEBRTC] \(message)"
            switch severity {
            case .verbose:
                logger.verbose(message)
            case .info:
                logger.info(message)
            case .warning:
                logger.warning(message)
            case .error:
                // Log WebRTC error with our warning
                // level to have cleaner error logs
                logger.warning("[RTC Error]\(message)")
            case .none:
                break
            @unknown default:
                logger.verbose(message)
            }
        }
    }

    func stopLogging() {
        rtcLogger?.stop()
    }
}
