import Foundation
import TrUAPIHost
import Products

extension TrUAPIProductExecutionProtocol {
    /// Camera/mic media-capture (getUserMedia) permission handler for the rust
    /// runtime. Answers query-only from the execution's persisted device
    /// authorization — the rust core's `devicePermission` flow prompts and
    /// persists earlier; this only enforces at capture time.
    func makeDeviceCapabilityHandler() -> JSDeviceCapabilityHandler {
        { capability in
            let request: HostDevicePermissionRequest =
                switch capability {
                case .camera: .camera
                case .microphone: .microphone
                }
            let status = try await self.permissionAuthorizationStatus(request: .device(request))
            return status == .authorized ? .allowed : .denied
        }
    }
}
