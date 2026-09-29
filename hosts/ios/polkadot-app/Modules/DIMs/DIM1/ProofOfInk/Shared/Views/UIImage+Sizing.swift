import UIKit

extension UIImage {
    /// Crops an image to a square based on the smallest dimension, centering the square within the original image.
    /// - Returns: A new image that is cropped to a square,
    /// or `nil` if an error occurs during the rendering process.
    func croppedToSquare() -> UIImage? {
        let contextSize: CGSize = size
        let minValue = min(contextSize.width, contextSize.height)
        let squareRect = CGRect(
            x: (contextSize.width - minValue) / 2,
            y: (contextSize.height - minValue) / 2,
            width: minValue,
            height: minValue
        )

        let format = UIGraphicsImageRendererFormat()
        format.scale = scale

        let renderer = UIGraphicsImageRenderer(size: CGSize(width: minValue, height: minValue), format: format)
        return renderer.image { _ in
            draw(at: CGPoint(x: -squareRect.origin.x, y: -squareRect.origin.y))
        }
    }

    /// Resizes the image to ensure its maximum dimension (width or height)
    /// does not exceed the specified maximum dimension.
    /// - Parameter maxDimension: The maximum allowed dimension (either width or height).
    /// - Returns: A resized image maintaining the original aspect ratio,
    /// or `nil` if an error occurs during the rendering process.
    func resize(toMaximumDimension maxDimension: CGFloat) -> UIImage {
        let aspectRatio = size.width / size.height
        let resizedSize =
            if size.width > size.height {
                CGSize(width: maxDimension, height: maxDimension / aspectRatio)
            } else {
                CGSize(width: maxDimension * aspectRatio, height: maxDimension)
            }

        let format = UIGraphicsImageRendererFormat()
        format.scale = scale

        let renderer = UIGraphicsImageRenderer(size: resizedSize, format: format)
        let resizedImage = renderer.image { _ in
            draw(in: CGRect(origin: .zero, size: resizedSize))
        }

        return resizedImage
    }
}
