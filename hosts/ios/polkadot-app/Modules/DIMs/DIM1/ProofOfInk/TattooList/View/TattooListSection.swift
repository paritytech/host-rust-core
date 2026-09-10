import Foundation

enum TattooListSection {
    struct Tattoo {
        let viewModel: TattooListViewModel
        let index: Int
    }

    case header
    case collection(Tattoo)

    init(section: Int, viewModels: [TattooListViewModel]) {
        if section > 0 {
            self = .collection(.init(viewModel: viewModels[section - 1], index: section - 1))
        } else {
            self = .header
        }
    }

    var numberOfItems: Int {
        switch self {
        case .header:
            1
        case let .collection(collection):
            collection.viewModel.items.count + 1
        }
    }

    static func numberOfSections(for viewModels: [TattooListViewModel]) -> Int {
        1 + viewModels.count
    }
}
