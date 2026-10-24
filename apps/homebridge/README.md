# Homebridge

Homebridge brings UniFi Protect cameras into Apple Home using [homebridge-unifi-protect](https://github.com/hjdhjd/homebridge-unifi-protect). The UI is available on the LAN at <http://192.168.4.161:8581> after deployment.

## First setup

1. Confirm the UNVR runs a stable **UniFi Protect 6 or later**. The current plugin requires this; do not upgrade the NVR as part of deploying this container.
2. Open the Homebridge UI and complete its account setup with a unique administrator password.
3. In **Plugins**, install the verified `homebridge-unifi-protect` plugin. Version **8.1.0** was checked against this image's Homebridge **2.4.0** and Node **24.22.1**. Plugin updates are managed in the UI, separately from Renovate's container updates.
4. On the [UNVR](https://192.168.4.60), create a dedicated local account for Homebridge. The plugin documents **Full Management** access to Protect for its full feature set. Keep this account local and enter its credentials only in Homebridge's plugin settings.
5. In the plugin's **Set Up** screen, enter controller address `192.168.4.60` and that account's credentials, then save and restart Homebridge.
6. Enable the plugin's **child bridge**, save, and restart. Use its **Connect to HomeKit** QR code to pair it from the iPhone Home app while on the home network.
7. Check a live camera stream, motion events, and audio where supported. For Apple's recording feature, follow the plugin's [HomeKit Secure Video requirements](https://github.com/hjdhjd/homebridge-unifi-protect/blob/main/docs/HomeKitSecureVideo.md), including an Apple home hub and an eligible iCloud+ plan.

The image includes FFmpeg. Start with the plugin defaults; this Compose file does not enable GPU passthrough. Verify CPU and memory use with the actual camera count before enabling many simultaneous streams or recordings.

## Home Assistant and other devices

Keep Zigbee devices on the existing Zigbee2MQTT → Home Assistant connection. Supported lights, switches, and sensors can be shared through Home Assistant's [HomeKit Bridge](https://www.home-assistant.io/integrations/homekit/); use Homebridge for the UniFi cameras to avoid duplicate accessories.

Home Assistant currently uses a Docker bridge network and publishes only port 8123. Its HomeKit Bridge still needs a reachable HomeKit TCP port and working LAN mDNS discovery before pairing; follow the integration's [Docker networking guidance](https://www.home-assistant.io/integrations/homekit/#docker-network-isolation). Deploying Homebridge does not enable that integration or change Home Assistant's networking.

Z-Wave requires a compatible controller and a [Z-Wave JS server](https://www.home-assistant.io/integrations/zwave_js/) connected to Home Assistant. The controller model and connection are not recorded in this repository, so this app does not create a Z-Wave service or re-pair existing devices.

## Networking and updates

- The [official Homebridge image](https://github.com/homebridge/docker-homebridge) uses host networking for HomeKit discovery and camera traffic. Its UI listens on host interfaces at port 8581; it is not published through Traefik. Keep WAN forwarding disabled for Homebridge and HomeKit ports.
- Keep the iPhone, Apple home hub, NVR, and Homebridge reachable on the LAN. If they are separated into VLANs, configure mDNS forwarding and the required HomeKit/camera traffic between those networks.
- The container has a pinned release tag and digest. Renovate tracks stable dated images and opens updates for manual review. Restarting may reinstall plugins from the persistent package manifest, so first startup can take several minutes.
- Homebridge's s6 init system owns PID 1. Its startup scripts require a writable root filesystem; capabilities are restricted to file ownership, user switching, and process shutdown.

## Backups and verification

All state lives in `/home/jaw/data/homebridge`, including plugin packages, credentials, `config.json`, `persist`, and `accessories`. Backrest copies the full directory nightly at **5:50 AM**, with the standard retention and verification hooks. Treat backups as sensitive because they contain credentials and HomeKit pairing keys.

To restore, stop Homebridge, restore the complete directory from its Backrest repository, and start the container. Keep the restored bridge identity and pairing files so accessories retain their Apple Home pairing. See [disaster recovery](../../docs/disaster-recovery.md).

After merging and deployment:

```bash
docker inspect --format '{{.State.Health.Status}}' homebridge
docker logs --tail 100 homebridge
curl --fail http://192.168.4.161:8581
```

Gatus monitors the UI and sends failure/recovery alerts. A healthy UI does not verify camera credentials, HomeKit pairing, live streams, or recordings; check those in Apple Home after setup.
