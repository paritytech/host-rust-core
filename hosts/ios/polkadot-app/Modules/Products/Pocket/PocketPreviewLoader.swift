import Foundation
import Products
import TrUAPIHost

/// Reads a file out of a product executable's content archive, fetching the
/// archive first when the host does not already hold it.
protocol PocketArchiveReading {
    func file(contentId: ProductId, path: String) async throws -> Data
}

enum PocketPreviewError: Error, CustomStringConvertible {
    case notReachable(String)
    case tooLarge(bytes: Int)
    case notReadable

    var description: String {
        switch self {
        case let .notReachable(url): "'\(url)' is not an address the preview can be read from"
        case let .tooLarge(bytes): "preview is \(bytes) bytes, larger than \(PocketPreviewLoader.maxBytes)"
        case .notReadable: "preview is not readable text"
        }
    }
}

/// Reads a published card's static face — the one the approval sheet shows.
///
/// This runs before the user has approved anything, so how much there is to
/// read is the product's choice. The size is checked rather than the content:
/// by the time a hostile face has been decoded it is already held whole.
struct PocketPreviewLoader {
    static let maxBytes = 256 * 1_024

    private let archive: any PocketArchiveReading
    private let fetch: @Sendable (URL) async throws -> Data
    private let decoder = RendererNodeJsonDecoder()

    init(archive: any PocketArchiveReading, fetch: @escaping @Sendable (URL) async throws -> Data) {
        self.archive = archive
        self.fetch = fetch
    }

    func load(contentId: ProductId, preview: PocketCardPreview) async throws -> RendererNode {
        let data =
            switch preview {
            case let .archive(path):
                try await archive.file(contentId: contentId, path: path)
            case let .url(url):
                try await fetched(url)
            }

        guard data.count <= Self.maxBytes else { throw PocketPreviewError.tooLarge(bytes: data.count) }
        guard let json = String(data: data, encoding: .utf8) else { throw PocketPreviewError.notReadable }

        return try decoder.decode(json)
    }

    private func fetched(_ url: String) async throws -> Data {
        guard let url = URL(string: url) else { throw PocketPreviewError.notReachable(url) }

        return try await fetch(url)
    }
}
