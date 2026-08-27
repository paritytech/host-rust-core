import { defineConfig, devices } from "@playwright/test";

const isCI = !!process.env.CI;
const hostBinary = process.env.TRUAPI_HOST_BIN ?? "truapi-host";

/**
 * The playground driven in a plain browser tab against a local `truapi-host
 * dev`, rather than inside a host's iframe shell. Needs no dotli checkout: the
 * host serves the bridge script the product loads in development.
 */
export default defineConfig({
  testDir: "./tests/e2e",
  fullyParallel: false,
  forbidOnly: isCI,
  retries: isCI ? 1 : 0,
  workers: 1,
  reporter: isCI ? [["github"], ["html", { open: "never" }]] : "list",
  use: {
    baseURL: "http://localhost:3000",
    serviceWorkers: "block",
    trace: "retain-on-failure",
    screenshot: "only-on-failure",
    video: "retain-on-failure",
  },
  projects: [
    {
      name: "chromium",
      use: {
        ...devices["Desktop Chrome"],
        // Sandboxes often ship only the headless shell. Set
        // PLAYWRIGHT_CHANNEL=chromium-headless-shell there.
        ...(process.env.PLAYWRIGHT_CHANNEL
          ? { channel: process.env.PLAYWRIGHT_CHANNEL }
          : {}),
      },
    },
  ],
  webServer: [
    {
      // One process: the signing host binds :9955 and serves the bridge, then
      // runs the dev server once its signer exists.
      command: 'exec "$TRUAPI_HOST_BIN" dev -- yarn dev',
      env: { TRUAPI_HOST_BIN: hostBinary },
      url: "http://localhost:3000",
      reuseExistingServer: false,
      timeout: 5 * 60 * 1000,
      stdout: "pipe",
      stderr: "pipe",
    },
  ],
});
