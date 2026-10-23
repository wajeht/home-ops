# Preserve the upstream application and replace only its vulnerable Node runtime.
FROM node:22.23.4-alpine3.24@sha256:fe4f6d74e20370acb04ad889077d14d0f64a9c8ea6a42bc60cddf1e844699914 AS runtime
FROM ghcr.io/gethomepage/homepage:v2.6.0@sha256:3e38fe788223cb46a3ce1f046ef11667b40f7707fdca0dcbfa3f86c5c42bf1e8
LABEL org.opencontainers.image.source="https://github.com/wajeht/home-ops"
COPY --from=runtime /usr/local/bin/node /usr/local/bin/node
ENV NODE_VERSION=22.23.4
RUN node -e "if (process.versions.node !== '22.23.4') process.exit(1)"
