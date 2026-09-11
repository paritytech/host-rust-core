import Foundation
import PolkadotUI
import SwiftUI
import DesignSystem
import Products

final class GameVideoWireframe: GameVideoWireframeProtocol {
    private let flowState: DIM2SharedFlowStateProtocol
    private let chatId: Chat.Id
    private let logger: LoggerProtocol
    private let spaFlowState: SPAFlowState

    init(
        flowState: DIM2SharedFlowStateProtocol,
        chatId: Chat.Id,
        spaFlowState: SPAFlowState,
        logger: LoggerProtocol = Logger.shared
    ) {
        self.flowState = flowState
        self.chatId = chatId
        self.spaFlowState = spaFlowState
        self.logger = logger
    }

    func close(view: (any GameVideoViewProtocol)?) {
        view?.controller.presentingViewController?.dismiss(animated: true)
    }

    @MainActor
    func showReport(from view: GameVideoViewProtocol?, for gameId: Game.Identifier) {
        guard let reportView = GameReportViewFactory.createView(
            flowState: flowState,
            gameId: gameId,
            chatId: chatId,
            spaFlowState: spaFlowState
        ) else {
            logger.debug("Missing report view")
            return
        }

        logger.debug("Showing report view from \(String(describing: view))")
        logger.debug("Nav: \(String(describing: view?.controller.navigationController))")
        logger.debug("Main thread: \(Thread.isMainThread)")

        view?.controller.navigationController?.setViewControllers(
            [reportView.controller],
            animated: false
        )
    }

    func showTutorial(from view: (any GameVideoViewProtocol)?) {
        let tutorialView = GameGestureTutorialView {
            view?.controller.dismiss(animated: true)
        }
        .environment(\.appTheme, ThemesRegistry.default)
        let hostingController = UIHostingController(rootView: tutorialView)
        hostingController.modalPresentationStyle = .fullScreen

        view?.controller.present(hostingController, animated: true)
    }
}
