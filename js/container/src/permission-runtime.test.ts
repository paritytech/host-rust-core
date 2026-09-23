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
    it(`keeps a host denial intact after attempts to replace ${name}`, async () => {
      const context = browser();
      runInContext(`
        try { ${attack} } catch (error) { if (!(error instanceof TypeError)) throw error; }
      `, context);
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

  it('allows React promise inheritance while preserving native then and host denial', async () => {
    const context = browser();
    expect(await runInContext(`
      (async () => {
        'use strict';
        const nativeThen = Promise.prototype.then;
        function ReactPromise() {}
        ReactPromise.prototype = Object.create(Promise.prototype);
        ReactPromise.prototype.then = function (resolve) { resolve('React is ready'); };
        const delivered = await Promise.resolve(new ReactPromise());
        let assignmentRejected = false;
        try { Promise.prototype.then = () => ({ granted: true }); }
        catch { assignmentRejected = true; }
        return {
          delivered,
          hasOwnThen: Object.hasOwn(ReactPromise.prototype, 'then'),
          unchanged: Promise.prototype.then === nativeThen,
          frozen: Object.isFrozen(Promise.prototype),
          assignmentRejected,
          redefined: Reflect.defineProperty(Promise.prototype, 'then', { value: () => ({ granted: true }) }),
        };
      })();
    `, context)).toEqual({
      delivered: 'React is ready',
      hasOwnThen: true,
      unchanged: true,
      frozen: true,
      assignmentRejected: true,
      redefined: false,
    });
    expect(await runInContext('authorize()', context)).toEqual({ granted: false });
  });

  it('allows Next and webpack array hooks while preserving native push and host denial', async () => {
    const context = browser();
    expect(runInContext(`
      const nativePush = Array.prototype.push;
      const delivered = [];
      const flight = [];
      (() => {
        'use strict';
        flight.push = (frame) => delivered.push(frame);
        flight.push('server component');
      })();
      const chunks = [];
      chunks.push = function (original, chunk) {
        delivered.push(chunk);
        return original(chunk);
      }.bind(null, chunks.push.bind(chunks));
      const length = chunks.push('module');
      let assignmentRejected = false;
      try { Array.prototype.push = () => ({ granted: true }); }
      catch { assignmentRejected = true; }
      ({ delivered, flight: [...flight], chunks: [...chunks], length, assignmentRejected,
        unchanged: Array.prototype.push === nativePush,
        frozen: Object.isFrozen(Array.prototype),
        redefined: Reflect.defineProperty(Array.prototype, 'push', { value: () => ({ granted: true }) }) });
    `, context)).toEqual({
      delivered: ['server component', 'module'],
      flight: [],
      chunks: ['module'],
      length: 1,
      assignmentRejected: true,
      unchanged: true,
      frozen: true,
      redefined: false,
    });
    expect(await runInContext('authorize()', context)).toEqual({ granted: false });
  });

  it('allows Buffer-style typed array overrides while preserving native methods and host denial', async () => {
    const context = browser();
    expect(runInContext(`
      (() => {
        'use strict';
        const prototype = Object.getPrototypeOf(Uint8Array.prototype);
        const nativeToString = prototype.toString;
        const nativeSlice = prototype.slice;
        const nativeIterator = prototype[Symbol.iterator];
        function ProductBuffer(...args) {
          return Object.setPrototypeOf(new Uint8Array(...args), ProductBuffer.prototype);
        }
        Object.setPrototypeOf(ProductBuffer.prototype, Uint8Array.prototype);
        Object.setPrototypeOf(ProductBuffer, Uint8Array);
        ProductBuffer.prototype.toString = function () { return 'buffer:' + this.join(','); };
        ProductBuffer.prototype.slice = function (start, end) {
          return Reflect.apply(nativeSlice, this, [start, end]);
        };
        const buffer = new ProductBuffer([72, 105]);
        buffer[Symbol.iterator] = function* () { yield this[1]; yield this[0]; };
        return {
          text: buffer.toString(), sliced: buffer.slice(1).toString(), iterated: [...buffer],
          unchanged: prototype.toString === nativeToString && prototype.slice === nativeSlice &&
            prototype[Symbol.iterator] === nativeIterator,
          frozen: Object.isFrozen(prototype),
          redefined: Reflect.defineProperty(prototype, 'slice', { value: () => ({ granted: true }) }),
        };
      })();
    `, context)).toEqual({
      text: 'buffer:72,105',
      sliced: 'buffer:105',
      iterated: [105, 72],
      unchanged: true,
      frozen: true,
      redefined: false,
    });
    expect(await runInContext('authorize()', context)).toEqual({ granted: false });
  });

  it('keeps the shared native call protected when functions may have their own call', async () => {
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
