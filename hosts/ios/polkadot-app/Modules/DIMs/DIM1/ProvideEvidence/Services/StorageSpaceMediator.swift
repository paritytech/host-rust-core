import Foundation

protocol FileSystemAttributesProtocol {
    func attributesOfFileSystem(forPath path: String) throws -> [FileAttributeKey: Any]
}

extension FileManager: FileSystemAttributesProtocol {}

enum StorageCheckError: Error {
    case unavailable
    case failure(Error)
}

protocol StorageSpaceMediating: AnyObject {
    func checkAvailableStorage(_ minimumFreeSpaceMB: Double) -> Result<Bool, StorageCheckError>
}

final class StorageSpaceMediator: StorageSpaceMediating {
    private enum Constants {
        static let bytesInMegabytes: Double = 1_024 * 1_024
    }

    private let fileManager: FileSystemAttributesProtocol

    init(fileManager: FileSystemAttributesProtocol = FileManager.default) {
        self.fileManager = fileManager
    }

    func checkAvailableStorage(_ minimumFreeSpaceMB: Double) -> Result<Bool, StorageCheckError> {
        do {
            let attributes = try fileManager.attributesOfFileSystem(forPath: NSHomeDirectory())
            if let freeSpace = attributes[.systemFreeSize] as? NSNumber {
                let freeSpaceMB = freeSpace.doubleValue / Constants.bytesInMegabytes
                return .success(freeSpaceMB >= minimumFreeSpaceMB)
            } else {
                return .failure(.unavailable)
            }
        } catch {
            return .failure(.failure(error))
        }
    }
}
