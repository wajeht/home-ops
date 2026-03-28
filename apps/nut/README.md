# NUT (Network UPS Tools)

UPS monitoring via [NUT](https://networkupstools.org/) + [PeaNUT](https://github.com/Brandawg93/PeaNUT) dashboard.

## Setup

- UPS: CyberPower 1500VA AVR (detected as PR1500LCDRT2U)
- USB cable from UPS → OptiPlex 7050
- NUT server runs on Docker host, exposes port 3493 for network clients
- PeaNUT dashboard at `nut.jaw.dev` (Google OAuth protected)

## NUT Clients

### Synology NAS

DSM → Control Panel → Hardware & Power → UPS:
- Enable UPS support
- Select "Use network UPS server"
- Server: `192.168.4.161`
- Port: `3493`

### OptiPlex 5050 (Proxmox)

```bash
apt install nut
```

Edit `/etc/nut/nut.conf`:
```
MODE=netclient
```

Edit `/etc/nut/upsmon.conf`:
```
MONITOR ups@192.168.4.161 1 monuser secret secondary
SHUTDOWNCMD "/sbin/shutdown -h now"
```

```bash
systemctl enable --now nut-client
```

## Verify

```bash
# From any machine on the network
upsc ups@192.168.4.161
```
