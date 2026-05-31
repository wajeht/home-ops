# Linx - File Sharing

Self-hosted file/image/code sharing server.

## URL

https://linx.jaw.dev

## Storage & Auth

- Files stored in Garage S3 (`linx` bucket via `s3.jaw.dev`), not local disk
- **Downloads are public** — shared links work without login
- **Uploads gated by Google SSO** via Traefik path matching: the upload routes (`/`, `/upload`, `/paste`) sit behind `oauth2-admin@file`; everything else (file/`selif` reads, static) is public. No app-level API key
- Because uploads ride the browser OAuth flow, **upload is browser-only** — CLI tools (`linx-client`, `curl`) can't complete the SSO handshake

## Features

- File uploads with shareable links
- Syntax highlighting for code
- Image/video preview
- Expiring links
- Random filenames; direct-linking blocked for non-browser agents
- Max file size: 100MB
- Max expiry: 30 days

## Uploading

Open https://linx.jaw.dev in a browser, sign in with Google (oauth2-admin), and
drag-drop or pick files. Uploads are browser-only — CLI clients (`linx-client`,
`curl`) can't complete the OAuth handshake, so they're not supported.

## Downloading

Shared links are public — no login needed:

```bash
curl -O https://linx.jaw.dev/<name>          # download a shared file
```
