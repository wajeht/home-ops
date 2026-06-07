# Prowlarr

## App Sync

Prowlarr pushes indexers to Sonarr/Radarr via Full Sync — edits made in those apps are overwritten each sync. The **Standard** sync profile (Settings → Apps → Sync Profiles) sets the shared flags: RSS on, Automatic/Interactive Search on. RSS is per-indexer, not per-app. App API keys live in Settings → Apps (update there if a key is regenerated).

## Proxy Setup

Prowlarr's indexers (e.g. 1337x) fetch `.torrent` files from sites like `itorrents.org`. Without a proxy, these requests go out from your real IP, which can trigger ISP flags or UniFi IPS P2P blocks.

To fix this, Prowlarr routes indexer traffic through Gluetun's built-in HTTP proxy (`port 8888`), which tunnels it through the VPN — same tunnel qBittorrent uses.

### 1. Gluetun (already configured)

In `apps/vpn-qbit/docker-compose.yml`, Gluetun has:

```yaml
- HTTPPROXY=on
- HTTPPROXY_LISTENING_ADDRESS=:8888
```

This starts an HTTP proxy inside Gluetun on port `8888`. Any traffic sent to this proxy exits through the VPN tunnel. Prowlarr reaches it at `gluetun:8888` over the shared `traefik` network.

### 2. Prowlarr

After deploy, configure in **Settings → General → Proxy**:

- **Use Proxy:** Yes
- **Proxy Type:** HTTP
- **Hostname:** `gluetun`
- **Port:** `8888`

Or edit `~/data/prowlarr/config.xml` directly:

```xml
<ProxyEnabled>True</ProxyEnabled>
<ProxyType>Http</ProxyType>
<ProxyHostname>gluetun</ProxyHostname>
<ProxyPort>8888</ProxyPort>
```
