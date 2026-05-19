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

## Prerequisites

- Cluster bootstrapped through cilium (so the in-cluster DNS + networking work)
- Flux running (so the Deployment lands via GitOps)
- SOPS decryption enabled in Flux (the tunnel credentials are a SOPS-encrypted secret)

## Setup (config-file mode — GitOps native)

We run cloudflared with a **credentials JSON** + **`config.yml` ingress rules** rather than the token-based mode. Public hostname routes live in git (`configmap.yaml`), not in the Cloudflare dashboard. Adding a new app = 2-line PR; no dashboard clicks per app.

### 1. Create the tunnel in the Cloudflare dashboard

1. **Cloudflare Zero Trust → Networks → Tunnels** → **Create a tunnel**
2. Choose **Cloudflared** as the connector type
3. Name it (e.g. `home-ops`)
4. **Copy the token** (long string starting with `eyJ...`) — we'll only use it once, to extract credentials
5. Skip the "Install connector" page (we deploy in-cluster)
6. Skip the "Public hostnames" page (we declare them in git)

### 2. Extract credentials from the token

The token is base64-encoded JSON wrapping the tunnel ID, account tag, and secret. Decode it locally:

```bash
echo '<the-token>' | base64 -d | jq
# {
#   "a": "<account-tag>",
#   "t": "<tunnel-id-uuid>",
#   "s": "<base64-tunnel-secret>"
# }
```

Cloudflared expects `credentials.json` with renamed keys:

```json
{
  "AccountTag": "<a>",
  "TunnelID": "<t>",
  "TunnelSecret": "<s>"
}
```

### 3. Commit the credentials (SOPS-encrypted) to the repo

```bash
# kubernetes/apps/cloudflared/app/secret.sops.yaml — stringData holds creds.json
cat > /tmp/secret.yaml <<EOF
---
apiVersion: v1
kind: Secret
metadata:
  name: cloudflared-tunnel
  namespace: network
type: Opaque
stringData:
  credentials.json: '{"AccountTag":"...","TunnelID":"...","TunnelSecret":"..."}'
EOF
SOPS_AGE_KEY_FILE=./.sops/age-key.txt sops -e /tmp/secret.yaml > kubernetes/apps/cloudflared/app/secret.sops.yaml
rm /tmp/secret.yaml
```

### 4. Declare ingress rules in `configmap.yaml`

`kubernetes/apps/cloudflared/app/configmap.yaml` holds the cloudflared `config.yml`:

```yaml
data:
  config.yml: |
    tunnel: <tunnel-id-uuid>
    credentials-file: /etc/cloudflared/creds/credentials.json
    metrics: 0.0.0.0:2000
    no-autoupdate: true
    ingress:
      - hostname: echo.wajeht.com
        service: http://cilium-gateway-internet.kube-system.svc.cluster.local:80
      - hostname: hello-world.wajeht.com
        service: http://cilium-gateway-internet.kube-system.svc.cluster.local:80
      - service: http_status:404   # default fallback
```

Adding a new app = add 2 lines (a new `- hostname: ... service: ...` block) and push. Reloader watches the ConfigMap and restarts cloudflared automatically (~30s tunnel reconnect).

### 5. Deploy via Flux

The Deployment is Service-less (cloudflared only initiates outbound connections), 2 replicas with anti-affinity, mounts both the creds Secret and config ConfigMap.

```bash
git add kubernetes/apps/cloudflared
git commit -m "feat(cloudflared): add cloudflared tunnel"
git push
```

### 6. Cloudflare auto-creates DNS

For each hostname listed in `config.yml`, Cloudflare automatically creates a CNAME `<host>.wajeht.com → <tunnel-id>.cfargotunnel.com`. No manual DNS edits. Note: if you previously had public hostnames configured in the dashboard, the `config.yml` ingress rules take precedence — but it's still cleanest to remove the old dashboard entries to avoid confusion.

After this, the request flow is:

```
user → echo.wajeht.com (CNAME → tunnel)
     → Cloudflare edge (TLS termination + WAF)
     → tunnel (QUIC, outbound from cluster)
     → cloudflared pod
     → cilium-gateway-internet Service
     → Envoy proxy (Cilium Gateway)
     → HTTPRoute matches Host header
     → app pod
```

## Why two replicas with anti-affinity

cloudflared maintains multiple persistent connections to Cloudflare edge POPs. If a pod dies:

- The other replica keeps the tunnel up
- Cloudflare load-balances new requests to whichever replicas are connected
- A single node going down doesn't sever the tunnel

The `podAntiAffinity` rule prefers spreading pods across nodes, so it survives a node loss too.

## Token vs credentials-file mode

Cloudflare offers two ways to run cloudflared:

| Mode                               | Where ingress lives  | Add a new hostname                 |
| ---------------------------------- | -------------------- | ---------------------------------- |
| **Token** (single base64 JWT)      | Cloudflare dashboard | 1 click per hostname in the CF UI  |
| **Credentials file** (what we use) | `config.yml` in git  | 1 PR (2 lines in `configmap.yaml`) |

We picked credentials-file mode for GitOps purity — every public hostname mapping is auditable in git history. Trade-off: cloudflared restarts (~30s tunnel reconnect) when the ConfigMap changes, vs. token mode which only restarts on token rotation.

## Rotating the tunnel credentials

If the credentials leak (e.g. age key compromise):

1. **CF Zero Trust → Networks → Tunnels → home-ops → Configure** → delete the tunnel
2. Re-create the tunnel — copy the new token
3. Decode the token to extract creds (see Step 2 of Setup), build new `credentials.json`
4. Re-encrypt:
   ```bash
   sops kubernetes/apps/cloudflared/app/secret.sops.yaml  # interactive edit
   ```
5. Update the `tunnel:` UUID in `configmap.yaml` to match the new tunnel ID
6. Push. Reloader rolls the cloudflared pods automatically (~30s downtime).

## Troubleshooting

### Tunnel pods running but requests return 502/521 from Cloudflare

cloudflared can't reach the upstream service inside the cluster.

```bash
# Verify the gateway service exists
kubectl get svc -n kube-system cilium-gateway-internet
# Should show CLUSTER-IP and PORT 80
```

If missing, the Cilium Gateway hasn't been created yet (see [cilium.md](cilium.md)).

### Tunnel pods crash-looping

Check logs:

```bash
kubectl -n network logs -l app=cloudflared --tail=50
```

Common causes:

- Invalid credentials (e.g. wrong `AccountTag`/`TunnelID`/`TunnelSecret` in the SOPS secret) — re-extract from the dashboard token (see Setup → Step 2) and re-encrypt
- `tunnel:` UUID in `configmap.yaml` doesn't match the credentials' `TunnelID`
- Network egress blocked — Talos default allows it, but check NetworkPolicies if you added any
- DNS issues — cluster CoreDNS broken

### Requests reach Cloudflare but never the tunnel

You probably have a Cloudflare Redirect Rule or Page Rule intercepting before the tunnel. Check **Rules → Redirect Rules** for the zone. Common culprit: a `*.example.com → github.com/...` rule from years ago.

```bash
# Verify by checking cloudflared logs (empty = request never arrived)
kubectl -n network logs -l app=cloudflared --tail=20 | grep -E "GET|POST"
```

## Per-app hostname workflow

For every new app you add:

1. Write the HTTPRoute + Deployment + Service as normal (see [adding-apps.md](adding-apps.md))
2. Add a 2-line ingress block to `kubernetes/apps/cloudflared/app/configmap.yaml`:
   ```yaml
   - hostname: <app>.wajeht.com
     service: http://cilium-gateway-internet.kube-system.svc.cluster.local:80
   ```
   Keep the `- service: http_status:404` default fallback at the bottom.
3. Push. Flux reconciles, reloader sees the ConfigMap change, cloudflared restarts (~30s tunnel reconnect), Cloudflare auto-creates the CNAME.

No dashboard clicks. Every public hostname mapping lives in git.

## References

- [Cloudflare Tunnel docs](https://developers.cloudflare.com/cloudflare-one/connections/connect-networks/)
- [cloudflared image versions](https://github.com/cloudflare/cloudflared/releases)
- [architecture.md](architecture.md) — where the tunnel sits in the bigger picture
