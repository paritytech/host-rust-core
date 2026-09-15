import UIKit

final class TattooVideoPreviewInteractor {
    weak var presenter: TattooVideoPreviewInteractorOutputProtocol?

    let videoExportingService: VideoExportServiceProtocol
    let fileManager: EvidenceFileManaging
    let recordings: [URL]
    private let stateMediator: ProvideEvidenceStateMediating

    init(
        videoExportingService: VideoExportServiceProtocol,
        fileManager: EvidenceFileManaging,
        recordings: [URL],
        stateMediator: ProvideEvidenceStateMediating
    ) {
        self.videoExportingService = videoExportingService
        self.fileManager = fileManager
        self.recordings = recordings
        self.stateMediator = stateMediator
    }
}

extension TattooVideoPreviewInteractor: TattooVideoPreviewInteractorInputProtocol {
    func setup() {
        do {
            if let existingVideoExport = try fileManager.existingVideoExport() {
                MainActor.assumeIsolated {
                    presenter?.didReceive(videoUrl: existingVideoExport)
                }
                return
            }
            let exportUrl = try fileManager.prepareVideoExport()
            let settings = VideoExportSettings(inputUrls: recordings, outputUrl: exportUrl, quality: .medium)
            videoExportingService.export(
                for: settings,
                runCompletionIn: .main
            ) { [weak self] result in
                MainActor.assumeIsolated {
                    switch result {
                    case .success:
                        self?.presenter?.didReceive(videoUrl: exportUrl)
                    case let .failure(error):
                        self?.presenter?.didReceive(error: .videoExport(error))
                    }
                }
            }
        } catch {
            MainActor.assumeIsolated {
                presenter?.didReceive(error: .videoFile(error))
            }
        }
    }

    func confirmVideo() {
        stateMediator.confirmVideo()
    }
}
