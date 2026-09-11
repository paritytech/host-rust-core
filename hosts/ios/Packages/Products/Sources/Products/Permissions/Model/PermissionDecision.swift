import Foundation

/// Outcome of a permission prompt.
public enum PermissionDecision: Sendable {
    case allowAlways
    case allowOnce
    case deny
}
