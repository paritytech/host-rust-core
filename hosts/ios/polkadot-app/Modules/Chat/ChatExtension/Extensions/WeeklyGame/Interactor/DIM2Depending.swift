import Foundation

protocol DIM2Depending {
    var sharedState: DIM2SharedFlowStateProtocol { get }

    func setup()
}

final class DIM2Dependencies {
    let dim2SharedState: DIM2SharedFlowStateProtocol
    let dimsSharedState: DIMSSharedFlowStateProtocol

    init(dim2SharedState: DIM2SharedFlowStateProtocol, dimsSharedState: DIMSSharedFlowStateProtocol) {
        self.dim2SharedState = dim2SharedState
        self.dimsSharedState = dimsSharedState
    }
}

extension DIM2Dependencies: DIM2Depending {
    var sharedState: DIM2SharedFlowStateProtocol {
        dim2SharedState
    }

    func setup() {
        dimsSharedState.setup()
        dim2SharedState.setup()
    }
}
