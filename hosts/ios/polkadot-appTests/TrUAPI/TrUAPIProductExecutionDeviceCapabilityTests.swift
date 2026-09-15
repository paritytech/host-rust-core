import Foundation
import Testing
import Products
import TrUAPIHost
@testable import polkadot_app

struct TrUAPIProductExecutionDeviceCapabilityTests {
    @Test(arguments: [JSDeviceCapability.camera, .microphone])
    func allowedWhenExecutionAuthorized(capability: JSDeviceCapability) async throws {
        let expectedRequest: PermissionAuthorizationRequest =
            switch capability {
            case .camera: .device(.camera)
            case .microphone: .device(.microphone)
            }

        let execution = MockProductExecution()
        execution.permissionStatus = .authorized
        let handler = execution.makeDeviceCapabilityHandler()

        #expect(try await handler(capability) == .allowed)
        #expect(execution.permissionRequests == [expectedRequest])
    }

    @Test(arguments: zip(
        [JSDeviceCapability.camera, .microphone, .camera],
        [PermissionAuthorizationStatus.denied, .denied, .notDetermined]
    ))
    func deniedWhenNotAuthorized(
        capability: JSDeviceCapability,
        status: PermissionAuthorizationStatus
    ) async throws {
        let execution = MockProductExecution()
        execution.permissionStatus = status
        let handler = execution.makeDeviceCapabilityHandler()

        #expect(try await handler(capability) == .denied)
    }
}
