import UIKit

enum TattooCollectionViewLayout {
    static let maxTattooPerSection: Int = 3

    static func createLayout() -> UICollectionViewLayout {
        let layout = UICollectionViewCompositionalLayout { section, _ -> NSCollectionLayoutSection? in
            if section > 0 {
                Self.createTattooSection()
            } else {
                Self.createHeaderSection()
            }
        }

        return layout
    }

    private static func createHeaderSection() -> NSCollectionLayoutSection? {
        let itemLayoutSize = NSCollectionLayoutSize(
            widthDimension: .fractionalWidth(1.0),
            heightDimension: .estimated(44)
        )

        let item = NSCollectionLayoutItem(layoutSize: itemLayoutSize)

        let verticalGroupSize = NSCollectionLayoutSize(
            widthDimension: .fractionalWidth(1.0),
            heightDimension: .estimated(44)
        )

        let vertical = NSCollectionLayoutGroup.vertical(layoutSize: verticalGroupSize, subitems: [item])

        let section = NSCollectionLayoutSection(group: vertical)
        section.contentInsets = NSDirectionalEdgeInsets(top: 8, leading: 24, bottom: 12, trailing: 24)

        return section
    }

    private static func createTattooSection() -> NSCollectionLayoutSection? {
        let headerItemSize = NSCollectionLayoutSize(
            widthDimension: .fractionalWidth(1.0),
            heightDimension: .estimated(50)
        )

        let headerItem = NSCollectionLayoutItem(layoutSize: headerItemSize)

        let leadingItemLayoutSize = NSCollectionLayoutSize(
            widthDimension: .fractionalWidth(2.0 / 3.0),
            heightDimension: .fractionalHeight(1.0)
        )

        let leadingItem = NSCollectionLayoutItem(layoutSize: leadingItemLayoutSize)

        let secondaryItemLayoutsize = NSCollectionLayoutSize(
            widthDimension: .fractionalWidth(1.0),
            heightDimension: .fractionalHeight(0.5)
        )

        let secondaryItem = NSCollectionLayoutItem(layoutSize: secondaryItemLayoutsize)

        let verticalGroupSize = NSCollectionLayoutSize(
            widthDimension: .fractionalWidth(1.0 / 3.0),
            heightDimension: .fractionalHeight(1)
        )

        let verticalGroup = NSCollectionLayoutGroup.vertical(
            layoutSize: verticalGroupSize,
            subitems: [secondaryItem]
        )

        verticalGroup.interItemSpacing = .fixed(2)

        let horizontalGroupSize = NSCollectionLayoutSize(
            widthDimension: .fractionalWidth(1.0),
            heightDimension: .fractionalWidth(2.0 / 3.0)
        )

        let horizontalGroup = NSCollectionLayoutGroup.horizontal(
            layoutSize: horizontalGroupSize,
            subitems: [leadingItem, verticalGroup]
        )

        horizontalGroup.interItemSpacing = .fixed(2)

        let sectionGroup = NSCollectionLayoutGroup.vertical(
            layoutSize: .init(
                widthDimension: .fractionalWidth(1),
                heightDimension: .estimated(50)
            ),
            subitems: [headerItem, horizontalGroup]
        )

        sectionGroup.interItemSpacing = .fixed(12)

        let section = NSCollectionLayoutSection(group: sectionGroup)
        section.orthogonalScrollingBehavior = .none
        section.interGroupSpacing = 0
        section.contentInsets = NSDirectionalEdgeInsets(top: 12, leading: 8, bottom: 12, trailing: 8)

        return section
    }
}
