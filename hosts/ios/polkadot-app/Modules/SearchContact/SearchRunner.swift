import Foundation

final class SearchRunner {
    enum State<SearchResult> {
        case started
        case waiting
        case waitingLong
        case result(SearchResult)
    }

    private enum Constants {
        static let debounceDelay: Duration = .milliseconds(300)
        static let waitingDelay: Duration = .milliseconds(500)
        static let waitingLongDelay: Duration = .milliseconds(1_500)
    }

    func run<SearchResult>(
        _ operation: @escaping () async -> SearchResult?
    ) -> AsyncStream<State<SearchResult>> {
        AsyncStream { continuation in
            let loaderTask = Task {
                try? await Task.sleep(for: Constants.debounceDelay + Constants.waitingDelay)
                guard !Task.isCancelled else { return }
                continuation.yield(.waiting)

                try? await Task.sleep(for: Constants.waitingLongDelay)
                guard !Task.isCancelled else { return }
                continuation.yield(.waitingLong)
            }

            let searchTask = Task {
                continuation.yield(.started)

                try? await Task.sleep(for: Constants.debounceDelay)
                guard !Task.isCancelled else {
                    continuation.finish()
                    return
                }

                let result = await operation()
                loaderTask.cancel()

                guard !Task.isCancelled else {
                    continuation.finish()
                    return
                }

                if let result {
                    continuation.yield(.result(result))
                }
                continuation.finish()
            }

            continuation.onTermination = { _ in
                loaderTask.cancel()
                searchTask.cancel()
            }
        }
    }
}
