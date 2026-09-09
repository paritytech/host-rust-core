import Foundation
import WebKit

// JS → Swift bridge
final class GameResultsBridge: NSObject {
    static let messageHandlerName = "gameResults"

    let events: AsyncStream<GameResultsInboundEvent>

    private weak var webView: WKWebView?
    private let logger: LoggerProtocol
    private let continuation: AsyncStream<GameResultsInboundEvent>.Continuation

    init(webView: WKWebView, logger: LoggerProtocol = Logger.shared) {
        self.webView = webView
        self.logger = logger

        let (stream, continuation) = AsyncStream.makeStream(of: GameResultsInboundEvent.self)
        events = stream
        self.continuation = continuation

        super.init()

        webView.configuration.userContentController.add(self, name: Self.messageHandlerName)
    }

    deinit {
        webView?.configuration.userContentController.removeScriptMessageHandler(forName: Self.messageHandlerName)
        continuation.finish()
    }
}

extension GameResultsBridge: WKScriptMessageHandler {
    func userContentController(_: WKUserContentController, didReceive message: WKScriptMessage) {
        guard message.name == Self.messageHandlerName else { return }

        do {
            if let event = try GameResultsInboundEvent.decode(from: message.body) {
                continuation.yield(event)
            }
        } catch {
            logger.error("[GameDebug][bridge] decode failed: \(error). Body: \(message.body)")
        }
    }
}
