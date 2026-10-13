import assert from "node:assert/strict";
import test from "node:test";
import run, { checkAvailability } from "./availability.mjs";

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
      /Monitor cannot verify US-only sites|Runner location check returned no country/,
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

test("temporary location-service failures retry before checking the sites", async () => {
  let attempts = 0;
  let pauses = 0;
  const result = await checkAvailability({
    wait: async (milliseconds) => {
      assert.equal(milliseconds, 10_000);
      pauses++;
    },
    request: async (url) => {
      if (url.includes("cdn-cgi/trace")) {
        attempts++;
        if (attempts === 1) throw new Error("Connection timed out");
        if (attempts === 2) return new Response("temporary error", { status: 503 });
        return trace();
      }
      assert.equal(attempts, 3);
      return new Response(content(url));
    },
  });
  assert.equal(pauses, 2);
  assert.ok(result.every((site) => site.healthy));
});

test("persistent location failure is bounded and does not probe sites", async () => {
  let calls = 0;
  await assert.rejects(
    checkAvailability({
      wait: noWait,
      request: async (url) => {
        assert.ok(url.includes("cdn-cgi/trace"));
        calls++;
        throw new Error("Connection timed out");
      },
    }),
    /Connection timed out/,
  );
  assert.equal(calls, 3);
});

function incidentHarness() {
  const issues = [];
  const events = [];
  const summaries = [];
  const summary = {
    addRaw: (text) => {
      summaries.push(text);
      return summary;
    },
    write: async () => {},
  };
  const args = {
    github: {
      paginate: async (_method, params) => {
        assert.equal(params.state, "open");
        return issues.filter((issue) => issue.state === "open");
      },
      rest: {
        issues: {
          listForRepo: async () => {},
          create: async (params) => {
            assert.deepEqual(params.assignees, ["wajeht"]);
            const issue = {
              ...params,
              number: issues.length + 1,
              state: "open",
              html_url: "https://example.com/incident",
            };
            issues.push(issue);
            events.push("opened");
            return { data: issue };
          },
          update: async (params) => {
            const issue = issues.find((item) => item.number === params.issue_number);
            Object.assign(issue, params);
            events.push("recovered");
            return { data: issue };
          },
        },
      },
    },
    context: { repo: { owner: "wajeht", repo: "home-ops" }, runId: 123 },
    core: { info: () => {}, summary },
  };
  return { args, issues, events, summaries };
}

const healthy = async (url) =>
  url.includes("cdn-cgi/trace") ? trace() : new Response(content(url));
const outage = async (url) =>
  url.includes("cdn-cgi/trace") ? trace() : new Response("outage", { status: 502 });

test("one incident per outage, one recovery, quiet healthy runs, and a new incident after recurrence", async () => {
  const h = incidentHarness();
  await run(h.args, { request: outage, wait: noWait });
  await run(h.args, { request: outage, wait: noWait });
  assert.deepEqual(h.events, ["opened"]);
  assert.match(h.issues[0].body, /HTTP 502/);
  await run(h.args, { request: healthy, wait: noWait });
  assert.deepEqual(h.events, ["opened", "recovered"]);
  assert.equal(h.issues[0].state, "closed");
  assert.match(h.issues[0].body, /Recovered: both public checks passed/);
  await run(h.args, { request: healthy, wait: noWait });
  assert.deepEqual(h.events, ["opened", "recovered"]);
  await run(h.args, { request: outage, wait: noWait });
  assert.deepEqual(h.events, ["opened", "recovered", "opened"]);
});

test("a failed location check cannot close an existing outage", async () => {
  const h = incidentHarness();
  await run(h.args, { request: outage, wait: noWait });
  await run(h.args, {
    request: async () => {
      throw new Error("trace unavailable");
    },
    wait: noWait,
  });
  assert.deepEqual(h.events, ["opened"]);
  assert.equal(h.issues[0].state, "open");
  assert.match(h.summaries.at(-1), /FAIL Runner location check/);
});

test("location errors create one persistent incident and recover after real site checks pass", async () => {
  const h = incidentHarness();
  const options = {
    request: async () => {
      throw new Error("trace unavailable");
    },
    wait: noWait,
  };
  await run(h.args, options);
  await run(h.args, options);
  assert.deepEqual(h.events, ["opened"]);
  assert.match(h.issues[0].body, /trace unavailable/);
  await run(h.args, { request: healthy, wait: noWait });
  assert.deepEqual(h.events, ["opened", "recovered"]);
});

test("partial recovery keeps the incident open", async () => {
  const h = incidentHarness();
  await run(h.args, { request: outage, wait: noWait });
  await run(h.args, {
    request: async (url) =>
      url.includes("ip.jaw.dev") ? new Response("outage", { status: 502 }) : healthy(url),
    wait: noWait,
  });
  assert.deepEqual(h.events, ["opened"]);
});

test("healthy runs leave unrelated issues and matching pull requests untouched", async () => {
  const h = incidentHarness();
  h.issues.push({ number: 10, title: "Other issue", state: "open" });
  h.issues.push({
    number: 11,
    title: "🚨 External availability incident",
    state: "open",
    pull_request: {},
  });
  await run(h.args, { request: healthy, wait: noWait });
  assert.deepEqual(h.events, []);
  assert.ok(h.issues.every((issue) => issue.state === "open"));
});

test("issue API errors propagate instead of hiding failed notification delivery", async () => {
  const h = incidentHarness();
  h.args.github.rest.issues.create = async () => {
    throw new Error("GitHub unavailable");
  };
  await assert.rejects(run(h.args, { request: outage, wait: noWait }), /GitHub unavailable/);
});
