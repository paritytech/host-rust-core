import UIKit

enum TattooFamilyDetailsCollectionLayout {
    static func createLayout() -> UICollectionViewLayout {
        let layout = UICollectionViewCompositionalLayout { sectionIndex, layoutEnvironment
            -> NSCollectionLayoutSection? in
            switch sectionIndex {
            case 0:
                createHeaderSection()
            case 1:
                createTattooGridSection(layoutEnvironment: layoutEnvironment)
            default:
                nil
            }
        }
        return layout
    }
}

private extension TattooFamilyDetailsCollectionLayout {
    private enum Constants {
        static let headerInsets = NSDirectionalEdgeInsets(top: 0, leading: 24, bottom: 32, trailing: 24)
        static let headerSize = NSCollectionLayoutDimension.estimated(100)

        static let horizontalPadding: CGFloat = 8
        static let interItemSpacing: CGFloat = 4
        static let numberOfItemsPerRow: Int = 2
    }

    static func createHeaderSection() -> NSCollectionLayoutSection? {
        let itemSize = NSCollectionLayoutSize(
            widthDimension: .fractionalWidth(1.0),
            heightDimension: Constants.headerSize
        )
        let item = NSCollectionLayoutItem(layoutSize: itemSize)
        let group = NSCollectionLayoutGroup.vertical(layoutSize: itemSize, subitems: [item])
        let section = NSCollectionLayoutSection(group: group)
        section.contentInsets = Constants.headerInsets
        return section
    }

    static func createTattooGridSection(
        layoutEnvironment: NSCollectionLayoutEnvironment
    ) -> NSCollectionLayoutSection? {
        let containerWidth = layoutEnvironment.container.effectiveContentSize.width - Constants.horizontalPadding * 2

        let availableWidthForItems = containerWidth - Constants.interItemSpacing
            * CGFloat(Constants.numberOfItemsPerRow - 1)

        let itemWidth = availableWidthForItems / CGFloat(Constants.numberOfItemsPerRow)
        let itemSize = NSCollectionLayoutSize(
            widthDimension: .absolute(itemWidth),
            heightDimension: .absolute(itemWidth)
        )

        let item = NSCollectionLayoutItem(layoutSize: itemSize)
        let group = NSCollectionLayoutGroup.horizontal(
            layoutSize: NSCollectionLayoutSize(
                widthDimension: .fractionalWidth(1.0),
                heightDimension: .absolute(itemWidth)
            ),
            repeatingSubitem: item,
            count: Constants.numberOfItemsPerRow
        )
        group.interItemSpacing = .fixed(Constants.interItemSpacing)

        let section = NSCollectionLayoutSection(group: group)
        section.contentInsets = NSDirectionalEdgeInsets(
            top: 0,
            leading: Constants.horizontalPadding,
            bottom: 0,
            trailing: Constants.horizontalPadding
        )

        section.interGroupSpacing = Constants.interItemSpacing

        return section
    }
}
