// Property-locking helpers shared by the lockdown container and its policies.
//
// The container runs in the product's own realm, so a locked property must not
// be reachable, replaceable, or wrappable by product script. Every definition
// here is `configurable: false` with a setter that silently ignores writes,
// which is what makes the lock survive a product's own `defineProperty` or
// assignment attempt.
//
// A lock that does not take is a hole in the sandbox, so none of these helpers
// trusts `defineProperty` to have worked: each verifies the property afterwards
// and records a failure it could not repair. Failures are collected rather than
// thrown, because throwing mid-sequence would skip every lock after the failing
// one and widen the hole. The caller applies all of them and then reports —
// see `reportLockdownFailures`.

/* eslint-disable @typescript-eslint/no-explicit-any */

/** Properties whose lock could not be verified, in the order they were tried. */
const failures: string[] = [];

/** Name for `obj`, for a failure message a host can act on. */
function describe(obj: any): string {
  if (obj === globalThis) return 'window';
  const name = obj?.constructor?.name;
  return typeof name === 'string' && name.length > 0 ? name : 'object';
}

function recordFailure(obj: any, prop: string): void {
  failures.push(`${describe(obj)}.${prop}`);
}

/** Make `prop` read as `undefined` and stay that way. */
export function freezeAndDelete(obj: any, prop: string): void {
  try {
    Object.defineProperty(obj, prop, {
      get: () => undefined,
      set() { /* silently ignore */ },
      configurable: false,
    });
  } catch {
    // Property may already be non-configurable; try delete as fallback.
    try { delete obj[prop]; } catch { /* verified below */ }
  }
  // Both routes can fail without throwing, so trust the read, not the call.
  if (obj?.[prop] !== undefined) {
    recordFailure(obj, prop);
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
  } catch { /* verified below */ }
  if (obj?.[prop] !== value) {
    recordFailure(obj, prop);
  }
}

/**
 * Install `descriptor` on `prop`, recording a failure when `verify` rejects what
 * the property reads back as. For locks whose success is neither "reads as
 * `undefined`" nor "reads as this value".
 */
export function freezeCustom(
  obj: any,
  prop: string,
  descriptor: PropertyDescriptor,
  verify: (current: any) => boolean,
): void {
  try {
    Object.defineProperty(obj, prop, { configurable: false, ...descriptor });
  } catch { /* verified below */ }
  let locked = false;
  try { locked = verify(obj?.[prop]); } catch { /* treat a throwing read as a failure */ }
  if (!locked) {
    recordFailure(obj, prop);
  }
}

/** Properties whose lock did not take. Empty means the realm is locked down. */
export function lockdownFailures(): readonly string[] {
  return failures;
}

/** Forget recorded failures. For tests, which share one module instance. */
export function resetLockdownFailures(): void {
  failures.length = 0;
}

/**
 * Surface any lock that did not take, then throw.
 *
 * A half-locked realm is a security failure, and one that is silent is worse
 * than one that is loud: the host would keep serving products into a sandbox it
 * believes is closed. Call this last, once every lock has been attempted, so the
 * throw costs no further coverage.
 */
export function reportLockdownFailures(): void {
  if (failures.length === 0) {
    return;
  }
  const message = `TrUAPI container lockdown failed for: ${failures.join(', ')}`;
  // Console first: the throw below propagates out of the injected script, where
  // a host may see only that evaluation failed and not which property it was.
  try { console.error(message); } catch { /* console may itself be locked */ }
  throw new Error(message);
}
