import Foundation
import UIKit_iOS

protocol AppAdaptiveDesignable: AdaptiveDesignable {}

extension AppAdaptiveDesignable {
    var baseDesignSize: CGSize {
        CGSize(width: 390, height: 844)
    }
}
