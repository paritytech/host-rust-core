import Foundation

public struct ProductPage: Sendable {
    public let host: ProductHost
    public let page: String?

    public init(host: ProductHost, page: String? = nil) {
        self.host = host
        self.page = page
    }
}

extension ProductPage {
    static func fromUrl(_ url: URL, tld: String) -> ProductPage? {
        guard let host = ProductHost.fromUrl(url, tld: tld) else {
            return nil
        }

        return ProductPage(host: host, page: relativePart(of: url))
    }

    static func fromNavigationDestination(_ dest: String, tld: String) -> ProductPage? {
        guard let url = URL(string: dest), url.host() != nil else {
            return ProductHost.parse(dest, tld: tld).map { ProductPage(host: $0) }
        }

        return ProductPage.fromUrl(url, tld: tld)
    }

    public func applied(to url: URL) -> URL {
        guard
            let page,
            !page.isEmpty,
            var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        else {
            return url
        }

        components.path = ""
        components.query = nil
        components.fragment = nil

        guard let hostURL = components.string else {
            return url
        }

        let relative = page.hasPrefix("/") ? page : "/" + page

        return URL(string: hostURL + relative) ?? url
    }
}

private extension ProductPage {
    static func relativePart(of url: URL) -> String? {
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return nil
        }

        let full = components.string
        components.path = ""
        components.query = nil
        components.fragment = nil
        let base = components.string

        guard let full, let base, full.hasPrefix(base) else { return nil }

        let relative = String(full.dropFirst(base.count))

        return relative.isEmpty || relative == "/" ? nil : relative
    }
}
