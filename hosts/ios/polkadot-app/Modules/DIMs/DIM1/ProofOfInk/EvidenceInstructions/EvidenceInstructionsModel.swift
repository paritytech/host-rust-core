import Foundation

enum EvidenceInstructionsMode {
    case photo
    case video
}

struct EvidenceInstructionsModel {
    let onProceed: () -> Void
    let onClose: () -> Void

    init(
        onProceed: @escaping () -> Void,
        onClose: @escaping () -> Void
    ) {
        self.onClose = onClose
        self.onProceed = onProceed
    }
}

struct ProvideEvidenceDeviceStatus {
    let isLowBatteryStatus: Bool
    let isLowStorageStatus: Bool
}
