# Security

Security controls and verification for the OptiPlex Ubuntu server and home network.

## Server Access

Keep SSH and local app ports off the public internet. The public exceptions are listed under [Public Access](#public-access).

| Port   | Service        | Access and protection                                                                |
| ------ | -------------- | ------------------------------------------------------------------------------------ |
| 22     | SSH            | LAN or home VPN; key authentication only                                             |
| 80,443 | Traefik        | Public origin connections restricted to Cloudflare                                   |
| 1883   | MQTT           | Published to LAN; currently allows anonymous access                                  |
| 2283   | Immich         | LAN access for direct uploads; Immich authentication                                 |
| 8123   | Home Assistant | LAN access for the Companion App and camera streaming; Home Assistant authentication |
| 32400  | Plex           | LAN and US public access; Plex authentication                                        |

Direct app ports bypass Traefik's OAuth and Cloudflare country filtering. Do not forward MQTT, Immich, or Home Assistant ports from the internet.

### Host firewall

Keep incoming host traffic denied by default and allow only required services. Inspect rules with:

```bash
sudo ufw status verbose
sudo ufw status numbered
```

Do not assume UFW blocks Docker-published ports: MQTT, Immich, and Home Assistant are reachable from the main LAN. Control exposure through Docker port mappings and UniFi policies, then test from the relevant network. Preserve intentional LAN access when changing port mappings.

## SSH

SSH uses key-based authentication only. The Mac alias `ssh one` connects as `jaw`; password, keyboard-interactive, and direct root login are disabled.

Settings are in `/etc/ssh/sshd_config.d/00-homeops-key-only.conf`, loaded before the cloud-init configuration:

```
PubkeyAuthentication yes
PasswordAuthentication no
KbdInteractiveAuthentication no
PermitRootLogin no
```

For future changes, keep an existing SSH session open, validate the configuration, and reload:

```bash
sudo sshd -t && sudo systemctl reload ssh.service
```

Verify a fresh key login before closing the existing session:

```bash
ssh -o BatchMode=yes -o PreferredAuthentications=publickey -o ControlPath=none one 'id -un'
```

## Public Access

| Service                       | Allowed access                            | Enforcement                                                                         |
| ----------------------------- | ----------------------------------------- | ----------------------------------------------------------------------------------- |
| OptiPlex websites             | US visitors through Cloudflare            | Cloudflare country rule; UniFi and Traefik allow only Cloudflare origin connections |
| Direct Plex (`32400/tcp`)     | US sources                                | UniFi country rules; Plex authentication                                            |
| UniFi WireGuard (`51820/udp`) | Any country, with a configured client key | UniFi's built-in WireGuard allowance and VPN authentication                         |

Cloudflare and UniFi dashboard settings are managed manually; deploying this repo does not recreate them.

### Cloudflare and origin lock

Cloudflare's first active custom rule for `jaw.dev`, **only allow united states**, blocks `(ip.geoip.country ne "US")`. The apex, `www`, and wildcard DNS records are proxied.

UniFi forwards WAN1 ports `80,443` to `192.168.4.161` only from the **Cloudflare IPv4** source list. Traefik repeats the Cloudflare-only check on HTTPS routes, redirects HTTP to HTTPS, and trusts forwarded client headers only from Cloudflare. The **HTTP/HTTPS** port list contains only `80,443`.

Update Traefik's Cloudflare ranges with:

```bash
./scripts/cloudflare.sh
```

Review the diff and deploy through the normal git flow. This script **does not update UniFi's source list**; check that separately against [Cloudflare's published ranges](https://www.cloudflare.com/ips/).

### UniFi firewall

**CyberSecure → Region Blocking is OFF.** The global country filter would block WireGuard clients abroad and can also block Cloudflare origin connections classified outside the US. Country restrictions are applied per service instead.

UniFi uses the zone-based firewall. Default, Guest, and IoT are in Internal; WireGuard clients are in VPN. Manage policies under **Settings → Zones**:

| Zone pair           | Order | Policy                                  | Match                                                    | Action |
| ------------------- | ----- | --------------------------------------- | -------------------------------------------------------- | ------ |
| External → Internal | 10000 | Allow HTTP(S) from Cloudflare over IPv4 | Cloudflare IPv4 list → `192.168.4.161`, TCP/UDP `80,443` | Allow  |
| External → Internal | 10001 | Block HTTP(S) from Internet over IPv4   | Any IPv4 source → TCP/UDP `80,443`                       | Block  |
| External → Internal | 10002 | Allow US Plex                           | United States → `192.168.4.161`, IPv4 TCP `32400`        | Allow  |
| External → Internal | 10003 | Block other Plex access                 | Any source → TCP/UDP `32400`, IPv4 and IPv6              | Block  |
| External → Gateway  | 10000 | Block UCG services from WAN             | Any IPv4 source → ports `53,6789,8080,8443`              | Block  |
| External → Gateway  | 30002 | Allow WireGuard VPNs (built-in)         | Any source → gateway UDP `51820`, IPv4 and IPv6          | Allow  |

Order is evaluated within each zone pair. Custom policies precede generated port-forward allowances. The Plex port forward maps TCP/UDP `32400` to `192.168.4.161`; the policies above permit only US TCP traffic. Keep built-in return-traffic, invalid-traffic, default-deny, and IPv6 control-traffic policies intact. Do not add country restrictions to WireGuard.

WireGuard runs on the **UniFi gateway**, subnet `192.168.3.0/24`, with automatic DNS. Authenticated clients use the VPN zone's access rules. A full-tunnel client abroad can exit through the US home connection to access the websites; browsing directly from abroad remains subject to Cloudflare's country rule.

LAN IPv6 is disabled. Review equivalent IPv6 access restrictions before enabling it. Intrusion Prevention protects Default and Guest in **Notify and Block** mode.

## Guest and IoT Isolation

| Network | VLAN | Subnet            | Required isolation                                                                            |
| ------- | ---- | ----------------- | --------------------------------------------------------------------------------------------- |
| Default | 1    | `192.168.4.0/24`  | Trusted LAN                                                                                   |
| Guest   | 2    | `192.168.2.0/24`  | Internet allowed; access to other local networks blocked except the DNS allowance below       |
| IoT     | 30   | `192.168.30.0/24` | Internet and new connections to other local networks blocked; server-initiated access allowed |

Enable **Isolate Network** on Guest and IoT. Enable **Allow Internet Access** on Guest only, and Wi-Fi client isolation on Guest. Assign the IoT SSID to VLAN 30.

Keep these policies under **Settings → Zones**:

| Zone pair           | Order | Policy                                            | Match and action                                   |
| ------------------- | ----- | ------------------------------------------------- | -------------------------------------------------- |
| Internal → Internal | 10000 | Allow Server to IoT                               | Allow `192.168.4.161` → IoT                        |
| Internal → Internal | 10001 | Allow Established/Related IoT                     | Allow IoT replies only: **Return Traffic**         |
| Internal → Internal | 10002 | Allow Guest DNS to AdGuard                        | Allow Guest → `192.168.4.181`, TCP/UDP `53`        |
| Internal → Internal | 30000 | Isolated Networks (generated)                     | Block Guest and IoT access to other local networks |
| Internal → External | 30001 | Block 192.168.30.0/24 Internet Access (generated) | Block IoT internet access                          |

Keep allowances before the generated isolation policy. Every IoT reply allowance must use **Return Traffic**, including copies in other zone pairs, so it cannot permit new connections from IoT devices.

## App and Container Security

Use `oauth2-admin@file` for admin-only routes and `oauth2-media@file` for approved media routes. User allowlists are encrypted in `apps/oauth2-proxy/.env.sops`. Private app routes that intentionally bypass OAuth must retain their own application authentication; intentionally public pages do not require login.

Containers on the shared `traefik` network can reach each other's internal ports; ingress authentication does not isolate them. Keep databases on private app networks and expose only necessary ports. See [container hardening](adding-apps.md#container-hardening) for app requirements and [preview deployment](instant-deploy.md#temporary-pr-apps) for preview authentication.

Treat `/var/run/docker.sock` access as host administrator access. A read-only socket mount does not restrict Docker API operations. Grant access only to services that require it.

## Host Maintenance

Keep Ubuntu security updates, container images, and BIOS firmware current. Reboot when an update requires it.

Review unused services before disabling them. ModemManager, wpa_supplicant, packagekit, udisks2, and upower are candidates only if the server does not depend on their functions; do not disable them as a batch without checking.

If Intel AMT/vPro is enabled, restrict management ports `16992`, `16993`, and `5900` to trusted management clients at the network firewall. AMT operates independently of Ubuntu, so UFW does not protect it.

## Secrets

This repository is public. Store app secrets in encrypted `apps/<app>/.env.sops` files; never commit plaintext credentials or the age private key. See [Secrets Management](secrets.md) for editing and deployment instructions.

Follow the cadence in the [rotation inventory](../.github/secrets-rotation.json). The [monthly reminder workflow](../.github/workflows/secrets-rotation.yml) opens issues for credentials due for rotation. Replace compromised credentials immediately regardless of schedule.

Preserve offline access to the SOPS age key and backup password. Changing only `RESTIC_PASSWORD` in the environment does not change existing repositories' passwords. Key changes require a planned migration and verification that existing secrets and backups remain readable. See [Disaster Recovery](disaster-recovery.md#critical-files).

## Verify Security Controls

Run these checks after firewall or access changes. For phone Wi-Fi tests, enable Airplane Mode, turn Wi-Fi back on, and disable VPNs to prevent cellular or VPN access from masking the result. Use a fresh page to avoid cached content.

| Test                                                                                                              | Expected result                                                                            |
| ----------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------ |
| US cellular, home VPN off                                                                                         | Websites work; direct Plex access works with Plex authentication                           |
| Non-US connection, home VPN off                                                                                   | Websites and direct Plex access are blocked                                                |
| Connect directly to the public IP from outside Cloudflare, using the website's hostname for HTTP Host and TLS SNI | Origin access is blocked; a certificate error or unmatched route alone does not prove this |
| WireGuard from a non-US source                                                                                    | VPN connects with a valid client key; permitted home services work                         |
| Guest Wi-Fi                                                                                                       | Internet and DNS work; `192.168.4.161:8123` and `:2283` are blocked                        |
| Two Guest Wi-Fi clients                                                                                           | Clients cannot connect directly to each other                                              |
| IoT Wi-Fi                                                                                                         | Internet and new connections to main-LAN services are blocked                              |
| Server → IoT device                                                                                               | Required camera/device connections and replies work                                        |
| Fresh SSH connection                                                                                              | Key login works; password and direct root login are disabled                               |

Check Cloudflare **Security → Analytics**, UniFi **Flows**, policy hit counters, and WireGuard handshakes against the test's source IP and time. Plex playback alone does not prove a direct connection; an empty block log does not prove successful access. Testing two blocked ports does not establish isolation for every service.

Keep UniFi configuration backups before firewall changes. Cloudflare and UniFi settings are managed outside this repository and must be checked separately after recovery. See [Disaster Recovery](disaster-recovery.md) for server restore procedures.
