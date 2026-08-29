import { readFileSync } from "node:fs";
import { createServer, type Server } from "node:http";
import type { AddressInfo } from "node:net";
import { expect, test } from "@playwright/test";

const TOKEN = "11".repeat(32);
const ONE_PIXEL_PNG = Buffer.from(
  "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=",
  "base64",
);
const scannerPage = readFileSync(
  new URL("../../../rust/crates/truapi-host-cli/src/scanner_page.html", import.meta.url),
  "utf8",
).replaceAll("__CSP_NONCE__", "fixture-nonce");

let server: Server;
let scannerUrl: string;
let frameStatus = 200;
let lastFrame: Buffer | undefined;
let lastAuthorization: string | undefined;
let cancelRequests = 0;

test.beforeAll(async () => {
  server = createServer(async (request, response) => {
    if (request.method === "GET" && request.url === "/") {
      response.writeHead(200, { "Content-Type": "text/html; charset=utf-8" });
      response.end(scannerPage);
      return;
    }

    if (request.method === "POST" && request.url === "/frame") {
      const chunks: Buffer[] = [];
      for await (const chunk of request) chunks.push(Buffer.from(chunk));
      lastFrame = Buffer.concat(chunks);
      lastAuthorization = request.headers.authorization;
      response.writeHead(frameStatus);
      response.end();
      return;
    }

    if (request.method === "POST" && request.url === "/cancel") {
      cancelRequests += 1;
      lastAuthorization = request.headers.authorization;
      response.writeHead(204);
      response.end();
      return;
    }

    response.writeHead(404);
    response.end();
  });
  await new Promise<void>((resolve) => server.listen(0, "127.0.0.1", resolve));
  const address = server.address() as AddressInfo;
  scannerUrl = `http://127.0.0.1:${address.port}`;
});

test.afterAll(async () => {
  await new Promise<void>((resolve, reject) =>
    server.close((error) => (error ? reject(error) : resolve())),
  );
});

test.beforeEach(() => {
  frameStatus = 200;
  lastFrame = undefined;
  lastAuthorization = undefined;
  cancelRequests = 0;
});

test("offers every source and removes the capability from browser history", async ({ page }) => {
  await page.goto(`${scannerUrl}/#${TOKEN}`);

  await expect(page.locator("body")).toHaveAttribute("data-state", "choosing");
  await expect(page.getByRole("button", { name: "Choose an app window or screen" })).toBeVisible();
  await expect(page.getByRole("button", { name: "Use a camera" })).toBeVisible();
  await expect(page.getByText("Choose a QR image")).toBeVisible();
  await expect(page.getByText("Or paste or drop a QR image here")).toBeVisible();
  await expect(page).toHaveURL(`${scannerUrl}/`);
});

test("rejects an invalid or expired capability before choosing a source", async ({ page }) => {
  await page.goto(`${scannerUrl}/#not-a-capability`);

  await expect(page.locator("body")).toHaveAttribute("data-state", "expired");
  await expect(
    page.getByText("This scanner link is invalid or expired. Run /pair again in the terminal."),
  ).toBeVisible();
  await expect(page).toHaveURL(`${scannerUrl}/`);
});

test("recovers from denied camera access with an actionable alternative", async ({ page }) => {
  await page.addInitScript(() => {
    const denied = new DOMException("denied", "NotAllowedError");
    Object.defineProperty(navigator, "mediaDevices", {
      configurable: true,
      value: {
        enumerateDevices: async () => [],
        getDisplayMedia: async () => {
          throw denied;
        },
        getUserMedia: async () => {
          throw denied;
        },
      },
    });
  });
  await page.goto(`${scannerUrl}/#${TOKEN}`);

  await page.getByRole("button", { name: "Use a camera" }).click();

  await expect(page.locator("body")).toHaveAttribute("data-state", "choosing");
  await expect(page.getByRole("alert")).toContainText("Camera permission was denied");
  await expect(page.getByText("Choose a source to try again.")).toBeVisible();
});

test("sends a bounded grayscale image and completes without exposing the deeplink", async ({
  page,
}) => {
  await page.goto(`${scannerUrl}/#${TOKEN}`);

  await page.locator("#image-file").setInputFiles({
    name: "pairing.png",
    mimeType: "image/png",
    buffer: ONE_PIXEL_PNG,
  });

  await expect(page.locator("body")).toHaveAttribute("data-state", "complete");
  await expect(page.getByRole("heading", { name: "QR code scanned" })).toBeFocused();
  expect(lastAuthorization).toBe(`Bearer ${TOKEN}`);
  expect(lastFrame?.readUInt32LE(0)).toBe(1);
  expect(lastFrame?.readUInt32LE(4)).toBe(1);
  expect(lastFrame).toHaveLength(9);
});

test("identifies a lost terminal connection instead of blaming the image", async ({ page }) => {
  frameStatus = 500;
  await page.goto(`${scannerUrl}/#${TOKEN}`);

  await page.locator("#image-file").setInputFiles({
    name: "pairing.png",
    mimeType: "image/png",
    buffer: ONE_PIXEL_PNG,
  });

  await expect(page.locator("body")).toHaveAttribute("data-state", "expired");
  await expect(page.getByText("The scanner lost its connection to the terminal.")).toBeVisible();
});

test("cancels the terminal scan and leaves a clear final state", async ({ page }) => {
  await page.goto(`${scannerUrl}/#${TOKEN}`);

  await page.getByRole("button", { name: "Cancel scan" }).click();

  await expect(page.locator("body")).toHaveAttribute("data-state", "cancelled");
  await expect(page.getByText("QR scan cancelled. You can close this tab.")).toBeVisible();
  await expect.poll(() => cancelRequests).toBe(1);
  expect(lastAuthorization).toBe(`Bearer ${TOKEN}`);
});

test("closing the scanner releases the waiting terminal command", async ({ page }) => {
  await page.goto(`${scannerUrl}/#${TOKEN}`);

  await page.close();

  await expect.poll(() => cancelRequests).toBe(1);
  expect(lastAuthorization).toBe(`Bearer ${TOKEN}`);
});
