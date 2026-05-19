# Cloudflare Tunnel (cloudflared)

The cluster's external entry point. cloudflared makes an outbound QUIC connection from inside the cluster to Cloudflare's edge — no port forward, no exposed home IP, no need for dynamic DNS.

## Why this over a port forward

| Concern                               | Port forward (jaw.dev) | Cloudflare Tunnel (wajeht.com)  |
| ------------------------------------- | ---------------------- | ------------------------------- |
| Exposes home WAN IP                   | Yes                    | No                              |
| Needs port 443 free                   | Yes                    | No (already taken by docker-cd) |
| Needs dynamic DNS                     | Yes                    | No                              |
| TLS termination                       | Traefik in cluster     | Cloudflare edge                 |
| Outage if WAN IP rotates              | Yes (DNS update lag)   | No                              |
| Adds latency                          | None (direct)          | +1 hop via CF edge              |
| Security: WAF, region block, bot mgmt | Available              | Available                       |

For the k8s cluster we picked Tunnel because the docker-cd box is already using the home WAN port 443.

## Architecture (zero-touch per app)

The whole tunnel is one moving part. After the one-time setup below, adding a new app is **just an HTTPRoute** — no DNS edits, no `config.yml` edits, no dashboard clicks.

How it composes:

- **One wildcard CNAME** — `*.wajeht.com → <tunnel-id>.cfargotunnel.com` lives in the Cloudflare DNS zone. Any subdomain of `wajeht.com` resolves to the tunnel.
- **One wildcard catch-all in `config.yml`** — every request the tunnel receives gets forwarded to `cilium-gateway-internet.kube-system.svc.cluster.local:80`, regardless of Host header.
- **HTTPRoutes do the per-app routing** — the Cilium Gateway reads the Host header and forwards to the right Service.

Request flow:

```
user → <anything>.wajeht.com
     → wildcard CNAME → <tunnel-id>.cfargotunnel.com
     → Cloudflare edge (TLS termination + WAF)
     → tunnel (QUIC, outbound from cluster)
     → cloudflared pod
     → cilium-gateway-internet Service (any host)
     → Envoy (Cilium Gateway)
     → HTTPRoute matches Host header
     → app pod
```

## Prerequisites

- Cluster bootstrapped through cilium (so the in-cluster DNS + networking work)
- Flux running (so the Deployment lands via GitOps)
- SOPS decryption enabled in Flux (the tunnel credentials are a SOPS-encrypted secret)
- `cloudflared` installed locally (`brew install cloudflared`) — only needed at setup time, not for normal day-to-day work

## Setup (one-time, then forget)

We run cloudflared as a **locally-managed tunnel** — the tunnel is created via the `cloudflared` CLI, and `config.yml` (committed to git) is authoritative for ingress rules. Dashboard-created tunnels are remotely-managed and Cloudflare's edge will silently override your local `config.yml`; see the [locally vs remotely managed](#locally-vs-remotely-managed-tunnels-the-gotcha) section below.

### 1. Authenticate `cloudflared` against your Cloudflare account

```bash
cloudflared tunnel login
```

Opens a browser. Pick the `wajeht.com` zone and authorize. Writes `~/.cloudflared/cert.pem` (an Origin CA service token used for subsequent `cloudflared` API calls).

### 2. Create the tunnel via CLI

```bash
cloudflared tunnel create home-ops-cluster
```

Mints a new locally-managed tunnel. Prints:

```
Created tunnel home-ops-cluster with id <uuid>
Tunnel credentials written to ~/.cloudflared/<uuid>.json
```

The JSON file contains `AccountTag` / `TunnelID` / `TunnelSecret` — exactly what cloudflared needs inside the cluster.

### 3. Create the wildcard CNAME

```bash
cloudflared tunnel route dns home-ops-cluster "*.wajeht.com"
```

One DNS record covers every subdomain. If a previous record already exists, pass `--overwrite-dns`.

### 4. Commit the credentials (SOPS-encrypted) to the repo

```bash
cat > /tmp/secret.yaml <<EOF
---
apiVersion: v1
kind: Secret
metadata:
  name: cloudflared-tunnel
  namespace: network
type: Opaque
stringData:
  credentials.json: |
    $(cat ~/.cloudflared/<uuid>.json)
EOF

# Write plaintext into the SOPS path, then encrypt in place (the .sops.yaml
# creation_rule for `kubernetes/*.sops.yaml` adds the age recipient + regex).
cp /tmp/secret.yaml kubernetes/apps/cloudflared/app/secret.sops.yaml
rm /tmp/secret.yaml
SOPS_AGE_KEY_FILE=./.sops/age-key.txt \
  sops --encrypt --in-place kubernetes/apps/cloudflared/app/secret.sops.yaml
```

### 5. Point `configmap.yaml` at the new tunnel UUID

`kubernetes/apps/cloudflared/app/configmap.yaml` holds the cloudflared `config.yml`. The ingress section is a **single wildcard catch-all** — keep it that way:

```yaml
data:
  config.yml: |
    tunnel: <uuid>
    credentials-file: /etc/cloudflared/creds/credentials.json
    metrics: 0.0.0.0:2000
    no-autoupdate: true
    ingress:
      - service: http://cilium-gateway-internet.kube-system.svc.cluster.local:80
```

That's the whole config. Cilium Gateway + HTTPRoute resources handle per-hostname routing inside the cluster.

### 6. Push

```bash
make kustomize-lint
git add kubernetes/apps/cloudflared
git commit -m "feat(cloudflared): bootstrap locally-managed tunnel"
git push
```

Flux deploys 2 replicas with anti-affinity. Reloader watches the ConfigMap + Secret and rolls pods on change.

## Per-app workflow

Adding a new app:

1. Write the HTTPRoute on the `internet` Gateway with `hostnames: [<app>.wajeht.com]` (see [adding-apps.md](adding-apps.md))
2. Push

That's it. The wildcard CNAME already resolves `<app>.wajeht.com` to the tunnel. The catch-all in `config.yml` forwards everything to the Gateway. The HTTPRoute does the matching. No DNS edits, no `config.yml` edits, no dashboard clicks.

## Locally vs remotely managed tunnels (the gotcha)

Cloudflare has two flavors of tunnel and **the flag is set at creation, not configurable later**:

| Created via                     | Type             | Where ingress lives         | Local `config.yml` is…  |
| ------------------------------- | ---------------- | --------------------------- | ----------------------- |
| **Dashboard** ("Add a tunnel")  | Remotely-managed | Cloudflare's API (database) | **Silently overridden** |
| **`cloudflared tunnel create`** | Locally-managed  | `config.yml` in git         | Authoritative           |

If you ever see `Updated to new configuration: {...}` in cloudflared logs and the ingress doesn't match what's in your ConfigMap, the tunnel is remotely-managed — the only fix is to create a new tunnel via the CLI ([cloudflared#843](https://github.com/cloudflare/cloudflared/issues/843)).

## Why two replicas with anti-affinity

cloudflared maintains multiple persistent connections to Cloudflare edge POPs. If a pod dies:

- The other replica keeps the tunnel up
- Cloudflare load-balances new requests to whichever replicas are connected
- A single node going down doesn't sever the tunnel

The `podAntiAffinity` rule prefers spreading pods across nodes, so it survives a node loss too.

## Rotating the tunnel credentials

If the credentials leak (e.g. age key compromise):

1. `cloudflared tunnel delete home-ops-cluster` (deletes the tunnel + invalidates the secret)
2. Re-run setup steps 2–6 above (create new tunnel, wildcard CNAME stays — just gets `--overwrite-dns` to repoint at the new UUID)
3. Push. Reloader rolls cloudflared with the new creds + UUID (~30s reconnect)

## Troubleshooting

### Logs show `Updated to new configuration: {...}` and the ingress isn't what's in our ConfigMap

The tunnel is remotely-managed (dashboard-created). Locally-managed `config.yml` is being overridden by Cloudflare's edge. See [locally vs remotely managed](#locally-vs-remotely-managed-tunnels-the-gotcha) — fix is to recreate the tunnel via the CLI.

### One hostname works, another hangs / returns CF error

Check for an explicit CNAME shadowing the wildcard:

```bash
# Lists all wajeht.com DNS records (needs a CF API token with Zone:DNS:Read)
ZONE=$(curl -s -H "Authorization: Bearer $CF_TOKEN" \
  "https://api.cloudflare.com/client/v4/zones?name=wajeht.com" \
  | jq -r '.result[0].id')
curl -s -H "Authorization: Bearer $CF_TOKEN" \
  "https://api.cloudflare.com/client/v4/zones/$ZONE/dns_records?per_page=100" \
  | jq -r '.result[] | "\(.name) \(.type) \(.content)"'
```

More-specific records win over wildcards. Delete any leftover `<host>.wajeht.com` CNAMEs that point at an old tunnel ID.

### Tunnel pods running but requests return 502/521 from Cloudflare

cloudflared can't reach the upstream service inside the cluster.

```bash
# Verify the gateway service exists
kubectl get svc -n kube-system cilium-gateway-internet
# Should show CLUSTER-IP and PORT 80
```

If missing, the Cilium Gateway hasn't been created yet (see [cilium.md](cilium.md)).

### Tunnel pods crash-looping

```bash
kubectl -n network logs -l app=cloudflared --tail=50
```

Common causes:

- Invalid credentials (wrong `AccountTag`/`TunnelID`/`TunnelSecret` in the SOPS secret)
- `tunnel:` UUID in `configmap.yaml` doesn't match the credentials' `TunnelID`
- Network egress blocked — Talos default allows it, but check NetworkPolicies if you added any
- DNS issues — cluster CoreDNS broken

### Logs show `Cannot determine default origin certificate path`

Harmless — that path is only used for `cloudflared tunnel <subcommand>` CLI ops (i.e. the one-time setup commands run from a laptop), not for running the tunnel itself. Ignore.

### Requests reach Cloudflare but never the tunnel

You probably have a Cloudflare Redirect Rule or Page Rule intercepting before the tunnel. Check **Rules → Redirect Rules** for the zone.

```bash
# Verify by checking cloudflared logs (empty = request never arrived)
kubectl -n network logs -l app=cloudflared --tail=20 | grep -E "GET|POST"
```

## References

- [Cloudflare Tunnel docs](https://developers.cloudflare.com/cloudflare-one/connections/connect-networks/)
- [Locally-managed tunnels](https://developers.cloudflare.com/cloudflare-one/networks/connectors/cloudflare-tunnel/do-more-with-tunnels/local-management/) — the mode we use
- [cloudflared#843](https://github.com/cloudflare/cloudflared/issues/843) — long-running issue about disabling remote-config override
- [cloudflared image versions](https://github.com/cloudflare/cloudflared/releases)
- [architecture.md](architecture.md) — where the tunnel sits in the bigger picture
