import Foundation
import ChainRegistry

// TODO: Get rid of privacy voucher at all once migrated to Coinage
enum PrivacyVoucherFacade {
    private static var _statusSynchronizer: PrivacyVoucherStatusSynchronizing?
    private static var storeManagers = [PrivacyVoucherType: PrivacyVoucherStoreManaging]()
    private static var indexSynchronizers = [PrivacyVoucherType: PrivacyVoucherIndexSynchronizing]()

    static var statusSynchronizer: PrivacyVoucherStatusSynchronizing? {
        if let synchronizer = _statusSynchronizer {
            return synchronizer
        }

        let chainRegistry = ChainRegistryFacade.sharedRegistry

        guard
            let connection = chainRegistry.getConnection(for: AppConfig.Chains.usernameChain),
            let runtimeProvider = chainRegistry.getRuntimeProvider(for: AppConfig.Chains.usernameChain)
        else {
            return nil
        }

        _statusSynchronizer = PrivacyVoucherStatusSynchronizer(
            connection: connection,
            runtimeProvider: runtimeProvider
        )

        return _statusSynchronizer
    }

    static func storeManager(for type: PrivacyVoucherType) -> PrivacyVoucherStoreManaging? {
        if let manager = storeManagers[type] {
            return manager
        }

        guard let indexSynchronizer = indexSynchronizer(for: type) else {
            return nil
        }

        let manager = PrivacyVoucherStoreManager(indexSynchronizer: indexSynchronizer)

        storeManagers[type] = manager

        return manager
    }

    private static func indexSynchronizer(for type: PrivacyVoucherType) -> PrivacyVoucherIndexSynchronizing? {
        if let synchronizer = indexSynchronizers[type] {
            return synchronizer
        }

        let chainRegistry = ChainRegistryFacade.sharedRegistry

        guard
            let connection = chainRegistry.getConnection(for: AppConfig.Chains.usernameChain),
            let runtimeProvider = chainRegistry.getRuntimeProvider(for: AppConfig.Chains.usernameChain)
        else {
            return nil
        }

        let synchronizer = PrivacyVoucherIndexSynchronizer(
            type: type,
            connection: connection,
            runtimeProvider: runtimeProvider
        )

        indexSynchronizers[type] = synchronizer

        return synchronizer
    }
}
