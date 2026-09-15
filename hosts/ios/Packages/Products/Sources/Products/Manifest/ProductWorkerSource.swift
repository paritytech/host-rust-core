import Foundation

/// Where a product's chat worker is served from: its own subname when a worker manifest declares
/// one, the base name's archive and a conventional entry file otherwise.
public struct ProductWorkerSource: Hashable, Sendable {
    public let contentId: ProductId
    public let entryRelativePath: String

    public init(contentId: ProductId, entryRelativePath: String) {
        self.contentId = contentId
        self.entryRelativePath = entryRelativePath
    }
}
