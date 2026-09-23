import { freezeValue } from './freeze.js';
import { freezeInternalResults } from '@parity/truapi/internal';

export function freezePermissionRuntime(): void {
  // Metadata builders attach their own call property to ordinary functions.
  const nativeCall = Function.prototype.call;
  Object.defineProperty(Function.prototype, 'call', {
    get: () => nativeCall,
    set(value: unknown) {
      Object.defineProperty(this, 'call', { value, writable: true, configurable: true, enumerable: true });
    },
  });
  // Block inherited then hooks without preventing products' own toString/valueOf assignments.
  Object.preventExtensions(Object.prototype);
  for (const name of [
    'Object', 'Function', 'Array', 'Map', 'Set', 'WeakMap', 'Promise',
    'Number', 'BigInt', 'String', 'Uint8Array', 'ArrayBuffer',
    'DataView', 'TextEncoder', 'TextDecoder', 'Date',
    'MessageChannel', 'MessagePort', 'MessageEvent', 'EventTarget',
  ] as const) {
    const constructor = globalThis[name];
    Object.freeze(constructor);
    freezeValue(globalThis, name, constructor);
  }
  freezeValue(globalThis, 'Symbol', Symbol);
  freezeValue(globalThis, 'Reflect', Object.freeze(Reflect));
  freezeValue(globalThis, 'setTimeout', setTimeout);
  freezeValue(globalThis, 'clearTimeout', clearTimeout);
  freezeInternalResults();
}
