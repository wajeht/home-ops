# Security

Server hardening for the Dell OptiPlex 7050 (Ubuntu 24.04).

## Open Ports

Scanned from LAN via `nmap -F <server-ip>`:

| Port  | Service        | Status             | Action                                        |
| ----- | -------------- | ------------------ | --------------------------------------------- |
| 22    | SSH            | open               | Harden (see SSH below)                        |
| 80    | HTTP           | open (Traefik)     | OK — redirects to HTTPS                       |
| 443   | HTTPS          | open (Traefik)     | OK                                            |
| 111   | rpcbind        | **disabled**       | Unnecessary (NFS v4.1 doesn't need it)        |
| 1883  | MQTT           | open (Zigbee2MQTT) | Blocked by UFW, Docker-internal only          |
| 2283  | Immich         | open               | Blocked by UFW, access via Traefik only       |
| 8123  | Home Assistant | open               | Blocked by UFW, access via Traefik only       |
| 32400 | Plex           | open               | OK — needs direct access for remote streaming |

To restrict ports further, change Docker port mappings from `0.0.0.0:PORT:PORT` to `127.0.0.1:PORT:PORT`.

## Firewall (UFW)

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
| ModemManager   | Cellular modem management | Disable (no modem)   |
| wpa_supplicant | WiFi management           | Disable (wired only) |
| packagekit     | GUI package management    | Disable (headless)   |
| udisks2        | GUI disk management       | Disable (headless)   |
| upower         | Power management for GUI  | Disable (headless)   |

```bash
sudo systemctl disable --now ModemManager wpa_supplicant packagekit udisks2 upower
```

## Docker Socket

Traefik and Portainer mount `/var/run/docker.sock` (root-equivalent access). Consider [docker-socket-proxy](https://github.com/Tecnativa/docker-socket-proxy) to limit API access.

## Checklist

- [x] Disable rpcbind (NFS v4.1)
- [x] Enable UFW firewall
- [ ] SSH: key-only auth
- [ ] Install fail2ban
- [ ] Disable unnecessary services
- [ ] Bind non-Traefik ports to 127.0.0.1
- [ ] Docker socket proxy
- [ ] IoT VLAN ([#154](https://github.com/wajeht/home-ops/issues/154))
