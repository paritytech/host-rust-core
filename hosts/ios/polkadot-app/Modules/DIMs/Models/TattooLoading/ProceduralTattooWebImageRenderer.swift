import WebKit
import UIKit

final class ProceduralTattooWebImageRenderer: NSObject {
    private enum Constants {
        static let contentController = "tattooPngHandler"
    }

    private var completion: ((Data?) -> Void)?
    private weak var contentController: WKUserContentController?
    private var webView: WKWebView?
    private let logger: LoggerProtocol
    private let queue = DispatchQueue.global(qos: .userInitiated)

    init(logger: LoggerProtocol = Logger.shared) {
        self.logger = logger
    }

    func loadProceduralTattoo(input: ProceduralTattooInput, completion: @escaping (Data?) -> Void) {
        self.completion = completion
        let contentController = WKUserContentController()
        contentController.add(self, name: Constants.contentController)
        self.contentController = contentController
        let config = WKWebViewConfiguration()
        config.userContentController = contentController
        let webView = WKWebView(frame: .zero, configuration: config)
        self.webView = webView
        webView.navigationDelegate = self
        logger
            .debug(
                "Started loading tattoo design: \(input.generationScriptUrl.absoluteString) with input: \(input.scriptInput)"
            )

        webView.loadHTMLString(htmlTemplate(with: input), baseURL: nil)
    }

    private func cleanup() {
        contentController?.removeAllScriptMessageHandlers()
        webView?.navigationDelegate = nil
        webView?.stopLoading()
        webView = nil
        completion = nil
    }

    private func finalise(data: Data?) {
        DispatchQueue.main.async { [weak self] in
            self?.completion?(data)
            self?.cleanup()
        }
    }
}

extension ProceduralTattooWebImageRenderer: WKNavigationDelegate, WKScriptMessageHandler {
    func userContentController(_: WKUserContentController, didReceive message: WKScriptMessage) {
        guard message.name == Constants.contentController else { return }

        guard let dataURL = message.body as? String else {
            finalise(data: nil)
            return
        }

        queue.async { [weak self] in
            guard let url = URL(string: dataURL),
                  let data = try? Data(contentsOf: url) else {
                self?.finalise(data: nil)
                return
            }
            self?.finalise(data: data)
        }
    }

    func webView(_: WKWebView, didFail _: WKNavigation!, withError error: Error) {
        logger.error("Navigation failed: \(error.localizedDescription)")
        finalise(data: nil)
    }

    func webView(_: WKWebView, didFailProvisionalNavigation _: WKNavigation!, withError error: Error) {
        logger.error("Provisional navigation failed: \(error.localizedDescription)")
        finalise(data: nil)
    }
}

private extension ProceduralTattooWebImageRenderer {
    func htmlTemplate(with input: ProceduralTattooInput) -> String {
        """
        <!DOCTYPE html>
        <html>
        <head>
          <meta name="viewport" content="width=device-width, initial-scale=1, maximum-scale=1" />
        </head>
        <body>
          <div>
            <canvas id="canvas" width="640" height="640"></canvas>
          </div>
          <script type="module">
                const scriptUrl = "\(input.generationScriptUrl)";
                const canvas = document.getElementById("canvas");
                const width = canvas.width;
                const height = canvas.height;
                const ctx = canvas.getContext('2d');
                ctx.scale(width, height);
                ctx.aspect = width / height;

                fetch(scriptUrl)
                  .then(response => response.text())
                  .then(scriptText => {
                      const blob = new Blob([scriptText], { type: 'application/javascript' });
                      const url = URL.createObjectURL(blob);
                      return import(url);
                  })
                  .then(module => {
                      module.draw(ctx, \(input.scriptInput));
                      ctx.restore();
                      window.webkit.messageHandlers.\(Constants.contentController).postMessage(canvas.toDataURL());
                  })
                  .catch(error => {
                      console.error('Error loading or executing script:', error);
                      window.webkit.messageHandlers.\(Constants.contentController).postMessage(null);
                  });
          </script>
        </body>
        </html>
        """
    }
}
