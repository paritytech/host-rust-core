// Property-locking helpers shared by the lockdown container and its policies.
//
// The container runs in the product's own realm, so a locked property must not
// be reachable, replaceable, or wrappable by product script. Every definition
// here is `configurable: false` with a setter that silently ignores writes,
// which is what makes the lock survive a product's own `defineProperty` or
// assignment attempt.

/* eslint-disable @typescript-eslint/no-explicit-any */

/** Make `prop` read as `undefined` and stay that way. */
export function freezeAndDelete(obj: any, prop: string): void {
  try {
    Object.defineProperty(obj, prop, {
      get: () => undefined,
      set() { /* silently ignore */ },
      configurable: false,
    });
  } catch {
    // Property may already be non-configurable; try delete as fallback
    try { delete obj[prop]; } catch { /* best effort */ }
  }
}

/** Pin `prop` to `value` and stay that way. */
export function freezeValue(obj: any, prop: string, value: any): void {
  try {
    // Use a getter instead of a data property with writable:false.
    // A non-writable data property on the prototype chain prevents
    // descendant objects from shadowing it, which breaks polyfills
    // that create objects with window/self as prototype.
    Object.defineProperty(obj, prop, {
      get: () => value,
      set() { /* silently ignore */ },
      configurable: false,
    });
  } catch { /* best effort */ }
}
