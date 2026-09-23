import Foundation
import Products

/// Reads a card's face out of a worker's content archive, fetching the archive
/// from dotNS first when the host does not already hold it.
///
/// The path is resolved under the archive root and checked to stay there, so a
/// preview path a product publishes cannot reach a file outside its own archive.
struct DotNsPocketArchive: PocketArchiveReading {
    private let dotNsResolver: any DotNsResolverProtocol

    init(dotNsResolver: any DotNsResolverProtocol) {
        self.dotNsResolver = dotNsResolver
    }

    func file(contentId: ProductId, path: String, maxBytes: Int) async throws -> Data {
        let root = try await dotNsResolver.resolveToLocalURL(dotNsName: contentId)

        guard let file = PocketArchivePath.inside(root, path: path) else {
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
