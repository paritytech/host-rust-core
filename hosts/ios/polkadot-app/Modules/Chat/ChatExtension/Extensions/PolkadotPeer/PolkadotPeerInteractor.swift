import Foundation
import AsyncExtensions
import AsyncAlgorithms
import Individuality

protocol PolkadotPeerInteracting: AnyObject {
    func setup() async
    func observeFullUsernameClaimed() -> AnyAsyncSequence<FullUsernameClaimedMessageDecoder.Content>
    func observePersonhoodRegistered() -> AnyAsyncSequence<PeoplePallet.PersonalId>
}

final class PolkadotPeerInteractor {
    private let flowState: DIMSSharedFlowStateProtocol

    init(flowState: DIMSSharedFlowStateProtocol) {
        self.flowState = flowState
    }
}

extension PolkadotPeerInteractor: PolkadotPeerInteracting {
    func setup() async {
        flowState.setup()
    }

    func observeFullUsernameClaimed() -> AnyAsyncSequence<FullUsernameClaimedMessageDecoder.Content> {
        flowState
            .personDataStore
            .observe()
            .compactMap { personData in
                guard
                    let registeredData = personData?.makeRegisteredData(),
                    let fullUsername = registeredData.fullUsername else {
                    return nil
                }

                return FullUsernameClaimedMessageDecoder.Content(
                    liteUsername: registeredData.liteUsername,
                    fullUsername: fullUsername
                )
            }
            .removeDuplicates()
            .eraseToAnyAsyncSequence()
    }

    func observePersonhoodRegistered() -> AnyAsyncSequence<PeoplePallet.PersonalId> {
        flowState
            .personDataStore
            .observe()
            .compactMap { personData in
                guard let registeredData = personData?.makeRegisteredData() else {
                    return nil
                }

                return registeredData.personId
            }
            .removeDuplicates()
            .eraseToAnyAsyncSequence()
    }
}
