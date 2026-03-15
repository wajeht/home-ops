# frigate

Frigate NVR at `frigate.jaw.dev`. Self-hosted security camera system with AI object detection.

## hardware

- Dell OptiPlex 7050, Intel i7-7700 (Kaby Lake), Intel HD 630 GPU
- VAAPI hardware acceleration for ffmpeg decoding/encoding
- OpenVINO detector on Intel HD 630 iGPU (replaced CPU detector)

## camera setup (TP-Link Tapo Pan/Tilt 2K)

1. Plug in camera, set up via Tapo app (one-time only)
2. Tapo app → Settings → Advanced Settings → Camera Account → create username/password (enables RTSP + ONVIF)
3. Set video codec to **H.264** (not H.265/smart codec)
4. Turn off watermark/timestamp in Display settings
5. Set static IP in Network Settings (192.168.30.56 on IoT VLAN)
6. Connect to `IoT` WiFi SSID
7. Delete Tapo app — camera runs standalone

### camera specs

- RTSP: port 554 (`stream1` = main 2K, `stream2` = sub for detection)
- ONVIF: port **2020** (not default 8000)
- Credentials: same camera account for RTSP and ONVIF

## architecture

```
Camera (RTSP) → go2rtc (restream + VAAPI transcode) → Frigate (detect + record)
                                                      → Home Assistant (live view via MQTT + Frigate integration)
```

- **stream1** (2K main) → go2rtc restream → recording
- **stream2** (sub) → detection at 640x360@5fps (less CPU)
- go2rtc handles WebRTC/MSE/RTSP restreaming with VAAPI hardware transcode
- MQTT (mosquitto in zigbee2mqtt stack) bridges Frigate → Home Assistant

## storage

- Config + DB: `~/data/frigate/` (local SSD)
- Recordings: `~/data/frigate/media/` (local SSD, 7-day retention, ~7.6GB/day motion-only for one 2K camera, ~53GB total)
- No NAS needed at this scale, no borgmatic backup (config in git, recordings are ephemeral)

## secrets

Credentials in `.env.sops`, referenced in config.yml as `{FRIGATE_CAM_USER}`, `{FRIGATE_CAM_PASS}`, `{FRIGATE_CAM_IP}`, `{FRIGATE_TAPO_SHA256}`.

The SHA256 hash is of the Tapo **cloud/app** password (not camera account):

```bash
echo -n "tapo-cloud-password" | shasum -a 256 | awk '{print toupper($0)}'
```

```bash
sops apps/frigate/.env.sops
```

## key config decisions

- `auth: true` — Frigate's built-in auth enabled as defense in depth behind google-auth
- `tls: false` — Traefik handles TLS, Frigate doesn't need its own
- `proxy.header_map.user: X-Forwarded-User` — reads authenticated user from google-auth
- `trusted_proxies: 172.18.0.0/16` — trusts Traefik on Docker network
- `failed_login_rate_limit` — brute force protection
- Traefik routes to port 8971 (authenticated) instead of 5000 (unauthenticated)
- `openvino` detector on `GPU` — uses Intel HD 630 iGPU for object detection (much lower CPU than CPU detector)
- `preset-vaapi` — Intel HD 630 hardware decoding for ffmpeg
- `#hardware=vaapi` — go2rtc uses GPU for transcoding WebRTC/MSE streams
- `webrtc.candidates: 192.168.4.161:8555` — tells go2rtc the server LAN IP for WebRTC
- `rolling_update: false` — stateful app, can't run multiple instances
- Traefik routes to port 5000 (internal HTTP API), not 8971 (nginx with TLS)
- Only tracking `person` — apartment use case, no need for dog/cat detection
- Audio detection — fire alarm, scream, yell, glass breaking
- Two-way audio via `tapo://` protocol (SHA256 of Tapo cloud password in `.env.sops`)
- Object filter: `min_score: 0.5`, `min_area: 1500` to reduce false positives
- `clean_copy: false` — not using Frigate+, saves disk
- `preset-record-generic-audio-aac` — recordings include camera audio (Tapo outputs PCM-ALAW, must transcode to AAC for MP4)
- `contour_area: 25` — medium motion sensitivity (default 10 too sensitive for apartment)
- `api.origin: "*"` — CORS for hass-web-proxy integration (remote streaming via HA)

## PTZ

ONVIF PTZ on port 2020. Manual pan/tilt works in Frigate UI and HA Advanced Camera Card. Frigate autotracking does NOT work with Tapo (firmware lacks RelativePanTiltTranslationSpace).

## gotchas

- Tapo ONVIF port is **2020**, not 8000
- Don't use raw RTSP in go2rtc — use direct `rtsp://` (not `ffmpeg:rtsp://`) for the main stream, add ffmpeg transcode as second source
- Frigate uses s6-overlay — do NOT add `init: true`
- Frigate's TLS disabled (`tls: false`) — traefik handles TLS, routes to port 8971 (authenticated, no TLS)
- Config must NOT be mounted as `:ro` — Frigate needs to migrate config between versions
- `record.events` config removed in 0.15+ — causes validation error
- GPU stats polling fails without `SYS_PERF` cap (harmless, GPU accel still works)
- Streaming through Cloudflare adds latency — use LAN IP for best experience
- Two-way audio requires WebRTC (doesn't work through Cloudflare) — use LAN IP

## network

Camera is on IoT VLAN (192.168.30.0/24, VLAN 30), isolated from main LAN. Server reaches it via manual UniFi firewall rules. See `docs/security.md` for VLAN and firewall details.

## adding a new camera

1. Set up camera with static IP on IoT VLAN, H.264 codec, RTSP/ONVIF enabled
2. Connect to `IoT` WiFi SSID
3. Add credentials to `.env.sops`
4. Add go2rtc stream in `config.yml`
5. Add camera block with ffmpeg inputs, onvif, detect, record, snapshots
6. Push and redeploy
