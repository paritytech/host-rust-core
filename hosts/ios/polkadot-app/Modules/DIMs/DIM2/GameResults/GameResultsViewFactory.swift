import Foundation

@MainActor
enum GameResultsViewFactory {
    struct Module {
        let view: GameResultsViewProtocol
        let presenter: GameResultsPresenter
        let wireframe: GameResultsWireframeProtocol
        let interactor: GameResultsInteractorInputProtocol
    }

    static func createModule(
        webView: GameResultsWebViewController,
        context: ReportSuccessContext,
        dependencies: GameResultsDependencies,
        onClose: @escaping () -> Void
    ) -> Module {
        Logger.shared
            .debug(
                "[GameDebug] GameResultsViewFactory.createModule gameIndex=\(context.gameIndex) " +
                    "player=\(context.player.rawTypeValue) " +
                    "wasPerson=\(context.wasPersonBeforeReport)"
            )

        let sink = WebViewAttestationSink()
        sink.attach(webView: webView, initialHashes: [])

        let interactor = GameResultsInteractor(dependencies: dependencies)

        let closeOnce: () -> Void = { [weak sink, weak interactor] in
            Logger.shared.debug("[GameDebug] GameResults closing — stopping interactor + closing sink")
            interactor?.stop()
            sink?.close()
            onClose()
        }

        let wireframe = GameResultsWireframe(onClose: closeOnce)
        let orchestrator = GameResultsOrchestrator(bridge: webView.bridge)

        let presenter = GameResultsPresenter(
            wireframe: wireframe,
            interactor: interactor,
            orchestrator: orchestrator,
            sink: sink,
            context: context
        )
        presenter.view = webView
        interactor.presenter = presenter

        webView.onClose = closeOnce

        presenter.setup()

        return Module(
            view: webView,
            presenter: presenter,
            wireframe: wireframe,
            interactor: interactor
        )
    }
}
