import Foundation

enum TattooListRow {
    struct Tattoo {
        let item: TattooListViewModel.Item
        let collectionIndex: Int
    }

    struct Metadata {
        let item: TattooSectionMetadata
        let collectionIndex: Int
    }

    case header
    case metadata(Metadata)
    case tattoo(Tattoo)

    init(indexPath: IndexPath, viewModels: [TattooListViewModel]) {
        let section = TattooListSection(section: indexPath.section, viewModels: viewModels)

        switch section {
        case .header:
            self = .header
        case let .collection(collection):
            if indexPath.row == 0 {
                self = .metadata(.init(
                    item: collection.viewModel.metadata,
                    collectionIndex: collection.index
                ))
            } else {
                self = .tattoo(.init(
                    item: collection.viewModel.items[indexPath.row - 1],
                    collectionIndex: collection.index
                ))
            }
        }
    }
}
