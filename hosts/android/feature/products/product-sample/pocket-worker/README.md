# Pocket demo worker

A worker that publishes one Pocket card and draws its face live. It talks to the host through the
core's own client (`@parity/truapi`), so it needs no product SDK.

## Build

```sh
npm install
npm run build        # dist/worker.js
```

The published `@parity/truapi` (0.16.0) predates the Pocket API, so `client.pocket` is undefined
there and `npm run typecheck` fails against it. Until a release ships Pocket, build the client from
the core checkout that `truapi_ref` pins and install it over the published one:

```sh
"$TRUAPI_DIR"/js/scripts/codegen.sh
npm install --no-save "$TRUAPI_DIR/js/packages/truapi"
```

## Publish

The worker archive is what the host reads, so publish these files under the product's
`worker.<name>.<tld>` dotNS name:

```
worker.js            <- dist/worker.js
faces/loyalty.json   <- the static face the approval sheet shows
```

and set that name's `executable` text record to `manifest/worker.json`. The root manifest of
`<name>.<tld>` is unchanged.

## Try it on Android

1. Open `polkadotapp://<name>.<tld>/-/pocket/add?card=loyalty`. The approval sheet shows
   `faces/loyalty.json`; Add puts the card in the Pocket.
2. With the card on screen the host starts this worker, opens a render for `PocketCard { loyalty }`,
   and the face switches to the live tree. Stamp increments the counter; Remove asks the host to
   drop the card, which ends the render and stops the worker.
3. The console logs the card list on every change (`Pocket demo: cards ...`).
