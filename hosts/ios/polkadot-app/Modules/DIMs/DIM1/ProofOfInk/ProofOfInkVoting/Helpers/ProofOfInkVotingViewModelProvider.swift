import Foundation
import AVFoundation
import BulletinChain
import Individuality
import PolkadotUI

protocol ProofOfInkVotingViewModelProviding {
    func provideModel() -> ProofOfInkVotingViewModel
}

final class ProofOfInkVotingViewModelProvider {
    let statement: MobRulePallet.Statement.ProofOfInk
    let caseIdnex: MobRulePallet.CaseIndex
    let familyId: ProofOfInkPallet.FamilyId
    let votingAvailable: Bool
    let hexConverter: HexToCIDConverting

    init(
        statement: MobRulePallet.Statement.ProofOfInk,
        caseIdnex: MobRulePallet.CaseIndex,
        familyId: ProofOfInkPallet.FamilyId,
        votingAvailable: Bool,
        hexConverter: HexToCIDConverting = HexToCIDConverter()
    ) {
        self.statement = statement
        self.caseIdnex = caseIdnex
        self.familyId = familyId
        self.votingAvailable = votingAvailable
        self.hexConverter = hexConverter
    }
}

extension ProofOfInkVotingViewModelProvider: ProofOfInkVotingViewModelProviding {
    func provideModel() -> ProofOfInkVotingViewModel {
        let tattooProvider = createTattooProvider()
        let index = Int(caseIdnex)

        if statement.probableAcceptable {
            return .photo(
                tattooProvider: tattooProvider,
                previewProvider: createPhotoProvider(),
                index: index,
                votingAvailable: votingAvailable
            )
        } else {
            let videoProvider = createVideoProvider()
            return .video(
                tattooProvider: tattooProvider,
                previewProvider: videoProvider,
                videoItem: videoProvider?.playerItem(),
                index: index,
                votingAvailable: votingAvailable
            )
        }
    }
}

private extension ProofOfInkVotingViewModelProvider {
    func createTattooProvider() -> any ChatMessageMediaPreviewProviding {
        TattooChatMessageMediaPreviewProvider(
            design: statement.design,
            familyId: familyId
        )
    }

    func mainfestURL() -> URL? {
        let hash = statement.evidence.toHexString()
        return hexConverter.convertToIPFSURL(fileHash: hash, codec: .json)
    }

    func createPhotoProvider() -> (any ChatMessageMediaPreviewProviding)? {
        guard let url = mainfestURL() else {
            return nil
        }
        return PhotoEvidenceMediator(manifestURL: url)
    }

    func createVideoProvider() -> (ChatMessageMediaPreviewProviding & AVPlayerItemProvider)? {
        guard let url = mainfestURL() else {
            return nil
        }
        return IPFSVideoSource(manifestURL: url)
    }
}
