# Linx - File Sharing

Self-hosted file/image/code sharing server.

## URL

https://linx.jaw.dev

## Features

- File uploads with shareable links
- Syntax highlighting for code
- Image/video preview
- Expiring links
- Max file size: 100MB
- Max expiry: 30 days

## CLI Client

### Install linx-client

```bash
go install github.com/andreimarcu/linx-client@latest
```

### Usage

```bash
# Upload file
linx-client -s https://linx.jaw.dev/ file.txt

# Upload with expiry (seconds)
linx-client -s https://linx.jaw.dev/ -e 3600 file.txt

# Upload from stdin
cat file.txt | linx-client -s https://linx.jaw.dev/

# Delete (if delete key provided)
linx-client -s https://linx.jaw.dev/ -d <deletekey> <filename>
```

### Shell Alias

Add to ~/.bashrc or ~/.zshrc:

```bash
alias linx='linx-client -s https://linx.jaw.dev/'
```

Then: `linx myfile.png`

## cURL Upload

```bash
curl -T file.txt https://linx.jaw.dev/upload/
```
