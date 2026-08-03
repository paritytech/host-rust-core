import Foundation

/// Bundled truapi lockdown container built from `container/src/index.ts`.
/// Rebuild with `npm run build` inside `container/` (or `scripts/rebuild.sh`).
public enum ContainerScriptBundle {
    public enum LoadError: Error, LocalizedError {
        case resourceNotFound

        public var errorDescription: String? {
            switch self {
            case .resourceNotFound:
                "truapi-container.js not found in TrUAPI package bundle"
            }
        }
    }

    public static func load() throws -> String {
        guard let url = Bundle.module.url(forResource: "truapi-container", withExtension: "js") else {
            throw LoadError.resourceNotFound
        }

        return try String(contentsOf: url, encoding: .utf8)
    }
}
