import Foundation
import SubstrateSdk
import PolkadotUI
import SwiftUI

final class GameResultsMessageDecoder {
    let identifier = MessageDecoderIdentifier.gameResults

    let gameVoteRepositoryFactory: GameVoteRepositoryMaking

    init(
        gameVoteRepositoryFactory: GameVoteRepositoryMaking,
    ) {
        self.gameVoteRepositoryFactory = gameVoteRepositoryFactory
    }
}

extension GameResultsMessageDecoder: ChatMessageCustomDecoding {
    func decode(data: Data, context _: ChatMessageDecodingContext) -> [any HashableContentConfiguration] {
        do {
            let decoder = try ScaleDecoder(data: data)
            let result = try GameResult(scaleDecoder: decoder)
            let config = ChatSystemMessageConfiguration.gameResults(
                gameDate: result.gameDate,
                state: result.viewStatus,
                personhoodProgress: result.viewPersonhoodProgress,
                showChat: result.hasVotes,
                avatarProvider: { [self] in
                    await avatarProvider(result.index)
                },
                action: { [result] in
                    UIApplication.shared.open(AppConfig.DeepLink.players(
                        game: result.index,
                        gameDate: result.gameDate
                    ))
                }
            )
            return [config]
        } catch {
            return []
        }
    }

    func previewString(data: Data) -> String {
        do {
            let decoder = try ScaleDecoder(data: data)
            let result = try GameResult(scaleDecoder: decoder)

            let viewModel = GameResultsViewModel(
                gameDate: result.gameDate,
                status: result.viewStatus,
                personhoodProgress: result.viewPersonhoodProgress,
                shouldShowAction: false // we dont care about the action here as we need just the status messages
            )

            let statusMessage = viewModel.statusMessage()
            guard let additionalMessage = viewModel.additionalMessage() else {
                return statusMessage
            }
            return [statusMessage, additionalMessage]
                .joined(separator: " ")
        } catch {
            return ""
        }
    }
}

private extension GameResultsMessageDecoder {
    func avatarProvider(_ gameIndex: UInt32) async -> [AvatarViewModel] {
        let allVotes = try? await gameVoteRepositoryFactory.repository(forGame: gameIndex)
            .fetchAllOperation(with: .init())
            .asyncExecute()
        guard let allVotes else {
            return []
        }

        let avatars: [AvatarViewModel] = allVotes.map {
            guard
                let image = $0.previewImageData.flatMap({ UIImage(data: $0) })
            else {
                let username = UsernameGenerator().generate(from: $0.accountId)

                return AvatarViewModel.colored(
                    text: String(username.prefix(1)),
                    colorSeed: $0.accountId.toHex()
                )
            }
            return AvatarViewModel.image(image)
        }

        return avatars
    }
}

// MARK: - Content

extension GameResultsMessageDecoder {
    struct GameResult: ScaleCodable {
        let index: UInt32
        let gameDate: Date
        let gamesLeft: Int
        let state: State
        let personhoodState: PersonhoodState
        let hasVotes: Bool

        var identifier: String {
            "\(index)"
        }

        init(
            index: UInt32,
            gameDate: Date,
            gamesLeft: Int,
            state: State,
            personhoodState: PersonhoodState,
            hasVotes: Bool,
        ) {
            self.index = index
            self.gameDate = gameDate
            self.gamesLeft = gamesLeft
            self.state = state
            self.personhoodState = personhoodState
            self.hasVotes = hasVotes
        }

        func encode(scaleEncoder: any ScaleEncoding) throws {
            try index.encode(scaleEncoder: scaleEncoder)
            try gameDate.ISO8601Format().encode(scaleEncoder: scaleEncoder)
            try UInt32(gamesLeft).encode(scaleEncoder: scaleEncoder)
            try state.encode(scaleEncoder: scaleEncoder)
            try personhoodState.encode(scaleEncoder: scaleEncoder)
            try hasVotes.encode(scaleEncoder: scaleEncoder)
        }

        init(scaleDecoder: any ScaleDecoding) throws {
            index = try UInt32(scaleDecoder: scaleDecoder)
            let dateString = try String(scaleDecoder: scaleDecoder)
            gameDate = ISO8601DateFormatter().date(from: dateString)!

            gamesLeft = try Int(UInt32(scaleDecoder: scaleDecoder))
            state = try State(scaleDecoder: scaleDecoder)
            personhoodState = try PersonhoodState(scaleDecoder: scaleDecoder)
            hasVotes = try Bool(scaleDecoder: scaleDecoder)
        }
    }
}

extension GameResultsMessageDecoder.GameResult {
    enum State: ScaleCodable {
        case pending
        case success
        case failure

        init(scaleDecoder: any ScaleDecoding) throws {
            let val = try UInt8(scaleDecoder: scaleDecoder)
            switch val {
            case 0:
                self = .pending
            case 1:
                self = .success
            case 2:
                self = .failure
            default:
                throw ScaleDecoderError.outOfBounds
            }
        }

        func encode(scaleEncoder: any ScaleEncoding) throws {
            let value: UInt8 =
                switch self {
                case .pending:
                    0
                case .success:
                    1
                case .failure:
                    2
                }

            try value.encode(scaleEncoder: scaleEncoder)
        }
    }

    enum PersonhoodState: ScaleCodable {
        case playing(suspended: Bool)
        case externallyRecognized
        case reachedPersonhood
        case unknown

        init(scaleDecoder: any ScaleDecoding) throws {
            let val = try UInt8(scaleDecoder: scaleDecoder)
            switch val {
            case 0:
                self = .playing(suspended: false)
            case 1:
                self = .playing(suspended: true)
            case 2:
                self = .externallyRecognized
            case 3:
                self = .reachedPersonhood
            case 4:
                self = .unknown
            default:
                throw ScaleDecoderError.outOfBounds
            }
        }

        func encode(scaleEncoder: any ScaleEncoding) throws {
            let value: UInt8 =
                switch self {
                case .playing(suspended: false):
                    0
                case .playing(suspended: true):
                    1
                case .externallyRecognized:
                    2
                case .reachedPersonhood:
                    3
                case .unknown:
                    4
                }

            try value.encode(scaleEncoder: scaleEncoder)
        }
    }
}

private extension GameResultsMessageDecoder.GameResult {
    var viewStatus: GameResultStatus {
        switch state {
        case .failure: .failed
        case .pending: .pending
        case .success: .success
        }
    }

    var viewPersonhoodProgress: PolkadotUI.GamePersonhoodProgress {
        switch personhoodState {
        case let .playing(suspended): .playing(gamesLeft: gamesLeft, suspended: suspended)
        case .externallyRecognized: .externallyRecognized
        case .reachedPersonhood: .reachedPersonhood
        case .unknown: .unknown
        }
    }
}
