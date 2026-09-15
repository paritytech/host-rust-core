import Foundation
import UIKit

public protocol DeviceProtocol {
    var isSimulator: Bool { get }
}

public protocol FileManagingProtocol: AnyObject {
    func fileExists(atPath path: String) -> Bool
}

public protocol URLOpening: AnyObject {
    func canOpenURL(_ url: URL) -> Bool
}

public protocol ProcessInfoProtocol: AnyObject {
    var environment: [String: String] { get }
}

public final class JailbreakDetector {
    private let device: DeviceProtocol
    private let fileManager: FileManagingProtocol
    private let urlOpener: URLOpening
    private let processInfo: ProcessInfoProtocol

    public init(
        device: DeviceProtocol,
        fileManager: FileManagingProtocol,
        urlOpener: URLOpening,
        processInfo: ProcessInfoProtocol
    ) {
        self.device = device
        self.fileManager = fileManager
        self.urlOpener = urlOpener
        self.processInfo = processInfo
    }

    public func isJailbroken() -> Bool {
        let isJailbroken = [
            checkJailbreakFilesAndDirectories(),
            checkJailbreakTools(),
            checkSystemModifications(),
            checkEnvironmentVariables()
        ].contains(true)
        return isJailbroken || device.isSimulator
    }

    private func checkJailbreakFilesAndDirectories() -> Bool {
        Constants.jailbreakApplicationPaths
            .contains { fileManager.fileExists(atPath: $0) }
    }

    private func checkSystemModifications() -> Bool {
        Constants.inaccessibleSystemPaths
            .contains { fileManager.fileExists(atPath: $0) }
    }

    private func checkJailbreakTools() -> Bool {
        let jailbreakTools = [
            Constants.jailbreakToolCydia,
            Constants.jailbreakToolIcy,
            Constants.jailbreakToolInstaller
        ]
        return jailbreakTools.contains { urlOpener.canOpenURL($0!) }
    }

    private func checkEnvironmentVariables() -> Bool {
        let environmentVariables = [
            Constants.environmentVariableDyldInsertLibraries,
            Constants.environmentVariableDyldPrintToFile,
            Constants.environmentVariableDyldPrintOpts
        ]
        return environmentVariables.contains { processInfo.environment[$0] != nil }
    }
}

extension UIDevice: DeviceProtocol {
    public var isSimulator: Bool {
        #if targetEnvironment(simulator)
            true
        #else
            false
        #endif
    }
}

extension FileManager: FileManagingProtocol {}
extension UIApplication: URLOpening {}
extension ProcessInfo: ProcessInfoProtocol {}

private enum Constants {
    static let jailbreakToolCydia: URL! = URL(string: "cydia://")
    static let jailbreakToolIcy: URL! = URL(string: "icy://")
    static let jailbreakToolInstaller: URL! = URL(string: "installer://")
    static let environmentVariableDyldInsertLibraries = "DYLD_INSERT_LIBRARIES"
    static let environmentVariableDyldPrintToFile = "DYLD_PRINT_TO_FILE"
    static let environmentVariableDyldPrintOpts = "DYLD_PRINT_OPTS"
    static let jailbreakApplicationPaths: [String] = [
        "/Applications/Cydia.app",
        "/Applications/blackra1n.app",
        "/Applications/FakeCarrier.app",
        "/Applications/Icy.app",
        "/Applications/IntelliScreen.app",
        "/Applications/MxTube.app",
        "/Applications/RockApp.app",
        "/Applications/SBSettings.app",
        "/Applications/WinterBoard.app"
    ]

    static let inaccessibleSystemPaths: [String] = [
        "/Library/MobileSubstrate/DynamicLibraries/LiveClock.plist",
        "/Library/MobileSubstrate/DynamicLibraries/Veency.plist",
        "/private/var/lib/apt",
        "/private/var/lib/cydia",
        "/private/var/mobile/Library/SBSettings/Themes",
        "/private/var/stash",
        "/private/var/tmp/cydia.log",
        "/System/Library/LaunchDaemons/com.ikey.bbot.plist",
        "/System/Library/LaunchDaemons/com.saurik.Cydia.Startup.plist",
        "/usr/bin/sshd",
        "/bin/bash",
        "/usr/libexec/ssh-keysign",
        "/usr/libexec/sftp-server",
        "/usr/sbin/sshd",
        "/etc/apt",
        "/bin/sh",
        "/bin/su",
        "/etc/ssh/sshd_config",
        "/Library/MobileSubstrate/MobileSubstrate.dylib",
        "/pguntether",
        "/usr/bin/cycript",
        "/usr/bin/ssh",
        "/usr/sbin/frida-server",
        "/var/cache/apt",
        "/var/lib/cydia",
        "/var/log/syslog",
        "/var/mobile/Media/.evasi0n7_installed",
        "/var/tmp/cydia.log"
    ]
}
