/**
 * IndexedDB storage for the warm-start blobs the provider reads through
 * `ChainProviderBuilder.setWarmStore`.
 *
 * A snapshot runs to several megabytes, which is past what `localStorage`
 * holds and too much to write synchronously on the main thread, so blobs live
 * in one IndexedDB object store keyed by genesis hash.
 *
 * Every failure surfaces as a rejected promise carrying a
 * {@link WarmStoreError}. A read that cannot be answered must never resolve
 * empty: the provider reads an empty result as "nothing stored yet", and the
 * next `persist()` would write over state that is still good.
 */

/**
 * Database the blobs are kept in.
 *
 * This is a persisted browser key. A host that changes it strands every blob
 * already written under the old name, and those chains warp sync again.
 */
export const DEFAULT_WARM_STORE_DATABASE_NAME = "truapi-provider-warm-start";

const OBJECT_STORE_NAME = "chain-databases";
const DATABASE_VERSION = 1;
const GENESIS_HASH_HEX = /^0x[0-9a-f]{64}$/;

/** A warm-start read or write that could not be answered. */
export class WarmStoreError extends Error {
  constructor(message: string, options?: { cause?: unknown }) {
    super(message, options);
    this.name = "WarmStoreError";
  }
}

/** Where the provider keeps warm-start blobs between runs. */
export interface WarmStore {
  /**
   * Blob stored for the `0x`-prefixed genesis hash, or `null` when the store
   * holds none for that chain.
   */
  load(genesisHashHex: string): Promise<string | null>;

  /** Replace the blob stored for the `0x`-prefixed genesis hash. */
  save(genesisHashHex: string, blob: string): Promise<void>;

  /**
   * Drop the open database connection. The next `load` or `save` reopens it,
   * so this is not a teardown the provider needs: reach for it when the page
   * is done with the store, or to let another tab's upgrade proceed.
   */
  close(): void;
}

/** Options for {@link openIndexedDbWarmStore}. */
export interface IndexedDbWarmStoreOptions {
  /**
   * Database to use instead of {@link DEFAULT_WARM_STORE_DATABASE_NAME}. Pick
   * one name and keep it: see the constant's note on renaming.
   */
  databaseName?: string;
}

/**
 * Build a {@link WarmStore} over IndexedDB, ready to hand to
 * `ChainProviderBuilder.setWarmStore`.
 *
 * The database opens on the first read or write, so a context without
 * IndexedDB reports that as a rejection from `load`/`save` rather than
 * throwing here or quietly storing nothing.
 */
export function openIndexedDbWarmStore(
  options: IndexedDbWarmStoreOptions = {},
): WarmStore {
  const databaseName = options.databaseName ?? DEFAULT_WARM_STORE_DATABASE_NAME;
  let connection: Promise<IDBDatabase> | undefined;

  function database(): Promise<IDBDatabase> {
    if (connection === undefined) {
      const opening = openDatabase(databaseName).then(
        (db) => {
          db.onversionchange = () => {
            db.close();
            if (connection === opening) connection = undefined;
          };
          db.onclose = () => {
            if (connection === opening) connection = undefined;
          };
          return db;
        },
        (error: unknown) => {
          if (connection === opening) connection = undefined;
          throw error;
        },
      );
      connection = opening;
    }
    return connection;
  }

  return {
    async load(genesisHashHex: string): Promise<string | null> {
      const key = storageKey(genesisHashHex);
      const db = await database();
      const stored = await runTransaction<unknown>(db, "readonly", (store) =>
        store.get(key),
      );
      if (stored === undefined || stored === null) return null;
      if (typeof stored !== "string") {
        throw new WarmStoreError(
          `the blob stored for ${key} is a ${typeof stored}, not a string`,
        );
      }
      return stored;
    },

    async save(genesisHashHex: string, blob: string): Promise<void> {
      const key = storageKey(genesisHashHex);
      const db = await database();
      await runTransaction<IDBValidKey>(db, "readwrite", (store) =>
        store.put(blob, key),
      );
    },

    close(): void {
      const open = connection;
      connection = undefined;
      void open?.then(
        (db) => db.close(),
        () => {},
      );
    },
  };
}

/** Normalise a genesis hash into the key its blob is stored under. */
function storageKey(genesisHashHex: string): string {
  const key = genesisHashHex.toLowerCase();
  if (!GENESIS_HASH_HEX.test(key)) {
    throw new WarmStoreError(
      `\`${genesisHashHex}\` is not a 0x-prefixed 32-byte genesis hash`,
    );
  }
  return key;
}

/** The environment's IndexedDB, or an error naming what is missing. */
function indexedDbFactory(): IDBFactory {
  const factory: IDBFactory | undefined = globalThis.indexedDB;
  if (!factory) {
    throw new WarmStoreError(
      "IndexedDB is unavailable here, so warm-start blobs cannot be stored",
    );
  }
  return factory;
}

/** Open the database, creating the object store on first use. */
function openDatabase(name: string): Promise<IDBDatabase> {
  const factory = indexedDbFactory();
  return new Promise<IDBDatabase>((resolve, reject) => {
    let settled = false;
    const fail = (message: string, cause?: unknown) => {
      settled = true;
      reject(new WarmStoreError(message, { cause }));
    };
    try {
      const request = factory.open(name, DATABASE_VERSION);
      request.onupgradeneeded = () => {
        const db = request.result;
        if (!db.objectStoreNames.contains(OBJECT_STORE_NAME)) {
          db.createObjectStore(OBJECT_STORE_NAME);
        }
      };
      // An upgrade held up by an older connection would otherwise never
      // settle, and a warm-up that hangs blocks the connect behind it.
      request.onblocked = () =>
        fail(`another connection is holding the "${name}" database open`);
      request.onerror = () =>
        fail(`could not open the "${name}" database`, request.error);
      request.onsuccess = () => {
        if (settled) {
          request.result.close();
          return;
        }
        settled = true;
        resolve(request.result);
      };
    } catch (cause) {
      fail(`could not open the "${name}" database`, cause);
    }
  });
}

/** Run one request and resolve with its result once the transaction commits. */
function runTransaction<T>(
  db: IDBDatabase,
  mode: IDBTransactionMode,
  run: (store: IDBObjectStore) => IDBRequest<T>,
): Promise<T> {
  return new Promise<T>((resolve, reject) => {
    const fail = (cause: unknown) =>
      reject(
        new WarmStoreError(`the ${mode} warm-store transaction failed`, {
          cause,
        }),
      );
    try {
      const transaction = db.transaction(OBJECT_STORE_NAME, mode);
      const request = run(transaction.objectStore(OBJECT_STORE_NAME));
      transaction.oncomplete = () => resolve(request.result);
      transaction.onerror = () => fail(transaction.error ?? request.error);
      transaction.onabort = () => fail(transaction.error ?? request.error);
    } catch (cause) {
      fail(cause);
    }
  });
}
