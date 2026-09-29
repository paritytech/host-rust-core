import Foundation
import AVFoundation

typealias IPFSManifest = EvidenceSubmission.ChunksInfo

extension IPFSManifest {
    var contentType: String {
        let pathExtension = (path as NSString).pathExtension.lowercased()
        switch pathExtension {
        case "mp4":
            return AVFileType.mp4.rawValue
        case "mov":
            return AVFileType.mov.rawValue
        case "m4v":
            return AVFileType.m4v.rawValue
        default:
            return AVFileType.mp4.rawValue
        }
    }
}
