enum DIM1BackgroundSyncState: Comparable {
    case none // < candidate.selected
    case photoSubmission // == candidate.allocation.initial + judgeId == nil
    case photoInReview // == candidate.allocation.initial + judgeId != nil
    case photoReviewed // == candidate.allocation.initDone
    case videoSubmission // == candidate.allocation.full + judgeId == nil
    case videoInReview // == candidate.allocation.full + judgeId != nil
    case videoReviewed // == candidate.proven
}
