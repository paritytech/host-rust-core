import Coinage
import Foundation

/// Bridges a `DerivationIndex` to the signed `Int64` CoreData stores it in.
///
/// CoreData has no unsigned integer attribute, so the index is stored bit-for-bit as `Int64` and
/// reconstructed the same way — never reinterpreted numerically.
extension DerivationIndex {
    /// The bit-preserving `Int64` used to store this index in CoreData.
    func toCoreData() -> Int64 {
        Int64(bitPattern: self)
    }

    /// Reconstructs the index from its CoreData `Int64` storage.
    static func fromCoreData(_ value: Int64) -> DerivationIndex {
        DerivationIndex(bitPattern: value)
    }
}
