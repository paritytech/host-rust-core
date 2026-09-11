import UIKit
import UIKitExt
import FoundationExt
import WebKit

final class CollectiblesWebViewController: UIViewController, ViewHolder {
    typealias RootViewType = CollectiblesWebViewLayout

    let bridge: CollectiblesBridge

    var presenter: CollectiblesPresenterProtocol?

    private let url: URL
    private let logger: LoggerProtocol
    private let webView: WKWebView
    private var isPageReady = false
    private var pendingCollection: CollectionInput?

    init(
        url: URL,
        logger: LoggerProtocol = Logger.shared
    ) {
        self.url = url
        self.logger = logger

        let configuration = WKWebViewConfiguration()
        configuration.allowsInlineMediaPlayback = true

        Self.installConsoleHook(into: configuration.userContentController)
        let webView = WKWebView(frame: .zero, configuration: configuration)
        self.webView = webView
        bridge = CollectiblesBridge(webView: webView)

        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func loadView() {
        view = CollectiblesWebViewLayout(webView: webView)
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        setupNavigationBar()
        webView.navigationDelegate = self
        webView.load(URLRequest(url: url))
        presenter?.setup()
    }
}

private extension CollectiblesWebViewController {
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
        presenter?.close()
    }
}

extension CollectiblesWebViewController: CollectiblesViewProtocol {
    func didReceive(collection: CollectionInput) {
        guard isPageReady else {
            pendingCollection = collection
            return
        }
        guard let json = encodeJSON(collection) else { return }
        let script = "window.setCollection && window.setCollection(\(json));"
        webView.evaluateJavaScript(script, completionHandler: nil)
    }
}

private extension CollectiblesWebViewController {
    func encodeJSON(_ value: some Encodable) -> String? {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.withoutEscapingSlashes]
        guard let data = try? encoder.encode(value) else {
            logger.error("[Collectibles] failed to encode \(type(of: value))")
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
              window.webkit.messageHandlers.\(CollectiblesBridge.messageHandlerName).postMessage({
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

extension CollectiblesWebViewController: WKNavigationDelegate {
    func webView(_: WKWebView, didStartProvisionalNavigation _: WKNavigation!) {
        logger.debug("[Collectibles] didStartProvisionalNavigation url=\(url)")
        rootView.activityIndicatorView.startAnimating()
    }

    func webView(_ webView: WKWebView, didFinish _: WKNavigation!) {
        logger.debug("[Collectibles] didFinish currentURL=\(String(describing: webView.url))")
        rootView.activityIndicatorView.stopAnimating()
        isPageReady = true
        if let pendingCollection {
            self.pendingCollection = nil
            didReceive(collection: pendingCollection)
        }
    }

    func webView(_: WKWebView, didFailProvisionalNavigation _: WKNavigation!, withError error: Error) {
        logger.error("[Collectibles] didFailProvisionalNavigation error=\(error)")
        rootView.activityIndicatorView.stopAnimating()
    }

    func webView(_: WKWebView, didFail _: WKNavigation!, withError error: Error) {
        logger.error("[Collectibles] didFail error=\(error)")
        rootView.activityIndicatorView.stopAnimating()
    }
}
