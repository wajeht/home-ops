import assert from "node:assert/strict";
import test from "node:test";
import { checkAvailability } from "./availability.mjs";

const noWait = async () => {};
const content = (url) =>
  url.includes("ip.jaw.dev") ? "<span>Ok</span>" : "<title>~/jaw.dev</title>";
const trace = () => new Response("loc=US\n");

test("healthy sites include expected content and use bounded requests", async () => {
  const result = await checkAvailability({
    wait: noWait,
    request: async (url, options) => {
      assert.ok(options.signal instanceof AbortSignal);
      assert.equal(options.cache, "no-store");
      return url.includes("cdn-cgi/trace") ? trace() : new Response(content(url));
    },
  });
  assert.ok(result.every((site) => site.healthy && site.attempts === 1));
});

test("temporary network failures recover without a false outage", async () => {
  const attempts = new Map();
  const result = await checkAvailability({
    wait: noWait,
    request: async (url) => {
      if (url.includes("cdn-cgi/trace")) return trace();
      const count = (attempts.get(url) ?? 0) + 1;
      attempts.set(url, count);
      if (count === 1) throw new Error("Connection timed out");
      return new Response(content(url));
    },
  });
  assert.ok(result.every((site) => site.healthy && site.attempts === 2));
});

for (const status of [302, 403, 502]) {
  test(`HTTP ${status} remains a failure after three attempts`, async () => {
    const result = await checkAvailability({
      wait: noWait,
      request: async (url) =>
        url.includes("cdn-cgi/trace") ? trace() : new Response("unavailable", { status }),
    });
    assert.ok(
      result.every(
        (site) => !site.healthy && site.attempts === 3 && site.error === `HTTP ${status}`,
      ),
    );
  });
}

test("HTTP 200 with an error page is not healthy", async () => {
  const result = await checkAvailability({
    wait: noWait,
    request: async (url) => (url.includes("cdn-cgi/trace") ? trace() : new Response("error page")),
  });
  assert.ok(result.every((site) => !site.healthy && site.error === "Unexpected response body"));
});

test("non-US and unknown runners cannot silently report successful monitoring", async () => {
  for (const body of ["loc=GB\n", "missing location"]) {
    await assert.rejects(
      checkAvailability({ request: async () => new Response(body), wait: noWait }),
      /Monitor cannot verify US-only sites/,
    );
  }
});

test("location service failure fails the monitor", async () => {
  await assert.rejects(
    checkAvailability({
      request: async () => new Response("error", { status: 503 }),
      wait: noWait,
    }),
    /Runner location check returned HTTP 503/,
  );
});
