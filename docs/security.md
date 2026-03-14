# Server Hardening

Security audit and hardening guide for the Dell OptiPlex 7050 (<server-ip>, Ubuntu 24.04).

## Open Ports

Scanned from LAN via `nmap -F <server-ip>`:

| Port  | Service        | Status             | Action                                        |
| ----- | -------------- | ------------------ | --------------------------------------------- |
| 22    | SSH            | open               | Harden (see SSH below)                        |
| 80    | HTTP           | open (Traefik)     | OK — redirects to HTTPS                       |
| 443   | HTTPS          | open (Traefik)     | OK                                            |
| 111   | rpcbind        | **disabled**       | Was unnecessary (NFS v4.1 doesn't need it)    |
| 1883  | MQTT           | open (Zigbee2MQTT) | OK — LAN only, used by Home Assistant         |
| 2283  | Immich         | open               | Consider binding to localhost + Traefik only  |
| 8123  | Home Assistant | open               | Consider binding to localhost + Traefik only  |
| 32400 | Plex           | open               | OK — needs direct access for remote streaming |

### Ports to Investigate

- **1883 (MQTT)**: Bound to `0.0.0.0` — should only be accessible from localhost/Docker. No auth by default on Mosquitto.
- **2283 (Immich)**: Bound to `0.0.0.0` — accessible from any LAN device. Should go through Traefik only.
- **8123 (Home Assistant)**: Bound to `0.0.0.0` — same as Immich.

To fix, change Docker port mappings from `0.0.0.0:PORT:PORT` to `127.0.0.1:PORT:PORT` for apps that should only be accessed via Traefik.

## Firewall (UFW)

**Status: active** (enabled 2026-03-13).

```bash
# Current rules
sudo ufw status verbose

# What was applied:
sudo ufw default deny incoming
sudo ufw default allow outgoing
sudo ufw allow 22/tcp    # SSH
sudo ufw allow 80/tcp    # Traefik HTTP
sudo ufw allow 443/tcp   # Traefik HTTPS
sudo ufw allow 32400/tcp # Plex remote access
sudo ufw enable
```

| Port  | Action | Reason                            |
| ----- | ------ | --------------------------------- |
| 22    | allow  | SSH access                        |
| 80    | allow  | Traefik HTTP → HTTPS redirect     |
| 443   | allow  | Traefik HTTPS                     |
| 32400 | allow  | Plex remote streaming             |
| 1883  | deny   | MQTT — Docker-internal only       |
| 2283  | deny   | Immich — access via Traefik only  |
| 8123  | deny   | Home Assistant — via Traefik only |

This blocks direct LAN access to 1883, 2283, 8123 — only Traefik-proxied traffic gets through.

```bash
# If you need to add a port later:
sudo ufw allow <port>/tcp

# Check status:
sudo ufw status numbered

# Remove a rule:
sudo ufw delete <rule-number>
```

## SSH Hardening

Password auth should be disabled in favor of key-based auth.

### Step 1: Add SSH Key

From your Mac:

```bash
ssh-copy-id jaw@<server-ip>
```

### Step 2: Disable Password Auth

On the server, edit `/etc/ssh/sshd_config`:

```
PasswordAuthentication no
PermitRootLogin no
MaxAuthTries 3
```

Then restart: `sudo systemctl restart ssh`

### Step 3: Install fail2ban

```bash
sudo apt install fail2ban
sudo systemctl enable --now fail2ban
```

Default config bans IPs after 5 failed SSH attempts for 10 minutes.

## Unnecessary Services

Services running that can be disabled:

| Service        | Purpose                   | Action                                                               |
| -------------- | ------------------------- | -------------------------------------------------------------------- |
| rpcbind        | NFS v2/v3 port mapping    | **Already disabled** (NFS v4.1)                                      |
| ModemManager   | Cellular modem management | Disable: `sudo systemctl disable --now ModemManager`                 |
| wpa_supplicant | WiFi management           | Disable if wired only: `sudo systemctl disable --now wpa_supplicant` |
| packagekit     | GUI package management    | Disable (headless server): `sudo systemctl disable --now packagekit` |
| udisks2        | GUI disk management       | Disable (headless server): `sudo systemctl disable --now udisks2`    |
| upower         | Power management for GUI  | Disable (headless server): `sudo systemctl disable --now upower`     |
| fwupd          | Firmware updates          | Keep, but can disable if not needed                                  |

### One-liner to Disable Unnecessary Services

```bash
sudo systemctl disable --now ModemManager wpa_supplicant packagekit udisks2 upower
```

## Docker Socket

Traefik and Portainer mount `/var/run/docker.sock` — this grants root-equivalent access. Consider using [docker-socket-proxy](https://github.com/Tecnativa/docker-socket-proxy) to limit what API calls they can make.

## Checklist

- [x] Disable rpcbind (NFS v4.1 doesn't need it)
- [x] Enable UFW firewall
- [ ] SSH: add key, disable password auth
- [ ] Install fail2ban
- [ ] Disable unnecessary services (ModemManager, wpa_supplicant, etc.)
- [ ] Bind non-Traefik ports to 127.0.0.1
- [ ] Set up Docker socket proxy
- [ ] Set up IoT VLAN ([#154](https://github.com/wajeht/home-ops/issues/154))
