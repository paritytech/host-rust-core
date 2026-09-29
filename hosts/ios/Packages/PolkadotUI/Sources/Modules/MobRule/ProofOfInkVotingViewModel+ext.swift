import Foundation
import AVFoundation

public extension ProofOfInkVotingViewModel {
    static func video(
        tattooProvider: (any ChatMessageMediaPreviewProviding)?,
        previewProvider: (any ChatMessageMediaPreviewProviding)?,
        videoItem: AVPlayerItem?,
        index: Int,
        votingAvailable: Bool
    ) -> Self {
        .init(
            tattooProvider: tattooProvider,
            evidence: .video(videoItem, preview: previewProvider),
            title: String(localized: .chatEvidenceMessageVideo),
            subtitle: String(localized: .mobRuleCaseNumber(index: index)),
            votingAvailable: votingAvailable
        )
    }

    static func photo(
        tattooProvider: (any ChatMessageMediaPreviewProviding)?,
        previewProvider: (any ChatMessageMediaPreviewProviding)?,
        index: Int,
        votingAvailable: Bool
    ) -> Self {
        .init(
            tattooProvider: tattooProvider,
            evidence: .photo(previewProvider),
            title: String(localized: .chatEvidenceMessagePhoto),
            subtitle: String(localized: .mobRuleCaseNumber(index: index)),
            votingAvailable: votingAvailable
        )
    }
}
