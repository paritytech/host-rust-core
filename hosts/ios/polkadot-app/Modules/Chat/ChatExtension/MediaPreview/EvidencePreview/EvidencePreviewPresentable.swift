import Foundation
import UIKit

enum EvidencePreviewType {
    case photo
    case video
}

@MainActor
protocol EvidencePreviewPresentable: MediaPreviewPresentable {
    var evidencePreviewLogger: LoggerProtocol { get }
    var evidencePreviewFileManagerFactory: EvidenceFileManagerFactoryProtocol { get }

    func showEvidencePreview(
        evidenceId: String,
        type: EvidencePreviewType,
        from view: UIViewController?
    )
}

extension EvidencePreviewPresentable {
    var evidencePreviewLogger: LoggerProtocol { Logger.shared }
    var evidencePreviewFileManagerFactory: EvidenceFileManagerFactoryProtocol { EvidenceFileManagerFactory() }

    func showEvidencePreview(
        evidenceId: String,
        type: EvidencePreviewType,
        from view: UIViewController?
    ) {
        let evidenceFileManager = evidencePreviewFileManagerFactory.createManager(evidenceId: evidenceId)

        switch type {
        case .photo:
            showPhotoPreview(evidenceFileManager: evidenceFileManager, from: view)
        case .video:
            showVideoPreview(evidenceFileManager: evidenceFileManager, from: view)
        }
    }
}

private extension EvidencePreviewPresentable {
    func showPhotoPreview(
        evidenceFileManager: EvidenceFileManaging,
        from view: UIViewController?
    ) {
        guard let photoURL = try? evidenceFileManager.preparePhotoEvidenceUrl() else {
            evidencePreviewLogger.error("Photo file not found for evidence")
            return
        }
        showPhoto(url: photoURL, from: view)
    }

    func showVideoPreview(
        evidenceFileManager: EvidenceFileManaging,
        from view: UIViewController?
    ) {
        guard let videoURL = try? evidenceFileManager.existingVideoExport() else {
            evidencePreviewLogger.error("Video file not found for evidence")
            return
        }
        showVideo(url: videoURL, from: view)
    }
}
