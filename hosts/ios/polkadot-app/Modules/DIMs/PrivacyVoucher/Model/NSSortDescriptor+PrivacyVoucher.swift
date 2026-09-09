import Foundation

extension NSSortDescriptor {
    static var localPrivacyVouchersByType: NSSortDescriptor {
        NSSortDescriptor(key: #keyPath(CDLocalPrivacyVoucher.type), ascending: true)
    }

    static var localPrivacyVouchersByIndex: NSSortDescriptor {
        NSSortDescriptor(key: #keyPath(CDLocalPrivacyVoucher.index), ascending: true)
    }
}
