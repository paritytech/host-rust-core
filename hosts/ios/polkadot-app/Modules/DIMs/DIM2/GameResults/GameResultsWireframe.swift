import Foundation

@MainActor
final class GameResultsWireframe: GameResultsWireframeProtocol {
    private let onClose: () -> Void

    init(onClose: @escaping () -> Void) {
        self.onClose = onClose
    }

    func close(view _: GameResultsViewProtocol?) {
        onClose()
    }
}
