import Foundation

/// A coin or voucher derivation index.
///
/// Unsigned in the domain; stored bit-for-bit as `Int64` in CoreData (see `toCoreData()`), since
/// CoreData has no unsigned integer attribute.
public typealias DerivationIndex = UInt64
