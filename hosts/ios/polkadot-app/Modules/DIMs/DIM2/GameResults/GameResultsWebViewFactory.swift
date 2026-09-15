import Foundation

@MainActor
enum GameResultsWebViewFactory {
    nonisolated static let fallbackURL = URL(string: "https://game-results-six.vercel.app/")!

    static func createView(
        url: URL,
        input: GameResultsInput,
        onClose: @escaping () -> Void
    ) -> GameResultsWebViewController? {
        GameResultsWebViewController(url: url, input: input, onClose: onClose)
    }

    static func createPreloadedView(url: URL) -> GameResultsWebViewController? {
        GameResultsWebViewController(url: url, input: nil)
    }
}
