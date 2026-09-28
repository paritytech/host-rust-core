import Foundation
import Products

/// A product's worker archive on disk: the one place a card's face and the
/// images inside it are read from.
///
/// The archive already unpacked answers without a chain read and without a
/// download, which is what lets a card drawn from a kept face keep its images
/// offline. The fetch is paid only for a product nothing has been read for yet.
struct ProductWorkerArchive: PocketArchiveReading, Sendable {
    private let cachedRoot: @Sendable (ProductId) -> URL?
    private let dotNsResolver: any DotNsResolverProtocol

    init(
        dotNsResolver: any DotNsResolverProtocol,
        cachedRoot: @escaping @Sendable (ProductId) -> URL? = PocketArchiveCache.onDisk
    ) {
        self.dotNsResolver = dotNsResolver
        self.cachedRoot = cachedRoot
    }

    /// The file `path` names inside `contentId`'s archive, or nil when the
    /// archive cannot be reached or the path would leave it.
    func url(contentId: ProductId, path: String) async -> URL? {
        if let cached = cachedRoot(contentId) {
            return ContentArchivePath.inside(cached, path: path)
        }

        guard let fetched = try? await dotNsResolver.resolveToLocalURL(dotNsName: contentId) else { return nil }

        return ContentArchivePath.inside(fetched, path: path)
    }

    func file(contentId: ProductId, path: String, maxBytes: Int) async throws -> Data {
        guard let file = await url(contentId: contentId, path: path) else {
            throw PocketPreviewError.notReachable(path)
        }

        let handle = try FileHandle(forReadingFrom: file)
        defer { try? handle.close() }

        // One byte past the bound: enough to tell a file that is too large from
        // one that exactly fills it, without holding either of them whole.
        let read = try handle.read(upToCount: maxBytes + 1) ?? Data()
        guard read.count <= maxBytes else { throw PocketPreviewError.tooLarge(bytes: read.count) }

        return read
    }
}
