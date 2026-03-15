# frigate

Frigate NVR at `frigate.jaw.dev`. Self-hosted security camera system with AI object detection.

## hardware

- Dell OptiPlex 7050, Intel i7-7700 (Kaby Lake), Intel HD 630 GPU
- VAAPI hardware acceleration for ffmpeg decoding/encoding
- CPU detector (no Coral TPU yet)

## camera setup (TP-Link Tapo Pan/Tilt 2K)

1. Plug in camera, set up via Tapo app (one-time only)
2. Tapo app → Settings → Advanced Settings → Camera Account → create username/password (enables RTSP + ONVIF)
3. Set video codec to **H.264** (not H.265/smart codec)
4. Turn off watermark/timestamp in Display settings
5. Set static IP in Network Settings
6. Delete Tapo app — camera runs standalone

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
- Recordings: `~/data/frigate/media/` (local SSD, 1-day retention, ~2-3GB/day for one 2K camera)
- No NAS needed at this scale, no borgmatic backup (config in git, recordings are ephemeral)

## secrets

Credentials in `.env.sops`, referenced in config.yml as `{FRIGATE_CAM_USER}`, `{FRIGATE_CAM_PASS}`, `{FRIGATE_CAM_IP}`.

```bash
sops apps/frigate/.env.sops
```

## key config decisions

- `auth: false` — disabled, google-auth handles access
- `preset-vaapi` — Intel HD 630 hardware decoding for ffmpeg
- `#hardware=vaapi` — go2rtc uses GPU for transcoding WebRTC/MSE streams
- `webrtc.candidates: 192.168.4.161:8555` — tells go2rtc the server LAN IP for WebRTC
- `rolling_update: false` — stateful app, can't run multiple instances
- Traefik routes to port 5000 (internal HTTP API), not 8971 (nginx with TLS)

## PTZ

ONVIF PTZ on port 2020. Manual pan/tilt works in Frigate UI and HA Advanced Camera Card. Frigate autotracking does NOT work with Tapo (firmware lacks RelativePanTiltTranslationSpace).

## gotchas

- Tapo ONVIF port is **2020**, not 8000
- Don't use raw RTSP in go2rtc — use direct `rtsp://` (not `ffmpeg:rtsp://`) for the main stream, add ffmpeg transcode as second source
- Frigate uses s6-overlay — do NOT add `init: true`
- Frigate's nginx does TLS on port 8971 — traefik must point to port 5000 instead
- Config must NOT be mounted as `:ro` — Frigate needs to migrate config between versions
- `record.events` config removed in 0.15+ — causes validation error
- GPU stats polling fails without `SYS_PERF` cap (harmless, GPU accel still works)
- Streaming through Cloudflare adds latency — use LAN IP for best experience

## adding a new camera

1. Set up camera with static IP, H.264 codec, RTSP/ONVIF enabled
2. Add credentials to `.env.sops`
3. Add go2rtc stream in `config.yml`
4. Add camera block with ffmpeg inputs, onvif, detect, record, snapshots
5. Push and redeploy
