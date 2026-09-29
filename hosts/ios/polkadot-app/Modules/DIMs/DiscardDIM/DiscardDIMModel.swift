import Foundation

struct DiscardDIMModel {
    /// Discard DIM (terminate process)
    let discardClosure: () -> Void
    /// Cancel discard (do nothing)
    let cancelClosure: () -> Void
}
