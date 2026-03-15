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

## Frigate integration

Requires HACS. In HACS → search "Frigate" (type: Integration) → install → restart HA.

Then: Settings → Devices & Services → Add Integration → search "Frigate" → URL: `http://frigate:5000`

Auto-discovers cameras via MQTT (mosquitto in zigbee2mqtt stack).

## Advanced Camera Card

Requires HACS. In HACS → search "Advanced Camera Card" by dermotduffy (type: Frontend/Dashboard) → install → hard refresh browser (Cmd+Shift+R).

Create a custom dashboard (Settings → Dashboards → Add Dashboard) since the default Overview page doesn't support custom cards. Set view layout to **Panel (single card)**.

### dashboard YAML

```yaml
views:
  - type: panel
    path: ""
    cards:
      - type: custom:advanced-camera-card
        cameras:
          - camera_entity: camera.tapo_cam
            live_provider: go2rtc
            go2rtc:
              modes:
                - mse
                - webrtc
                - mp4
                - mjpeg
              stream: tapo_cam
        live:
          auto_play:
            - selected
            - visible
          auto_pause:
            - unselected
            - hidden
          lazy_load: true
          show_image_during_load: true
          transition_effect: none
          controls:
            ptz:
              mode: "on"
              position: bottom-right
    title: Camera
    icon: mdi:webcam
```

### streaming notes

- `mse` first for remote/Cloudflare access (WebRTC fails through reverse proxy)
- `webrtc` first for LAN access (lowest latency)
- go2rtc with VAAPI hardware transcode handles the stream
- Cloudflare adds latency — use LAN IP (`192.168.4.161:8123`) for best experience
