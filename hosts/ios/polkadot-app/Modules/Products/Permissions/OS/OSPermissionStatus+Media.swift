import Foundation
import AVFoundation
import Products

extension OSPermissionStatus {
    init(mediaStatus: AVAuthorizationStatus) {
        switch mediaStatus {
        case .notDetermined:
            self = .notDetermined
        case .denied:
            self = .denied
        case .authorized,
             .restricted:
            // be optimistic and treat restricted as allowed
            self = .allowed
        @unknown default:
            self = .notDetermined
        }
    }
}
