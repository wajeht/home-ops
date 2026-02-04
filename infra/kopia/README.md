# Kopia Backup

Web UI backup solution with deduplication, compression, and encryption.

## Access

**Web UI:** https://backup.jaw.dev (protected by Authelia)

**Login:** jaw / (password in secrets)

## What's Backed Up

- `/data` - All app configs and databases
- `/sops` - Age encryption key (critical)
- `/dumps` - SQLite database dumps (for consistency)

## First-Time Setup

1. Deploy the stack
2. Access https://backup.jaw.dev
3. Create repository:
   - Select "Local Directory or NAS"
   - Path: `/repository`
   - Set encryption password (use same as kopia_password secret)
4. Create snapshot policy:
   - Add path `/data`
   - Add path `/sops`
   - Add path `/dumps`
   - Set schedule (e.g., daily at 3am)
   - Set retention (7 daily, 4 weekly, 6 monthly)

## SQLite Database Dumps

For consistent SQLite backups, run the dump script before snapshots:

```bash
# On the server
sudo /home/jaw/home-ops/infra/kopia/dump-databases.sh
```

### Automated Dumps (Cron)

Add to server crontab (`sudo crontab -e`):

```bash
# Dump databases 5 minutes before Kopia snapshot
55 2 * * * /home/jaw/home-ops/infra/kopia/dump-databases.sh >> /var/log/kopia-dump.log 2>&1
```

Then set Kopia snapshot schedule to 3:00 AM in the web UI.

## CLI Commands

```bash
# Enter container
docker exec -it $(docker ps -q -f name=kopia) /bin/bash

# List snapshots
kopia snapshot list

# Create manual snapshot
kopia snapshot create /data

# Show repository status
kopia repository status

# Mount snapshot for browsing
kopia mount all /tmp/kopia-mount &
ls /tmp/kopia-mount/
umount /tmp/kopia-mount
```

## Restore

### Via Web UI

1. Go to Snapshots
2. Browse to desired snapshot
3. Click file/folder → Download or Restore

### Via CLI

```bash
# Restore entire snapshot
kopia restore <snapshot-id> /tmp/restore/

# Restore specific path
kopia restore <snapshot-id>/data/radarr /tmp/restore/radarr

# List snapshot contents
kopia ls <snapshot-id>
```

## Disaster Recovery

### Full Restore to New Server

1. Install Docker, clone repo
2. Mount NFS backup to `~/backup/kopia`
3. Create password secret:
   ```bash
   export SOPS_AGE_KEY_FILE=~/.sops/age-key.txt
   sops -d ~/home-ops/infra/kopia/.enc.env | grep KOPIA_PASSWORD | cut -d= -f2 | docker secret create kopia_password -
   ```
4. Deploy Kopia stack
5. Connect to existing repository in Web UI:
   - Select "Local Directory or NAS"
   - Path: `/repository`
   - Enter encryption password
6. Restore snapshots as needed

### Restore Single App

```bash
# Example: restore radarr
docker exec $(docker ps -q -f name=kopia) kopia restore <snapshot-id>/data/radarr /data/radarr-restored
mv ~/data/radarr ~/data/radarr.bak
mv ~/data/radarr-restored ~/data/radarr
docker service update --force media_radarr
```

## Retention Policy

Configure in Web UI under Snapshot Policy:

| Keep | Count |
|------|-------|
| Latest | 7 |
| Daily | 7 |
| Weekly | 4 |
| Monthly | 6 |
| Annual | 0 |

## Security

- **Encryption:** AES-256-GCM (set during repo creation)
- **Password:** Stored in Docker secret (encrypted with SOPS)
- **Web UI:** Protected by Authelia SSO

## NFS Mount

Mount NAS to `~/backup/kopia`:

```bash
# /etc/fstab
nas:/backup/kopia /home/jaw/backup/kopia nfs defaults,_netdev 0 0
```

## Troubleshooting

### Can't Connect to Repository

```bash
# Check if repository exists
ls -la ~/backup/kopia/

# Check Kopia logs
docker service logs kopia_kopia
```

### Snapshot Stuck

```bash
# Cancel stuck operations
docker exec $(docker ps -q -f name=kopia) kopia snapshot cancel --all
```

### Check Repository Health

```bash
docker exec $(docker ps -q -f name=kopia) kopia repository validate-client
```

## Sources

- [Kopia Docs](https://kopia.io/docs/)
- [Kopia Docker Setup](https://kopia.io/docs/installation/#docker-images)
