import {
  encodeWireMessage,
  MESSAGE_TYPE_REQUEST,
  MESSAGE_TYPE_RESPONSE,
  type MethodIds,
  scale,
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
import { freezeAndDelete } from './freeze.js';

export type NetworkAuthorization = (
  url: string,
  decide: (allowed: boolean) => void,
) => () => void;

export type WebRtcAuthorization = (
  decide: (allowed: boolean) => void,
) => () => void;

export type MediaAuthorization = (
  audio: boolean,
  video: boolean,
  decide: (allowed: boolean) => void,
) => () => void;

interface NetworkPort {
  postMessage(message: Uint8Array): void;
  start?(): void;
  close?(): void;
  onmessage?: ((event: MessageEvent) => void) | null;
  onmessageerror?: (() => void) | null;
}

interface PendingRequest {
  expected: Uint8Array;
  frame: Uint8Array;
  decide: (allowed: boolean) => void;
  deadline: number;
  next?: PendingRequest;
}

export function createPermissionAuthorization(
  win: Window & typeof globalThis,
): {
  network: NetworkAuthorization;
  webRtc: WebRtcAuthorization | false;
  media: MediaAuthorization | false;
} {
  const bootstrap = win as unknown as {
    __truapi_network_port__?: NetworkPort;
    __truapi_localhost?: { url?: string };
  };
  const port = bootstrap.__truapi_network_port__;
  freezeAndDelete(win, '__truapi_network_port__');
  const endpoint = bootstrap.__truapi_localhost?.url;
  const apply = Reflect.apply;
  const descriptor = Object.getOwnPropertyDescriptor;
  const hasOwn = Object.prototype.hasOwnProperty;
  const NativeBytes = win.Uint8Array;
  const bytesPrototype = Object.getPrototypeOf(NativeBytes.prototype);
  const bytesLength = descriptor(bytesPrototype, 'length')!.get!;
  const bytesBuffer = descriptor(bytesPrototype, 'buffer')!.get!;
  const bytesOffset = descriptor(bytesPrototype, 'byteOffset')!.get!;
  const bufferLength = descriptor(
    win.ArrayBuffer.prototype,
    'byteLength',
  )!.get!;
  const messageData = descriptor(win.MessageEvent.prototype, 'data')!.get!;
  const encoder = new win.TextEncoder();
  const encode = win.TextEncoder.prototype.encode;
  const schedule = win.setTimeout.bind(win);
  const cancel = win.clearTimeout.bind(win);
  const NativeURL = win.URL;
  const hostname = descriptor(NativeURL.prototype, 'hostname')!.get!;
  const protocol = descriptor(NativeURL.prototype, 'protocol')!.get!;
  const indexOf = String.prototype.indexOf;

  // Codecs run before product code can replace the primitives they use.
  const requestId = '0000000000000000';
  const idLength = scale.str.enc(requestId).length;
  const idOffset = idLength - requestId.length;
  function template(
    ids: MethodIds,
    messageType: number,
    value: Uint8Array,
  ): Uint8Array {
    return encodeWireMessage({
      requestId,
      payload: {
        traitId: ids.trait,
        methodId: ids.method,
        messageType,
        value,
      },
    })._unsafeUnwrap();
  }
  const requestTemplate = template(
    PERMISSIONS_AUTHORIZE_REMOTE_PERMISSION,
    MESSAGE_TYPE_REQUEST,
    VersionedRemotePermissionRequest.enc({
      tag: 'V1',
      value: { permission: { tag: 'Remote', value: { domains: [''] } } },
    }),
  );
  const requestPrefixLength = requestTemplate.length - scale.str.enc('').length;
  const responseTemplate = template(
    PERMISSIONS_AUTHORIZE_REMOTE_PERMISSION,
    MESSAGE_TYPE_RESPONSE,
    scale.Result(
      VersionedRemotePermissionResponse,
      scale.CallError(VersionedRemotePermissionError),
    ).enc({ success: true, value: { tag: 'V1', value: { granted: true } } }),
  );
  const webRtcRequest = template(
    PERMISSIONS_AUTHORIZE_REMOTE_PERMISSION,
    MESSAGE_TYPE_REQUEST,
    VersionedRemotePermissionRequest.enc({
      tag: 'V1',
      value: { permission: { tag: 'WebRtc' } },
    }),
  );
  const cameraRequest = template(
    PERMISSIONS_AUTHORIZE_DEVICE_PERMISSION,
    MESSAGE_TYPE_REQUEST,
    VersionedHostDevicePermissionRequest.enc({ tag: 'V1', value: 'Camera' }),
  );
  const microphoneRequest = template(
    PERMISSIONS_AUTHORIZE_DEVICE_PERMISSION,
    MESSAGE_TYPE_REQUEST,
    VersionedHostDevicePermissionRequest.enc({ tag: 'V1', value: 'Microphone' }),
  );
  const deviceResponse = template(
    PERMISSIONS_AUTHORIZE_DEVICE_PERMISSION,
    MESSAGE_TYPE_RESPONSE,
    scale.Result(
      VersionedHostDevicePermissionResponse,
      scale.CallError(VersionedHostDevicePermissionError),
    ).enc({ success: true, value: { tag: 'V1', value: { granted: true } } }),
  );

  let pending: PendingRequest | undefined;
  let tail: PendingRequest | undefined;
  let counter = 0;
  let open = false;
  let closed = false;
  let send: ((frame: Uint8Array) => void) | undefined;
  let close: (() => void) | undefined;

  function remove(request: PendingRequest): boolean {
    let previous: PendingRequest | undefined;
    for (let entry = pending; entry; entry = entry.next) {
      if (entry === request) {
        if (previous) previous.next = entry.next;
        else pending = entry.next;
        if (tail === entry) tail = previous;
        cancel(entry.deadline);
        return true;
      }
      previous = entry;
    }
    return false;
  }

  function disconnect(): void {
    if (closed) return;
    closed = true;
    while (pending) {
      const entry = pending;
      remove(entry);
      entry.decide(false);
    }
    try {
      close?.();
    } catch {
      /* already disconnected */
    }
  }

  function receive(event: MessageEvent): void {
    try {
      let data: unknown;
      try {
        data = apply(messageData, event, []);
      } catch {
        const field = descriptor(event, 'data');
        if (field && apply(hasOwn, field, ['value'])) data = field.value;
      }
      let bytes: Uint8Array;
      try {
        const length = apply(bufferLength, data, []);
        bytes = new NativeBytes(data as ArrayBuffer, 0, length);
      } catch {
        bytes = new NativeBytes(
          apply(bytesBuffer, data, []),
          apply(bytesOffset, data, []),
          apply(bytesLength, data, []),
        );
      }
      const length = apply(bytesLength, bytes, []);
      for (let entry = pending; entry; entry = entry.next) {
        let matches = length >= idLength;
        for (let index = 0; matches && index < idLength; index++) {
          matches = bytes[index] === entry.expected[index];
        }
        if (!matches) continue;
        let allowed = length === apply(bytesLength, entry.expected, []);
        for (let index = idLength; allowed && index < length; index++) {
          allowed = bytes[index] === entry.expected[index];
        }
        remove(entry);
        entry.decide(allowed);
        return;
      }
    } catch {
      disconnect();
    }
  }

  try {
    if (port) {
      const postMessage = port.postMessage;
      const closePort = port.close;
      send = (frame) => apply(postMessage, port, [frame]);
      close = () => {
        if (closePort) apply(closePort, port, []);
      };
      port.onmessage = receive;
      port.onmessageerror = disconnect;
      port.start?.();
      open = true;
    } else if (typeof endpoint === 'string') {
      const socket = new win.WebSocket(endpoint);
      const socketSend = win.WebSocket.prototype.send;
      const socketClose = win.WebSocket.prototype.close;
      const listen = win.EventTarget.prototype.addEventListener;
      socket.binaryType = 'arraybuffer';
      send = (frame) => apply(socketSend, socket, [frame]);
      close = () => apply(socketClose, socket, []);
      apply(listen, socket, ['message', receive]);
      apply(listen, socket, ['error', disconnect]);
      apply(listen, socket, ['close', disconnect]);
      apply(listen, socket, [
        'open',
        () => {
          open = true;
          try {
            for (let entry = pending; entry; entry = entry.next)
              send!(entry.frame);
          } catch {
            disconnect();
          }
        },
      ]);
    } else {
      closed = true;
    }
  } catch {
    disconnect();
  }

  function authorize(
    template: Uint8Array,
    response: Uint8Array,
    domain: string | null,
    decide: (allowed: boolean) => void,
  ): () => void {
    if (closed || !send) {
      decide(false);
      return () => {};
    }
    try {
      const encodedDomain = domain === null
        ? new NativeBytes(0)
        : apply(encode, encoder, [domain]) as Uint8Array;
      const length = apply(bytesLength, encodedDomain, []) as number;
      if (length >= 2 ** 30) {
        decide(false);
        return () => {};
      }
      const width = domain === null ? 0 : length < 64 ? 1 : length < 16384 ? 2 : 4;
      let compactLength = length * 4 + (width === 1 ? 0 : width === 2 ? 1 : 2);
      const prefixLength = domain === null
        ? apply(bytesLength, template, [])
        : requestPrefixLength;
      const responseLength = apply(bytesLength, response, []);
      const frame = new NativeBytes(prefixLength + width + length);
      const expected = new NativeBytes(responseLength);
      for (let index = 0; index < prefixLength; index++)
        frame[index] = template[index];
      for (let index = 0; index < responseLength; index++)
        expected[index] = response[index];
      let sequence = ++counter;
      for (let index = idLength - 1; index >= idOffset; index--) {
        const digit = sequence % 16;
        sequence = (sequence - digit) / 16;
        frame[index] = expected[index] = digit < 10 ? 48 + digit : 87 + digit;
      }
      for (let index = 0; index < width; index++) {
        frame[prefixLength + index] = compactLength & 255;
        compactLength >>>= 8;
      }
      for (let index = 0; index < length; index++)
        frame[prefixLength + width + index] = encodedDomain[index];
      const entry: PendingRequest = {
        expected,
        frame,
        decide,
        next: undefined,
        deadline: schedule(() => {
          if (remove(entry)) decide(false);
        }, 120_000),
      };
      if (tail) tail.next = entry;
      else pending = entry;
      tail = entry;
      if (open) send(frame);
      return () => {
        remove(entry);
      };
    } catch {
      disconnect();
      decide(false);
      return () => {};
    }
  }

  function authorizeNetwork(
    url: string,
    decide: (allowed: boolean) => void,
  ): () => void {
    let domain: string;
    try {
      const destination = new NativeURL(url);
      const scheme = apply(protocol, destination, []);
      domain = apply(hostname, destination, []);
      if (
        (scheme !== 'http:' && scheme !== 'https:' && scheme !== 'ws:' && scheme !== 'wss:') ||
        !domain ||
        apply(indexOf, domain, ['*']) !== -1
      ) {
        decide(false);
        return () => {};
      }
    } catch {
      decide(false);
      return () => {};
    }
    return authorize(requestTemplate, responseTemplate, domain, decide);
  }

  function authorizeMedia(
    audio: boolean,
    video: boolean,
    decide: (allowed: boolean) => void,
  ): () => void {
    let pending: { cancel: (() => void) | undefined } | undefined;
    function request(template: Uint8Array, microphoneNext: boolean): void {
      const entry = { cancel: undefined as (() => void) | undefined };
      pending = entry;
      const cancel = authorize(template, deviceResponse, null, (allowed) => {
        if (pending !== entry) return;
        pending = undefined;
        if (allowed && microphoneNext) request(microphoneRequest, false);
        else decide(allowed);
      });
      if (pending === entry) entry.cancel = cancel;
      else cancel();
    }
    if (video) request(cameraRequest, audio);
    else if (audio) request(microphoneRequest, false);
    else decide(false);
    return () => {
      const cancel = pending?.cancel;
      pending = undefined;
      cancel?.();
    };
  }

  return {
    network: authorizeNetwork,
    webRtc: closed ? false : (decide) => authorize(webRtcRequest, responseTemplate, null, decide),
    media: closed ? false : authorizeMedia,
  };
}
