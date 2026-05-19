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
- SOPS decryption enabled in Flux (the tunnel token is a SOPS-encrypted secret)

## Setup

### 1. Create the tunnel in the Cloudflare dashboard

1. **Cloudflare Zero Trust → Networks → Tunnels** → **Create a tunnel**
2. Choose **Cloudflared** as the connector type
3. Name it (e.g. `home-ops` or `k8s`)
4. **Copy the token** (long string starting with `eyJ...`) — only shown once
5. Skip the "Install connector" page (we deploy in-cluster)
6. Skip the "Public hostnames" page (we'll add routes later via the dashboard)

### 2. Commit the tunnel token (SOPS-encrypted) to the repo

```bash
# kubernetes/apps/network/cloudflared/app/secret.sops.yaml
cat > /tmp/secret.yaml <<EOF
---
apiVersion: v1
kind: Secret
metadata:
  name: cloudflared-tunnel
  namespace: network
type: Opaque
stringData:
  token: eyJ...your-tunnel-token...
EOF
SOPS_AGE_KEY_FILE=./.sops/age-key.txt sops -e /tmp/secret.yaml > kubernetes/apps/network/cloudflared/app/secret.sops.yaml
rm /tmp/secret.yaml
```

### 3. Deploy via Flux

The Deployment, Service-less (cloudflared doesn't need to receive inbound traffic), 2-replica with anti-affinity, lives in `kubernetes/apps/network/cloudflared/app/deployment.yaml`. Push it and Flux applies it.

```bash
git add kubernetes/apps/network
git commit -m "feat(network): add cloudflared"
git push
```

### 4. Add Public Hostname routes in the dashboard

Back in **Cloudflare Zero Trust → Networks → Tunnels → home-ops → Configure → Public Hostname**:

For each app you want exposed, click **Add a public hostname**:

| Field        | Value                                                      | Why                                      |
| ------------ | ---------------------------------------------------------- | ---------------------------------------- |
| Subdomain    | `<app>` (e.g. `echo`, `plex`)                              | The hostname users hit                   |
| Domain       | `wajeht.com`                                               | Your Cloudflare zone                     |
| Path         | leave empty                                                | Unless you want path-based routing       |
| Service Type | `HTTP`                                                     | TLS is at the edge; inside is plain HTTP |
| Service URL  | `cilium-gateway-internet.kube-system.svc.cluster.local:80` | Where to send traffic in-cluster         |

**Cloudflare auto-creates** a CNAME `<app>.wajeht.com → <tunnel-id>.cfargotunnel.com`. No manual DNS edits.

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

## Tunnel token vs credentials file

Cloudflare offers two ways to authenticate cloudflared:

| Method                  | What you store                             | When to use                                                   |
| ----------------------- | ------------------------------------------ | ------------------------------------------------------------- |
| **Token** (what we use) | A single base64-encoded JWT                | Simpler, all config in CF dashboard                           |
| **Credentials file**    | `<tunnel-id>.json` with tunnel ID + secret | Config-as-code (`config.yml` defines hostname routes locally) |

Token is the modern recommended path. All hostname routes live in the CF dashboard, which means changes to routing don't need a git commit — useful for quick testing but less GitOps-pure.

If you ever want config-as-code, switch to the credentials file approach and commit `config.yml` to the repo. Trade-off is more YAML for stricter audit.

## Rotating the tunnel token

If the token leaks (e.g., gets pasted in a chat 😅):

1. **CF Zero Trust → Networks → Tunnels → home-ops → Configure → Token tab → Refresh**
2. Copy the new token
3. SOPS-encrypt + commit:
   ```bash
   sopsd kubernetes/apps/network/cloudflared/app/secret.sops.yaml  # decrypt to check current value
   # Edit the file, replace the token, re-encrypt
   sops kubernetes/apps/network/cloudflared/app/secret.sops.yaml  # interactive edit
   ```
4. Push. reloader sees the Secret change and rolls the cloudflared pods automatically.

Total downtime: ~30 seconds (the gap between old pods terminating and new pods establishing tunnel connections).

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

- Invalid token (TUNNEL_TOKEN env wrong) — re-encrypt secret
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
2. Push
3. Add the Public Hostname route in CF dashboard (`<app>.wajeht.com → cilium-gateway-internet.kube-system.svc.cluster.local:80`)
4. Done — works in <30s

Step 3 is the only manual bit. Future: external-dns + Cloudflare Tunnel ingress operator can automate it, but for a handful of apps it's not worth the complexity.

## References

- [Cloudflare Tunnel docs](https://developers.cloudflare.com/cloudflare-one/connections/connect-networks/)
- [cloudflared image versions](https://github.com/cloudflare/cloudflared/releases)
- [architecture.md](architecture.md) — where the tunnel sits in the bigger picture
