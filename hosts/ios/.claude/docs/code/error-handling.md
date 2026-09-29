# Error Handling

## Core Rules

1. **Throw errors instead of force unwrapping** — prefer `guard let x = value else { throw SomeError }` over `value!`
2. **Never silently fallback** — if decoding fails, throw; don't fall back to raw bytes or defaults
3. **Use `ErrorPresentable` protocol** for user-facing error display
4. **Typed error enums** — define specific error types per domain, not generic strings

## Error Presentation Pattern

```swift
// Common/Protocols/ErrorPresentable.swift
protocol ErrorPresentable {
    func present(error: Error, from view: UIViewController)
}
```

- Interactor throws typed errors
- Presenter catches and maps to user-facing messages
- ViewController displays via ErrorPresentable

## Patterns

### Do
```swift
guard let decoded = try? decoder.decode(Model.self, from: data) else {
    throw DecodingError.invalidData
}
```

### Don't
```swift
// Force unwrap
let decoded = try! decoder.decode(Model.self, from: data)

// Silent fallback
let decoded = try? decoder.decode(Model.self, from: data) ?? defaultValue
```

## Logging

- Use `SwiftyBeaver` for logging, not `print` or `NSLog`
- Log at appropriate levels: error for failures, warning for recoverable issues, info for state changes, debug for development
- Never log PII (except public AccountId/pubkey)
- Sentry handles non-fatal error monitoring in non-debug builds

## Notification Cleanup

When cleaning up notifications, both cancel pending AND remove already-delivered notifications:

```swift
// GOOD: Cancel + remove
UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: ids)
UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: ids)

// BAD: Only cancelling pending (leaves delivered notifications visible)
UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: ids)
```

(review: "Cancelling cancels the scheduled notification, but does not remove an already delivered notification.")

Cleanup scope: clean up notifications for all states except `.registration`.

## From PR Reviews

- "We shouldn't fallback to raw bytes here - throw an error. Always expect decodable call."
- "Use `utf8View` to prevent optional" — prefer safe conversion APIs
