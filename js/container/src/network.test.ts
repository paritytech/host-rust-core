import { describe, expect, it } from 'bun:test';
import { createContext, runInContext } from 'node:vm';
import {
  decodeWireMessage,
  encodeWireMessage,
  MESSAGE_TYPE_RESPONSE,
  scale,
  type HostDevicePermissionRequest,
  VersionedRemotePermissionRequest,
  VersionedRemotePermissionResponse,
  VersionedRemotePermissionError,
  VersionedHostDevicePermissionRequest,
  VersionedHostDevicePermissionResponse,
  VersionedHostDevicePermissionError,
} from '@parity/truapi';
import {
  PERMISSIONS_AUTHORIZE_REMOTE_PERMISSION,
  PERMISSIONS_AUTHORIZE_DEVICE_PERMISSION,
} from '@parity/truapi/wire-table';
import { createPermissionAuthorization } from './network-transport.js';
import { installFetchGate } from './network.js';

const build = await Bun.build({
  entrypoints: [new URL('./index.ts', import.meta.url).pathname],
  target: 'browser',
  format: 'iife',
});
if (!build.success) throw new Error(build.logs.join('\n'));
const container = await build.outputs[0].text();
const origin = 'https://product.example';

function browser(
  authorize?: (domain: string) => boolean | Promise<boolean>,
  pageUrl = `${origin}/index.html`,
  transport: 'port' | 'socket' = 'port',
  transformReply: (bytes: Uint8Array) => Uint8Array = (bytes) => bytes,
  authorizeWebRtc: () => boolean | Promise<boolean> = () => false,
  authorizeDevice: (request: HostDevicePermissionRequest) => boolean | Promise<boolean> = () => false,
) {
  class BrowserRequest extends Request {
    constructor(input: RequestInfo | URL, init?: RequestInit) {
      super(
        input instanceof Request ? input : new URL(String(input), pageUrl),
        init,
      );
    }
  }
  for (const [name, descriptor] of Object.entries(
    Object.getOwnPropertyDescriptors(Request.prototype),
  )) {
    Object.defineProperty(BrowserRequest.prototype, name, {
      ...descriptor,
      configurable: true,
    });
  }

  const requests: Request[] = [];
  const sent: Uint8Array[] = [];
  const sockets: BrowserSocket[] = [];
  const deadlines: (() => void)[] = [];
  const sdkHandler = () => {};
  const sdkPort = { onmessage: sdkHandler };
  class BrowserEvents extends EventTarget {}
  const NativeMessageEvent: new (
    type: string,
    init?: MessageEventInit,
  ) => MessageEvent = MessageEvent;
  class BrowserMessage extends NativeMessageEvent {}
  class BrowserEncoder extends TextEncoder {}
  for (const [target, source] of [
    [BrowserEvents, EventTarget],
    [BrowserMessage, MessageEvent],
    [BrowserEncoder, TextEncoder],
  ]) {
    for (const [name, descriptor] of Object.entries(
      Object.getOwnPropertyDescriptors(source!.prototype),
    )) {
      if (name !== 'constructor')
        Object.defineProperty(target!.prototype, name, descriptor);
    }
  }
  const privatePort = {
    onmessage: null as ((event: MessageEvent) => void) | null,
    onmessageerror: null as (() => void) | null,
    postMessage(message: Uint8Array) {
      handle(message, (data) =>
        privatePort.onmessage?.({ data } as MessageEvent),
      );
    },
  };
  function handle(message: Uint8Array, deliver: (data: Uint8Array) => void) {
    const prototype = Object.getPrototypeOf(Uint8Array.prototype);
    const buffer = Object.getOwnPropertyDescriptor(
      prototype,
      'buffer',
    )!.get!.call(message);
    const offset = Object.getOwnPropertyDescriptor(
      prototype,
      'byteOffset',
    )!.get!.call(message);
    const length = Object.getOwnPropertyDescriptor(
      prototype,
      'byteLength',
    )!.get!.call(message);
    message = new Uint8Array(buffer, offset, length);
    sent.push(message);
    const decoded = decodeWireMessage(message)._unsafeUnwrap();
    const device = decoded.payload.methodId === PERMISSIONS_AUTHORIZE_DEVICE_PERMISSION.method;
    expect({
      trait: decoded.payload.traitId,
      method: decoded.payload.methodId,
      kind: 'request',
    }).toEqual(device ? PERMISSIONS_AUTHORIZE_DEVICE_PERMISSION : PERMISSIONS_AUTHORIZE_REMOTE_PERMISSION);
    let decision: boolean | Promise<boolean>;
    if (device) {
      decision = authorizeDevice(VersionedHostDevicePermissionRequest.dec(decoded.payload.value).value);
    } else {
      const { permission } = VersionedRemotePermissionRequest.dec(decoded.payload.value).value;
      if (permission.tag === 'Remote') {
        expect(permission.value.domains).toHaveLength(1);
        decision = authorize!(permission.value.domains[0]!);
      } else {
        expect(permission).toEqual({ tag: 'WebRtc' });
        decision = authorizeWebRtc();
      }
    }
    Promise.resolve(decision).then(
      (granted) => {
        const reply = encodeWireMessage({
          requestId: decoded.requestId,
          payload: {
            ...decoded.payload,
            messageType: MESSAGE_TYPE_RESPONSE,
            value: scale
              .Result(
                device ? VersionedHostDevicePermissionResponse : VersionedRemotePermissionResponse,
                scale.CallError(device ? VersionedHostDevicePermissionError : VersionedRemotePermissionError),
              )
              .enc({ success: true, value: { tag: 'V1', value: { granted } } }),
          },
        })._unsafeUnwrap();
        deliver(transformReply(reply));
      },
      () => privatePort.onmessageerror?.(),
    );
  }
  class BrowserSocket extends BrowserEvents {
    static CONNECTING = 0;
    static OPEN = 1;
    static CLOSING = 2;
    static CLOSED = 3;
    private state = 0;
    private binary = 'blob';
    get url() { return this.destination; }
    get readyState() { return this.state; }
    get bufferedAmount() { return 0; }
    get extensions() { return ''; }
    get protocol() { return ''; }
    get binaryType() { return this.binary; }
    set binaryType(value: string) { this.binary = value; }
    constructor(private destination: string) {
      super();
      sockets.push(this);
      queueMicrotask(() => {
        this.state = 1;
        this.dispatchEvent(new Event('open'));
      });
    }
    send(frame: Uint8Array | string) {
      if (this.destination === 'ws://127.0.0.1:1234/?t=secret') {
        handle(frame as Uint8Array, (data) =>
          this.dispatchEvent(new BrowserMessage('message', { data: data.buffer })),
        );
      } else {
        this.dispatchEvent(new BrowserMessage('message', { data: frame }));
      }
    }
    close() {
      this.state = 3;
      queueMicrotask(() => this.dispatchEvent(new CloseEvent('close', { code: 1000, wasClean: true })));
    }
  }
  const context = createContext({
    URL,
    Request: BrowserRequest,
    Response,
    AbortSignal,
    DOMException,
    Event,
    CloseEvent,
    Blob,
    EventTarget: BrowserEvents,
    MessageEvent: BrowserMessage,
    TextEncoder: BrowserEncoder,
    TextDecoder,
    setTimeout(callback: () => void, delay: number) {
      deadlines.push(callback);
      return setTimeout(callback, delay);
    },
    clearTimeout,
    WebSocket: BrowserSocket,
    WebTransport: class {},
    Worker: class {},
    SharedWorker: class {},
    navigator: {},
    document: { createElement: () => ({}) },
    location: { href: pageUrl, origin: new URL(pageUrl).origin },
    fetch: async (input: RequestInfo | URL, init?: RequestInit) => {
      requests.push(new BrowserRequest(input, init));
      return new Response('received');
    },
    __HOST_API_PORT__: sdkPort,
    __truapi_network_port__:
      authorize && transport === 'port' ? privatePort : undefined,
    __truapi_localhost:
      authorize && transport === 'socket'
        ? { url: 'ws://127.0.0.1:1234/?t=secret' }
        : undefined,
  });
  runInContext('window = globalThis', context);
  runInContext(`
    window.mediaCalls = [];
    window.navigator.mediaDevices = new (class {
      getUserMedia(constraints) {
        mediaCalls.push(constraints);
        return Promise.resolve('capture');
      }
    })();
    window.RTCPeerConnection = class {
      constructor(config = {}) { this.config = { ...config, iceCandidatePoolSize: config.iceCandidatePoolSize ?? 0 }; }
      getConfiguration() { return { ...this.config }; }
      setConfiguration(config) { this.config = { ...config }; }
      createOffer() { return Promise.resolve({ type: 'offer', sdp: 'native' }); }
      createAnswer() { return Promise.resolve({ type: 'answer', sdp: 'native' }); }
      setLocalDescription() { return Promise.resolve(); }
      setRemoteDescription() { return Promise.resolve(); }
      addIceCandidate() { return Promise.resolve(); }
      close() {}
    };
  `, context);
  runInContext(container, context);
  return {
    context,
    requests,
    sent,
    sockets,
    sdkPort,
    sdkHandler,
    privatePort,
    deadlines,
    fetch: context.fetch as typeof fetch,
  };
}

describe('container fetch authorization', () => {
  it('requires permission for every origin when the runtime has no page URL', async () => {
    const runtime: typeof globalThis = Object.create(globalThis);
    const requested: string[] = [];
    installFetchGate(runtime, (url, decide) => {
      requested.push(url);
      decide(false);
      return () => {};
    });
    for (const url of ['https://product.example/', 'https://api.example/']) {
      await expect(runtime.fetch(url)).rejects.toThrow('Network access is not allowed');
    }
    expect(requested).toEqual(['https://product.example/', 'https://api.example/']);
  });

  it('uses one Remote decision per WebSocket connection over either private transport', async () => {
    for (const transport of ['port', 'socket'] as const) {
      const authorized: string[] = [];
      const realm = browser((url) => {
        authorized.push(url);
        return authorized.length === 1;
      }, undefined, transport);
      await runInContext(`
        window.remote = new WebSocket('wss://api.example/socket');
        new Promise((resolve, reject) => {
          remote.addEventListener('open', resolve, { once: true });
          remote.addEventListener('error', reject, { once: true });
        });
      `, realm.context);
      const result = await runInContext(`
        new Promise(resolve => {
          remote.addEventListener('message', event => resolve({ data: event.data, target: event.target === remote }), { once: true });
          remote.send('first');
        });
      `, realm.context);
      expect(result).toEqual({ data: 'first', target: true });
      await runInContext(`
        window.denied = new WebSocket.prototype.constructor('wss://api.example/socket');
        new Promise(resolve => denied.addEventListener('close', resolve, { once: true }));
      `, realm.context);
      const second = await runInContext(`
        new Promise(resolve => {
          remote.addEventListener('message', event => resolve(event.data), { once: true });
          remote.send('still open');
        });
      `, realm.context);
      expect({
        authorized,
        sockets: realm.sockets.map(socket => socket.url),
        second,
      }).toEqual({
        authorized: ['api.example', 'api.example'],
        sockets: transport === 'socket'
          ? ['ws://127.0.0.1:1234/?t=secret', 'wss://api.example/socket']
          : ['wss://api.example/socket'],
        second: 'still open',
      });
    }
  });

  it('reserves only the exact private bridge endpoint without a Remote decision', async () => {
    const authorized: string[] = [];
    const realm = browser(url => { authorized.push(url); return false; }, undefined, 'socket');
    runInContext(`window.bridge = new WebSocket('ws://127.0.0.1:1234/?t=secret');`, realm.context);
    await runInContext(`
      window.changed = new bridge.constructor('ws://127.0.0.1:1234/?t=other');
      new Promise(resolve => changed.addEventListener('close', resolve, { once: true }));
    `, realm.context);
    expect({ authorized, sockets: realm.sockets.map(socket => socket.url) }).toEqual({
      authorized: ['127.0.0.1'],
      sockets: ['ws://127.0.0.1:1234/?t=secret', 'ws://127.0.0.1:1234/?t=secret'],
    });
  });

  it('authorizes each capture over the private Rust channel', async () => {
    for (const transport of ['port', 'socket'] as const) {
      const decisions: HostDevicePermissionRequest[] = [];
      const grants = [true, true, false, true, false];
      const realm = browser(() => false, undefined, transport, (bytes) => bytes,
        () => false, (request) => {
          decisions.push(request);
          return grants[decisions.length - 1]!;
        });
      const capture = (audio: boolean, video: boolean) => runInContext(
        `navigator.mediaDevices.getUserMedia({ audio: ${audio}, video: ${video} })`, realm.context);
      expect(await capture(true, true)).toBe('capture');
      await expect(capture(true, true)).rejects.toMatchObject({ name: 'NotAllowedError' });
      expect(await capture(true, false)).toBe('capture');
      await expect(capture(false, true)).rejects.toMatchObject({ name: 'NotAllowedError' });
      expect({ decisions, captures: realm.context.mediaCalls }).toEqual({
        decisions: ['Camera', 'Microphone', 'Camera', 'Microphone', 'Camera'],
        captures: [{ audio: true, video: true }, { audio: true, video: false }],
      });
    }
  });

  it('cancels whichever media permission is pending without continuing capture', () => {
    for (const cancelAfterCamera of [false, true]) {
      const frames: Uint8Array[] = [];
      const port = {
        onmessage: null as ((event: MessageEvent) => void) | null,
        postMessage(frame: Uint8Array) {
          frames.push(frame);
        },
      };
      const win = {
        Uint8Array,
        ArrayBuffer,
        URL,
        MessageEvent,
        TextEncoder,
        setTimeout,
        clearTimeout,
        __truapi_network_port__: port,
      };
      const { media } = createPermissionAuthorization(
        win as unknown as Window & typeof globalThis,
      );
      if (!media) throw new Error('Expected media authorization transport');
      function approve(frame: Uint8Array): void {
        const message = decodeWireMessage(frame)._unsafeUnwrap();
        message.payload.messageType = MESSAGE_TYPE_RESPONSE;
        message.payload.value = scale.Result(
          VersionedHostDevicePermissionResponse,
          scale.CallError(VersionedHostDevicePermissionError),
        ).enc({ success: true, value: { tag: 'V1', value: { granted: true } } });
        port.onmessage!(new MessageEvent('message', {
          data: encodeWireMessage(message)._unsafeUnwrap(),
        }));
      }
      const decisions: boolean[] = [];
      const cancel = media(true, true, (allowed) => decisions.push(allowed));
      if (cancelAfterCamera) approve(frames[0]!);
      cancel();
      approve(frames[frames.length - 1]!);
      expect({
        decisions,
        requested: frames.map((frame) =>
          VersionedHostDevicePermissionRequest.dec(
            decodeWireMessage(frame)._unsafeUnwrap().payload.value,
          ).value,
        ),
      }).toEqual({
        decisions: [],
        requested: cancelAfterCamera ? ['Camera', 'Microphone'] : ['Camera'],
      });
      media(false, false, (allowed) => decisions.push(allowed));
      expect(decisions).toEqual([false]);
    }
  });

  it('authorizes each peer connection over the private Rust channel', async () => {
    let authorizations = 0;
    const realm = browser(() => false, undefined, 'port', (bytes) => bytes,
      () => ++authorizations === 1);
    const first = runInContext('new RTCPeerConnection()', realm.context);
    expect(await first.createOffer()).toEqual({ type: 'offer', sdp: 'native' });
    expect(await first.createOffer()).toEqual({ type: 'offer', sdp: 'native' });
    const second = runInContext('new RTCPeerConnection()', realm.context);
    await expect(second.createOffer()).rejects.toThrow('WebRTC access is not allowed');
    expect({ authorizations, fetches: realm.requests.length }).toEqual({
      authorizations: 2,
      fetches: 0,
    });
    first.close();
    second.close();
  });

  it('sends authorization through a private binary port without replacing the SDK port', async () => {
    const realm = browser(() => true);
    await realm.fetch('https://api.example/data');
    expect({
      sent: realm.sent.length,
      sdkHandler: realm.sdkPort.onmessage,
    }).toEqual({ sent: 1, sdkHandler: realm.sdkHandler });
  });
  it('uses an existing grant immediately for a cross-origin fetch', async () => {
    const authorized: string[] = [];
    const realm = browser(async (url) => {
      authorized.push(url);
      return true;
    });
    const response = await realm.fetch('https://api.example/data');
    expect({
      status: response.status,
      authorized,
      requested: realm.requests.map((request) => request.url),
    }).toEqual({
      status: 200,
      authorized: ['api.example'],
      requested: ['https://api.example/data'],
    });
  });

  it('uses the authenticated native bridge without the legacy Swift hook', async () => {
    const authorized: string[] = [];
    const realm = browser(
      (url) => {
        authorized.push(url);
        return true;
      },
      undefined,
      'socket',
    );
    await realm.fetch('https://api.example/data');
    expect({
      authorized,
      sockets: realm.sockets.map((socket) => socket.url),
      requests: realm.requests.length,
    }).toEqual({
      authorized: ['api.example'],
      sockets: ['ws://127.0.0.1:1234/?t=secret'],
      requests: 1,
    });
  });

  it('correlates concurrent replies and rejects stale grants for a different request', async () => {
    const decisions = new Map<string, (allowed: boolean) => void>();
    const realm = browser(
      (url) =>
        new Promise((resolve) => {
          decisions.set(url, resolve);
        }),
    );
    const denied = realm.fetch('https://denied.example/data');
    const granted = realm.fetch('https://allowed.example/data');
    decisions.get('allowed.example')!(true);
    await granted;
    const stale = decodeWireMessage(realm.sent[1]!)._unsafeUnwrap();
    stale.payload.messageType = MESSAGE_TYPE_RESPONSE;
    stale.payload.value = scale
      .Result(
        VersionedRemotePermissionResponse,
        scale.CallError(VersionedRemotePermissionError),
      )
      .enc({ success: true, value: { tag: 'V1', value: { granted: true } } });
    realm.privatePort.onmessage!({
      data: encodeWireMessage(stale)._unsafeUnwrap(),
    } as MessageEvent);
    decisions.get('denied.example')!(false);
    await expect(denied).rejects.toThrow('Network access is not allowed');
    expect(realm.requests.map((request) => request.url)).toEqual([
      'https://allowed.example/data',
    ]);
  });

  for (const corruption of [
    'method',
    'message type',
    'trailing bytes',
    'truncated payload',
  ]) {
    it(`rejects a grant reply with ${corruption}`, async () => {
      const realm = browser(
        () => true,
        undefined,
        'port',
        (frame) => {
          const decoded = decodeWireMessage(frame)._unsafeUnwrap();
          if (corruption === 'method') decoded.payload.methodId++;
          if (corruption === 'message type') decoded.payload.messageType++;
          if (corruption === 'trailing bytes')
            decoded.payload.value = new Uint8Array([
              ...decoded.payload.value,
              0,
            ]);
          if (corruption === 'truncated payload')
            decoded.payload.value = decoded.payload.value.slice(0, -1);
          return encodeWireMessage(decoded)._unsafeUnwrap();
        },
      );
      await expect(realm.fetch('https://denied.example/data')).rejects.toThrow(
        'Network access is not allowed',
      );
      expect(realm.requests).toEqual([]);
    });
  }

  it('encodes concrete domains with the generated permission schema', async () => {
    const authorized: string[] = [];
    const realm = browser((url) => {
      authorized.push(url);
      return true;
    });
    const urls = [
      'https://API.EXAMPLE:8443/short',
      'https://Bücher.example/雪',
      `https://${'a'.repeat(100)}.example/path`,
      `https://${'b'.repeat(16_400)}.example/path`,
    ];
    for (const url of urls) await realm.fetch(url);
    expect(authorized).toEqual(urls.map((url) => new URL(url).hostname));
  });

  it('denies pending and later fetches when the private transport closes', async () => {
    const realm = browser(() => new Promise(() => {}));
    const pending = realm.fetch('https://api.example/pending');
    realm.privatePort.onmessageerror!();
    await expect(pending).rejects.toThrow('Network access is not allowed');
    await expect(realm.fetch('https://api.example/later')).rejects.toThrow(
      'Network access is not allowed',
    );
    expect({ frames: realm.sent.length, requests: realm.requests }).toEqual({
      frames: 1,
      requests: [],
    });
  });

  it('bounds an unanswered permission request and ignores a late approval', async () => {
    let reply!: (allowed: boolean) => void;
    const realm = browser(
      () =>
        new Promise((resolve) => {
          reply = resolve;
        }),
    );
    const pending = realm.fetch('https://denied.example/data');
    realm.deadlines[0]!();
    await expect(pending).rejects.toThrow('Network access is not allowed');
    reply(true);
    await Promise.resolve();
    expect(realm.requests).toEqual([]);
  });

  it('ignores forged public SDK replies and a replacement legacy authorization hook', async () => {
    const realm = browser(() => false);
    realm.context.__truapi_network__ = async () => true;
    realm.context.__HOST_API_PORT__ = { onmessage: null, postMessage() {} };
    await expect(realm.fetch('https://denied.example/data')).rejects.toThrow(
      'Network access is not allowed',
    );
    expect(realm.requests).toEqual([]);
  });

  it('keeps decisions private when product code replaces transport and codec primitives', async () => {
    const authorized: string[] = [];
    const realm = browser(
      (url) => {
        authorized.push(url);
        return false;
      },
      undefined,
      'socket',
    );
    runInContext(
      `
      WebSocket.prototype.send = function () { throw new Error('intercepted socket'); };
      EventTarget.prototype.addEventListener = function () { throw new Error('intercepted listener'); };
      Object.defineProperty(MessageEvent.prototype, 'data', { get() { throw new Error('intercepted message'); } });
      const bytesPrototype = Object.getPrototypeOf(Uint8Array.prototype);
      for (const name of ['length', 'byteLength', 'byteOffset', 'buffer']) {
        Object.defineProperty(bytesPrototype, name, { get() { throw new Error('intercepted bytes'); } });
      }
      Uint8Array.prototype.set = function () { throw new Error('intercepted bytes'); };
      TextEncoder.prototype.encode = function () { throw new Error('intercepted URL'); };
      Map.prototype.set = function (key, value) { if (value.resolve) value.resolve(true); return this; };
      DataView.prototype.getUint8 = function () { return 1; };
    `,
      realm.context,
    );
    await expect(realm.fetch('https://denied.example/data')).rejects.toThrow(
      'Network access is not allowed',
    );
    expect({ authorized, requests: realm.requests }).toEqual({
      authorized: ['denied.example'],
      requests: [],
    });
  });

  it('does not invoke a substituted message data getter', async () => {
    const realm = browser(() => new Promise(() => {}));
    let read = false;
    const pending = realm.fetch('https://denied.example/data');
    realm.privatePort.onmessage!({
      get data() {
        read = true;
        return new Uint8Array();
      },
    } as MessageEvent);
    await expect(pending).rejects.toThrow('Network access is not allowed');
    expect({ read, requests: realm.requests }).toEqual({
      read: false,
      requests: [],
    });
  });

  it('sends no network request when Rust denies authorization', async () => {
    const realm = browser(async () => false);
    await expect(realm.fetch('https://denied.example/data')).rejects.toThrow(
      'Network access is not allowed',
    );
    expect(realm.requests).toEqual([]);
  });

  it('fails closed when the host transport is missing', async () => {
    const realm = browser();
    await expect(realm.fetch('https://denied.example/data')).rejects.toThrow(
      'Network access is not allowed',
    );
    expect({
      requests: realm.requests,
      peerConnection: realm.context.RTCPeerConnection,
    }).toEqual({ requests: [], peerConnection: undefined });
  });

  it('fails closed when the host authorization fails', async () => {
    const realm = browser(async () => {
      throw new Error('host disconnected');
    });
    await expect(realm.fetch('https://denied.example/data')).rejects.toThrow(
      'Network access is not allowed',
    );
    expect(realm.requests).toEqual([]);
  });

  it('leaves same-origin resources available without prompting', async () => {
    const realm = browser();
    await realm.fetch('/asset.json');
    expect(realm.requests.map((request) => request.url)).toEqual([
      `${origin}/asset.json`,
    ]);
  });

  it('does not consume a remote grant for same-origin fetches', async () => {
    const authorized: string[] = [];
    const realm = browser(async (url) => {
      authorized.push(url);
      return true;
    });
    await realm.fetch('/asset.json');
    expect(authorized).toEqual([]);
  });

  it('does not treat distinct native product origins as the same null origin', async () => {
    const realm = browser(undefined, 'polkadot://product/index.html');
    await realm.fetch('/asset.json');
    await expect(realm.fetch('polkadot://other/asset.json')).rejects.toThrow(
      'Network access is not allowed',
    );
    expect(realm.requests.map((request) => request.url)).toEqual([
      'polkadot://product/asset.json',
    ]);
  });

  it('does not authorize non-HTTP remote requests', async () => {
    const authorized: string[] = [];
    const realm = browser(async (url) => {
      authorized.push(url);
      return true;
    });
    for (const url of ['file:///secret', 'https://*.example/data']) {
      await expect(realm.fetch(url)).rejects.toThrow('Network access is not allowed');
    }
    expect({ authorized, requests: realm.requests }).toEqual({
      authorized: [],
      requests: [],
    });
  });

  it('consumes the bootstrap capability before product code runs', () => {
    const realm = browser(async () => true);
    realm.context.__truapi_network_port__ = { postMessage() {} };
    expect(realm.context.__truapi_network_port__).toBeUndefined();
  });

  it('uses current host decisions after a grant is revoked', async () => {
    let granted = true;
    const realm = browser(async () => granted);
    await realm.fetch('https://api.example/data');
    granted = false;
    await expect(realm.fetch('https://api.example/data')).rejects.toThrow(
      'Network access is not allowed',
    );
    expect(realm.requests.map((request) => request.url)).toEqual([
      'https://api.example/data',
    ]);
  });

  it('snapshots the destination, headers and body before awaiting permission', async () => {
    let grant!: (allowed: boolean) => void;
    const authorized: string[] = [];
    const realm = browser((url) => {
      authorized.push(url);
      return new Promise<boolean>((resolve) => {
        grant = resolve;
      });
    });
    const url = new URL('https://api.example/data');
    const headers = new Headers({ 'x-product': 'original' });
    const options = { method: 'POST', body: 'original', headers };
    const pending = realm.fetch(url, options);
    url.hostname = 'denied.example';
    headers.set('x-product', 'changed');
    options.body = 'changed';
    grant(true);
    await pending;
    const request = realm.requests[0];
    expect({
      authorized,
      url: request.url,
      method: request.method,
      body: await request.text(),
      header: request.headers.get('x-product'),
    }).toEqual({
      authorized: ['api.example'],
      url: 'https://api.example/data',
      method: 'POST',
      body: 'original',
      header: 'original',
    });
  });

  it('preserves Request input and fetch overrides', async () => {
    const realm = browser(async () => true);
    const input = new Request('https://api.example/data', {
      method: 'POST',
      body: 'body',
      credentials: 'include',
    });
    await realm.fetch(input, {
      headers: { 'x-product': 'override' },
      redirect: 'error',
    });
    const request = realm.requests[0];
    expect({
      url: request.url,
      method: request.method,
      body: await request.text(),
      credentials: request.credentials,
      redirect: request.redirect,
      header: request.headers.get('x-product'),
    }).toEqual({
      url: 'https://api.example/data',
      method: 'POST',
      body: 'body',
      credentials: 'include',
      redirect: 'error',
      header: 'override',
    });
  });

  it('rejects an aborted request while permission is still pending', async () => {
    let grant!: (allowed: boolean) => void;
    const realm = browser(
      () =>
        new Promise<boolean>((resolve) => {
          grant = resolve;
        }),
    );
    const controller = new AbortController();
    const pending = realm.fetch('https://api.example/data', {
      signal: controller.signal,
    });
    controller.abort(new Error('cancelled'));
    await expect(pending).rejects.toThrow('cancelled');
    grant(true);
    await Promise.resolve();
    expect(realm.requests).toEqual([]);
  });

  it('does not prompt for an already aborted request', async () => {
    const authorized: string[] = [];
    const realm = browser(async (url) => {
      authorized.push(url);
      return true;
    });
    const controller = new AbortController();
    controller.abort(new Error('cancelled'));
    await expect(
      realm.fetch('https://api.example/data', { signal: controller.signal }),
    ).rejects.toThrow('cancelled');
    expect({ authorized, requests: realm.requests }).toEqual({
      authorized: [],
      requests: [],
    });
  });

  it('checks native Request URLs even when the product changes their getters', async () => {
    const authorized: string[] = [];
    const realm = browser(async (url) => {
      authorized.push(url);
      return false;
    });
    runInContext(
      `Object.defineProperty(Request.prototype, 'url', { get() { return '${origin}/asset.json'; } });`,
      realm.context,
    );
    await expect(realm.fetch('https://denied.example/data')).rejects.toThrow(
      'Network access is not allowed',
    );
    expect({ authorized, requests: realm.requests }).toEqual({
      authorized: ['denied.example'],
      requests: [],
    });
  });

  it('cannot forge approval by replacing Promise.prototype.then', async () => {
    const realm = browser(async () => false);
    runInContext(
      `
      const then = Promise.prototype.then;
      Promise.prototype.then = function (resolve) { resolve(true); };
      const pending = window.fetch('https://denied.example/data');
      Reflect.apply(then, pending, [() => {}, () => {}]);
    `,
      realm.context,
    );
    await Promise.resolve();
    expect(realm.requests).toEqual([]);
  });

  it('does not expose the permission callback to a substituted Promise species', async () => {
    const realm = browser(async () => false);
    runInContext(
      `
      const then = Promise.prototype.then;
      const NativePromise = Promise;
      let forge;
      Promise.prototype.constructor = {
        [Symbol.species]: function (executor) {
          return new NativePromise((resolve, reject) => {
            executor(resolve, reject);
            forge = () => resolve(true);
          });
        },
      };
      const pending = window.fetch('https://denied.example/data');
      if (forge) forge();
      Reflect.apply(then, pending, [() => {}, () => {}]);
    `,
      realm.context,
    );
    await Promise.resolve();
    expect(realm.requests).toEqual([]);
  });

  it('blocks workers that would otherwise have an unguarded fetch', () => {
    const realm = browser();
    expect({
      worker: realm.context.Worker,
      sharedWorker: realm.context.SharedWorker,
    }).toEqual({ worker: undefined, sharedWorker: undefined });
  });

  it('blocks WebTransport egress outside the HTTP request gate', () => {
    expect(browser().context.WebTransport).toBeUndefined();
  });
});
