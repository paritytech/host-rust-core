import UIKit
import UIKitExt
import FoundationExt
import WebKit
import Products

final class GameResultsWebViewController: UIViewController, ViewHolder, GameResultsViewProtocol {
    typealias RootViewType = GameResultsWebViewLayout

    let bridge: GameResultsBridge

    var onClose: () -> Void
    var onPageReady: (() -> Void)?

    private let loadRequestURL: URL
    private let webView: WKWebView
    private let input: GameResultsInput?
    private let schemeHandler: ProductScriptSchemeHandler?
    private let logger: LoggerProtocol = Logger.shared

    init(
        url: URL,
        input: GameResultsInput?,
        onClose: @escaping () -> Void = {}
    ) {
        self.input = input
        self.onClose = onClose

        let configuration = WKWebViewConfiguration()
        configuration.allowsInlineMediaPlayback = true

        if let input {
            Self.installInputScript(input: input, into: configuration.userContentController)
        }
        Self.installConsoleHook(into: configuration.userContentController)

        if url.isFileURL, let handler = Self.makeLocalSchemeHandler(for: url) {
            configuration.setURLSchemeHandler(handler, forURLScheme: ProductScriptSchemeHandler.scheme)
            schemeHandler = handler
            loadRequestURL = handler.getProductUrl() ?? url
        } else {
            schemeHandler = nil
            loadRequestURL = url
        }

        let webView = WKWebView(frame: .zero, configuration: configuration)
        self.webView = webView
        bridge = GameResultsBridge(webView: webView)

        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func loadView() {
        view = GameResultsWebViewLayout(webView: webView)
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        setupNavigationBar()
        webView.navigationDelegate = self

        webView.load(URLRequest(url: loadRequestURL))
    }
}

private extension GameResultsWebViewController {
    static let localProductId: ProductId = "game-results"

    static func makeLocalSchemeHandler(for fileURL: URL) -> ProductScriptSchemeHandler? {
        let contentURL = fileURL.deletingLastPathComponent()
        return ProductScriptSchemeHandler(
            productId: localProductId,
            entryRelativePath: fileURL.lastPathComponent,
            productFileProvider: DotNsFileProvider(contentURL: contentURL)
        )
    }
}

private extension GameResultsWebViewController {
    func setupNavigationBar() {
        navigationItem.largeTitleDisplayMode = .never
        navigationItem.hidesBackButton = true

        let closeButton = UIBarButtonItem(
            image: UIImage(systemName: "xmark"),
            style: .plain,
            target: self,
            action: #selector(actionBack)
        )
        closeButton.tintColor = .textAndIconsPrimaryDark
        navigationItem.leftBarButtonItem = closeButton
    }

    @objc func actionBack() {
        onClose()
    }
}

extension GameResultsWebViewController {
    func deliverInput(_ input: GameResultsInput) {
        guard let json = Self.encodeJSON(input) else {
            logger.error("[GameDebug] deliverInput: encoding FAILED")
            return
        }
        logger.debug("[GameDebug] app→webview setGameResults len=\(json.count)\n\(json)")
        let script = "window.setGameResults && window.setGameResults(\(json));"
        webView.evaluateJavaScript(script) { [weak self] result, error in
            if let error {
                self?.logger.error("[GameDebug] setGameResults JS eval error=\(error)")
            } else {
                self?.logger.debug("[GameDebug] setGameResults JS eval ok result=\(String(describing: result))")
            }
        }
    }

    func deliverOutcome(_ outcome: GameOutcome) {
        guard let json = Self.encodeJSON(outcome) else {
            logger.error("[GameDebug] deliverOutcome: encoding FAILED")
            return
        }
        logger.debug("[GameDebug] app→webview setGameOutcome \(json)")
        let script = "window.setGameOutcome && window.setGameOutcome(\(json));"
        webView.evaluateJavaScript(script) { [weak self] result, error in
            if let error {
                self?.logger.error("[GameDebug] setGameOutcome JS eval error=\(error)")
            } else {
                self?.logger.debug("[GameDebug] setGameOutcome JS eval ok result=\(String(describing: result))")
            }
        }
    }

    func deliverDisplayName(_ name: String) {
        logger.debug("[GameDebug] app→webview setDisplayName name='\(name)'")
        let escaped = name
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        let script = "window.setDisplayName && window.setDisplayName(\"\(escaped)\");"
        webView.evaluateJavaScript(script) { [weak self] _, error in
            if let error {
                self?.logger.error("[GameDebug] setDisplayName JS eval error=\(error)")
            }
        }
    }

    func deliverUsernameAvailability(
        _ availability: GameResultsInput.UsernameClaim.Availability,
        alternatives: [String]? = nil
    ) {
        let payload = UsernameAvailabilityPayload(
            availability: availability,
            alternatives: alternatives
        )
        guard let json = Self.encodeJSON(payload) else {
            logger.error("[GameDebug] deliverUsernameAvailability: encoding FAILED")
            return
        }
        logger
            .debug("[GameDebug] app→webview setUsernameAvailability availability=\(availability) payload=\(json)")
        let script = "window.setUsernameAvailability && window.setUsernameAvailability(\(json));"
        webView.evaluateJavaScript(script) { [weak self] _, error in
            if let error {
                self?.logger.error("[GameDebug] setUsernameAvailability JS eval error=\(error)")
            }
        }
    }

    func pushAttestation(index: Int, hash: String, highValue: Bool? = nil) {
        let payload = AttestationPushPayload(
            index: index,
            hash: hash,
            highValue: highValue
        )
        guard let json = Self.encodeJSON(payload) else {
            logger.error("[GameDebug] pushAttestation: encoding FAILED index=\(index) hash=\(hash)")
            return
        }
        logger.debug("[GameDebug] app→webview pushAttestation index=\(index) hash=\(hash) payload=\(json)")
        let script = "window.pushAttestation && window.pushAttestation(\(json));"
        webView.evaluateJavaScript(script) { [weak self] _, error in
            if let error {
                self?.logger.error("[GameDebug] pushAttestation JS eval error=\(error) index=\(index)")
            }
        }
    }
}

private struct UsernameAvailabilityPayload: Encodable {
    let availability: GameResultsInput.UsernameClaim.Availability
    let alternatives: [String]?
}

private struct AttestationPushPayload: Encodable {
    let index: Int
    let hash: String
    let highValue: Bool?
}

private extension GameResultsWebViewController {
    static func installInputScript(input: GameResultsInput, into controller: WKUserContentController) {
        guard let json = encodeJSON(input) else {
            Logger.shared.error("[GameDebug] installInputScript: encoding FAILED")
            return
        }
        Logger.shared
            .debug("[GameDebug] installing window.__GAME_RESULTS__ at documentStart len=\(json.count)\n\(json)")
        let source = "window.__GAME_RESULTS__ = \(json);"
        let script = WKUserScript(
            source: source,
            injectionTime: .atDocumentStart,
            forMainFrameOnly: true
        )
        controller.addUserScript(script)
    }

    static func encodeJSON(_ value: some Encodable) -> String? {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.withoutEscapingSlashes]
        guard let data = try? encoder.encode(value) else {
            Logger.shared.error("[GameDebug] failed to encode \(type(of: value))")
            return nil
        }
        return String(data: data, encoding: .utf8)
    }

    // swiftlint:disable line_length
    static func installConsoleHook(into controller: WKUserContentController) {
        let source = """
        (function(){
          var post = function(level, message){
            try {
              window.webkit.messageHandlers.\(GameResultsBridge.messageHandlerName).postMessage({
                type: 'log', level: level, message: String(message)
              });
            } catch (_) {}
          };
          ['log','error','warn','info'].forEach(function(level){
            var orig = console[level];
            console[level] = function(){
              try {
                post(level, Array.from(arguments).map(String).join(' '));
              } catch (_) {}
              orig.apply(console, arguments);
            };
          });
          window.addEventListener('error', function(e){
            var t = e.target;
            if (t && (t.tagName === 'IMG' || t.tagName === 'AUDIO' || t.tagName === 'VIDEO' || t.tagName === 'SOURCE' || t.tagName === 'LINK' || t.tagName === 'SCRIPT')) {
              post('error', 'resource.error <' + t.tagName + '> src=' + (t.src || t.href));
            } else {
              post('error', 'window.error: ' + e.message + ' @ ' + e.filename + ':' + e.lineno);
            }
          }, true);
          window.addEventListener('unhandledrejection', function(e){
            post('error', 'unhandledrejection: ' + (e.reason && e.reason.message ? e.reason.message : String(e.reason)));
          });
        })();
        """
        let script = WKUserScript(
            source: source,
            injectionTime: .atDocumentStart,
            forMainFrameOnly: false
        )
        controller.addUserScript(script)
    }
    // swiftlint:enable line_length
}

extension GameResultsWebViewController: WKNavigationDelegate {
    func webView(_: WKWebView, didStartProvisionalNavigation _: WKNavigation!) {
        logger.debug("[GameDebug] webview didStartProvisionalNavigation url=\(loadRequestURL)")
        if schemeHandler == nil {
            rootView.activityIndicatorView.startAnimating()
        }
    }

    func webView(_ webView: WKWebView, didFinish _: WKNavigation!) {
        logger.debug("[GameDebug] webview didFinish currentURL=\(String(describing: webView.url))")
        rootView.activityIndicatorView.stopAnimating()
        onPageReady?()
        onPageReady = nil
    }

    func webView(_: WKWebView, didFailProvisionalNavigation _: WKNavigation!, withError error: Error) {
        logger.error("[GameDebug] webview didFailProvisionalNavigation error=\(error)")
        rootView.activityIndicatorView.stopAnimating()
    }

    func webView(_: WKWebView, didFail _: WKNavigation!, withError error: Error) {
        logger.error("[GameDebug] webview didFail error=\(error)")
        rootView.activityIndicatorView.stopAnimating()
    }

    func webViewWebContentProcessDidTerminate(_: WKWebView) {
        logger.error(
            "[GameDebug] webview WebContent process TERMINATED (renderer crash) — this is the black screen"
        )
    }
}
