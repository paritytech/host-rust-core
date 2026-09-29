import UIKit
import AVFoundation

protocol PhotoCompressionServising: AnyObject {
    func compressPhoto(_ photo: AVCapturePhoto) -> Data?
}

final class PhotoCompressionService: PhotoCompressionServising {
    private enum Constants {
        static let sizeLimitBytes: Int = 1_000 * 1_000
        static let minimumCompressionQuality: CGFloat = 0.6
        static let maximumDimension: CGFloat = 2_500.0
    }

    func compressPhoto(_ photo: AVCapturePhoto) -> Data? {
        guard let imageData = photo.fileDataRepresentation(),
              var image = UIImage(data: imageData) else { return nil }

        var compressionQuality: CGFloat = 1.0
        var finalImageData: Data?

        image = image.croppedToSquare() ?? image

        if max(image.size.width, image.size.height) > Constants.maximumDimension {
            image = image.resize(toMaximumDimension: Constants.maximumDimension)
        }

        repeat {
            finalImageData = image.jpegData(compressionQuality: compressionQuality)
            compressionQuality -= 0.1
        } while (finalImageData?.count ?? 0 >= Constants.sizeLimitBytes) && compressionQuality > Constants
            .minimumCompressionQuality

        return finalImageData
    }
}
