import Foundation
import SubstrateSdk
import Individuality
import KeyDerivation
import ChainRegistry

extension People {
    struct RegisteredData: Hashable {
        let mobRuleAlias: PeoplePallet.ContextualAlias
        let scoreAlias: PeoplePallet.ContextualAlias
        let resourcesAlias: PeoplePallet.ContextualAlias
        let personId: ProofOfInkPallet.PersonalId
        let source: RegisteredSource
        let liteUsername: Username
        let fullUsername: Username?
    }

    enum RegisteredSource: Hashable {
        case proofOfInk(ProofOfInkPallet.Person)
        case game
    }
}

extension People.RegisteredData {
    var isUsernameUpgradeAvailable: Bool {
        fullUsername == nil
    }
}

extension People.RegisteredSource {
    var isGameRecognizedPerson: Bool {
        self == .game
    }

    var isNotGameRecognizedPerson: Bool {
        !isGameRecognizedPerson
    }
}

enum GameAccountFactory {
    static func makeAccount(
        chain: ChainModel,
        registeredSource: People.RegisteredSource?
    ) -> AccountProtocol? {
        guard let wallet = try? makeWallet(for: registeredSource) else {
            return nil
        }
        return try? wallet.fetchAccount(for: chain)
    }

    static func makeWallet(for registeredSource: People.RegisteredSource?) throws -> WalletManaging {
        let walletRepo: WalletManagerRepositoryProtocol = .shared
        switch registeredSource {
        case .proofOfInk:
            return try walletRepo.scoreAlias()
        case .game,
             nil:
            return try walletRepo.candidate()
        }
    }

    static func makeWalletKeyId(for registeredSource: People.RegisteredSource?) throws -> String {
        let tld = try DotNsTldProviderFacade.shared.currentTldOrError()
        switch registeredSource {
        case .proofOfInk:
            return WalletDerivationPath.score(for: tld)
        case .game,
             nil:
            return WalletDerivationPath.candidate(for: tld)
        }
    }
}
