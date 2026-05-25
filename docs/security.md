# Security

Server hardening for the Dell OptiPlex 7050 (Ubuntu 24.04).

Use this doc for host/network controls. App-level container requirements live in [Adding Apps](adding-apps.md#container-hardening).

## Open Ports

Scanned from LAN via `nmap -F <server-ip>`:

| Port  | Service         | Status               | Action                                     |
| ----- | --------------- | -------------------- | ------------------------------------------ |
| 22    | SSH             | open                 | Harden through SSH settings                |
| 80    | HTTP            | open through Traefik | Redirects to HTTPS                         |
| 443   | HTTPS           | open (Traefik)       | OK                                         |
| 111   | rpcbind         | **disabled**         | Unnecessary for NFS v4.1                   |
| 1883  | MQTT            | open (Zigbee2MQTT)   | Blocked by UFW, Docker-internal only       |
| 2283  | Immich          | open                 | Blocked by UFW, access via Traefik only    |
| 8123  | Home Assistant  | open                 | Blocked by UFW, access via Traefik only    |
| 16992 | Intel AMT HTTP  | open                 | LAN-only remote management                 |
| 16993 | Intel AMT HTTPS | open                 | LAN-only remote management                 |
| 5900  | AMT KVM/VNC     | open                 | LAN-only remote screen access              |
| 32400 | Plex            | open                 | Direct Plex access; bypasses Traefik OAuth |

To restrict ports further, change Docker port mappings from `0.0.0.0:PORT:PORT` to `127.0.0.1:PORT:PORT`.

## Firewall

Active since 2026-03-13.

```bash
sudo ufw default deny incoming
sudo ufw default allow outgoing
sudo ufw allow 22/tcp    # SSH
sudo ufw allow 80/tcp    # Traefik HTTP
sudo ufw allow 443/tcp   # Traefik HTTPS
sudo ufw allow 32400/tcp # Plex remote access
sudo ufw enable
```

`plex.jaw.dev` is protected by `oauth2-media@file`, but direct access to `<server-ip>:32400` does not pass through Traefik. Keep `32400/tcp` open only if direct Plex client access is required. Close it if Plex must be reachable only through Cloudflare/Traefik/OAuth.

```bash
# Management
sudo ufw status verbose
sudo ufw status numbered
sudo ufw allow <port>/tcp
sudo ufw delete <rule-number>
```

## SSH

Disable password auth, use key-based auth only.

```bash
# Copy key from Mac
ssh-copy-id user@<server-ip>
```

Edit `/etc/ssh/sshd_config`:

```
PasswordAuthentication no
PermitRootLogin no
MaxAuthTries 3
```

```bash
sudo systemctl restart ssh
```

## fail2ban

```bash
sudo apt install fail2ban
sudo systemctl enable --now fail2ban
```

Bans IPs after 5 failed SSH attempts for 10 minutes.

## Unnecessary Services

| Service        | Purpose                   | Action               |
| -------------- | ------------------------- | -------------------- |
| rpcbind        | NFS v2/v3 port mapping    | **Already disabled** |
| ModemManager   | Cellular modem management | Disable              |
| wpa_supplicant | WiFi management           | Disable              |
| packagekit     | GUI package management    | Disable              |
| udisks2        | GUI disk management       | Disable              |
| upower         | Power management for GUI  | Disable              |

```bash
sudo systemctl disable --now ModemManager wpa_supplicant packagekit udisks2 upower
```

## Docker Socket

Several services mount `/var/run/docker.sock` (root-equivalent access) — Traefik, Backrest, Dozzle, Beszel, Homepage, Walker, docker-cd. Consider [docker-socket-proxy](https://github.com/Tecnativa/docker-socket-proxy) to limit API access.

## Cloudflare and Origin Lock

Web traffic is layered:

1. Cloudflare handles edge WAF/DDoS/bot filtering.
2. UniFi allows only Cloudflare IPs to reach `80/443`.
3. Traefik repeats the Cloudflare-only check and trusts forwarded real-client headers only from Cloudflare.

Keep Cloudflare IP ranges current with:

```bash
./scripts/cloudflare.sh
```

If it changes files, review the diff and deploy through the normal git flow.

## IoT VLAN

Isolates IoT devices (cameras, sensors, smart plugs) from the main LAN. Devices can't reach the internet or other VLANs, but the server can reach them.

### Network layout

| Network | VLAN ID | Subnet          | Internet | Purpose              |
| ------- | ------- | --------------- | -------- | -------------------- |
| Default | 1       | 192.168.4.0/24  | Yes      | Main LAN, server     |
| Guest   | 2       | 192.168.2.0/24  | Yes      | Guest WiFi           |
| IoT     | 30      | 192.168.30.0/24 | No       | Cameras, IoT devices |

### Setup (UniFi Cloud Gateway Fiber)

#### 1. Create IoT network

Settings → Networks → Create New:

- **Name:** IoT
- **VLAN ID:** 30
- **IPv4 Address:** 192.168.30.1, Netmask /24
- **Isolate Network:** checked (blocks IoT → other VLANs)
- **Allow Internet Access:** unchecked (blocks IoT → internet)
- **mDNS:** checked (device discovery across VLANs)
- **DHCP:** Server, range 192.168.30.6 - 192.168.30.254

#### 2. Create IoT WiFi

Settings → WiFi → Create New:

- **Name:** IoT
- **Password:** set one
- **Network:** IoT (VLAN 30)
- **Radio Band:** 2.4 GHz only (most IoT devices are 2.4 only)

#### 3. Firewall rules

UniFi auto-creates isolation rules when "Isolate Network" is checked, but two **manual** LAN In rules are needed so the server can talk to IoT devices:

| Rule                          | Action | Source          | Destination | State                | Purpose                  |
| ----------------------------- | ------ | --------------- | ----------- | -------------------- | ------------------------ |
| Allow Server to IoT           | Accept | 192.168.4.161   | IoT network | Any                  | Server can reach cameras |
| Allow Established/Related IoT | Accept | IoT network     | Any         | Established, Related | Return traffic only      |
| Isolate IoT (auto)            | Drop   | 192.168.30.0/24 | All VLANs   | Any                  | IoT can't reach main LAN |
| Block IoT internet (auto)     | Drop   | 192.168.30.0/24 | Any         | Any                  | No cloud phoning home    |

**Why two manual rules?** The "Isolate Network" toggle blocks all inter-VLAN traffic, including return traffic from IoT devices back to the server. Without these rules, the server can send packets to the camera but never gets a response.

**Why Established/Related instead of a broad allow?** A broad "Allow IoT → Server" rule lets a compromised IoT device initiate new connections to the server. Using Established/Related state means IoT devices can only respond to connections the server started — they can never open new connections to anything.

Both manual rules must have a lower ID than the auto-created isolation rules (60001+) so they're evaluated first.

#### 4. Move devices to IoT WiFi

1. Open device app (e.g., Tapo) → WiFi settings → connect to `IoT` SSID
2. Set static IP (e.g., 192.168.30.56 for camera)
3. Update `.env.sops` with new IP
4. Push and redeploy

#### 5. Verify isolation

From your main LAN (192.168.4.x):

```bash
# Server can reach camera
ping 192.168.30.56
nc -zv 192.168.30.56 554   # RTSP
nc -zv 192.168.30.56 2020  # ONVIF

# Camera can't reach server (test from camera's perspective)
# No way to test directly, but Tapo app should fail remotely
```

### Key points

- IoT devices get no internet — TP-Link, Tuya, etc. can't phone home
- IoT devices can't reach your main LAN — compromised camera can't attack your server
- Server (192.168.4.161) can reach IoT VLAN — Frigate/HA connects to cameras
- mDNS enabled — allows device discovery across VLANs if needed
- Camera credentials still in `.env.sops` — only the IP changes when moving VLANs
- Delete vendor apps after setup — camera runs standalone on RTSP/ONVIF

## Intel AMT/vPro

AMT runs on the Management Engine chipset independently of the OS. It listens on ports 16992/16993/5900 and provides remote power control and KVM.

- **Access**: `http://192.168.4.161:16992` or HTTPS on 16993
- **KVM**: VNC client to port 5900
- **Risk**: AMT has had critical CVEs (auth bypass, RCE) — keep BIOS firmware updated
- **Mitigation**: LAN-only access, UFW doesn't affect AMT (runs below OS), firewall at router blocks inbound
- USB Provision disabled, User Consent set to None, Remote IT config disabled

## Checklist

- [x] Disable rpcbind (NFS v4.1)
- [x] Enable UFW firewall
- [x] IoT VLAN (VLAN 30, 192.168.30.0/24)
- [x] Intel AMT/vPro enabled (remote power + KVM)
- [ ] SSH: key-only auth
- [ ] Install fail2ban
- [ ] Disable unnecessary services
- [ ] Bind non-Traefik ports to 127.0.0.1
- [ ] Docker socket proxy
