import UIKit

@MainActor
final class GameResultsPreloader {
    private let urlProvider: GameResultsURLProviding
    private var viewController: GameResultsWebViewController?
    private var isPageReady = false
    private var resolvedURL: URL?

    init(urlProvider: GameResultsURLProviding) {
        self.urlProvider = urlProvider
    }

    func start() {
        guard viewController == nil else { return }

        Task { [weak self, urlProvider] in
            let url = await urlProvider.resolveURL()
            self?.applyResolvedURL(url)
        }
    }

    func consume(onClose: @escaping () -> Void) -> GameResultsWebViewController? {
        if let controller = viewController, isPageReady {
            viewController = nil
            isPageReady = false
            controller.onClose = onClose
            return controller
        }
        let url = resolvedURL ?? GameResultsWebViewFactory.fallbackURL
        Logger.shared
            .debug(
                "[GameDebug] preloader.consume: not ready — creating on-demand with " +
                    "\(url.isFileURL ? "file://" + url.path : url.absoluteString)"
            )
        return GameResultsWebViewFactory.createPreloadedView(url: url).map { controller in
            controller.onClose = onClose
            return controller
        }
    }
}

private extension GameResultsPreloader {
    func applyResolvedURL(_ url: URL) {
        resolvedURL = url
        guard
            viewController == nil,
            let controller = GameResultsWebViewFactory.createPreloadedView(url: url)
        else { return }

        Logger.shared
            .debug(
                "[GameDebug] preloader: warming with " +
                    "\(url.isFileURL ? "file://" + url.path : url.absoluteString)"
            )
        controller.onPageReady = { [weak self] in
            self?.isPageReady = true
        }
        viewController = controller
        _ = controller.view
    }
}
