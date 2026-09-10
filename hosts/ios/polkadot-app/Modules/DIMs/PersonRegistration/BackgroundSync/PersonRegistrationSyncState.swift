enum PersonRegistrationSyncState: Comparable {
    case personRegistered // == personId != nil
    case personAdded // == member key exists in ring
    case aliasAssigned // == alias.isRelevant == true
}
