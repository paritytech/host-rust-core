import UIKit
import UIKit_iOS

extension GameVideoPlayersView {
    final class GridView: UIStackView {
        private var placeholderViews = [UIView]()

        override init(frame: CGRect) {
            super.init(frame: frame)
            setupLayout()
        }

        @available(*, unavailable)
        required init(coder _: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }
    }
}

extension GameVideoPlayersView.GridView {
    func setItemsViews(_ viewsWithIndices: [(Int, GameVideoPlayerItemView)]) {
        for (index, itemView) in viewsWithIndices {
            guard index < placeholderViews.count else {
                continue
            }
            itemView.snp.remakeConstraints {
                $0.edges.equalTo(placeholderViews[index].snp.edges)
            }
        }
    }
}

private extension GameVideoPlayersView.GridView {
    enum Constants {
        static let rows = 3
        static let columns = 2
    }

    func setupLayout() {
        axis = .vertical
        distribution = .fillEqually
        spacing = 8

        snp.makeConstraints {
            $0.height.equalTo(snp.width)
                .multipliedBy(
                    CGFloat(Constants.rows) / CGFloat(Constants.columns)
                )
                .priority(.init(999))
        }

        addArrangedViews()
    }

    func addArrangedViews() {
        for _ in 0 ..< Constants.rows {
            let rowStack = UIStackView()
            rowStack.axis = .horizontal
            rowStack.distribution = .fillEqually
            rowStack.spacing = 8

            for _ in 0 ..< Constants.columns {
                let view = UIView()
                rowStack.addArrangedSubview(view)
                placeholderViews.append(view)
            }

            addArrangedSubview(rowStack)
        }
    }
}
