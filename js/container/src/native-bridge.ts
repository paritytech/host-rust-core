// =============================================================================
// Platform-independent entry point: selects the first available native bridge.
// =============================================================================

import { createAndroidNativeBridge } from './android-bridge.js';
import { createIOSNativeBridge } from './ios-bridge.js';
import type { NativeTransport } from './native-transport.js';

/**
 * Returns the transport for the first available native bridge — iOS first, then
 * Android — or `undefined` when neither host is present (fail-closed).
 */
export function createNativeBridge(): NativeTransport | undefined {
  return createIOSNativeBridge() ?? createAndroidNativeBridge();
}
