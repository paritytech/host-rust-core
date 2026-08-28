import { execSync } from 'node:child_process';

/**
 * Product manifest for the TrUAPI playground (RFC paritytech/triangle-js-sdks #0001).
 *
 * With this file present, `bulletin-deploy` also writes the root `manifest`
 * text record on the base name and one `executable` record per subname:
 * `app.<name>` for the SPA and `worker.<name>` for the Chat diagnosis worker.
 * `includes: { chat: true }` on the worker is what makes a host surface a chat
 * entry point for the playground — on iOS it is the only gate
 * (`executables.worker?.includesChat`).
 *
 * The name below MUST equal the positional argument the CLI is invoked with,
 * byte for byte: `publishManifest` compares them and aborts otherwise. The
 * environment decides the TLD (`paseo-next-v2` -> `.paseo`, `preview` ->
 * `.test`, everything else -> dotNS's default `.dot`), so the workflow derives
 * the full name once and passes it both as the argument and as
 * `PLAYGROUND_DOTNS_NAME`. The default here matches the workflow's default
 * environment so a local `bulletin-deploy ./out truapi-playground.paseo` works
 * with no extra setup.
 *
 * Paths resolve relative to this file. `app` points at `out` so it reuses the
 * CID from the build-dir upload instead of re-uploading the same bytes. The
 * worker stays nested at `out/worker` on purpose: brevity-dozer decides
 * whether a product has chat by probing for `worker/index.js` inside the app
 * archive rather than reading `includes.chat`, so moving it out would cost us
 * chat there. The trade-off is that the worker bytes are stored twice.
 *
 * `bulletin-deploy` is installed globally rather than as a project dependency,
 * so this file imports nothing from it. That also means there is no
 * compile-time checking of the shape below; it is validated at deploy time by
 * `validateProductConfig`.
 */

// Build identifier: the short commit hash of the deployed tree, stamped into
// the SemVer's 4th element. Falls back to 'dev' when git isn't available
// (e.g. deploying from a tarball outside a checkout).
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
