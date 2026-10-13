import { appendFile } from "node:fs/promises";
import { setTimeout as delay } from "node:timers/promises";
import { pathToFileURL } from "node:url";

const sites = [
  { url: "https://jaw.dev/", body: "<title>~/jaw.dev</title>" },
  { url: "https://ip.jaw.dev/healthz", body: "<span>Ok</span>" },
];

// GitHub sends workflow-failure notifications independently of the home server.
// No self-hosted ntfy dependency: it may be down along with the sites.
export async function checkAvailability({ request = fetch, wait = delay } = {}) {
  const trace = await request("https://www.cloudflare.com/cdn-cgi/trace", {
    signal: AbortSignal.timeout(15_000),
    redirect: "error",
    cache: "no-store",
  });
  if (!trace.ok) throw new Error(`Runner location check returned HTTP ${trace.status}`);
  const country = /^loc=([A-Z]{2})$/m.exec(await trace.text())?.[1];
  if (country !== "US") {
    throw new Error(
      `Monitor cannot verify US-only sites from runner country ${country ?? "unknown"}. Use a US runner; preserve the existing country restrictions.`,
    );
  }

  return Promise.all(
    sites.map(async (site) => {
      let error;
      for (let attempt = 1; attempt <= 3; attempt++) {
        try {
          const response = await request(site.url, {
            signal: AbortSignal.timeout(15_000),
            redirect: "manual",
            cache: "no-store",
          });
          if (response.status !== 200) throw new Error(`HTTP ${response.status}`);
          if (!(await response.text()).includes(site.body)) {
            throw new Error("Unexpected response body");
          }
          return { url: site.url, healthy: true, attempts: attempt };
        } catch (err) {
          error = err.message;
          if (attempt < 3) await wait(10_000);
        }
      }
      return { url: site.url, healthy: false, attempts: 3, error };
    }),
  );
}

async function main() {
  try {
    const results = await checkAvailability();
    const summary = results
      .map(
        (result) =>
          `- ${result.healthy ? "PASS" : "FAIL"} ${result.url}: ${result.error ?? "HTTP 200 and expected content"} (${result.attempts} attempts)`,
      )
      .join("\n");
    console.log(summary);
    if (process.env.GITHUB_STEP_SUMMARY) {
      await appendFile(process.env.GITHUB_STEP_SUMMARY, `${summary}\n`);
    }
    if (results.some((result) => !result.healthy)) process.exitCode = 1;
  } catch (err) {
    console.error(err.message);
    process.exitCode = 1;
  }
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  await main();
}
