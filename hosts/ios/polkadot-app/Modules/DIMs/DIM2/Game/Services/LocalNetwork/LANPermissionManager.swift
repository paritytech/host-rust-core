import Foundation

protocol LANPermissionManagerProtocol {
    func triggerPermissionRequest()
}

final class LANPermissionManager: LANPermissionManagerProtocol {
    func triggerPermissionRequest() {
        DispatchQueue.global().async {
            _ = ProcessInfo.processInfo.hostName
        }
    }
}
