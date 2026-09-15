import Foundation

/// Protocol that serves as the interface to store and retrieve objects from `UserDefaults`
protocol DefaultsStoring: AnyObject {
    /// Returns the object associated with the specified key.
    /// - Parameter key: A key in the current user‘s defaults database.
    subscript(_: DefaultsKey) -> Any? { get set }
    /// Returns `Boolean` value associated with the specified key.
    /// - Parameter key: A key in the current users defaults database.
    subscript(bool _: DefaultsKey) -> Bool { get set }
}

/// Supported values in `UserDefaults`
enum DefaultsKey: String, CustomStringConvertible {
    case isVideoConfirmed

    var description: String { rawValue }
}

extension UserDefaults: DefaultsStoring {
    subscript(key: DefaultsKey) -> Any? {
        get { value(forKey: key.description) }
        set { set(newValue, forKey: key.description) }
    }

    subscript(bool key: DefaultsKey) -> Bool {
        get { bool(forKey: key.description) }
        set { set(newValue, forKey: key.description) }
    }
}
