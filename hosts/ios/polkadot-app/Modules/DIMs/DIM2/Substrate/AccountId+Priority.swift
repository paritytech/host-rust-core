import SubstrateSdk

extension AccountId {
    func precedes(_ accountId: AccountId) -> Bool {
        lexicographicallyPrecedes(accountId)
    }
}
