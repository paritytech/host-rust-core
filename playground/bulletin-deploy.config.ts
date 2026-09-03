import { execSync } from 'node:child_process';

/**
 * Product manifest for the TrUAPI playground (RFC paritytech/triangle-js-sdks #0001).
 *
 * With this file present, `bulletin-deploy` also writes the root `manifest`
 * record plus one `executable` record per subname. `includes: { chat: true }`
 * on the worker is what makes a host offer a chat entry point; on iOS it is
 * the only gate (`executables.worker?.includesChat`).
 *
 * `domain` MUST equal the name the CLI is invoked with, byte for byte, or
 * `publishManifest` aborts. The TLD belongs to the target environment, so the
 * workflow derives the full name once and passes it both as the argument and
 * as `PLAYGROUND_DOTNS_NAME`; the default below matches its default
 * environment.
 *
 * Paths resolve relative to this file. `app` points at `out` to reuse the CID
 * from the build-dir upload. The worker stays nested at `out/worker` on
 * purpose: brevity-dozer decides whether a product has chat by probing for
 * `worker/index.js` inside the app archive rather than reading
 * `includes.chat`, so moving it out would cost us chat there.
 */

// Short commit hash of the deployed tree, stamped into the SemVer's 4th
// element; 'dev' when git isn't available.
const buildId = (() => {
  try {
    return execSync('git rev-parse --short HEAD', { encoding: 'utf8' }).trim();
  } catch {
    return 'dev';
  }
})();

const appVersion = [0, 0, 1, buildId];

export default {
  domain: process.env.PLAYGROUND_DOTNS_NAME ?? 'truapi-playground.paseo',
  displayName: 'TrUAPI Playground',
  description: 'Browse, edit, and call TrUAPI methods live against a connected Polkadot host.',
  icon: {
    path: 'public/icon.png',
    format: 'png',
  },
  executables: [
    {
      kind: 'app',
      path: 'out',
      appVersion,
    },
    {
      kind: 'worker',
      path: 'out/worker',
      appVersion,
      entrypoint: 'index.js',
      includes: { chat: true, pocket: false },
    },
  ],
};
