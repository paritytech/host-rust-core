import Foundation

protocol URLSessionProtocol {
    func dataTask(with url: URL, completionHandler: @escaping @Sendable (Data?, URLResponse?, Error?) -> Void)
        -> URLSessionDataTask
}

extension URLSession: URLSessionProtocol {}

extension URLSession {
    static func videoStreamingSession() -> URLSession {
        let cache = URLCache(
            memoryCapacity: 100 * 1_024 * 1_024,
            diskCapacity: 400 * 1_024 * 1_024,
            diskPath: nil
        )
        let configuration = URLSessionConfiguration.default
        configuration.requestCachePolicy = .returnCacheDataElseLoad
        configuration.urlCache = cache
        return URLSession(configuration: configuration)
    }
}
