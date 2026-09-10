import Foundation
import FoundationExt

@MainActor
final class WebViewAttestationSink: AttestationSink {
    private weak var webView: GameResultsWebViewController?
    private var hexHashes: [String] = []
    private var nextIndex = 0
    private var isClosed = false
    private var hasFlushedInitial = false
    private var isReady = false

    func attach(webView: GameResultsWebViewController, initialHashes: [String]) {
        Logger.shared.debug("[GameDebug] sink.attach initialHashes=\(initialHashes.count)")
        self.webView = webView
        hexHashes = initialHashes
    }

    func deliverInitialAttestations() {
        guard !hasFlushedInitial else { return }
        hasFlushedInitial = true
        isReady = true
        let snapshot = hexHashes
        for (index, hash) in snapshot.enumerated() {
            Logger.shared.debug("[GameDebug] sink initial pushAttestation index=\(index) hash=\(hash)")
            webView?.pushAttestation(index: index, hash: hash)
        }
        nextIndex = snapshot.count
    }

    func push(hash: Data) {
        guard !isClosed else { return }
        let hex = hash.toHex()
        guard !hexHashes.contains(hex) else {
            Logger.shared.debug("[GameDebug] sink skip duplicate hash=\(hex)")
            return
        }
        hexHashes.append(hex)
        guard isReady, let webView else {
            Logger.shared.debug("[GameDebug] sink queued (not ready) hash=\(hex)")
            return
        }
        let index = nextIndex
        nextIndex += 1
        Logger.shared.debug("[GameDebug] sink stream pushAttestation index=\(index) hash=\(hex)")
        webView.pushAttestation(index: index, hash: hex)
    }

    func close() {
        guard !isClosed else { return }
        isClosed = true
        webView = nil
    }
}
