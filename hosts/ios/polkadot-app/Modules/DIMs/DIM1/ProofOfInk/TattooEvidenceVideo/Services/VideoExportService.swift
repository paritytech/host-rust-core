import Foundation
import AVFoundation
import Operation_iOS

enum VideoExportQuality {
    case low
    case medium
    case high
}

struct VideoExportSettings {
    let inputUrls: [URL]
    let outputUrl: URL
    let quality: VideoExportQuality
}

enum VideoExportServiceError: Error {
    case internalError(Error)
    case invalidInput
    case stitchingUnsupported
    case stitchingFailed(Error)
    case exportingFailed(Error?)
    case noCompatibleTypes
}

typealias VideoExportCompletionClosure = (Result<Void, VideoExportServiceError>) -> Void

protocol VideoExportServiceProtocol {
    func export(
        for settings: VideoExportSettings,
        runCompletionIn queue: DispatchQueue,
        completion closure: @escaping VideoExportCompletionClosure
    )
}

final class VideoExportService {
    let logger: LoggerProtocol

    init(logger: LoggerProtocol) {
        self.logger = logger
    }

    private func getInternalQuality(from videoQuality: VideoExportQuality) -> String {
        switch videoQuality {
        case .low:
            AVAssetExportPresetLowQuality
        case .medium:
            AVAssetExportPresetMediumQuality
        case .high:
            AVAssetExportPresetHighestQuality
        }
    }

    private func createStichingExportSession(
        for inputUrls: [URL],
        quality: VideoExportQuality
    ) throws -> AVAssetExportSession {
        let composition = AVMutableComposition()
        guard
            let track = composition.addMutableTrack(
                withMediaType: .video,
                preferredTrackID: kCMPersistentTrackID_Invalid
            ) else {
            throw VideoExportServiceError.stitchingUnsupported
        }

        var insertTime = CMTime.zero

        logger.debug("Creating video from stiches: \(inputUrls.count)")

        for segmentURL in inputUrls {
            logger.debug("Stitching: \(segmentURL)")

            let asset = AVAsset(url: segmentURL)
            guard let assetTrack = asset.tracks(withMediaType: .video).first else { continue }

            do {
                let timeRange = CMTimeRangeMake(start: .zero, duration: asset.duration)
                try track.insertTimeRange(timeRange, of: assetTrack, at: insertTime)
                insertTime = CMTimeAdd(insertTime, asset.duration)

                logger.debug("Did complete stitching")
            } catch {
                throw VideoExportServiceError.stitchingFailed(error)
            }
        }

        let preset = getInternalQuality(from: quality)
        guard let session = AVAssetExportSession(asset: composition, presetName: preset) else {
            throw VideoExportServiceError.exportingFailed(nil)
        }

        logger.debug("Created multi file session")

        return session
    }

    private func createSingleInputExportSession(
        for inputUrl: URL,
        quality: VideoExportQuality
    ) throws -> AVAssetExportSession {
        let asset = AVAsset(url: inputUrl)
        let preset = getInternalQuality(from: quality)

        guard let session = AVAssetExportSession(asset: asset, presetName: preset) else {
            throw VideoExportServiceError.exportingFailed(nil)
        }

        logger.debug("Created single file session")

        return session
    }

    private func createExportSession(for settings: VideoExportSettings) throws -> AVAssetExportSession {
        if settings.inputUrls.count > 1 {
            return try createStichingExportSession(
                for: settings.inputUrls,
                quality: settings.quality
            )
        } else if let url = settings.inputUrls.first {
            return try createSingleInputExportSession(for: url, quality: settings.quality)
        } else {
            throw VideoExportServiceError.invalidInput
        }
    }

    private func completeExport(
        for session: AVAssetExportSession,
        runCompletionIn queue: DispatchQueue,
        completion closure: @escaping VideoExportCompletionClosure
    ) {
        session.exportAsynchronously { [weak self] in
            switch session.status {
            case .unknown:
                self?.logger.debug("Status: unknown")
            case .waiting:
                self?.logger.debug("Status: waiting")
            case .exporting:
                self?.logger.debug("Status: exporting")
            case .completed:
                self?.logger.debug("Export completed")

                dispatchInQueueWhenPossible(queue) {
                    closure(.success(()))
                }
            case .failed:
                self?.logger.error("Export failed")

                dispatchInQueueWhenPossible(queue) {
                    closure(.failure(.exportingFailed(session.error)))
                }
            case .cancelled:
                self?.logger.warning("Export cancelled")
            @unknown default:
                self?.logger.warning("Unhandled case")
            }
        }
    }
}

extension VideoExportService: VideoExportServiceProtocol {
    func export(
        for settings: VideoExportSettings,
        runCompletionIn queue: DispatchQueue,
        completion closure: @escaping VideoExportCompletionClosure
    ) {
        do {
            logger.debug("Starting export for: \(settings.inputUrls)")
            logger.debug("Output url: \(settings.outputUrl)")
            logger.debug("Quality: \(settings.quality)")

            let exportSession = try createExportSession(for: settings)

            exportSession.outputURL = settings.outputUrl

            exportSession.determineCompatibleFileTypes { [weak self] types in
                self?.logger.debug("Compatible types: \(types)")

                if types.isEmpty {
                    dispatchInQueueWhenPossible(queue) {
                        closure(.failure(.noCompatibleTypes))
                    }
                    return
                }

                exportSession.outputFileType = types.contains(.mov) ? .mov : types.first

                self?.completeExport(for: exportSession, runCompletionIn: queue, completion: closure)
            }
        } catch {
            if let knownError = error as? VideoExportServiceError {
                dispatchInQueueWhenPossible(queue) {
                    closure(.failure(knownError))
                }
            } else {
                dispatchInQueueWhenPossible(queue) {
                    closure(.failure(.internalError(error)))
                }
            }
        }
    }
}
