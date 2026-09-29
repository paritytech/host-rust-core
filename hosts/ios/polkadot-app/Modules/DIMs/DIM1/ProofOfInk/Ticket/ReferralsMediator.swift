import Foundation
import Keystore_iOS
import SubstrateSdk
import KeyDerivation
import Individuality
import ChainRegistry

enum ReferralTicketStateError: Error {
    case ticketMismatch
    case ticketGenerationFailed(Error)
    case ticketSubmissionFailed(Error)
}

enum ReferralTicketState {
    case available
    case generating(personalId: PeoplePallet.PersonalId)
    case generated(URL)
    case inUse
    case unavailable
    case error(ReferralTicketStateError)
}

struct ReferralTicketKey: Codable {
    let seed: Data
    let publicKey: Data
    let privateKey: Data
}

protocol ReferralTicketStateDelegate: AnyObject {
    func didUpdate(with state: ReferralTicketState)
}

protocol ReferralsMediatorProtocol {
    func use(delegate: ReferralTicketStateDelegate)
    func requestReferralLink(for personalId: PeoplePallet.PersonalId)
    func dismissInUseVoucher()
    func didUpdate(
        person: ProofOfInkPallet.Person?,
        referralTicket: ProofOfInkPallet.ReferralTicket?
    )
}

final class ReferralsMediator {
    private enum Constants {
        static let keySeedEntropyLength = 32
    }

    private let logger: LoggerProtocol
    private let keystore: KeystoreProtocol
    private let entropyGenerator: EntropyGenerating
    private let keypairFactory: KeypairFactoryProtocol
    private let jsonDecoder: JSONDecoder
    private let jsonEncoder: JSONEncoder
    private let selectedWallet: MetaAccountModelProtocol
    private let chainRegistry: ChainRegistryProtocol
    private let settingsManager: SettingsManagerProtocol
    private let referralTicketService: ReferralTicketServicing
    private let referralLinkBuilder: ReferralLinkBuilderProtocol
    private var existingTicket: ProofOfInkPallet.ReferralTicket?
    private weak var delegate: ReferralTicketStateDelegate?
    private var currentState: ReferralTicketState = .unavailable {
        didSet {
            logger.debug("Did update state: \(currentState)")
            delegate?.didUpdate(with: currentState)
        }
    }

    init(
        keystore: KeystoreProtocol,
        selectedWallet: MetaAccountModelProtocol,
        chainRegistry: ChainRegistryProtocol = ChainRegistryFacade.sharedRegistry,
        entropyGenerator: EntropyGenerating = EntropyGenerator(),
        keypairFactory: KeypairFactoryProtocol = SR25519KeypairFactory(),
        settingsManager: SettingsManagerProtocol = SettingsManager.shared,
        referralTicketService: ReferralTicketServicing,
        referralLinkBuilder: ReferralLinkBuilderProtocol = ReferralLinkBuilder(),
        logger: LoggerProtocol = Logger.shared,
        jsonDecoder: JSONDecoder = JSONDecoder(),
        jsonEncoder: JSONEncoder = JSONEncoder()
    ) {
        self.keystore = keystore
        self.selectedWallet = selectedWallet
        self.chainRegistry = chainRegistry
        self.entropyGenerator = entropyGenerator
        self.keypairFactory = keypairFactory
        self.settingsManager = settingsManager
        self.referralTicketService = referralTicketService
        self.referralLinkBuilder = referralLinkBuilder
        self.logger = logger
        self.jsonDecoder = jsonDecoder
        self.jsonEncoder = jsonEncoder
    }
}

extension ReferralsMediator: ReferralsMediatorProtocol {
    func use(delegate: ReferralTicketStateDelegate) {
        self.delegate = delegate
    }

    func dismissInUseVoucher() {
        settingsManager.set(value: true, for: .voucherInUseDismissed)
        currentState = .unavailable
    }

    func requestReferralLink(for personalId: PeoplePallet.PersonalId) {
        if let existingTicket, let referral = referralLink(for: existingTicket, personalId: personalId) {
            currentState = .generated(referral)
            return
        }

        if existingTicket != nil {
            // a ticket created on another device and the user might want to cancel it
            currentState = .error(.ticketMismatch)
            return
        }

        currentState = .generating(personalId: personalId)
        do {
            let newTicket = try generateNewTicket()
            referralTicketService.submitNewReferral(
                ticket: newTicket,
                dispatchIn: .main
            ) { [weak self] result in
                guard let self else { return }
                switch result {
                case .success:
                    ()
                case let .failure(error):
                    currentState = .error(.ticketSubmissionFailed(error))
                }
            }
        } catch {
            currentState = .error(.ticketGenerationFailed(error))
        }
    }

    func didUpdate(
        person: ProofOfInkPallet.Person?,
        referralTicket: ProofOfInkPallet.ReferralTicket?
    ) {
        guard let person else {
            currentState = .unavailable
            return
        }

        guard person.pendingReferralRewards == 0 else {
            currentState = settingsManager.value(for: .voucherInUseDismissed) ? .unavailable : .inUse
            return
        }

        if !person.activeReferrals.isEmpty {
            currentState = settingsManager.value(for: .voucherInUseDismissed) ? .unavailable : .inUse
        }

        switch currentState {
        case .inUse,
             .unavailable:
            if person.activeReferrals.isEmpty {
                settingsManager.set(value: false, for: .voucherInUseDismissed)
                currentState = .available
            }
        default:
            break
        }

        guard self.existingTicket != referralTicket else { return }

        self.existingTicket = referralTicket

        guard
            let existingTicket,
            case let .generating(personalId) = currentState,
            let referral = referralLink(for: existingTicket, personalId: personalId) else {
            return
        }

        currentState = .generated(referral)
    }
}

private extension ReferralsMediator {
    func generateNewTicket() throws -> ProofOfInkPallet.ReferralTicket {
        let seed = try entropyGenerator.generateEntropy(of: Constants.keySeedEntropyLength).get()
        let keypair = try keypairFactory.createKeypairFromSeed(
            seed,
            chaincodeList: []
        )
        let referralTicketKey = ReferralTicketKey(
            seed: seed,
            publicKey: keypair.publicKey().rawData(),
            privateKey: keypair.privateKey().rawData()
        )
        let jsonData = try jsonEncoder.encode(referralTicketKey)
        try keystore.saveKey(jsonData, with: keystoreTag())
        return ProofOfInkPallet.ReferralTicket(ticket: referralTicketKey.publicKey)
    }

    func referralLink(
        for existingTicket: ProofOfInkPallet.ReferralTicket,
        personalId: PeoplePallet.PersonalId
    ) -> URL? {
        guard let currentTicket = currentTicket(), currentTicket.publicKey == existingTicket.ticket else { return nil }
        return referralLinkBuilder.buildReferralLink(ticket: currentTicket, personalId: personalId)
    }

    func currentTicket() -> ReferralTicketKey? {
        guard let keyPairData = try? keystore.fetchKey(for: keystoreTag()) else {
            return nil
        }
        do {
            return try jsonDecoder.decode(ReferralTicketKey.self, from: keyPairData)
        } catch {
            logger.error("Failed to decode ReferralTicketKey: \(error)")
            return nil
        }
    }

    func keystoreTag() -> String {
        guard let peopleChain = chainRegistry.getChain(for: AppConfig.Chains.usernameChain),
              let accountId = try? selectedWallet.fetchAccount(for: peopleChain).accountId
        else { return "" }
        return KeystoreTag.referralTicketTag(accountId)
    }

    func clearTicket() {
        try? keystore.deleteKeyIfExists(for: keystoreTag())
    }
}
