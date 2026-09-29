import Foundation

struct TattooConfirmModel {
    let confirmClosure: () -> Void
    let cancelClosure: (() -> Void)?
}
