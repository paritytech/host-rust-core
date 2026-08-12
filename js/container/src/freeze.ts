// =============================================================================
// Lockdown primitives: make a property non-configurable so product scripts in
// the same realm cannot reach, replace, or wrap it.
// =============================================================================

/** Replaces a property with an undefined getter and swallows writes. */
export function freezeAndDelete(obj: object, prop: string): void {
  try {
    Object.defineProperty(obj, prop, {
      get: () => undefined,
      set() {
        /* silently ignore */
      },
      configurable: false,
    });
  } catch {
    // Property may already be non-configurable; try delete as fallback.
    try {
      delete (obj as Record<string, unknown>)[prop];
    } catch {
      /* best effort */
    }
  }
}

/** Pins a property to `value` via a getter and swallows writes. */
export function freezeValue(obj: object, prop: string, value: unknown): void {
  try {
    // Use a getter instead of a data property with writable:false.
    // A non-writable data property on the prototype chain prevents
    // descendant objects from shadowing it, which breaks polyfills
    // that create objects with window/self as prototype.
    Object.defineProperty(obj, prop, {
      get: () => value,
      set() {
        /* silently ignore */
      },
      configurable: false,
    });
  } catch {
    /* best effort */
  }
}
