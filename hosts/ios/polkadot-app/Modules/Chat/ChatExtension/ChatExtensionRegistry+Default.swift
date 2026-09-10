import Foundation
import Keystore_iOS
import Operation_iOS

extension ChatExtensionsRegistry {
    // swiftlint:disable:next function_parameter_count
    @MainActor static func createDefault(
        syncStateStore: DetermineStateSyncStore,
        personDataStore: DetermineStatePersonDataStore,
        syncService: DetermineStateSyncServicing,
        personhoodRegistrationService: PersonhoodRegistrationServicing,
        claimStatusStore: ClaimStatusStore,
        productBotProvider: ProductBotProviding,
        audioSessionManager: AudioSessionManaging
    ) -> ChatExtensionsRegistering {
        let storageFacade = UserDataStorageFacade.shared

        let reactionRepository = ChatReactionRepository(
            repository: AnyDataProviderRepository(
                storageFacade.createRepository(
                    filter: nil,
                    sortDescriptors: [],
                    mapper: AnyCoreDataMapper(ChatMessageReactionMapper())
                )
            )
        )

        let commonExtensions: [ChatExtending] = [
            ChatReactionExtension(reactionRepository: reactionRepository),
            CoinageTransferExtension(claimStatusStore: claimStatusStore)
        ]

        let dimsExtension = ChatExtensionsRegistry.createDimExtensions(
            syncStateStore: syncStateStore,
            personDataStore: personDataStore,
            syncService: syncService,
            personhoodRegistrationService: personhoodRegistrationService,
            audioSessionManager: audioSessionManager
        )

        let extensionStore = ChatExtensionStore(
            staticExtensions: commonExtensions + dimsExtension,
            productBotProvider: productBotProvider
        )

        let registry = ChatExtensionsRegistry(
            extensionStore: extensionStore,
            storageFacade: storageFacade,
            settingsManager: SettingsManager.shared
        )

        return registry
    }
}
