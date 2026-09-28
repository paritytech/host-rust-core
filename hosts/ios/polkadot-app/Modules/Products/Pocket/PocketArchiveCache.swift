import Foundation
import Products

/// Where a product's content is already unpacked on this device.
///
/// The same pair ``CompositeProductFileProvider`` reads a worker's files
/// through: the name's content hash, and the directory that hash was unpacked
/// into. Nil means nothing has been fetched for that name yet.
enum PocketArchiveCache {
    static let onDisk: @Sendable (ProductId) -> URL? = { productId in
        guard let hash = ContentHashCache.shared.getContentHash(name: productId) else { return nil }

        return DotNsContentStorage().getContentDirectory(contentHash: hash)
    }
}
