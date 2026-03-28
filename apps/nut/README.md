# NUT (Network UPS Tools)

UPS monitoring via [NUT](https://networkupstools.org/) + [PeaNUT](https://github.com/Brandawg93/PeaNUT) dashboard.

## Setup

- UPS: CyberPower 1500VA AVR (detected as PR1500LCDRT2U)
- USB cable from UPS → OptiPlex 7050
- NUT server runs on Docker host, exposes port 3493 for network clients
- PeaNUT dashboard at `nut.jaw.dev` (Google OAuth protected)
- Synology hardcodes credentials: UPS name must be `ups`, user `monuser`, password `secret`

## NUT Server (Docker)

Runs on OptiPlex 7050 via `docker-compose.yml`. Key env vars:

- `NAME=ups` — UPS device name (must be `ups` for Synology compatibility)
- `DRIVER=usbhid-ups` — CyberPower USB driver
- `VENDORID=0764`, `PRODUCTID=0601` — CyberPower USB IDs
- `API_USER=monuser`, `API_PASSWORD=secret` — NUT client credentials

Verify USB is detected:

```bash
lsusb | grep 0764
# Bus 001 Device 003: ID 0764:0601 Cyber Power System, Inc. PR1500LCDRT2U UPS
```

## PeaNUT Dashboard

Configure in settings (gear icon):

- Server Address: `nut`
- Port: `3493`
- Username: `monuser`
- Password: `secret`

## NUT Clients

### Synology NAS — DONE

DSM GUI alone doesn't work with non-Synology NUT servers. Needs SSH config:

1. DSM → Control Panel → Hardware & Power → UPS:
   - Enable UPS support
   - UPS type: "Synology UPS server"
   - Network UPS server IP: `192.168.4.161`
   - Apply (will show "Cannot connect" — that's expected)

2. DSM → Control Panel → Terminal & SNMP → Enable SSH

3. SSH into NAS and fix the shutdown command:

   ```bash
   ssh jaw@192.168.4.218
   sudo sed -i 's|SHUTDOWNCMD ""|SHUTDOWNCMD "/sbin/shutdown -h now"|' /etc/ups/upsmon.conf
   sudo systemctl restart ups-net.service
   ```

4. DSM UPS page should now show connected

**WARNING:** DSM updates may overwrite `/etc/ups/upsmon.conf`. If NUT stops working after a DSM update, re-run step 3.

DSM auto-configures the correct MONITOR line (`MONITOR ups@192.168.4.161 1 monuser secret slave`) — only the empty `SHUTDOWNCMD` needs fixing via SSH.

### OptiPlex 5050 (Proxmox) — DONE

```bash
apt install -y nut-client
```

Edit `/etc/nut/nut.conf`:

```
MODE=netclient
```

Edit `/etc/nut/upsmon.conf`:

```
MONITOR ups@192.168.4.161 1 monuser secret secondary
SHUTDOWNCMD "/sbin/shutdown -h now"
POWERDOWNFLAG /etc/killpower
POLLFREQ 5
POLLFREQALERT 5
HOSTSYNC 15
DEADTIME 15
FINALDELAY 5
```

```bash
systemctl enable --now nut-client
```

## Verify

```bash
# From any machine on the network
upsc ups@192.168.4.161

# Check NUT client status on Proxmox
systemctl status nut-client
```

## How It Works

When UPS battery gets low:

1. NUT server detects low battery via USB
2. NUT server notifies all connected clients
3. Proxmox (secondary) runs `shutdown -h now`
4. Docker host (primary) shuts down last after all secondaries
