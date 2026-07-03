// Opens a GitHub issue with a secret-rotation checklist when a cadence is due.
// Invoked from .github/workflows/secrets-rotation.yml via actions/github-script:
//   const run = require('./.github/scripts/secrets-rotation.js')
//   await run({ github, context, core })
// The secret inventory lives in .github/secrets-rotation.json (names only, no values).

const fs = require("fs");

const CADENCE = {
  quarterly: {
    emoji: "🔴",
    label: "Quarterly",
    months: [1, 4, 7, 10],
    note: "External, billed, or high-blast-radius tokens.",
  },
  semiannual: {
    emoji: "🟠",
    label: "Semi-annual",
    months: [1, 7],
    note: "OAuth client secrets, provider keys, internal API keys.",
  },
  annual: {
    emoji: "🔵",
    label: "Annual",
    months: [1],
    note: "App signing secrets, DB passwords, admin & SMTP creds. Master keys are review-only.",
  },
};

// Render one manifest entry as a task-list item. "app / SECRET" ids get the app
// bolded and the secret in monospace; everything else falls back to bold.
function item(entry) {
  const parts = entry.id.split(" / ");
  const label = parts.length === 2 ? `**${parts[0]}** · \`${parts[1]}\`` : `**${entry.id}**`;
  return `- [ ] ${label} — ${entry.what}\n  <sub>↳ ${entry.where}</sub>\n`;
}

module.exports = async ({ github, context, core }) => {
  const manifest = JSON.parse(fs.readFileSync(".github/secrets-rotation.json", "utf8"));

  const now = new Date();
  const month = now.getUTCMonth() + 1; // 1-12
  const year = now.getUTCFullYear();
  const quarter = Math.floor((month - 1) / 3) + 1;
  const force = context.payload.inputs && context.payload.inputs.force_all === "true";

  const due = Object.keys(CADENCE).filter((c) => force || CADENCE[c].months.includes(month));
  if (due.length === 0) {
    core.info(`Nothing due in month ${month}. Exiting.`);
    return;
  }

  const title = `🔐 Secret rotation — ${year} Q${quarter}`;

  // Idempotency: skip if an open issue with this title already exists.
  const open = await github.paginate(github.rest.issues.listForRepo, {
    owner: context.repo.owner,
    repo: context.repo.repo,
    state: "open",
    per_page: 100,
  });
  if (open.some((i) => i.title === title)) {
    core.info(`Issue "${title}" already open. Skipping.`);
    return;
  }

  const total = due.reduce((n, c) => n + manifest[c].length, 0);

  let body = "";
  body += `> [!WARNING]\n`;
  body += `> This repo is **public** — SOPS is the only thing protecting these values. Rotate promptly on any suspected exposure.\n\n`;
  body += `Rotate each secret at its source, then update the encrypted \`apps/<app>/.env.sops\`, commit, and push — docker-cd redeploys.\n\n`;
  body += `📖 [Rotation policy & how-to](../blob/main/docs/security.md#secret-rotation)  ·  **${total}** secrets due this cycle\n`;
  for (const cadence of due) {
    const c = CADENCE[cadence];
    body += `\n## ${c.emoji} ${c.label}  <sub>· ${manifest[cadence].length}</sub>\n\n`;
    body += `<sub>${c.note}</sub>\n\n`;
    for (const entry of manifest[cadence]) body += item(entry);
  }

  // Ensure labels exist, then open the issue assigned to the repo owner.
  for (const [name, color] of [
    ["security", "d93f0b"],
    ["rotation", "fbca04"],
  ]) {
    try {
      await github.rest.issues.getLabel({
        owner: context.repo.owner,
        repo: context.repo.repo,
        name,
      });
    } catch {
      await github.rest.issues.createLabel({
        owner: context.repo.owner,
        repo: context.repo.repo,
        name,
        color,
      });
    }
  }

  const issue = await github.rest.issues.create({
    owner: context.repo.owner,
    repo: context.repo.repo,
    title,
    body,
    labels: ["security", "rotation"],
    assignees: [context.repo.owner],
  });
  core.info(`Opened ${issue.data.html_url}`);
};
