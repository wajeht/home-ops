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
        profiles:
          - scrubbing
        cameras:
          - camera_entity: camera.tapo_cam
            live_provider: go2rtc
            go2rtc:
              modes:
                - webrtc
                - mse
              stream: tapo_cam
        menu:
          buttons:
            microphone:
              enabled: true
              type: momentary
            fullscreen:
              enabled: true
            media_player:
              enabled: false
            snapshots:
              enabled: true
            clips:
              enabled: true
            timeline:
              enabled: true
        live:
          microphone:
            always_connected: true
            disconnect_seconds: 1
          auto_play:
            - selected
            - visible
          auto_pause:
            - unselected
            - hidden
          auto_unmute:
            - selected
            - visible
          lazy_load: true
          show_image_during_load: true
          transition_effect: none
          controls:
            ptz:
              mode: "on"
              position: bottom-right
            timeline:
              mode: above
    title: Camera
    icon: mdi:webcam
```

### streaming notes

- `webrtc` first — lowest latency, two-way audio works on LAN
- `mse` fallback — works through Cloudflare (no two-way audio)
- go2rtc with VAAPI hardware transcode handles the stream
- Two-way audio requires WebRTC — only works on LAN (`192.168.4.161:8123`)
- Cloudflare adds latency — use LAN IP for best experience
