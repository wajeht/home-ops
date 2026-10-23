# Preserve the upstream application and replace only its vulnerable Node runtime.
LABEL org.opencontainers.image.source="https://github.com/wajeht/home-ops"
FROM node:24.22.1-alpine@sha256:06d7adf3e0ef61a13f1d28682726366f97a15aa1888c934d3ecec86c33918b53 AS runtime
FROM ghcr.io/koenkk/zigbee2mqtt:2.14.2@sha256:addbfb08fcef2e4477de1535636118241e10d13e898fbe4d9faba8a4d7396311
COPY --from=runtime /usr/local/bin/node /usr/bin/node
ENV NODE_VERSION=24.22.1
RUN node -e "if (process.versions.node !== '24.22.1') process.exit(1)"
