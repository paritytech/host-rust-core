import Foundation
import PolkadotUI
import Products

/// Turns an image source inside a face into an address the image loader can
/// fetch: a file in the product's own archive, or a bulletin gateway address.
///
/// Nothing here throws. A source that cannot be resolved answers nil, and the
/// rest of the face still draws with a hole where the image would be — a card
/// whose product ships a bad path is worth more than no card at all.
struct PocketImageResolver: Sendable {
    /// Resolved per call: the archive a face is drawn from is the product's
    /// worker, whose subname is only known once the product's manifest is read.
    private let contentId: @Sendable () async -> ProductId?
    private let dotNsResolver: any DotNsResolverProtocol
    private let ipfsUrl: @Sendable (String) -> URL?

    init(
        contentId: @escaping @Sendable () async -> ProductId?,
        dotNsResolver: any DotNsResolverProtocol,
        ipfsUrl: @escaping @Sendable (String) -> URL?
    ) {
        self.contentId = contentId
        self.dotNsResolver = dotNsResolver
        self.ipfsUrl = ipfsUrl
    }

    func resolve(_ source: CustomMessageWidgetNode.ImageSource) async -> URL? {
        switch source {
        case let .bulletin(cid): ipfsUrl(cid)
        case let .archive(path): await archived(path)
        }
    }

    /// The path is written by the product, so it is checked to stay inside the
    /// archive it belongs to rather than trusted to.
    private func archived(_ path: String) async -> URL? {
        guard let contentId = await contentId(),
              let root = try? await dotNsResolver.resolveToLocalURL(dotNsName: contentId)
        else {
            return nil
        }

        let file = root.appending(path: path).standardizedFileURL
        guard file.path().hasPrefix(root.standardizedFileURL.path()) else { return nil }

        return file
    }
}
