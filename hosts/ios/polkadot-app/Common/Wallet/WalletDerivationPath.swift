import Foundation
import KeyDerivation

/// Derivation paths of the built-in accounts. Product-account paths carry the 32-byte
/// index as a hex segment — always build them via `ProductDerivationPath`, never hand-format.
enum WalletDerivationPath {
    /// Main identity account `//product//uid.dot/{index_bytes(0)}`.
    static func main(for tld: String) -> String {
        ProductDerivationPath.builtInAccount(BuiltInProduct.uid(for: tld), index: 0)
    }

    /// Game candidate account `//product//dim2.dot/{index_bytes(0)}`.
    static func candidate(for tld: String) -> String {
        ProductDerivationPath.builtInAccount(BuiltInProduct.dim2(for: tld), index: 0)
    }

    /// Game score account `//product//dim2.dot/{index_bytes(1)}`.
    static func score(for tld: String) -> String {
        ProductDerivationPath.builtInAccount(BuiltInProduct.dim2(for: tld), index: 1)
    }

    /// Deposit account `//product//fund.dot/{index_bytes(0)}`.
    static func deposit(for tld: String) -> String {
        ProductDerivationPath.builtInAccount(BuiltInProduct.fund(for: tld), index: 0)
    }

    static var bulletInForChat: String { "//allowance//bulletin//chat" }
}
