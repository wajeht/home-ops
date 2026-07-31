# Minecraft

Private Minecraft cross-play server for a small group, running Paper with
Geyser and Floodgate on the current pinned game release.

- macOS and other desktop players use Minecraft Java Edition.
- iOS, Android, and Windows Bedrock players connect through Geyser.
- Floodgate authenticates Bedrock players with Xbox Live without requiring
  them to also own Java Edition.

## Access

The server listens directly on TCP `25565` for Java and UDP `19132` for
Bedrock; neither protocol is routed through Traefik or Cloudflare's HTTP proxy.

Before internet access works:

1. Add two UniFi WAN port-forwards:

   - TCP `25565` to `192.168.4.161:25565` for Java
   - UDP `19132` to `192.168.4.161:19132` for Bedrock

2. Allow the port on the host:

   ```bash
   sudo ufw allow 25565/tcp comment 'Minecraft Java'
   sudo ufw allow 19132/udp comment 'Minecraft Bedrock'
   ```

3. Create `mc.jaw.dev` as a DNS-only A record pointing at the home WAN IPv4
   address. Bedrock does not support DNS SRV records.

Connect using:

| Client            | Address         | Port                |
| ----------------- | --------------- | ------------------- |
| macOS Java        | `mc.jaw.dev`    | `25565` (default)   |
| iOS/Bedrock       | `mc.jaw.dev`    | `19132`             |
| Same-LAN fallback | `192.168.4.161` | Same ports as above |

On iOS, sign in to the Microsoft/Xbox account, open **Play → Servers → Add
Server**, and enter the Bedrock address and port above.

Keep the DNS record unproxied: Cloudflare's normal HTTP proxy carries neither
Minecraft's Java TCP protocol nor Bedrock's UDP protocol.

## Player access

Online account authentication and the whitelist are enforced for both editions.
The initial whitelist is empty, so add each player after deployment.

Java player:

```bash
docker exec minecraft rcon-cli whitelist add <username>
```

Bedrock player (use the Xbox gamertag without Floodgate's internal prefix):

```bash
docker exec minecraft rcon-cli fwhitelist add <gamertag>
```

Review the combined Java and Floodgate whitelist:

```bash
docker exec minecraft rcon-cli whitelist list
```

Grant operator access sparingly. Bedrock names normally use Floodgate's `.` prefix
for standard Java commands:

```bash
docker exec minecraft rcon-cli op <username>
docker exec minecraft rcon-cli op .<bedrock-gamertag>
```

RCON remains internal to the container and is not published on the host.
Floodgate generates `/home/jaw/data/minecraft/plugins/floodgate/key.pem`; never
copy that key into Git or share it.

## Operations

```bash
docker logs -f minecraft
docker exec minecraft rcon-cli list
docker exec minecraft rcon-cli geyser connectiontest mc.jaw.dev 19132
docker exec minecraft rcon-cli save-all flush
```

World and server data live at `/home/jaw/data/minecraft`. Backrest flushes and
pauses world saves around its nightly snapshot, resumes saves afterward, and
sends the standard success/failure notifications.

The Compose configuration accepts the
[Minecraft EULA](https://www.minecraft.net/eula).

## Compatibility

Geyser `2.11.0-b1204` supports Bedrock `26.0` through `26.33` and translates
those clients into Java 26.2 clients. It supports normal vanilla gameplay and
server-side Paper plugins, but Java-client-only mods and some edition-specific
behavior cannot be translated perfectly.

Pinned cross-play components:

- Geyser `2.11.0-b1204`
- Floodgate `2.2.5-b138`

When iOS auto-updates beyond Geyser's supported Bedrock versions, bump both
plugin download URLs from the official GeyserMC download API and retest before
deploying.
