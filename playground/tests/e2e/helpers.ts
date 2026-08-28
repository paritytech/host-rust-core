import { expect, type FrameLocator, type Page } from "@playwright/test";

/**
 * Where the playground's own DOM lives. Under a host that iframes it that is a
 * frame; driven directly against a local `truapi-host dev` bridge it is the
 * page itself. Specs only ever reach for playground selectors, so they read the
 * same either way.
 */
export type PlaygroundSurface = Pick<Page, "locator" | "getByRole" | "getByText">;

/** Host the suite runs against. `cli` needs `truapi-host dev` on :9955. */
export const HOST_MODE = process.env.TRUAPI_E2E_HOST === "cli" ? "cli" : "dotli";

/**
 * Open the playground against whichever host the run targets.
 */
export async function openPlayground(page: Page): Promise<PlaygroundSurface> {
  return HOST_MODE === "cli"
    ? openPlaygroundOnCliHost(page)
    : openPlaygroundInDotli(page);
}

/**
 * Open the playground in a plain tab, hosted by a local `truapi-host dev`.
 *
 * The product's development-only `<script>` tag installs the bridge, so there
 * is no iframe and no host shell: the page is the playground.
 */
export async function openPlaygroundOnCliHost(
  page: Page,
): Promise<PlaygroundSurface> {
  await page.addInitScript(() => {
    localStorage.setItem("truapi:playground:e2e", "1");
    (
      window as typeof window & { __TRUAPI_PLAYGROUND_E2E__?: boolean }
    ).__TRUAPI_PLAYGROUND_E2E__ = true;
  });
  await page.goto("/");
  await expect(page.locator(".status")).toBeVisible({ timeout: 30_000 });
  return page;
}

/**
 * Open the playground inside dotli's iframe shell and wait for it to mount.
 *
 * The dotli host parses `/localhost:<port>` as a proxy directive and iframes
 * `http://localhost:3000`. The `dotliProductId` query param is host-only; it
 * makes local e2e use the same product id as the deployed playground examples.
 * We hand back the FrameLocator scoped to that iframe so individual specs only
 * need to know about playground selectors.
 */
export async function openPlaygroundInDotli(page: Page): Promise<FrameLocator> {
  await page.addInitScript(() => {
    localStorage.setItem("dotli:mode", "gateway");
    localStorage.setItem("dotli:chain-backend", "rpc");
    localStorage.setItem("dotli:content-backend", "ipfs-gateway");
    localStorage.setItem(
      "dotli:permissions:localhost:3000",
      JSON.stringify({ Camera: "granted" }),
    );
    localStorage.setItem("desktop-banner-dismissed", "1");
    localStorage.setItem("truapi:playground:e2e", "1");
    (
      window as typeof window & { __TRUAPI_PLAYGROUND_E2E__?: boolean }
    ).__TRUAPI_PLAYGROUND_E2E__ = true;
  });
  await page.goto("/localhost:3000?dotliProductId=truapi-playground.dot");
  // dotli renders an additional hidden iframe (host.localhost:5173?mode=direct)
  // alongside the proxied playground; scope to the playground src so the
  // FrameLocator is unique under Playwright strict mode.
  const frame = page.frameLocator('iframe[src^="http://localhost:3000"]');
  // The playground renders the masthead once mounted; the status chip is
  // there from the first render in either splash or shell mode.
  await expect(frame.locator(".status")).toBeVisible({ timeout: 30_000 });
  return frame;
}

/**
 * Wait for the connection chip to flip to "Host Linked" (status--connected).
 *
 * Pre-handshake the playground renders the splash; the chip lives in the
 * masthead which only mounts once status !== connecting. We wait on the
 * class rather than the label so the assertion is locale-agnostic.
 */
export async function waitForOnline(frame: PlaygroundSurface): Promise<void> {
  await expect(frame.locator(".status.status--connected")).toBeVisible({
    timeout: 15_000,
  });
}

/**
 * Click the method button in the service rail.
 *
 * Selectors are stable thanks to `data-testid="method-<service>-<method>"`
 * on each ServiceTable button.
 */
export async function selectMethod(
  frame: PlaygroundSurface,
  service: string,
  method: string,
): Promise<void> {
  await frame.locator(`[data-testid="method-${service}-${method}"]`).click();
}
