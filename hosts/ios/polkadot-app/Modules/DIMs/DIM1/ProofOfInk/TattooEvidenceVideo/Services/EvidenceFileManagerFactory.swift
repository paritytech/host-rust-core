import Foundation

protocol EvidenceFileManagerFactoryProtocol {
    func createManager(evidenceId: String) -> EvidenceFileManaging
}

final class EvidenceFileManagerFactory: EvidenceFileManagerFactoryProtocol {
    private let fileManager: FileManager

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    func createManager(evidenceId: String) -> EvidenceFileManaging {
        EvidenceFileManager(fileManager: fileManager, evidenceId: evidenceId)
    }
}
