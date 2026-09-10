import AVFoundation
import UIKit
internal import SnapKit

public struct ProofOfInkVotingViewModel {
    public enum EvidenceType {
        case photo(ChatMessageMediaPreviewProviding?)
        case video(AVPlayerItem?, preview: ChatMessageMediaPreviewProviding?)
    }

    public let tattooProvider: ChatMessageMediaPreviewProviding?
    public let evidence: EvidenceType
    public let title: String
    public let subtitle: String
    public let votingAvailable: Bool
    public let minimumWatchTime: Int?

    public init(
        tattooProvider: ChatMessageMediaPreviewProviding?,
        evidence: EvidenceType,
        title: String,
        subtitle: String,
        votingAvailable: Bool,
        minimumWatchTime: Int? = nil
    ) {
        self.tattooProvider = tattooProvider
        self.evidence = evidence
        self.title = title
        self.subtitle = subtitle
        self.votingAvailable = votingAvailable
        self.minimumWatchTime = minimumWatchTime
    }
}

#if DEBUG
    #Preview("Photo") {
        let model = ProofOfInkVotingViewModel(
            tattooProvider: StaticImagePreviewProvider(image: .actions),
            evidence: .photo(StaticImagePreviewProvider(image: .checkmark)),
            title: "Documentation Photo",
            subtitle: "Mob Rule Case #42",
            votingAvailable: true
        )
        let vc = UIViewController()
        let view = ProofOfInkVotingLayout()
        vc.view.addSubview(view)
        view.snp.makeConstraints { $0.edges.equalToSuperview() }
        view.bind(viewModel: model)
        return vc
    }

    #Preview("Video") {
        let sampleURL =
            URL(
                string: "https://devstreaming-cdn.apple.com/videos/streaming/examples/bipbop_4x3/bipbop_4x3_variant.m3u8"
            )!
        let playerItem = AVPlayerItem(url: sampleURL)

        let model = ProofOfInkVotingViewModel(
            tattooProvider: StaticImagePreviewProvider(image: .actions),
            evidence: .video(playerItem, preview: StaticImagePreviewProvider(image: .remove)),
            title: "Documentation Video",
            subtitle: "Mob Rule Case #23",
            votingAvailable: true
        )

        let vc = UIViewController()
        let view = ProofOfInkVotingLayout()
        view.setParentViewController(vc)
        vc.view.addSubview(view)
        view.snp.makeConstraints { $0.edges.equalToSuperview() }
        view.bind(viewModel: model)
        return vc
    }

#endif
