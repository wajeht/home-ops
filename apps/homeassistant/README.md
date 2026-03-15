# homeassistant

Home Assistant at `ha.jaw.dev`.

## first deploy

After deploy, add trusted proxy config on the server:

```yaml
# ~/data/homeassistant/configuration.yaml
http:
  use_x_forwarded_for: true
  trusted_proxies:
    - 172.18.0.0/16
```

Then restart: `sudo docker restart homeassistant`

## HACS

HACS (Home Assistant Community Store) must be installed manually once (persists across image updates via `~/data/homeassistant/custom_components/`):

```bash
docker exec homeassistant bash -c "wget -O - https://get.hacs.xyz | bash -"
sudo docker restart homeassistant
```

Then in HA UI: Settings → Devices & Services → Add Integration → search "HACS" → follow GitHub auth flow.

## Frigate

Requires HACS. In HACS → search "Frigate" → install → restart HA.

Then: Settings → Devices & Services → Add Integration → search "Frigate" → URL: `http://frigate:5000`
