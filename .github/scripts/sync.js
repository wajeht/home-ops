// Triggers a docker-cd deploy sync after CI passes on main, for an instant
// deploy. docker-cd also polls every ~5 min, so a failed webhook is non-fatal —
// this step never fails the build; it just reports what happened.
// Invoked from .github/workflows/ci.yml: `node .github/scripts/sync.js`
// with DOCKER_CD_URL and DOCKER_CD_API_SECRET in the environment.

const url = process.env.DOCKER_CD_URL;
const secret = process.env.DOCKER_CD_API_SECRET;

(async () => {
  try {
    const res = await fetch(`${url}/api/sync`, {
      method: "POST",
      headers: { Authorization: `Bearer ${secret}` },
      signal: AbortSignal.timeout(10_000),
    });
    const text = await res.text();
    try {
      console.log(JSON.stringify(JSON.parse(text), null, 2));
    } catch {
      console.log(`Response (${res.status}): ${text}`);
    }
  } catch (err) {
    console.log(`Sync request failed (non-fatal): ${err.message}`);
  }
})();
