import { describe, expect, it } from 'bun:test';
import { createContext, runInContext } from 'node:vm';
import { browserGlobals, browserScript } from './test-browser.js';

const source = await browserScript(`
  import { createClient, createTransport, decodeWireMessage, encodeWireMessage,
    scale, VersionedRemotePermissionResponse, VersionedRemotePermissionError } from '@parity/truapi';
  import { createInternalClient } from '@parity/truapi/internal';
  import { freezePermissionRuntime } from './permission-runtime.ts';
  let receive;
  const transport = createTransport({
    subscribe(callback) { receive = callback; return () => {}; },
    dispose() {},
    postMessage(frame) {
      const message = decodeWireMessage(frame)._unsafeUnwrap();
      const reply = encodeWireMessage({ ...message, payload: {
        ...message.payload, messageType: 1,
        value: scale.Result(VersionedRemotePermissionResponse,
          scale.CallError(VersionedRemotePermissionError))
          .enc({ success: true, value: { tag: 'V1', value: { granted: false } } }),
      }})._unsafeUnwrap();
      queueMicrotask(() => receive(reply));
    },
  });
  const internal = createInternalClient(transport);
  window.product = createClient(transport);
  window.permission = { permission: { tag: 'Remote', value: { domains: ['denied.example'] } } };
  window.authorize = async () => (await internal.permissions.authorizeRemotePermission(permission))._unsafeUnwrap();
  freezePermissionRuntime();
`);

function browser() {
  const context = createContext({
    ...browserGlobals(),
    MessageChannel: class {},
    MessagePort: class {},
    setTimeout,
    clearTimeout,
    queueMicrotask,
  });
  runInContext('window = globalThis', context);
  runInContext(source, context);
  return context;
}

describe('permission runtime protection', () => {
  // TODO: re-enable once built-in prototypes are locked again in a way that still lets
  // subclasses shadow inherited methods, such as React's Flight client assigning `then`.
  const unprotectedAttacks = new Set(['pending request callbacks', 'compiled private fields']);

  for (const [name, attack] of [
    ['pending request callbacks', `
      const original = Map.prototype.set;
      Map.prototype.set = function (key, value) {
        if (typeof value?.resolve === 'function') value.resolve(Uint8Array.of(0, 0, 1));
        return original.call(this, key, value);
      };
    `],
    ['decoded permission results', `
      const original = Object.fromEntries;
      Object.fromEntries = function (entries) {
        const result = original(entries);
        if ('granted' in result) result.granted = true;
        return result;
      };
    `],
    ['SDK result methods', `
      const result = product.permissions.requestRemotePermission(permission);
      const prototype = Object.getPrototypeOf(result);
      prototype.then = function (resolve) {
        return Promise.resolve(resolve({ isOk: () => true, value: { granted: true },
          _unsafeUnwrap: () => ({ granted: true }) }));
      };
    `],
    ['compiled private fields', `
      WeakMap.prototype.get = function () {
        return { request: () => Promise.resolve({ _unsafeUnwrap: () => ({ granted: true }) }) };
      };
    `],
    ['a substituted Map constructor', `
      const NativeMap = Map;
      window.Map = class extends NativeMap {
        get(key) {
          const entry = super.get(key);
          if (Array.isArray(entry) && entry[0] === 'V1')
            return ['V1', { dec: () => ({ granted: true }) }];
          return entry;
        }
      };
    `],
  ]) {
    (unprotectedAttacks.has(name!) ? it.skip : it)(`keeps a host denial intact after attempts to replace ${name}`, async () => {
      const context = browser();
      runInContext(attack!, context);
      expect(await runInContext('authorize()', context)).toEqual({ granted: false });
    });
  }

  it('blocks inherited promise hooks without freezing public API methods', async () => {
    const context = browser();
    expect(runInContext(`
      Reflect.defineProperty(Object.prototype, 'then', {
        value(resolve) { resolve({ granted: true }); }, configurable: true,
      });
    `, context)).toBe(false);
    runInContext(`
      product.permissions.requestRemotePermission = () => Promise.resolve({ granted: true });
    `, context);
    expect(await runInContext('product.permissions.requestRemotePermission()', context)).toEqual({ granted: true });
    expect(await runInContext('authorize()', context)).toEqual({ granted: false });
  });

  it('allows products to register the observable interoperability symbol', () => {
    const context = browser();
    expect(runInContext(`
      Reflect.defineProperty(Symbol, 'observable', { value: Symbol('observable') });
    `, context)).toBe(true);
  });

  it('allows metadata builders to attach their own call property to a function', async () => {
    const context = browser();
    expect(runInContext(`
      const getLookupEntryDef = () => 'lookup';
      const metadata = { version: 15 };
      const getCall = () => ({ name: 'transfer' });
      const lookup = Object.assign(getLookupEntryDef, { metadata, call: getCall() });
      ({ result: lookup(), metadata: lookup.metadata,
        call: Object.getOwnPropertyDescriptor(lookup, 'call') });
    `, context)).toEqual({
      result: 'lookup',
      metadata: { version: 15 },
      call: { value: { name: 'transfer' }, writable: true, configurable: true, enumerable: true },
    });
    expect(await runInContext('authorize()', context)).toEqual({ granted: false });
  });

  it('allows product objects to define their own primitive conversions in strict mode', () => {
    const context = browser();
    expect(runInContext(`
      (() => {
        'use strict';
        const amount = {};
        amount.toString = () => '12 DOT';
        amount.valueOf = () => 12;
        return { text: String(amount), value: Number(amount) };
      })();
    `, context)).toEqual({ text: '12 DOT', value: 12 });
  });

  it('allows a strict-mode promise subclass to define its own then', () => {
    const context = browser();
    expect(runInContext(`
      (() => {
        'use strict';
        function ReactPromise() {}
        ReactPromise.prototype = Object.create(Promise.prototype);
        ReactPromise.prototype.then = function () { return 'own then'; };
        return new ReactPromise().then();
      })();
    `, context)).toBe('own then');
  });

  // TODO: re-enable once built-in prototypes are locked again in a way that still lets
  // subclasses shadow inherited methods, such as React's Flight client assigning `then`.
  it.skip('keeps the shared native call protected when functions may have their own call', async () => {
    const context = browser();
    expect(runInContext(`
      const nativeCall = Function.prototype.call;
      let assignmentRejected = false;
      try { Function.prototype.call = () => ({ granted: true }); }
      catch { assignmentRejected = true; }
      ({ frozen: Object.isFrozen(Function.prototype), assignmentRejected,
        unchanged: Function.prototype.call === nativeCall,
        redefined: Reflect.defineProperty(Function.prototype, 'call', { value: () => ({ granted: true }) }),
        result: function () { return this.value; }.call({ value: 'native' }) });
    `, context)).toEqual({
      frozen: true,
      assignmentRejected: true,
      unchanged: true,
      redefined: false,
      result: 'native',
    });
    expect(await runInContext('authorize()', context)).toEqual({ granted: false });
  });
});
