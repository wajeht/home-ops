import { setTimeout as delay } from "node:timers/promises";

const sites = [
  { url: "https://jaw.dev/", body: "<title>~/jaw.dev</title>" },
  { url: "https://ip.jaw.dev/healthz", body: "<span>Ok</span>" },
];
const incidentTitle = "🚨 External availability incident";

async function retry(action, wait) {
  for (let attempt = 1; attempt <= 3; attempt++) {
    try {
      return { value: await action(), attempts: attempt };
    } catch (err) {
      if (attempt === 3) throw err;
      await wait(10_000);
    }
  }
}

export async function checkAvailability({ request = fetch, wait = delay } = {}) {
  const { value: country } = await retry(async () => {
    const trace = await request("https://www.cloudflare.com/cdn-cgi/trace", {
      signal: AbortSignal.timeout(15_000),
      redirect: "error",
      cache: "no-store",
    });
    if (!trace.ok) throw new Error(`Runner location check returned HTTP ${trace.status}`);
    const country = /^loc=([A-Z]{2})$/m.exec(await trace.text())?.[1];
    if (!country) throw new Error("Runner location check returned no country");
    return country;
  }, wait);
  if (country !== "US") {
    throw new Error(
      `Monitor cannot verify US-only sites from runner country ${country}. Use a US runner; preserve the existing country restrictions.`,
    );
  }

  return Promise.all(
    sites.map(async (site) => {
      try {
        const { attempts } = await retry(async () => {
          const response = await request(site.url, {
            signal: AbortSignal.timeout(15_000),
            redirect: "manual",
            cache: "no-store",
          });
          if (response.status !== 200) throw new Error(`HTTP ${response.status}`);
          if (!(await response.text()).includes(site.body))
            throw new Error("Unexpected response body");
        }, wait);
        return { url: site.url, healthy: true, attempts };
      } catch (err) {
        return { url: site.url, healthy: false, attempts: 3, error: err.message };
      }
    }),
  );
}

// Like secrets-rotation.mjs, use an open issue for persistent, deduplicated state.
// GitHub issue notifications remain available when the home server is offline.
export default async function run({ github, context, core }, options = {}) {
  let results;
  try {
    results = await checkAvailability(options);
  } catch (err) {
    results = [{ url: "Runner location check", healthy: false, error: err.message }];
  }
  const summary = results
    .map(
      (result) =>
        `- ${result.healthy ? "PASS" : "FAIL"} ${result.url}: ${result.error ?? "HTTP 200 and expected content"}`,
    )
    .join("\n");
  core.info(summary);
  await core.summary.addRaw(`${summary}\n`).write();

  const open = await github.paginate(github.rest.issues.listForRepo, {
    owner: context.repo.owner,
    repo: context.repo.repo,
    state: "open",
    per_page: 100,
  });
  const incident = open.find((issue) => !issue.pull_request && issue.title === incidentTitle);
  const runUrl = `https://github.com/${context.repo.owner}/${context.repo.repo}/actions/runs/${context.runId}`;
  if (results.some((result) => !result.healthy)) {
    if (incident) {
      core.info(`Incident #${incident.number} already open. Skipping notification.`);
      return;
    }
    const issue = await github.rest.issues.create({
      owner: context.repo.owner,
      repo: context.repo.repo,
      title: incidentTitle,
      body: `${summary}\n\n[Workflow run](${runUrl})\n\nThis issue closes automatically when both public checks pass.`,
      assignees: [context.repo.owner],
    });
    core.info(`Opened ${issue.data.html_url}`);
  } else if (incident) {
    await github.rest.issues.update({
      owner: context.repo.owner,
      repo: context.repo.repo,
      issue_number: incident.number,
      state: "closed",
      state_reason: "completed",
      body: `${incident.body}\n\nRecovered: both public checks passed. [Workflow run](${runUrl})`,
    });
    core.info(`Closed incident #${incident.number}: recovered.`);
  }
}
