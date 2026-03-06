# Garage

S3-compatible object storage at `s3.jaw.dev` with web UI at `garage.jaw.dev`.

## Setup

### 1. Create secrets

```bash
cat > apps/garage/.env <<'EOF'
GARAGE_RPC_SECRET=<openssl rand -hex 32>
GARAGE_ADMIN_TOKEN=<openssl rand -base64 32>
GARAGE_METRICS_TOKEN=<openssl rand -base64 32>
EOF
sops -e --input-type dotenv --output-type dotenv apps/garage/.env > apps/garage/.env.sops
```

### 2. Deploy

Push to git, wait for docker-cd to sync.

### 3. Initialize cluster layout (one-time)

```bash
docker exec garage /garage node id -q
docker exec garage /garage layout assign -z dc1 -c 100GB <NODE_ID>
docker exec garage /garage layout apply --version 1
```

This is required because Garage is designed for multi-node clusters — even single-node needs an explicit layout assignment. Once applied, it persists across restarts.

### 4. Create buckets and keys

Use the web UI at `garage.jaw.dev` to create buckets, access keys, and manage permissions.

## Backups

Borgmatic backs up `~/data/garage/` to `~/backup/garage/` (NFS) daily at 2:10 AM.

## Ports (internal)

| Port | Purpose          |
| ---- | ---------------- |
| 3900 | S3 API           |
| 3901 | RPC (inter-node) |
| 3902 | S3 web hosting   |
| 3903 | Admin API        |
| 3909 | Web UI           |
