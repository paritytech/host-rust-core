import Foundation

/// Errors that can occur during coin selection.
public enum CoinSelectionError: Error, Equatable {
    /// The wallet does not have enough funds to cover the requested amount.
    case insufficientFunds
    /// The requested amount cannot be represented with available denominations.
    case amountNotRepresentable
    /// The requested amount is zero.
    case zeroAmount
    /// The wallet contains no coins or vouchers.
    case emptyWallet
    /// Voucher is not ready
    case selectedVoucherIsNotReady
    /// A recycler group contains more vouchers than the pallet allows per consolidation.
    case tooManyVouchersInGroup(count: Int, max: Int)
}
