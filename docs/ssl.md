# SSL/TLS Certificates

Caddy handles TLS automatically. `*.jaw.dev` uses Cloudflare DNS challenge.

## How It Works

1. Caddy obtains certs using Cloudflare DNS challenge.
2. `*.jaw.dev` is handled by wildcard routing in `apps/caddy/Caddyfile`.
3. Apps only need Docker labels (`caddy`, `caddy.reverse_proxy`) and the `proxy` network.

## Config (apps/caddy/Caddyfile)

```caddy
https://*.jaw.dev {
  tls {
    dns cloudflare {env.CF_DNS_API_TOKEN}
  }
  redir https://jaw.dev{uri} permanent
}
```

Non-wildcard domains can import this snippet in labels:

```yaml
labels:
  caddy: "jaw.dev www.jaw.dev"
  caddy.import: cf-tls
  caddy.reverse_proxy: "{{upstreams 80}}"
```

## Cloudflare Token

Stored in `apps/caddy/.env.sops` as `CF_DNS_API_TOKEN`. Needs permissions:

- Zone:DNS:Edit
- Zone:Zone:Read

## Troubleshooting

Rate-limited or challenge failures:

- Check Caddy logs: `docker logs caddy`
- Verify `CF_DNS_API_TOKEN` has required zone permissions
- Confirm public DNS points to your host
