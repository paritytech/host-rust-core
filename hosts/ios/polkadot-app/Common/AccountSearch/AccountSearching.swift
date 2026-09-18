import Foundation
import AsyncExtensions

protocol AccountSearching<RecentPayload, MatchPayload>: AnyObject {
    associatedtype RecentPayload
    associatedtype MatchPayload

    func setup()
    func sourcesChanged() -> AnyAsyncSequence<Void>
    func search(query: String?) async throws -> AccountSearchSections<RecentPayload, MatchPayload>
}
