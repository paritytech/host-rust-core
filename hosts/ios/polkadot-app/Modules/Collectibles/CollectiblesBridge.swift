import Foundation
import WebKit

// JS → Swift bridge
final class CollectiblesBridge: NSObject {
    static let messageHandlerName = "collectibles"

    let events: AsyncStream<CollectiblesInboundEvent>

    private weak var webView: WKWebView?
    private let logger: LoggerProtocol
    private let continuation: AsyncStream<CollectiblesInboundEvent>.Continuation

    init(webView: WKWebView, logger: LoggerProtocol = Logger.shared) {
        self.webView = webView
        self.logger = logger

        let (stream, continuation) = AsyncStream.makeStream(of: CollectiblesInboundEvent.self)
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

extension CollectiblesBridge: WKScriptMessageHandler {
    func userContentController(_: WKUserContentController, didReceive message: WKScriptMessage) {
        guard message.name == Self.messageHandlerName else { return }

        do {
            if let event = try CollectiblesInboundEvent.decode(from: message.body) {
                continuation.yield(event)
            }
        } catch {
            logger.error("[Collectibles][bridge] decode failed: \(error). Body: \(message.body)")
        }
    }
}
