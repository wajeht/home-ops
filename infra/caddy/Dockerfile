# This Dockerfile is intentionally kept in home-ops even though production
# pulls ghcr.io/wajeht/docker-cd-caddy. It provides a local fallback path
# and documents the required plugin set in-repo.
FROM caddy:2-builder AS builder

RUN xcaddy build \
    --with github.com/lucaslorentz/caddy-docker-proxy/v2 \
    --with github.com/caddy-dns/cloudflare \
    --with github.com/greenpau/caddy-security \
    --with github.com/mholt/caddy-ratelimit

FROM caddy:2

COPY --from=builder /usr/bin/caddy /usr/bin/caddy
