# Prowlarr

## Proxy Setup

Prowlarr routes indexer requests through Gluetun's HTTP proxy to avoid exposing your real IP to torrent sites.

After deploy, configure in **Settings → General → Proxy**:

- **Use Proxy:** Yes
- **Proxy Type:** HTTP
- **Hostname:** `gluetun`
- **Port:** `8888`

Or edit `/config/config.xml` directly:

```xml
<ProxyEnabled>True</ProxyEnabled>
<ProxyType>Http</ProxyType>
<ProxyHostname>gluetun</ProxyHostname>
<ProxyPort>8888</ProxyPort>
```

Requires `HTTPPROXY=on` on the Gluetun container (configured in `apps/vpn-qbit/docker-compose.yml`).
