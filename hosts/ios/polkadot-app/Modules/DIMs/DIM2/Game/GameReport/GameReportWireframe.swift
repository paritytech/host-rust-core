import Foundation
import SubstrateSdk
import UIKit

@MainActor
final class GameReportWireframe {
    let chatId: Chat.Id
    private let moduleNavigator: ModuleNavigating
    private let resultsDependencies: GameResultsDependencies
    private let preloader: GameResultsPreloader
    private var resultsModule: GameResultsViewFactory.Module?

    init(
        chatId: Chat.Id,
        resultsDependencies: GameResultsDependencies,
        moduleNavigator: ModuleNavigating = ModuleNavigator()
    ) {
        self.chatId = chatId
        self.resultsDependencies = resultsDependencies
        self.moduleNavigator = moduleNavigator

        let urlProvider = GameResultsURLProvider(
            spaFlowState: resultsDependencies.spaFlowState,
            dotNsLabel: AppConfig.DotNs.dotNsGameWebview,
            firebaseFallback: { FirebaseApplicationService.shared.asyncWaitGameResultsFallbackURL() },
            bundledFallbackURL: GameResultsWebViewFactory.fallbackURL
        )
        preloader = GameResultsPreloader(urlProvider: urlProvider)
        preloader.start()
    }
}

extension GameReportWireframe: GameReportWireframeProtocol {
    func close(view: (any GameReportViewProtocol)?) {
        view?.controller.presentingViewController?.dismiss(animated: true)
    }

    func registerForNextGame(view: (any GameReportViewProtocol)?) {
        dismissToChat(view: view)
    }

    func showReveal(view: (any GameReportViewProtocol)?, context: ReportSuccessContext) {
        #if FEATURE_PRIZES
            Logger.shared
                .debug(
                    "[GameDebug] showReveal called gameIndex=\(context.gameIndex) " +
                        "player=\(context.player.rawTypeValue) " +
                        "wasPerson=\(context.wasPersonBeforeReport) " +
                        "snapshot.maxGroupSize=\(context.gameSnapshot.maxGroupSize) " +
                        "snapshot.playerCount=\(context.gameSnapshot.playerCount)"
                )

            let onClose: () -> Void = { [weak self, weak view] in
                Logger.shared.debug("[GameDebug] GameResults closed — dismissing report flow to chat")
                self?.resultsModule = nil
                self?.dismissToChat(view: view)
            }

            guard let webView = preloader.consume(onClose: onClose) else {
                Logger.shared.debug("[GameDebug] preloader returned nil webView — dismissing report flow to chat")
                dismissToChat(view: view)
                return
            }
            preloader.start()

            let module = GameResultsViewFactory.createModule(
                webView: webView,
                context: context,
                dependencies: resultsDependencies,
                onClose: onClose
            )
            resultsModule = module

            let nav = AppNavigationController(rootViewController: module.view.controller)
            nav.modalPresentationStyle = .fullScreen
            Logger.shared.debug("[GameDebug] presenting GameResults module modally")
            view?.controller.present(nav, animated: true)
        #else
            Logger.shared.debug("[GameDebug] showReveal: prizes feature disabled — dismissing report flow to chat")
            dismissToChat(view: view)
        #endif
    }
}

private extension GameReportWireframe {
    func dismissToChat(view: (any GameReportViewProtocol)?) {
        view?.controller.presentingViewController?.dismiss(animated: true) { [chatId, moduleNavigator] in
            moduleNavigator.openChat(chatId)
        }
    }
}
