# homeassistant

Home Assistant at `ha.jaw.dev`.

## auth

Two Traefik routers, two subdomains, same backend:

- **`ha.jaw.dev`** — protected by `oauth2-admin` (browser access)
- **`ha-app.jaw.dev`** — no `oauth2-admin`, HA's own auth + rate limiting (Companion App)

Google blocks OAuth in WebViews (`disallowed_useragent`), so the Companion App can't use the admin Google OAuth layer. Separate subdomain is the standard solution — HA's own auth (username/password + optional 2FA) protects the app endpoint.

### Companion App setup

1. Add `ha-app.jaw.dev` CNAME in Cloudflare DNS (same target as `ha.jaw.dev`)
2. In the app: Settings → Home → External URL → `https://ha-app.jaw.dev`
3. Internal URL stays `http://192.168.4.161:8123`

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

## Home Assistant Web Proxy

Required for proxying go2rtc streams through HA. Install via HACS → Integrations → search "hass-web-proxy" → install → restart HA → Settings → Devices & Services → Add Integration → search "Proxy".

## Advanced Camera Card

Requires HACS. In HACS → search "Advanced Camera Card" by dermotduffy (type: Frontend/Dashboard) → install → hard refresh browser (Cmd+Shift+R).

One dashboard with two tabs: **LAN** (full features) and **Remote** (clear streaming through Cloudflare).

Create dashboard: Settings → Dashboards → Add Dashboard → set to **Panel (single card)**.

### setup

1. Install **Advanced Camera Card** via HACS (Frontend/Dashboard)
2. Install **hass-web-proxy** via HACS (Integration) → add integration in Settings → Devices & Services
3. Create dashboard, edit YAML, paste the config below

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
            screenshot:
              enabled: true
            download:
              enabled: true
            ptz_home:
              enabled: true
        live:
          microphone:
            always_connected: false
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
              mode: below
        view:
          keyboard_shortcuts:
            enabled: true
    title: LAN
    icon: mdi:lan
  - type: panel
    path: remote
    title: Remote
    icon: mdi:cloud
    cards:
      - type: custom:advanced-camera-card
        profiles:
          - scrubbing
        cameras:
          - camera_entity: camera.tapo_cam
            live_provider: ha
        menu:
          buttons:
            microphone:
              enabled: false
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
            screenshot:
              enabled: true
            download:
              enabled: true
            ptz_home:
              enabled: true
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
            timeline:
              mode: below
        view:
          keyboard_shortcuts:
            enabled: true
    title: Remote
    icon: mdi:cloud
```

### streaming notes

- **LAN tab** (`192.168.4.161:8123`): `go2rtc` provider → WebRTC (lowest latency, two-way audio, PTZ)
- **Remote tab** (`ha.jaw.dev`): `ha` provider → HA native stream (clear quality through Cloudflare, PTZ works)
- Two-way audio requires WebRTC (direct UDP) — LAN only, Cloudflare can't proxy UDP
- PTZ works on both tabs — it's HTTP API calls (browser → HA → Frigate → ONVIF → camera)
- `scrubbing` profile enables dragging the timeline to scrub through recordings
- `always_connected: false` — mic connects on demand (avoids permission errors remotely)
- `screenshot` / `download` — capture stills or download clips from live view
- `ptz_home` — return camera to home position after panning
- `keyboard_shortcuts` — arrow keys control PTZ
- go2rtc with VAAPI hardware transcode handles all streams
- Frigate needs `go2rtc.api.origin: "*"` in config for hass-web-proxy CORS
