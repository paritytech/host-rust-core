import Foundation

struct EvidenceFiles {
    let videoUrl: URL
    let photoUrl: URL
}

protocol EvidenceFileManaging {
    func generateVideoRecordingUrl() throws -> URL
    func existingVideoRecordings() throws -> [URL]
    func forgetVideoEvidence() throws
    func prepareVideoExport() throws -> URL
    func existingVideoExport() throws -> URL?

    func preparePhotoEvidenceUrl() throws -> URL
    func forgetPhotoEvidence() throws

    var videoDirectory: URL { get }
    var photoDirectory: URL { get }

    func completeEvidenceProviding() throws -> EvidenceFiles
}

enum EvidenceFileManagerError: Error {
    case fileNotExists(URL)
}

final class EvidenceFileManager {
    enum Constants {
        static let videoName = "videoEvidence"
        static let photoName = "photoEvidence"
    }

    let baseUrl: URL
    let fileManager: FileManager
    let evidenceDirectory: URL
    let videoDirectoryName: String
    let photoDirectoryName: String
    let evidenceId: String

    init(
        fileManager: FileManager,
        evidenceId: String,
        baseUrl: URL? = nil,
        evidenceDirectoryName: String = "Evidence",
        videoDirectoryName: String = "Video",
        photoDirectoryName: String = "Photo"
    ) {
        self.fileManager = fileManager
        self.evidenceId = evidenceId
        self.videoDirectoryName = videoDirectoryName
        self.photoDirectoryName = photoDirectoryName

        if let baseUrl {
            self.baseUrl = baseUrl
        } else {
            let paths = fileManager.urls(
                for: .documentDirectory,
                in: .userDomainMask
            )

            self.baseUrl = paths[0]
        }

        evidenceDirectory = self.baseUrl.appendingPathComponent(evidenceDirectoryName, conformingTo: .directory)
    }
}

extension EvidenceFileManager: EvidenceFileManaging {
    func generateVideoRecordingUrl() throws -> URL {
        let videoFileName = UUID().uuidString
        return try prepareVideoBaseUrl()
            .appendingPathComponent(videoFileName, conformingTo: .quickTimeMovie)
    }

    func existingVideoRecordings() throws -> [URL] {
        let allVideos = try fileManager.contentsOfDirectory(at: videoDirectory, includingPropertiesForKeys: nil)
        let exportVideoUrl = videoDirectory.appendingPathComponent(Constants.videoName, conformingTo: .quickTimeMovie)
        return allVideos.filter { $0 != exportVideoUrl }
    }

    func forgetVideoEvidence() throws {
        try removeDirectoryIfExists(for: videoDirectory)
    }

    func prepareVideoExport() throws -> URL {
        try prepareVideoBaseUrl()
            .appendingPathComponent(Constants.videoName, conformingTo: .quickTimeMovie)
    }

    func existingVideoExport() throws -> URL? {
        let exportVideoUrl = try prepareVideoBaseUrl()
            .appendingPathComponent(Constants.videoName, conformingTo: .quickTimeMovie)
        if fileExistsAt(url: exportVideoUrl) {
            return exportVideoUrl
        } else {
            return nil
        }
    }

    func completeEvidenceProviding() throws -> EvidenceFiles {
        let videoUrl = videoDirectory
            .appendingPathComponent(Constants.videoName, conformingTo: .quickTimeMovie)

        if !fileExistsAt(url: videoUrl) {
            throw EvidenceFileManagerError.fileNotExists(videoUrl)
        }

        let photoUrl = photoDirectory
            .appendingPathComponent(Constants.photoName, conformingTo: .jpeg)

        if !fileExistsAt(url: photoUrl) {
            throw EvidenceFileManagerError.fileNotExists(photoUrl)
        }

        return .init(videoUrl: videoUrl, photoUrl: photoUrl)
    }

    func preparePhotoEvidenceUrl() throws -> URL {
        try preparePhotoBaseUrl()
            .appendingPathComponent(Constants.photoName, conformingTo: .jpeg)
    }

    func forgetPhotoEvidence() throws {
        try removeDirectoryIfExists(for: photoDirectory)
    }

    var videoDirectory: URL {
        evidenceDirectory
            .appendingPathComponent(evidenceId, conformingTo: .directory)
            .appendingPathComponent(videoDirectoryName, conformingTo: .directory)
    }

    var photoDirectory: URL {
        evidenceDirectory
            .appendingPathComponent(evidenceId, conformingTo: .directory)
            .appendingPathComponent(photoDirectoryName, conformingTo: .directory)
    }
}

private extension EvidenceFileManager {
    func removeDirectoryIfExists(for url: URL) throws {
        var isDirectory: ObjCBool = false

        if fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory), isDirectory.boolValue {
            try fileManager.removeItem(at: url)
        }
    }

    func createDirectoryIfNotExists(for url: URL) throws {
        var isDirectory: ObjCBool = false

        if !fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory) || !isDirectory.boolValue {
            try fileManager.createDirectory(at: url, withIntermediateDirectories: true)
        }
    }

    func prepareEvidenceDirectory() throws -> URL {
        let directory = evidenceDirectory.appendingPathComponent(evidenceId, conformingTo: .directory)
        try createDirectoryIfNotExists(for: directory)
        return directory
    }

    func prepareVideoBaseUrl() throws -> URL {
        try createDirectoryIfNotExists(for: videoDirectory)
        return videoDirectory
    }

    func preparePhotoBaseUrl() throws -> URL {
        try createDirectoryIfNotExists(for: photoDirectory)
        return photoDirectory
    }

    func fileExistsAt(url: URL) -> Bool {
        if let path = (url as NSURL).path, fileManager.fileExists(atPath: path) {
            true
        } else {
            false
        }
    }
}
