# frigate

Frigate NVR at `frigate.jaw.dev`. Self-hosted security camera system with AI object detection.

## hardware

- Dell OptiPlex 7050, Intel i7-7700 (Kaby Lake), Intel HD 630 GPU
- VAAPI hardware acceleration for ffmpeg decoding/encoding
- OpenVINO detector on Intel HD 630 iGPU with YOLOv9-t model (upgraded from default MobileNet SSD)
- Micron M600 1TB SATA mounted at `/mnt/sata` — dedicated to Frigate recordings

## devices

| Device                   | Type       | Connection      | Path            | Resolution                   | Format     |
| ------------------------ | ---------- | --------------- | --------------- | ---------------------------- | ---------- |
| TP-Link Tapo Pan/Tilt 2K | IP camera  | WiFi (IoT VLAN) | RTSP via go2rtc | 2K main + 640x360 sub        | H.264      |
| Elgato Facecam MK.2      | USB webcam | USB 2.0         | `/dev/video0`   | 1080p@60, 720p@120, 540p@120 | MJPEG only |

### server-side tools

`v4l-utils` installed on server for diagnosing USB cameras:

```bash
# list connected V4L2 devices
v4l2-ctl --list-devices

# list supported formats/resolutions for a device
sudo v4l2-ctl -d /dev/video0 --list-formats-ext
```

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
- `openvino` detector on `GPU` with YOLOv9-t (320x320) — much better accuracy than default MobileNet SSD (300x300), ~30ms inference on HD 630
- No `hwaccel_args` on any Frigate ffmpeg input — record stream doesn't decode (just copies), detect stream uses CPU decode. Eliminates GPU contention with OpenVINO + face recognition + embeddings. VAAPI is only used by go2rtc for WebRTC/MSE transcode (separate from Frigate's ffmpeg)
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
- Detect stream uses CPU decode (no hwaccel_args) — VAAPI causes "Failed to sync surface" when GPU is busy with OpenVINO + face recognition + embeddings (known Intel iHD driver bug, see media-driver#469). QSV causes "exceeded fps limit" on 7th gen. CPU decode at 640x360@5fps is ~1% CPU, stable. Record stream doesn't need hwaccel_args either — Frigate just copies the raw stream without decoding
- `model` is a **top-level** config block, not nested under `detectors` — Frigate's config migration mangles it otherwise
- `api.origin: "*"` — CORS for hass-web-proxy integration (remote streaming via HA)

## PTZ

ONVIF PTZ on port 2020. Manual pan/tilt works in Frigate UI and HA Advanced Camera Card. Frigate autotracking does NOT work with Tapo (firmware lacks RelativePanTiltTranslationSpace).

## gotchas

- Tapo ONVIF port is **2020**, not 8000
- ONVIF `host` env var `{FRIGATE_CAM_IP}` doesn't resolve — Frigate bug (ONVIF module skips env substitution despite docs saying it's supported). Hardcoded IP as workaround
- Don't use raw RTSP in go2rtc — use direct `rtsp://` (not `ffmpeg:rtsp://`) for the main stream, add ffmpeg transcode as second source
- Frigate uses s6-overlay — do NOT add `init: true`
- Frigate's TLS disabled (`tls: false`) — traefik handles TLS, routes to port 8971 (authenticated, no TLS)
- Config must NOT be mounted as `:ro` — Frigate needs to migrate config between versions
- `record.events` config removed in 0.15+ — causes validation error
- GPU stats polling needs `PERFMON` cap (added, shows GPU usage in Frigate UI)
- Streaming through Cloudflare adds latency — use LAN IP for best experience
- Two-way audio requires WebRTC (doesn't work through Cloudflare) — use LAN IP
- YOLOv9 model uses `nchw` input tensor and `float` dtype — different from MobileNet's `nhwc`/`bgr`. Wrong config = silent bad detections
- YOLOv9 uses COCO-80 labels (`/labelmap/coco-80.txt`, built into container), MobileNet uses COCO-91 — don't mix them up
- First startup after model change is very slow (OpenVINO ONNX→IR compilation), don't assume it's broken

## network

Camera is on IoT VLAN (192.168.30.0/24, VLAN 30), isolated from main LAN. Server reaches it via manual UniFi firewall rules. See `docs/security.md` for VLAN and firewall details.

## detection model

### why YOLOv9-t over MobileNet SSD (default)

Frigate ships with SSDLite MobileNet v2 (2018-era, 300x300) as the default OpenVINO model. It works but has noticeably worse detection accuracy — more false positives, missed detections at distance, and lower confidence scores compared to modern YOLO models.

Frigate's own docs now recommend OpenVINO on Intel iGPU over Google Coral TPU for new setups. The Coral is locked to MobileNet SSD (can't run YOLO), has increasingly problematic driver maintenance across kernel updates, and offers no accuracy advantage. Our Intel HD 630 iGPU with OpenVINO runs YOLOv9-t at ~30ms inference — well within the 200ms budget at 5fps detect — with significantly better accuracy.

### why not Coral TPU

Evaluated and decided against for this setup:

- **Accuracy**: Coral is locked to old MobileNet SSD models (300x300). YOLOv9 on iGPU is much more accurate
- **Speed**: Coral is faster (~2-3ms vs ~30ms) but speed isn't the bottleneck with 1 camera at 5fps (200ms budget)
- **Drivers**: Coral gasket driver is unsigned (requires Secure Boot disabled), breaks across kernel updates, increasingly unmaintained
- **Hardware**: OptiPlex 7050 Micro has a free M.2 A+E WiFi slot (Q270 chipset, standard PCIe — no CNVi lockout) where a Coral M.2 would physically fit. USB Coral also works (confirmed by other 7050 users). But neither is worth it given the accuracy trade-off
- **Scaling**: Coral becomes worthwhile at 5+ cameras where dedicated inference offloads the iGPU for ffmpeg decode. At 1 camera, no benefit

### why 320x320 and not 640

Frigate crops frames to motion regions before running detection. At 320x320 the model sees a zoomed-in crop of where motion was detected, so effective resolution is similar to 640 on the full frame. Going to 640 doubles inference time (~60ms) with minimal accuracy gain. Only useful for very small/distant objects.

### why `t` (tiny) and not `s` (small)

The `s` model is ~2x slower (~60ms on HD 630). With 1 camera and 200ms frame budget, `s` would still work, but `t` leaves more headroom for future cameras or iGPU contention with VAAPI decode and Immich ML.

### model file

The model file (`yolov9-t-320.onnx`, 8.8MB) is checked into git and bind-mounted read-only into the container at `/config/model_cache/`. Frigate doesn't auto-download YOLO models for OpenVINO — you must export and supply the `.onnx` file yourself.

First startup after a model change is slow (OpenVINO compiles ONNX to an internal IR cache). Subsequent starts are fast.

### re-exporting the model

To re-export (e.g., different size or model variant), run on any machine with Docker:

```bash
cd /tmp && docker build . --build-arg MODEL_SIZE=t --build-arg IMG_SIZE=320 --output . -f- <<'EOF'
FROM python:3.11 AS build
RUN apt-get update && apt-get install --no-install-recommends -y cmake libgl1 && rm -rf /var/lib/apt/lists/*
COPY --from=ghcr.io/astral-sh/uv:0.10.4 /uv /bin/
WORKDIR /yolov9
ADD https://github.com/WongKinYiu/yolov9.git .
RUN uv pip install --system -r requirements.txt
RUN uv pip install --system onnx==1.18.0 onnxruntime onnxscript
ARG MODEL_SIZE
ARG IMG_SIZE
ADD https://github.com/WongKinYiu/yolov9/releases/download/v0.1/yolov9-${MODEL_SIZE}-converted.pt yolov9-${MODEL_SIZE}.pt
RUN sed -i "s/ckpt = torch.load(attempt_download(w), map_location='cpu')/ckpt = torch.load(attempt_download(w), map_location='cpu', weights_only=False)/g" models/experimental.py
RUN python3 export.py --weights ./yolov9-${MODEL_SIZE}.pt --imgsz ${IMG_SIZE} --include onnx
FROM scratch
ARG MODEL_SIZE
ARG IMG_SIZE
COPY --from=build /yolov9/yolov9-${MODEL_SIZE}.onnx /yolov9-${MODEL_SIZE}-${IMG_SIZE}.onnx
EOF

# copy into repo
cp yolov9-t-320.onnx ~/Dev/home-ops/apps/frigate/
```

Build args: `MODEL_SIZE` = `t` (tiny) or `s` (small), `IMG_SIZE` = `320` or `640`. Output is `yolov9-{size}-{img}.onnx`.

## adding a new camera

1. Set up camera with static IP on IoT VLAN, H.264 codec, RTSP/ONVIF enabled
2. Connect to `IoT` WiFi SSID
3. Add credentials to `.env.sops`
4. Add go2rtc stream in `config.yml`
5. Add camera block with ffmpeg inputs, onvif, detect, record, snapshots
6. Push and redeploy
