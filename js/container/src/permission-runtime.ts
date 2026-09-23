import { freezeValue } from './freeze.js';
import { freezeInternalResults } from '@parity/truapi/internal';

function freezePrototype(prototype: object): void {
  // Libraries must be able to shadow inherited methods on their own objects.
  for (const name of Reflect.ownKeys(prototype)) {
    const { value, writable, configurable } = Object.getOwnPropertyDescriptor(prototype, name)!;
    if (!writable || !configurable) continue;
    Object.defineProperty(prototype, name, {
      get: () => value,
      set(ownValue: unknown) {
        Object.defineProperty(this, name, { value: ownValue, writable: true, configurable: true, enumerable: true });
      },
    });
  }
  Object.freeze(prototype);
}

export function freezePermissionRuntime(): void {
  // Block inherited then hooks without preventing products' own toString/valueOf assignments.
  Object.preventExtensions(Object.prototype);
  for (const name of [
    'Object', 'Function', 'Array', 'Map', 'Set', 'WeakMap', 'Promise',
    'Number', 'String', 'Uint8Array', 'DataView',
    'MessageChannel', 'MessagePort', 'MessageEvent', 'EventTarget',
  ] as const) {
    const constructor = globalThis[name];
    if (name !== 'Object' && name !== 'Number') freezePrototype(constructor.prototype);
    Object.freeze(constructor);
    freezeValue(globalThis, name, constructor);
  }
  for (const prototype of [
    TextEncoder.prototype,
    TextDecoder.prototype,
    Object.getPrototypeOf(Uint8Array.prototype),
    Object.getPrototypeOf(Uint8Array),
    Object.getPrototypeOf([][Symbol.iterator]()),
    Object.getPrototypeOf(Object.getPrototypeOf([][Symbol.iterator]())),
    Object.getPrototypeOf(new Map()[Symbol.iterator]()),
    Object.getPrototypeOf(new Set()[Symbol.iterator]()),
  ]) freezePrototype(prototype);
  freezeValue(globalThis, 'BigInt', BigInt);
  freezeValue(globalThis, 'Symbol', Symbol);
  freezeValue(globalThis, 'Reflect', Object.freeze(Reflect));
  freezeValue(globalThis, 'setTimeout', setTimeout);
  freezeValue(globalThis, 'clearTimeout', clearTimeout);
  freezeInternalResults();
}
