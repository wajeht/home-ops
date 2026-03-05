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
