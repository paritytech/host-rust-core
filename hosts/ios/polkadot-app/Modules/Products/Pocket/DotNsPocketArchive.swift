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

    func file(contentId: ProductId, path: String) async throws -> Data {
        let root = try await dotNsResolver.resolveToLocalURL(dotNsName: contentId)
        let file = root.appending(path: path).standardizedFileURL

        guard file.path().hasPrefix(root.standardizedFileURL.path()) else {
            throw PocketPreviewError.notReachable(path)
        }

        return try Data(contentsOf: file)
    }
}
