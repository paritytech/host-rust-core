import Foundation

enum DiscardEvidenceMode {
    case photo
    case video
}

struct DiscardEvidenceModel {
    let mode: DiscardEvidenceMode
    let discardClosure: () -> Void
    let cancelClosure: (() -> Void)?

    init(
        mode: DiscardEvidenceMode,
        discardClosure: @escaping () -> Void,
        cancelClosure: (() -> Void)? = nil
    ) {
        self.mode = mode
        self.discardClosure = discardClosure
        self.cancelClosure = cancelClosure
    }
}
