# vaultwarden

Self-hosted Bitwarden-compatible password vault ([dani-garcia/vaultwarden](https://github.com/dani-garcia/vaultwarden)).

WebUI: `https://vault.jaw.dev`
Admin: `https://vault.jaw.dev/admin` (gated by `ADMIN_TOKEN`)

## ADMIN_TOKEN (Argon2 PHC)

Vaultwarden stores the admin token as an Argon2id PHC hash. The plaintext password you type into the prompt is what you'll enter at `/admin` to log in; the hash is what lives in `.env.sops`.

### Generate / rotate

1. **Hash the password** — run on the server (vaultwarden container must be running):

   ```bash
   docker exec -it vaultwarden /vaultwarden hash
   ```

   It prompts twice for your desired admin password and outputs a line like:

   ```
   ADMIN_TOKEN='$argon2id$v=19$m=65540,t=3,p=4$...$...'
   ```

   The single quotes are part of the output — keep them; they protect the `$` characters from shell/dotenv interpolation.

2. **Update `.env.sops`** — locally, from the repo root:

   ```bash
   export SOPS_AGE_KEY_FILE=./.sops/age-key.txt
   sops --input-type dotenv --output-type dotenv apps/vaultwarden/.env.sops
   ```

   Replace the `ADMIN_TOKEN=...` line with the new hashed value (including the single quotes). Save and exit.

3. **Commit + push** — docker-cd redeploys on next poll. The `[NOTICE] You are using a plain text ADMIN_TOKEN` log line should disappear.

4. **Store the plaintext password** in your password manager. It's the only way to access `/admin`; if you lose it, you must regenerate the hash and update `.env.sops` again.

### Login

At `https://vault.jaw.dev/admin`, enter the **plaintext password** from step 1 — NOT the `$argon2id...` hash.

### "Too many requests" on /admin

Vaultwarden's admin page has its own failure-counter rate limit (separate from Traefik's). Three failed token entries triggers a temporary ban. Fastest reset:

```bash
docker restart vaultwarden
```

## Caps

Needs `CHOWN, DAC_OVERRIDE, FOWNER, NET_BIND_SERVICE, SETGID, SETUID`. The recent vaultwarden image runs as a non-root user and writes to `/data` — without `DAC_OVERRIDE` you get `attempt to write a readonly database` panics on startup.
